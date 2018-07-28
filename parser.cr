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

    private def curToken(bias = 0)
        @tokens[@i + bias]
    end

    private def operatorError(operator, operand, expected, side="")
        side += ' ' unless side.empty?

        STDERR.puts "#{lineMsg operand}For #{operator.code} #{side}operand: \
            expected #{expected}, not #{operand.class}."
        exit FAIL
    end

    # For error messages
    private def lineMsg(expr)
        "Line #{expr.line} -> "
    end

    # Environment necessary to maintain scope of variables (and perhaps
    # functions in the future)
    def parse(env : Environment)
        statements = [] of Statement
        until curToken.type == TT::EOF
            statements << statement env
        end

        Block.new statements
    end

    private def statement(env)
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
            # Stop if nested in if/while/def etc
            if env.level > 0
                STDERR.puts "#{lineMsg curToken}Must define function at \
                    global scope."
                exit FAIL
            end

            # Function call can see all global variables and all functions
            # including itself, but cannot see previous Environment's
            # nonglobal variables

            # Get global variables
            variables = {} of String => Variable
            env.variables.each do |variable|
                if variable.last.global
                    variables[variable.first] = variable.last
                end
            end

            scope = Environment.new(
                variables,
                env.functions,
                env.level + 1
            )
            define scope
        elsif curToken.type == TT::Identifier
            # Get operator, though it might not actually be an operator
            operator = curToken(1)
            if operator.type == TT::Assign
                assign env
            elsif operator.type == TT::AssignMultiply ||
                    operator.type == TT::AssignDivide ||
                    operator.type == TT::AssignMod ||
                    operator.type == TT::AssignAdd ||
                    operator.type == TT::AssignSubtract

                # *= /= %/ += -=
                arithmeticAssign env
            elsif operator.type == TT::AssignAnd ||
                    operator.type == TT::AssignOr

                # &= |=
                logicalAssign env
            elsif env.functions.has_key?(curToken.code) &&
                    env.functions[curToken.code].returnType == RT::Void

                call env
            else
                # Function which returns non-Void is handled here, in case it
                # is part of a larger expression
                expression env
            end
        else
            expression env
        end
    end

    # if
    private def conditional(env)
        line = curToken.line
        @i += 1

        # Get if condition
        ifCondition = expression env
        unless ifCondition.is_a? BooleanExpression | PlaceholderCall
            STDERR.puts "#{lineMsg ifCondition}Expected BooleanExpression, \
                not #{ifCondition.class}."
            exit FAIL
        end

        ifBody = getBody env, "if", [TT::Elf, TT::Else, TT::End]

        # elf (else if)
        elfBodies = [] of Tuple(BooleanExpression | PlaceholderCall, Block)
        while curToken.type == TT::Elf
            @i += 1
            j = elfBodies.size

            # Get condition
            elfCondition = expression env
            unless elfCondition.is_a? BooleanExpression | PlaceholderCall
                STDERR.puts "#{lineMsg elfCondition}Expected \
                    BooleanExpression, not #{elfCondition.class}."
                exit FAIL
            end

            elfBody = getBody env, "elf", [TT::Elf, TT::Else, TT::End]
            elfBodies << {elfCondition, Block.new(elfBody)}
        end

        # else
        elseBody = [] of Statement
        if curToken.type == TT::Else
            @i += 1
            elseBody = getBody env, "else"
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

    private def whileLoop(env)
        line = curToken.line
        @i += 1

        # Get condition
        condition = expression env
        unless condition.is_a? BooleanExpression | PlaceholderCall
            STDERR.puts "#{lineMsg condition}Expected BooleanExpression, \
                not #{condition.class}."
            exit FAIL
        end

        body = getBody env, "while"

        # end
        @i += 1

        While.new condition, Block.new(body), line
    end

    private def define(env)
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

        # Add function to environment. Body not necessary because parser only
        # checks whether function exists.
        body = [] of Statement
        env.functions[name] = Function.new(
            formals,
            Block.new(body),

            # Placeholder function bypasses all type checks
            RT::Placeholder
        )
        checkpoint = @i

        # Get statements, type checking turned off for calls to self
        body = getBody env, "def"

        # Go back
        @i = checkpoint

        returnType = getReturnType body
        env.functions[name].returnType = returnType

        # Get statements again, type checking turned back on since returnType
        # of self is known
        body = getBody env, "def"

        # end
        @i += 1

        Definition.new name, formals, Block.new(body), returnType, line
    end

    # Called by define
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

    # Called by conditional, whileLoop, define
    private def getBody(env, source, boundaries = [TT::End])
        body = [] of Statement
        until boundaries.includes? curToken.type
            if curToken.type == TT::EOF
                STDERR.puts "#{lineMsg curToken}Expected end after \
                    #{source}, not EOF."
                exit FAIL
            end
            body << statement env
        end
        body
    end

    # Called by define
    # Return type is type of last statement. If last statement is if, all
    # bodies must match return type, else error. Call to self is
    # PlaceholderCall and matches any return type.
    private def getReturnType(body)
        if body.empty?
            RT::Void
        elsif body[-1].is_a? PlaceholderCall
            RT::Placeholder
        elsif body[-1].is_a? IntegerExpression
            RT::Integer
        elsif body[-1].is_a? BooleanExpression
            RT::Boolean
        elsif body[-1].is_a? If
            # Cast because it's an Array of Statement
            ifStatement = body[-1].as If

            ifRT = getReturnType ifStatement.ifBody.statements

            elfRTs = [] of RT
            ifStatement.elfBodies.each do |elfBody|
                elfRTs << getReturnType elfBody.last.statements
            end

            elseRT = getReturnType ifStatement.elseBody.statements

            # RT::match returns whether return types are equal or one is
            # Placeholder
            match = ifRT.match elseRT
            if match
                # Check if elfRTs match too, until one doesn't match
                i = 0
                while match && i < elfRTs.size
                    # Check both if and else in case one is Placeholder
                    match &= elfRTs[i].match(ifRT) && elfRTs[i].match(elseRT)
                    i += 1
                end

                if match
                    # Don't return the Placeholder
                    if ifRT != RT::Placeholder
                        ifRT
                    elsif elseRT != RT::Placeholder
                        elseRT
                    else
                        # if and else bodies return Placeholders, so return
                        # the first elf that is not a Placeholder
                        value = RT::Placeholder
                        i = 0
                        while value == RT::Placeholder && i < elfRTs.size
                            value = elfRTs[i]
                        end

                        # If they're all Placeholders, error
                        if value == RT::Placeholder
                            expr = ifStatement.elseBody.statements[-1]
                            STDERR.puts "#{lineMsg expr}Cannot determine\
                                return type"
                            exit FAIL
                        end

                        value
                    end
                else
                    expr = ifStatement.elfBodies[i - 1].last.statements[-1]
                    STDERR.puts "#{lineMsg expr}Cannot determine return type"
                    exit FAIL
                end
            else
                if ifStatement.elseBody.statements.empty?
                    # elseBody is empty because it's literally empty, or there
                    # is no else (returns Void)
                    expr = ifStatement.ifBody.statements[-1]
                else
                    # Else return type doesn't match
                    expr = ifStatement.elseBody.statements[-1]
                end

                STDERR.puts "#{lineMsg expr}Cannot determine return type"
                exit FAIL
            end
        else
            RT::Void
        end
    end

    private def assign(env)
        id = curToken
        @i += 1

        # = sign
        @i += 1

        # Right side of =
        r = expression env

        if r.is_a? IntegerExpression | PlaceholderCall
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

    private def arithmeticAssign(env)
        # Let atom get variable because BinaryArithmetic takes in two
        # IntegerExpressions
        l = atom env

        operator = curToken
        @i += 1

        unless l.is_a? IntegerVariable
            operatorError operator, l, IntegerVariable, "L"
        end

        r = expression env

        unless r.is_a? IntegerExpression | PlaceholderCall
            operatorError operator, r, IntegerExpression, "R"
        end

        type = VT::Integer
        if operator.type == TT::AssignMultiply
            r = Multiply.new l, r, l.line
        elsif operator.type == TT::AssignDivide
            r = Divide.new l, r, l.line
        elsif operator.type == TT::AssignMod
            r = Mod.new l, r, l.line
        elsif operator.type == TT::AssignAdd
            r = Add.new l, r, l.line
        else
            r = Subtract.new l, r, l.line
        end

        Assignment.new l.name, type, r, l.line
    end

    private def logicalAssign(env)
        l = atom env

        operator = curToken
        @i += 1

        unless l.is_a? BooleanVariable
            operatorError operator, l, BooleanVariable, "L"
        end

        r = expression env

        unless r.is_a? BooleanExpression | PlaceholderCall
            operatorError operator, r, BooleanExpression, "R"
        end

        type = VT::Boolean
        if operator.type == TT::AssignAnd
            r = And.new l, r, l.line
        else
            r = Or.new l, r, l.line
        end

        Assignment.new l.name, type, And.new(l, r, l.line), l.line
    end

    # Function call
    private def call(env)
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

        if env.functions[id.code].returnType == RT::Placeholder
            PlaceholderCall.new
        elsif env.functions[id.code].returnType == RT::Integer
            IntegerCall.new id.code, actuals, id.line
        elsif env.functions[id.code].returnType == RT::Boolean
            BooleanCall.new id.code, actuals, id.line
        else
            VoidCall.new id.code, actuals, id.line
        end
    end

    private def getActuals(env, id)
        actuals = [] of Expression

        numArgs = env.functions[id.code].numArgs
        #s = (numArgs == 1 ? "" : "s")  # Singular/plural?

        loop do
            # Ensure expression type matches formal type
            arg = expression env
            type = env.functions[id.code].formals[actuals.size].type

            if (type.match arg)
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

    private def expression(env)
        logicalOr env
    end

    private def logicalOr(env)
        # Get left side
        a = logicalAnd env
        while curToken.type == TT::Or
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression | PlaceholderCall
                operatorError operator, a, BooleanExpression, "L"
            end

            # Get right side
            b = logicalAnd env

            unless b.is_a? BooleanExpression | PlaceholderCall
                operatorError operator, b, BooleanExpression, "R"
            end

            a = Or.new a, b, a.line
        end
        a
    end

    private def logicalAnd(env)
        a = relational env
        while curToken.type == TT::And
            operator = curToken
            @i += 1

            unless a.is_a? BooleanExpression | PlaceholderCall
                operatorError operator, a, BooleanExpression, "L"
            end

            b = relational env

            unless b.is_a? BooleanExpression | PlaceholderCall
                operatorError operator, b, BooleanExpression, "R"
            end

            a = And.new a, b, a.line
        end
        a
    end

    private def relational(env)
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

    private def comparison(env)
        a = additive env
        while curToken.type == TT::Greater ||
                curToken.type == TT::GreaterOrEqual ||
                curToken.type == TT::LessOrEqual ||
                curToken.type == TT::Less

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, a, IntegerExpression, "L"
            end

            b = additive env

            unless b.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, b, IntegerExpression, "R"
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

    private def additive(env)
        a = multiplicative env
        while curToken.type == TT::Plus ||
                curToken.type == TT::Minus

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, a, IntegerExpression, "L"
            end

            b = multiplicative env

            unless b.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, b, IntegerExpression, "R"
            end

            if operator.type == TT::Plus
                a = Add.new a, b, a.line
            else
                a = Subtract.new a, b, a.line
            end
        end
        a
    end

    private def multiplicative(env)
        a = unary env
        while curToken.type == TT::Star ||
                curToken.type == TT::Slash ||
                curToken.type == TT::Percent

            operator = curToken
            @i += 1

            unless a.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, a, IntegerExpression, "L"
            end

            b = unary env

            unless b.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, b, IntegerExpression, "R"
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

    private def unary(env)
        if curToken.type == TT::Minus
            operator = curToken
            @i += 1
            a = atom env

            unless a.is_a? IntegerExpression | PlaceholderCall
                operatorError operator, a, IntegerExpression
            end

            Negate.new a, a.line
        elsif curToken.type == TT::Bang
            operator = curToken
            @i += 1
            a = atom env

            unless a.is_a? BooleanExpression | PlaceholderCall
                operatorError operator, a, BooleanExpression
            end

            Not.new a, a.line
        else
            atom env
        end
    end

    private def atom(env)
        if curToken.type == TT::Integer
            # Integer literal
            int = Integer.new curToken.code.to_i, curToken.line
            @i += 1
            int
        elsif curToken.type == TT::Boolean
            # Boolean literal
            bool = Boolean.new (curToken.code == "true"), curToken.line
            @i += 1
            bool
        elsif curToken.type == TT::Identifier
            id = curToken

            if env.variables.has_key? id.code
                @i += 1
                if env.variables[id.code].type.is_a? VT::Integer
                    IntegerVariable.new id.code, id.line
                else
                    BooleanVariable.new id.code, id.line
                end
            elsif env.functions.has_key? id.code
                value = call env

                if value.is_a? VoidCall
                    STDERR.puts "#{lineMsg id}Expected expression, not \
                        #{value.class}"
                    exit FAIL
                end
                value
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
