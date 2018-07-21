# Usage:
# parser = Parser.new tokens
# program = parser.parse
# program.evaluate Environment.new
class Parser
    private alias TT = Token::TokenType
    private alias VT = Variable::VariableType
    private alias RT = Function::ReturnType
    
    # For exit status
    FAIL = 1

    # Token index
    @i = 0

    def initialize(@tokens : Array(Token)) end

    def curToken(bias = 0)
        @tokens[@i + bias]
    end

    def operatorRaise(operator, operand, expected, side="")
        side += ' ' unless side.empty?

        STDERR.puts "#{lineMsg operand}For #{operator.code} #{side}operand: \
            expected #{expected}, not #{operand.class}."
        exit FAIL
    end

    # For error messages
    def lineMsg(expr)
        "Line #{expr.line} -> "
    end

    # Environment necessary to maintain scope of variables
    def parse(env : Environment)
        statements = [] of Statement
        until curToken.type == TT::EOF
            statements << statement env
        end

        Block.new statements
    end

    def statement(env)
        if curToken.type == TT::Print
            line = curToken.line
            @i += 1
            Print.new expression(env), line
        elsif curToken.type == TT::Println
            line = curToken.line
            @i += 1
            Println.new expression(env), line
        elsif curToken.type == TT::If
            # Variables changed in if are changed in outer scope, too. New
            # variables in if go away at end.
            scope = Environment.new(
                env.variables.dup,
                env.functions,
                env.level + 1
            )
            conditional scope
        elsif curToken.type == TT::While
            # Scope same as if
            scope = Environment.new(
                env.variables.dup,
                env.functions,
                env.level + 1
            )
            whileLoop scope
        elsif curToken.type == TT::Define
            # New scope for def so function definition can reuse existing
            # variables
            scope = Environment.new(
                {} of String => Variable,
                env.functions,
                env.level + 1
            )
            define scope
        elsif curToken.type == TT::Identifier
            if curToken(1).type == TT::Assign
                assign env
            elsif curToken(1).type == TT::AssignMultiply ||
                    curToken(1).type == TT::AssignDivide ||
                    curToken(1).type == TT::AssignMod ||
                    curToken(1).type == TT::AssignAdd ||
                    curToken(1).type == TT::AssignSubtract

                # *= /= %/ += -=
                arithmeticAssign env
            elsif curToken(1).type == TT::AssignAnd ||
                    curToken(1).type == TT::AssignOr

                # &= |=
                logicalAssign env
            elsif env.functions.has_key? curToken.code
                call env
            else
                expression env
                #STDERR.puts "#{lineMsg curToken}Unexpected identifier: \
                    ##{curToken.code}"
                #exit FAIL
            end
        else
            expression env
            #STDERR.puts "#{lineMsg curToken}Unexpected token: \
                ##{curToken.code}"
            #exit FAIL
        end
    end

    # if
    def conditional(env)
        line = curToken.line
        @i += 1

        # Get if condition
        ifCondition = expression env
        unless ifCondition.is_a? BooleanExpression
            STDERR.puts "#{lineMsg ifCondition}Expected BooleanExpression, \
                not #{ifCondition.class}."
            exit FAIL
        end

        ifBody = [] of Statement
        until curToken.type == TT::Elf ||
                curToken.type == TT::Else ||
                curToken.type == TT::End

            if curToken.type == TT::EOF
                STDERR.puts "#{lineMsg curToken}Expected end after if, not \
                    EOF."
                exit FAIL
            end
            ifBody << statement env
        end

        # elf (else if)
        elfBodies = [] of Tuple(BooleanExpression, Block)
        while curToken.type == TT::Elf
            @i += 1
            j = elfBodies.size

            # Get condition
            elfCondition = expression env
            unless elfCondition.is_a? BooleanExpression
                STDERR.puts "#{lineMsg elfCondition}Expected \
                    BooleanExpression, not #{elfCondition.class}."
                exit FAIL
            end

            elfBody = [] of Statement
            until curToken.type == TT::Elf ||
                    curToken.type == TT::Else ||
                    curToken.type == TT::End

                if curToken.type == TT::EOF
                    STDERR.puts "#{lineMsg curToken}Expected end after elf, \
                        not EOF."
                    exit FAIL
                end
                elfBody << statement env
            end

            elfBodies << {elfCondition, Block.new(elfBody)}
        end

        # else
        elseBody = [] of Statement
        if curToken.type == TT::Else
            @i += 1
            until curToken.type == TT::End
                if curToken.type == TT::EOF
                    STDERR.puts "#{lineMsg curToken}Expected end after else, \
                        not EOF."
                    exit FAIL
                end
                elseBody << statement env
            end
        end

        # end
        @i += 1

        If.new(
            ifCondition,
            Block.new(ifBody),
            elfBodies,
            Block.new(elseBody),
            line
        )
    end

    def whileLoop(env)
        line = curToken.line
        @i += 1

        # Get condition
        condition = expression env
        unless condition.is_a? BooleanExpression
            STDERR.puts "#{lineMsg condition}Expected BooleanExpression, \
                not #{condition.class}."
            exit FAIL
        end

        body = [] of Statement
        until curToken.type == TT::End
            if curToken.type == TT::EOF
                STDERR.puts "#{lineMsg curToken}Expected end after while, \
                    not EOF."
                exit FAIL
            end
            body << statement env
        end

        # end
        @i += 1

        While.new condition, Block.new(body), line
    end

    def define(env)
        if env.level > 1
            STDERR.puts "#{lineMsg curToken}Must define function at global \
                scope."
            exit FAIL
        end

        line = curToken.line
        @i += 1

        unless curToken.type == TT::Identifier
            STDERR.puts "#{lineMsg curToken}Identifier expected after def, \
                not #{curToken.code}." 
            exit FAIL
        end

        name = curToken.code
        @i += 1

        # Formals are the formal parameter variables:
        # def function(int formal1, bool formal2) end
        formals = [] of Function::Formal

        # In function defined with no parameters, parentheses are optional
        if curToken.type == TT::ParenthesisL
            @i += 1

            # If it doesn't look like function(), get formals
            unless curToken.type == TT::ParenthesisR
                loop do
                    formals << getFormal env
                    break unless curToken.type == TT::Comma
                    @i += 1
                end

                unless curToken.type == TT::ParenthesisR
                    STDERR.puts "#{lineMsg curToken(-1)}Expected )."
                    exit FAIL
                end
            end
            @i += 1
        end

        # Add function to environment. Body not necessary, because parser only
        # checks whether function exists.
        # This may change with updates to return types.
        body = [] of Statement
        env.functions[name] = Function.new(
            formals,
            Block.new(body),
            RT::Void
        )

        # Get statements
        until curToken.type == TT::End
            if curToken.type == TT::EOF
                STDERR.puts "#{lineMsg curToken}Expected end after def, not \
                    EOF."
                exit FAIL
            end
            body << statement env
        end

        @i += 1

        Definition.new name, formals, Block.new(body), RT::Void, line
    end

    # Helper function
    # Probably doesn't need to be private
    private def getFormal(env)
        # Get type
        if curToken.type == TT::Type
            if curToken.code == "int"
                v = Variable.new VT::Integer, 0
            else
                v = Variable.new VT::Boolean, false
            end
            @i += 1
        else
            STDERR.puts "#{lineMsg curToken}Must name parameter types in \
                function definition."
            exit FAIL
        end

        # Get name
        if curToken.type == TT::Identifier
            formal = Function::Formal.new curToken.code, v.type
            env.variables[curToken.code] = v
            @i += 1
        else
            STDERR.puts "#{lineMsg curToken}Invalid formal parameter name: \
                #{curToken.code}"
            exit FAIL
        end

        formal
    end

    def assign(env)
        id = curToken
        @i += 1

        # = sign
        @i += 1

        # Right side of =
        r = expression env

        if r.is_a? IntegerExpression
            type = VT::Integer
            value = 0
        elsif r.is_a? BooleanExpression
            type = VT::Boolean
            value = false
        else
            STDERR.puts "#{lineMsg id}Error in variable assignment: \
                #{id.code}"
            exit FAIL
        end

        if env.variables.has_key? id.code
            # Variable already exists: changing object instead of replacing.
            # This way parent environments receive changes.
            env.variables[id.code].type = type
            env.variables[id.code].value = value
        else
            # New variable
            env.variables[id.code] = Variable.new type, value
        end

        Assignment.new id.code, type, r, id.line
    end

    def arithmeticAssign(env)
        # Let atom get variable because BinaryArithmetic takes in two
        # IntegerExpressions
        l = atom env

        operator = curToken
        @i += 1

        unless l.is_a? IntegerVariable
            operatorRaise operator, l, IntegerVariable, "L"
        end

        r = expression env

        unless r.is_a? IntegerExpression
            operatorRaise operator, r, IntegerExpression, "R"
        end

        type = VT::Integer
        if operator.type == TT::AssignMultiply
            Assignment.new l.name, type, Multiply.new(l, r, l.line), l.line
        elsif operator.type == TT::AssignDivide
            Assignment.new l.name, type, Divide.new(l, r, l.line), l.line
        elsif operator.type == TT::AssignMod
            Assignment.new l.name, type, Mod.new(l, r, l.line), l.line
        elsif operator.type == TT::AssignAdd
            Assignment.new l.name, type, Add.new(l, r, l.line), l.line
        else
            Assignment.new l.name, type, Subtract.new(l, r, l.line), l.line
        end
    end

    def logicalAssign(env)
        l = atom env

        operator = curToken
        @i += 1

        unless l.is_a? BooleanVariable
            operatorRaise operator, l, BooleanVariable, "L"
        end

        r = expression env

        unless r.is_a? BooleanExpression
            operatorRaise operator, r, BooleanExpression, "R"
        end

        type = VT::Boolean
        if operator.type == TT::AssignAnd
            Assignment.new l.name, type, And.new(l, r, l.line), l.line
        else
            Assignment.new l.name, type, Or.new(l, r, l.line), l.line
        end
    end

    # Function call
    def call(env)
        id = curToken
        @i += 1

        # Actuals are expressions passed in as arguments to function:
        # function(actual 1, (actual2.1 && actual2.2))
        actuals = [] of Expression

        # Function has no parameters? Skip.
        # But in calling a function with no parameters, parentheses are
        # optional. Enter to pass parentheses
        if env.functions[id.code].numArgs > 0 ||
                curToken.type == TT::ParenthesisL

            unless curToken.type == TT::ParenthesisL
                STDERR.puts "#{lineMsg curToken(-1)}Expected () for passing \
                    arguments to function."
                exit FAIL
            end
            @i += 1

            # Check again because some people are in here with parentheses but
            # no parameters
            if env.functions[id.code].numArgs > 0
                actuals = getActuals env, id
            end

            unless curToken.type == TT::ParenthesisR
                STDERR.puts "#{lineMsg curToken(-1)}Expected )."
                exit FAIL
            end
            @i += 1
        end

        VoidCall.new id.code, actuals, id.line
    end

    # Helper function
    # Probably doesn't need to be private
    private def getActuals(env, id)
        actuals = [] of Expression

        numArgs = env.functions[id.code].numArgs
        #s = (numArgs == 1 ? "" : "s")  # Singular/plural?

        loop do
            # Ensure expression type matches formal type
            arg = expression env
            type = env.functions[id.code].formals[actuals.size].type

            if (arg.is_a? IntegerExpression && type.is_a? VT::Integer) ||
                    (arg.is_a? BooleanExpression && type.is_a? VT::Boolean)

                actuals << arg
            else
                STDERR.puts "#{lineMsg arg}Argument #{actuals.size + 1} \
                    type does not match type signature in #{id.code}."

                exit FAIL
            end

            break unless curToken.type == TT::Comma
            @i += 1

            # Must not be too many arguments
            unless numArgs > actuals.size
                STDERR.puts "#{lineMsg id}Too many arguments to function \
                    #{id.code}. \ Expected #{numArgs}."

                exit FAIL
            end
        end

        # Must not be too few arguments
        unless actuals.size == numArgs
            STDERR.puts "#{lineMsg id}Too few arguments to function \
                #{id.code}. Expected #{numArgs}, not #{actuals.size}."

            exit FAIL
        end

        actuals
    end

    # Logic behind order of precedence starts here
    def expression(env)
        logicalOr env
    end

    def logicalOr(env)
        a = logicalAnd env
        while curToken.type == TT::Or
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression
                operatorRaise operator, a, BooleanExpression, "L"
            end

            b = logicalAnd env

            unless b.is_a? BooleanExpression
                operatorRaise operator, b, BooleanExpression, "R"
            end

            a = Or.new a, b, a.line
        end
        a
    end

    def logicalAnd(env)
        a = relational env
        while curToken.type == TT::And
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression
                operatorRaise operator, a, BooleanExpression, "L"
            end

            b = relational env

            unless b.is_a? BooleanExpression
                operatorRaise operator, b, BooleanExpression, "R"
            end

            a = And.new a, b, a.line
        end
        a
    end

    def relational(env)
        a = comparison env
        while curToken.type == TT::Equal ||
                curToken.type == TT::NotEqual

            operator = curToken
            @i += 1
            b = comparison env
            if operator.type == TT::Equal
                a = Equal.new a, b, a.line
            else
                a = NotEqual.new a, b, a.line
            end
        end
        a
    end

    def comparison(env)
        a = additive env
        while curToken.type == TT::Greater ||
                curToken.type == TT::GreaterOrEqual ||
                curToken.type == TT::LessOrEqual ||
                curToken.type == TT::Less

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression, "L"
            end

            b = additive env

            unless b.is_a? IntegerExpression
                operatorRaise operator, b, IntegerExpression, "R"
            end

            if operator.type == TT::Greater
                a = Greater.new a, b, a.line
            elsif operator.type == TT::GreaterOrEqual
                a = GreaterOrEqual.new a, b, a.line
            elsif operator.type == TT::LessOrEqual
                a = LessOrEqual.new a, b, a.line
            else
                a = Less.new a, b, a.line
            end
        end
        a
    end

    def additive(env)
        a = multiplicative env
        while curToken.type == TT::Plus ||
                curToken.type == TT::Minus

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression, "L"
            end

            b = multiplicative env

            unless b.is_a? IntegerExpression
                operatorRaise operator, b, IntegerExpression, "R"
            end

            if operator.type == TT::Plus
                a = Add.new a, b, a.line
            else
                a = Subtract.new a, b, a.line
            end
        end
        a
    end

    def multiplicative(env)
        a = unary env
        while curToken.type == TT::Star ||
                curToken.type == TT::Slash ||
                curToken.type == TT::Percent

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression, "L"
            end

            b = unary env

            unless b.is_a? IntegerExpression
                operatorRaise operator, b, IntegerExpression, "R"
            end

            if operator.type == TT::Star
                a = Multiply.new a, b, a.line
            elsif operator.type == TT::Slash
                a = Divide.new a, b, a.line
            else
                a = Mod.new a, b, a.line
            end
        end
        a
    end

    def unary(env)
        if curToken.type == TT::Minus
            operator = curToken
            @i += 1
            a = atom env

            unless a.is_a? IntegerExpression
                operatorRaise operator, a, IntegerExpression
            end

            Negate.new a, a.line
        elsif curToken.type == TT::Bang
            operator = curToken
            @i += 1
            a = atom env

            unless a.is_a? BooleanExpression
                operatorRaise operator, a, BooleanExpression
            end

            Not.new a, a.line
        else
            atom env
        end
    end

    def atom(env)
        if curToken.type == TT::Integer
            int = Integer.new curToken.code.to_i, curToken.line
            @i += 1
            int
        elsif curToken.type == TT::Boolean
            bool = Boolean.new (curToken.code == "true"), curToken.line
            @i += 1
            bool
        elsif curToken.type == TT::Identifier
            id = curToken
            @i += 1

            if env.variables.has_key? id.code
                if env.variables[id.code].type.is_a? VT::Integer
                    IntegerVariable.new id.code, id.line
                else
                    BooleanVariable.new id.code, id.line
                end
            else
                STDERR.puts "#{lineMsg id}Uninitialized variable: #{id.code}"
                exit FAIL
            end
        elsif curToken.type == TT::ParenthesisL
            @i += 1
            e = expression env

            unless curToken.type == TT::ParenthesisR
                STDERR.puts "#{lineMsg curToken(-1)}Expected )."
                exit FAIL
            end

            @i += 1
            e
        else
            STDERR.puts "#{lineMsg curToken}Unexpected token: \
                #{curToken.code}. Expected expression."
            exit FAIL
        end
    end
end
