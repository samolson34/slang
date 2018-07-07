class Parser
    private alias TT = Token::TokenType
    private alias VT = Variable::VariableType
    private alias RT = Function::ReturnType
    
    FAIL = 1

    @i = 0
    @variables = {} of String => VT
    @functions = {} of String => Function
    @noDef = false
    @defVars = {} of String => VT

    def initialize(@tokens : Array(Token)) end

    def curToken
        @tokens[@i]
    end

    def operatorRaise(operator, operand, expected, side="")
        side += ' ' unless side.empty?
        STDERR.puts "For #{operator.code} #{side}operand: \
            expected #{expected}, not #{operand.class}. #{@i}"
        exit FAIL
    end

    def parse
        statements = [] of Statement

        until curToken.tokenType == TT::EOF
            statements << statement
        end

        Block.new statements
    end

    def statement
        if curToken.tokenType == TT::Print
            @i += 1
            Print.new expression
        elsif curToken.tokenType == TT::Println
            @i += 1
            Println.new expression
        elsif curToken.tokenType == TT::If
            conditional
        elsif curToken.tokenType == TT::While
            whileLoop
        elsif curToken.tokenType == TT::Define
            define
        elsif curToken.tokenType == TT::Identifier
            id = curToken
            @i += 1

            if curToken.tokenType == TT::Assign
                assign id
            elsif @functions.has_key? id.code
                call id
            else
                STDERR.puts "Unexpected identifier: #{@i} #{id.code}"
                exit FAIL
            end
        else
            STDERR.puts "Unexpected token: #{@i} #{curToken.code}"
            exit FAIL
        end
    end

    def conditional
        @i += 1
        #@noDef = true
        
        condition = expression
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
            body << statement
        end
        # Check for end?
        # Check for else? else if?

        @i += 1
        #@noDef = false

        If.new condition, Block.new body
    end

    def whileLoop
        @i += 1
        #@noDef = true

        condition = expression
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
            body << statement
        end
        # Check for end?

        @i += 1
        #@noDef = false

        While.new condition, Block.new body
    end

    def define
        if @noDef
           STDERR.puts "Must define function at global scope."
           exit FAIL
        end

        @i += 1
        @noDef = true

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
                        t = VT::Integer
                    else
                        t = VT::Boolean
                    end
                    @i += 1
                else
                    STDERR.puts "Must name parameter types in function definition. #{@i}"
                    exit FAIL
                end

                if curToken.tokenType == TT::Identifier
                    formals << Function::Formal.new curToken.code, t
                    @defVars[curToken.code] = t
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
        @functions[name] = Function.new formals, (Block.new statements), RT::Void

        until curToken.tokenType == TT::End
            if curToken.tokenType == TT::EOF
                STDERR.puts "Expected end after def, not EOF."
                exit FAIL
            end
            statements << statement
        end
        # Check for end? EOF?

        @i += 1
        @noDef = false
        @defVars.clear

        Definition.new name, formals, (Block.new statements), RT::Void
    end

    def assign(id)
        @i += 1
        r = expression

        if r.is_a? IntegerExpression || r.is_a? IntegerVariable
            if @noDef
                @defVars[id.code] = VT::Integer
            else
                @variables[id.code] = VT::Integer
            end

            Assignment.new id.code, VT::Integer, r

        elsif r.is_a? BooleanExpression || r.is_a? BooleanVariable
            if @noDef
                @defVars[id.code] = VT::Boolean
            else
                @variables[id.code] = VT::Boolean
            end

            Assignment.new id.code, VT::Boolean, r

        else
            STDERR.puts "Error in variable assignment: #{@i} #{id.code}"
            exit FAIL
        end
    end

    def call(id)
        actuals = [] of Expression
        numArgs = @functions[id.code].numArgs 
        #s = (numArgs == 1 ? "" : "s")

        if numArgs > 0 
            unless curToken.tokenType == TT::ParenthesisL
                STDERR.puts "Expected () for passing arguments to function."
                exit FAIL
            end
            @i += 1

            j = 0

            loop do
                arg = expression
                t = @functions[id.code].formals[j].type

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

    def expression
        logicalOr
    end

    def logicalOr
        a = logicalAnd
        while curToken.tokenType == TT::Or
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression || a.is_a? BooleanVariable
                operatorRaise operator, a, BooleanExpression, "L"
                # Crystal for some reason doesn't recognize operatorRaise as NoReturn
                # when assigning type to a, b (fixed?)
                exit
            end

            b = logicalAnd

            unless b.is_a? BooleanExpression || b.is_a? BooleanVariable
                operatorRaise operator, b, BooleanExpression, "R"
                exit
            end

            a = Or.new a, b
        end
        a
    end

    def logicalAnd
        a = relational
        while curToken.tokenType == TT::And
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression || a.is_a? BooleanVariable
                operatorRaise operator, a, BooleanExpression, "L"
                exit
            end

            b = relational

            unless b.is_a? BooleanExpression || b.is_a? BooleanVariable
                operatorRaise operator, b, BooleanExpression, "R"
                exit
            end

            a = And.new a, b
        end
        a
    end

    def relational
        a = comparison
        while curToken.tokenType == TT::Equal ||
                curToken.tokenType == TT::NotEqual

            operator = curToken
            @i += 1
            b = comparison
            if operator.tokenType == TT::Equal
                a = Equal.new a, b
            else
                a = NotEqual.new a, b
            end
        end
        a
    end

    def comparison
        a = additive
        while curToken.tokenType == TT::Greater ||
                curToken.tokenType == TT::GreaterOrEqual ||
                curToken.tokenType == TT::LessOrEqual ||
                curToken.tokenType == TT::Less

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression || a.is_a? IntegerVariable
                operatorRaise operator, a, IntegerExpression, "L"
                exit
            end

            b = additive

            unless b.is_a? IntegerExpression || b.is_a? IntegerVariable
                operatorRaise operator, b, IntegerExpression, "R"
                exit
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

    def additive
        a = multiplicative
        while curToken.tokenType == TT::Plus ||
                curToken.tokenType == TT::Minus

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression || a.is_a? IntegerVariable
                operatorRaise operator, a, IntegerExpression, "L"
                exit
            end

            b = multiplicative

            unless b.is_a? IntegerExpression || b.is_a? IntegerVariable
                operatorRaise operator, b, IntegerExpression, "R"
                exit
            end

            if operator.tokenType == TT::Plus
                a = Add.new a, b
            else
                a = Subtract.new a, b
            end
        end
        a
    end

    def multiplicative
        a = unary
        while curToken.tokenType == TT::Star ||
                curToken.tokenType == TT::Slash ||
                curToken.tokenType == TT::Percent

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression || a.is_a? IntegerVariable
                operatorRaise operator, a, IntegerExpression, "L"
                exit
            end

            b = unary

            unless b.is_a? IntegerExpression || b.is_a? IntegerVariable
                operatorRaise operator, b, IntegerExpression, "R"
                exit
            end

            begin
                if operator.tokenType == TT::Star
                    a = Multiply.new a, b
                elsif operator.tokenType == TT::Slash
                    a = Divide.new a, b
                else
                    a = Mod.new a, b
                end
            rescue e
                STDERR.puts "#{@i} #{a} #{e.message}"
                exit FAIL
            end
        end
        a
    end

    def unary
        if curToken.tokenType == TT::Minus
            operator = curToken
            @i += 1
            a = atom

            unless a.is_a? IntegerExpression || a.is_a? IntegerVariable
                operatorRaise operator, a, IntegerExpression
                exit
            end

            Negate.new a
        elsif curToken.tokenType == TT::Bang
            operator = curToken
            @i += 1
            a = atom

            unless a.is_a? BooleanExpression || a.is_a? BooleanVariable
                operatorRaise operator, a, BooleanExpression
                exit
            end

            Not.new a
        else
            atom
        end
    end

    def atom
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

            if !@noDef && @variables.has_key? id.code
                if @variables[id.code].is_a? VT::Integer
                    IntegerVariable.new id.code
                else
                    BooleanVariable.new id.code
                end
            elsif @noDef && @defVars.has_key? id.code 
                if @defVars[id.code].is_a? VT::Integer
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
            e = expression

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
