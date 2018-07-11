class Parser
    private alias TT = Token::TokenType
    private alias VT = Variable::VariableType
    private alias RT = Function::ReturnType
    
    FAIL = 1

    @i = 0

    def initialize(@tokens : Array(Token)) end

    def curToken(bias = 0)
        @tokens[@i + bias]
    end

    def operatorRaise(operator, operand, expected, side="")
        side += ' ' unless side.empty?
        STDERR.puts "For #{operator.code} #{side}operand: \
            expected #{expected}, not #{operand.class}. #{@i}"
        exit FAIL
    end

    def parse
        statements = [] of Statement
        env = Environment.new

        until curToken.tokenType == TT::EOF
            statements << statement env
        end

        Block.new statements
    end

    def statement(env)
        if curToken.tokenType == TT::Print
            @i += 1
            Print.new expression env
        elsif curToken.tokenType == TT::Println
            @i += 1
            Println.new expression env
        elsif curToken.tokenType == TT::If
            scope = Environment.new(
                env.variables.dup,
                env.functions,
                env.level + 1
            )
            conditional scope
        elsif curToken.tokenType == TT::While
            scope = Environment.new(
                env.variables.dup,
                env.functions,
                env.level + 1
            )
            whileLoop scope
        elsif curToken.tokenType == TT::Define
            scope = Environment.new(
                {} of String => Variable,
                env.functions,
                env.level + 1
            )
            define scope
        elsif curToken.tokenType == TT::Identifier
            if curToken(1).tokenType == TT::Assign
                assign env
            elsif env.functions.has_key? curToken.code
                call env
            else
                STDERR.puts "Unexpected identifier: #{@i} #{curToken.code}"
                exit FAIL
            end
        else
            STDERR.puts "Unexpected token: #{@i} #{curToken.code}"
            exit FAIL
        end
    end

    def conditional(env)
        @i += 1
        
        condition = expression env
        unless condition.is_a? BooleanExpression
            STDERR.puts "Expected BooleanExpression, not #{condition.class}. #{@i}"
            exit FAIL
        end

        body = [] of Statement
        until curToken.tokenType == TT::End
            if curToken.tokenType == TT::EOF
                STDERR.puts "Expected end after if, not EOF."
                exit FAIL
            end
            body << statement env
        end
        # Check for else? else if?

        @i += 1

        If.new condition, Block.new body
    end

    def whileLoop(env)
        @i += 1

        condition = expression env
        unless condition.is_a? BooleanExpression
            STDERR.puts "Expected BooleanExpression, not #{condition.class}. #{@i}"
            exit FAIL
        end

        body = [] of Statement
        until curToken.tokenType == TT::End
            if curToken.tokenType == TT::EOF
                STDERR.puts "Expected end after while, not EOF."
                exit FAIL
            end
            body << statement env
        end

        @i += 1

        While.new condition, Block.new body
    end

    def define(env)
        if env.level > 1
           STDERR.puts "Must define function at global scope."
           exit FAIL
        end

        @i += 1

        unless curToken.tokenType == TT::Identifier
            STDERR.puts "Identifier expected after def, not #{curToken.code}. #{@i}" 
            exit FAIL
        end

        name = curToken.code
        @i += 1

        formals = [] of Function::Formal

        if curToken.tokenType == TT::ParenthesisL
            @i += 1

            loop do
                if curToken.tokenType == TT::Type
                    if curToken.code == "int"
                        v = Variable.new VT::Integer, 0
                    else
                        v = Variable.new VT::Boolean, false
                    end
                    @i += 1
                else
                    STDERR.puts "Must name parameter types in function definition. #{@i}"
                    exit FAIL
                end

                if curToken.tokenType == TT::Identifier
                    formals << Function::Formal.new curToken.code, v.type
                    env.variables[curToken.code] = v
                    @i += 1
                else
                    STDERR.puts "Parameters expected in (). #{@i}"
                    exit FAIL
                end

                break unless curToken.tokenType == TT::Comma
                @i += 1
            end

            unless curToken.tokenType == TT::ParenthesisR
                STDERR.puts "Expected ) after formals. #{@i}"
                exit FAIL
            end
            @i += 1
        end

        statements = [] of Statement
        env.functions[name] = Function.new formals, (Block.new statements), RT::Void

        until curToken.tokenType == TT::End
            if curToken.tokenType == TT::EOF
                STDERR.puts "Expected end after def, not EOF."
                exit FAIL
            end
            statements << statement env
        end

        @i += 1

        Definition.new name, formals, (Block.new statements), RT::Void
    end

    def assign(env)
        id = curToken
        @i += 1

        # = sign
        @i += 1

        r = expression env

        if r.is_a? IntegerExpression
            if env.variables.has_key? id.code
                env.variables[id.code].type = VT::Integer
                env.variables[id.code].value = 0
            else
                env.variables[id.code] = Variable.new VT::Integer, 0
            end

            Assignment.new id.code, VT::Integer, r

        elsif r.is_a? BooleanExpression
            if env.variables.has_key? id.code
                env.variables[id.code].type = VT::Boolean
                env.variables[id.code].value = false
            else
                env.variables[id.code] = Variable.new VT::Boolean, false
            end

            Assignment.new id.code, VT::Boolean, r

        else
            STDERR.puts "Error in variable assignment: #{@i} #{id.code}"
            exit FAIL
        end
    end

    def call(env)
        id = curToken
        @i += 1

        actuals = [] of Expression
        numArgs = env.functions[id.code].numArgs
        #s = (numArgs == 1 ? "" : "s")

        if numArgs > 0 
            unless curToken.tokenType == TT::ParenthesisL
                STDERR.puts "Expected () for passing arguments to function."
                exit FAIL
            end
            @i += 1

            j = 0

            loop do
                arg = expression env
                t = env.functions[id.code].formals[j].type

                if (arg.is_a? IntegerExpression && t.is_a? VT::Integer) ||
                        (arg.is_a? BooleanExpression && t.is_a? VT::Boolean)

                    actuals << arg
                else
                    STDERR.puts "Argument #{j + 1} type does not match \
                        type signature in #{id.code}."

                    exit FAIL
                end

                j += 1

                break unless curToken.tokenType == TT::Comma

                unless numArgs > j
                    STDERR.puts "Too many arguments to function #{id.code}. \
                        Expected #{numArgs}."

                    exit FAIL
                end

                @i += 1
            end

            unless j == numArgs
                STDERR.puts "Too few arguments to function #{id.code}. \
                    Expected #{numArgs}, not #{j}."

                exit FAIL
            end

            unless curToken.tokenType == TT::ParenthesisR
                STDERR.puts "Expected ), not #{curToken.code}. #{@i}"
                exit FAIL
            end
            @i += 1
        end

        Call.new id.code, actuals
    end

    def expression(env)
        logicalOr env
    end

    def logicalOr(env)
        a = logicalAnd env
        while curToken.tokenType == TT::Or
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression
                operatorRaise operator, a, BooleanExpression, "L"
            end

            b = logicalAnd env

            unless b.is_a? BooleanExpression
                operatorRaise operator, b, BooleanExpression, "R"
            end

            a = Or.new a, b
        end
        a
    end

    def logicalAnd(env)
        a = relational env
        while curToken.tokenType == TT::And
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression
                operatorRaise operator, a, BooleanExpression, "L"
            end

            b = relational env

            unless b.is_a? BooleanExpression
                operatorRaise operator, b, BooleanExpression, "R"
            end

            a = And.new a, b
        end
        a
    end

    def relational(env)
        a = comparison env
        while curToken.tokenType == TT::Equal ||
                curToken.tokenType == TT::NotEqual

            operator = curToken
            @i += 1
            b = comparison env
            if operator.tokenType == TT::Equal
                a = Equal.new a, b
            else
                a = NotEqual.new a, b
            end
        end
        a
    end

    def comparison(env)
        a = additive env
        while curToken.tokenType == TT::Greater ||
                curToken.tokenType == TT::GreaterOrEqual ||
                curToken.tokenType == TT::LessOrEqual ||
                curToken.tokenType == TT::Less

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression, "L"
            end

            b = additive env

            unless b.is_a? IntegerExpression
                operatorRaise operator, b, IntegerExpression, "R"
            end

            if operator.tokenType == TT::Greater
                a = Greater.new a, b
            elsif operator.tokenType == TT::GreaterOrEqual
                a = GreaterOrEqual.new a, b
            elsif operator.tokenType == TT::LessOrEqual
                a = LessOrEqual.new a, b
            else
                a = Less.new a, b
            end
        end
        a
    end

    def additive(env)
        a = multiplicative env
        while curToken.tokenType == TT::Plus ||
                curToken.tokenType == TT::Minus

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression, "L"
            end

            b = multiplicative env

            unless b.is_a? IntegerExpression
                operatorRaise operator, b, IntegerExpression, "R"
            end

            if operator.tokenType == TT::Plus
                a = Add.new a, b
            else
                a = Subtract.new a, b
            end
        end
        a
    end

    def multiplicative(env)
        a = unary env
        while curToken.tokenType == TT::Star ||
                curToken.tokenType == TT::Slash ||
                curToken.tokenType == TT::Percent

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression, "L"
            end

            b = unary env

            unless b.is_a? IntegerExpression
                operatorRaise operator, b, IntegerExpression, "R"
            end

            if operator.tokenType == TT::Star
                a = Multiply.new a, b
            elsif operator.tokenType == TT::Slash
                a = Divide.new a, b
            else
                a = Mod.new a, b
            end
        end
        a
    end

    def unary(env)
        if curToken.tokenType == TT::Minus
            operator = curToken
            @i += 1
            a = atom env

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression
            end

            Negate.new a
        elsif curToken.tokenType == TT::Bang
            operator = curToken
            @i += 1
            a = atom env

            unless a.is_a? BooleanExpression
                operatorRaise operator, a, BooleanExpression
            end

            Not.new a
        else
            atom env
        end
    end

    def atom(env)
        if curToken.tokenType == TT::Integer
            int = Integer.new curToken.code.to_i
            @i += 1
            int
        elsif curToken.tokenType == TT::Boolean
            bool = Boolean.new (curToken.code == "true")
            @i += 1
            bool
        elsif curToken.tokenType == TT::Identifier
            id = curToken
            @i += 1

            if env.variables.has_key? id.code
                if env.variables[id.code].type.is_a? VT::Integer
                    IntegerVariable.new id.code
                else
                    BooleanVariable.new id.code
                end
            else
                STDERR.puts "Uninitialized variable: #{@i} #{id.code}"
                exit FAIL
            end
        elsif curToken.tokenType == TT::ParenthesisL
            @i += 1
            e = expression env

            unless curToken.tokenType == TT::ParenthesisR
                STDERR.puts "Expected ), not #{@i} #{curToken.code}."
                exit FAIL
            end

            @i += 1
            e
        else
            STDERR.puts "Bad token: #{@i} #{curToken.code}. Expected expression"
            exit FAIL
        end
    end
end
