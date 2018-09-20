class Environment
    getter variables, functions, level

    def initialize(
        @variables = {} of String => Variable,
        @functions = {} of String => Function,
        @level = 0
    ) end
end

# This class is only used in Environment, not as a type of expression
class Variable
    enum VariableType
        Boolean
        Integer
        BooleanArray
        IntegerArray

        def match(expr : Expression | PlaceholderCall)
            expr.is_a? PlaceholderCall ||
                (self == Boolean && expr.is_a? BooleanExpression) ||
                (self == Integer && expr.is_a? IntegerExpression) ||
                (self == BooleanArray && expr.is_a? BooleanArray) ||
                (self == IntegerArray && expr.is_a? IntegerArray)
        end
    end

    property type, value
    getter global

    def initialize(
        @type : VariableType,
        @value : Int32 | Bool | Array(Int32) | Array(Bool),
        @global = false
    ) end

    # For deep copy in cli.cr
    def clone
        Variable.new @type, @value, @global
    end
end

# This class is only used in Environment, not as a type of expression
class Function
    enum ReturnType
        Boolean
        Integer
        BooleanArray
        IntegerArray
        Void
        Placeholder

        def match(other : ReturnType)
            self == Placeholder ||
                other == Placeholder ||
                self == other
        end
    end

    # Formals are the formal parameter variables:
    # def function(int formal1, bool formal2) end
    # Used in Definition and Parser::define
    class Formal
        getter id, type

        def initialize(
            @id : String,
            @type : Variable::VariableType
        ) end
    end

    property returnType
    getter formals, body

    def initialize(
        @formals : Array(Formal),
        @body : Block,
        @returnType : ReturnType
    ) end

    def numArgs
        formals.size
    end
end

# Block is Array of Statements. Used in If, While, Definition, Parser::define,
# and to collect the entire program
class Block
    getter statements

    def initialize(@statements : Array(Statement | PlaceholderCall)) end

    def evaluate(env : Environment)
        value = 0
        @statements.each do |statement|
            unless statement.is_a? Statement
                STDERR.puts "Line #{statement.line} -> PlaceholderCall \
                    evaluated"
                exit 1
            end
            value = statement.evaluate env
        end

        # The last statement in the block is the return value
        value
    end
end

# Statement may return Void
abstract class Statement
    getter line = 0

    abstract def evaluate(env : Environment)
end

class Print < Statement
    def initialize(@message : Expression, @line) end

    def initialize(@message : Expression | PlaceholderCall, @line)
        unless @message.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end

    def evaluate(env)
        print @message.evaluate env
    end
end

class Println < Print
    def evaluate(env)
        puts @message.evaluate env
    end
end

class If < Statement
    getter ifBody, elfBodies, elseBody

    def initialize(
        @ifCondition : BooleanExpression,
        @ifBody : Block,
        @elfBodies : Array(Tuple(BooleanExpression, Block)),
        @elseBody : Block,
        @line
    ) end

    def initialize(
        @ifCondition : BooleanExpression | PlaceholderCall,
        @ifBody : Block,
        @elfBodies : Array(
            Tuple(BooleanExpression | PlaceholderCall, Block)
        ),
        @elseBody : Block,
        @line
    ) end

    def evaluate(env)
        # Variables changed in if are changed in outer scope, too. New
        # variables in if go away at end.
        scope = Environment.new(
            env.variables.dup,
            env.functions,
            env.level + 1
        )
        if @ifCondition.evaluate scope
            value = @ifBody.evaluate scope
        else
            # Loop allows for infinite elfs, or 0
            done = false
            i = 0
            value = 0
            while !done && i < @elfBodies.size
                # first is condition
                done = @elfBodies[i].first.evaluate scope
                if done
                    # last is body
                    value = @elfBodies[i].last.evaluate scope
                end
                i += 1
            end

            if !done
                # All conditions are false, so evaluate else body. If no else,
                # elseBody is empty and nothing happens.
                value = @elseBody.evaluate scope
            end
        end
        value
    end
end

class While < Statement
    def initialize(
        @condition : BooleanExpression,
        @body : Block,
        @line
    ) end

    def initialize(
        @condition : BooleanExpression | PlaceholderCall,
        @body : Block,
        @line
    )
        unless @condition.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end

    def evaluate(env)
        # Scope same as if
        scope = Environment.new(
            env.variables.dup,
            env.functions,
            env.level + 1
        )
        while @condition.evaluate scope
            @body.evaluate scope
        end
    end
end

class Assignment < Statement
    def initialize(
        @id : String,
        @type : Variable::VariableType,
        @expression : Expression,
        @line
    ) end

    def initialize(
        @id : String,
        @type : Variable::VariableType,
        @expression : Expression | PlaceholderCall,
        @line
    )
        unless @expression.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end

    def evaluate(env)
        if env.variables.has_key? @id
            # Reusing key so changes apply to parent Environments
            env.variables[@id].type = @type
            env.variables[@id].value = @expression.evaluate env
        else
            # New variable
            env.variables[@id] = Variable.new(
                @type,
                @expression.evaluate env
            )
        end
        return
    end
end

class Definition < Statement
    def initialize(
        @id : String,
        @formals : Array(Function::Formal),
        @body : Block,
        @returnType : Function::ReturnType,
        @line
    ) end

    def evaluate(env)
        if env.level > 1
            STDERR.puts "Line #{@line} -> Must define function at global \
                scope"
            exit 1
        end

        env.functions[@id] = Function.new @formals, @body, @returnType
        return
    end
end

# Function call which returns void
class VoidCall < Statement
    def initialize(
        @id : String,
        @actuals : Array(Expression | PlaceholderCall),
        @line
    ) end

    def evaluate(env)
        func = env.functions[@id]

        unless func.returnType == Function::ReturnType::Void
            STDERR.puts "VoidCall error"
            exit 1
        end

        # Function call can see all global variables and all functions
        # including itself, but cannot see previous Environment's nonglobal
        # variables

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
        # Give formal parameters actual values
        @actuals.each_with_index do |actual, i|
            if actual.is_a? IntegerExpression
                t = Variable::VariableType::Integer
            elsif actual.is_a? BooleanExpression
                t = Variable::VariableType::Boolean
            elsif actual.is_a? IntegerArray
                t = Variable::VariableType::IntegerArray
            elsif actual.is_a? BooleanArray
                t = Variable::VariableType::BooleanArray
            else
                STDERR.puts "Actual type error"
                exit 1
            end

            id = func.formals[i].id
            scope.variables[id] = Variable.new t, actual.evaluate env
        end

        func.body.evaluate scope
        return
    end
end

# Expression returns non-Void
abstract class Expression < Statement
    getter parenthesized = false

    def parenthesize
        @parenthesized = true
        return
    end
end

# PlaceholderCall is used in first parse of function definition in order to
# determine function return type. It satisfies all type checks. During first 
# parse while self's return type is unknown, calls to self are marked with 
# PlaceholderCall so parsing can bypass type checks. Following this parse, the
# function's return type is known, and the definition is parsed a second time,
# this time checking the types to ensure calls to self satisfy operators,
# function calls etc.
class PlaceholderCall
    getter line
    getter parenthesized = false

    def initialize(@line : Int32) end

    def evaluate(env, n = 0)
        if n > 0
            50
        else
            false
        end
    end

    def parenthesize
        @parenthesized = true
        return
    end
end

abstract class IntegerExpression < Expression
    abstract def evaluate(env) : Int32
end

class IntegerVariable < IntegerExpression
    getter id

    def initialize(@id : String, @line) end

    def evaluate(env)
        value = env.variables[@id].value
        unless value.is_a? Int32
            STDERR.puts "Line #{@line} -> Integer variable error"
            exit 1
        end
        value
    end
end

# Function call which returns Integer
class IntegerCall < IntegerExpression
    def initialize(
        @id : String,
        @actuals : Array(Expression | PlaceholderCall),
        @line
    ) end

    def evaluate(env)
        func = env.functions[@id]

        unless func.returnType == Function::ReturnType::Integer
            STDERR.puts "IntegerCall error"
            exit 1
        end

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
        @actuals.each_with_index do |actual, i|
            if actual.is_a? IntegerExpression
                t = Variable::VariableType::Integer
            elsif actual.is_a? BooleanExpression
                t = Variable::VariableType::Boolean
            elsif actual.is_a? IntegerArray
                t = Variable::VariableType::IntegerArray
            elsif actual.is_a? BooleanArray
                t = Variable::VariableType::BooleanArray
            else
                STDERR.puts "Actual type error"
                exit 1
            end

            id = func.formals[i].id
            scope.variables[id] = Variable.new t, actual.evaluate env
        end

        value = func.body.evaluate scope
        unless value.is_a? Int32
            STDERR.puts "IntegerCall return error: #{@id}"
            exit 1
        end

        value
    end
end

# Integer literal
class Integer < IntegerExpression
    def initialize(@value : Int32, @line) end

    def evaluate(env)
        @value
    end
end

# Operator which takes one or more Integers
abstract class ArithmeticOperator < IntegerExpression
    def initialize(@a : IntegerExpression, @line) end

    # Constructor to satisfy PlaceholderCall. Should never be evaluated
    def initialize(@a : IntegerExpression | PlaceholderCall, @line)
        unless @a.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end
end

abstract class UnaryArithmetic < ArithmeticOperator end

class Negate < UnaryArithmetic
    def evaluate(env)
        # Cast to satisfy (impossible) possibility of PlaceholderCall. Many
        # similar casts to follow
        a = @a.evaluate(env).as Int32
        -a
    end
end

abstract class BinaryArithmetic < ArithmeticOperator
    def initialize(@a : IntegerExpression, @b : IntegerExpression, @line) end

    def initialize(
        @a : IntegerExpression | PlaceholderCall,
        @b : IntegerExpression | PlaceholderCall,
        @line
    )
        unless @a.is_a? PlaceholderCall || @b.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end
end

class Multiply < BinaryArithmetic
    def evaluate(env)
        a = @a.evaluate(env).as Int32
        b = @b.evaluate(env).as Int32
        a * b
    end
end

class Divide < BinaryArithmetic
    def evaluate(env)
        a = @a.evaluate(env).as Int32
        b = @b.evaluate(env).as Int32

        if b == 0
            STDERR.puts "Line #{@line} -> Division by zero not supported"
            exit 1
        end
        a / b
    end
end

class Mod < BinaryArithmetic
    def evaluate(env)
        a = @a.evaluate(env).as Int32
        b = @b.evaluate(env).as Int32

        if b == 0
            STDERR.puts "Line #{@line} -> Modulus zero not supported"
            exit 1
        end
        a % b
    end
end

class Add < BinaryArithmetic
    def evaluate(env)
        a = @a.evaluate(env).as Int32
        b = @b.evaluate(env).as Int32
        a + b
    end
end

class Subtract < BinaryArithmetic
    def evaluate(env)
        a = @a.evaluate(env).as Int32
        b = @b.evaluate(env).as Int32
        a - b
    end
end

abstract class BooleanExpression < Expression
    abstract def evaluate(env) : Bool
end

class BooleanVariable < BooleanExpression
    getter id

    def initialize(@id : String, @line) end

    def evaluate(env)
        value = env.variables[@id].value
        unless value.is_a? Bool
            STDERR.puts "Line #{@line} -> Boolean variable error"
            exit 1
        end
        value
    end
end

# Function call which returns Boolean
class BooleanCall < BooleanExpression
    def initialize(
        @id : String,
        @actuals : Array(Expression | PlaceholderCall),
        @line
    ) end

    def evaluate(env)
        func = env.functions[@id]

        unless func.returnType == Function::ReturnType::Boolean
            STDERR.puts "BooleanCall error"
            exit 1
        end

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
        @actuals.each_with_index do |actual, i|
            if actual.is_a? IntegerExpression
                t = Variable::VariableType::Integer
            elsif actual.is_a? BooleanExpression
                t = Variable::VariableType::Boolean
            elsif actual.is_a? IntegerArray
                t = Variable::VariableType::IntegerArray
            elsif actual.is_a? BooleanArray
                t = Variable::VariableType::BooleanArray
            else
                STDERR.puts "Actual type error"
                exit 1
            end

            id = func.formals[i].id
            scope.variables[id] = Variable.new t, actual.evaluate env
        end

        value = func.body.evaluate scope
        unless value.is_a? Bool
            STDERR.puts "BooleanCall return error: #{@id}"
            exit 1
        end

        value
    end
end

# Boolean literal
class Boolean < BooleanExpression
    def initialize(@value : Bool, @line) end

    def evaluate(env)
        @value
    end
end

class Not < BooleanExpression
    def initialize(@a : BooleanExpression, @line) end

    def initialize(@a : Expression | PlaceholderCall, @line)
        unless @a.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end

    def evaluate(env)
        !@a.evaluate env
    end
end

abstract class RelationalOperator < BooleanExpression
    def initialize(@a : Expression, @b : Expression, @line) end

    def initialize(
        @a : Statement | PlaceholderCall,
        @b : Statement | PlaceholderCall,
        @line
    )
        unless @a.is_a? PlaceholderCall || @b.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end
end

class Equal < RelationalOperator
    def evaluate(env)
        @a.evaluate(env) == @b.evaluate(env)
    end
end

class NotEqual < RelationalOperator
    def evaluate(env)
        @a.evaluate(env) != @b.evaluate(env)
    end
end

abstract class ComparisonOperator < RelationalOperator
    def initialize(@a : IntegerExpression, @b : IntegerExpression, @line) end

    def initialize(
        @a : Expression | PlaceholderCall,
        @b : Expression | PlaceholderCall,
        @line
    )
        unless @a.is_a? PlaceholderCall || @b.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end
end

class Greater < ComparisonOperator
    def evaluate(env)
        @a.evaluate(env).as(Int32) > @b.evaluate(env).as(Int32)
    end
end

class GreaterOrEqual < ComparisonOperator
    def evaluate(env)
        @a.evaluate(env).as(Int32) >= @b.evaluate(env).as(Int32)
    end
end

class Less < ComparisonOperator
    def evaluate(env)
        @a.evaluate(env).as(Int32) < @b.evaluate(env).as(Int32)
    end
end

class LessOrEqual < ComparisonOperator
    def evaluate(env)
        @a.evaluate(env).as(Int32) <= @b.evaluate(env).as(Int32)
    end
end

abstract class LogicalOperator < BooleanExpression
    def initialize(@a : BooleanExpression, @b : BooleanExpression, @line) end

    def initialize(
        @a : BooleanExpression | PlaceholderCall,
        @b : BooleanExpression | PlaceholderCall,
        @line
    )
        unless @a.is_a? PlaceholderCall || @b.is_a? PlaceholderCall
            STDERR.puts "Line #{@line} -> Placeholder error"
            exit 1
        end
    end
end

class Or < LogicalOperator
    def evaluate(env)
        value = @a.evaluate(env) || @b.evaluate(env)
        unless value.is_a? Bool
            STDERR.puts "Line #{@a.line} -> Or return type error"
            exit 1
        end
        value
    end
end

class And < LogicalOperator
    def evaluate(env)
        value = @a.evaluate(env) && @b.evaluate(env)
        unless value.is_a? Bool
            STDERR.puts "Line #{@a.line} -> Or return type error"
            exit 1
        end
        value
    end
end

abstract class ArrayExpression < Expression
end

abstract class IntegerArray < ArrayExpression
end

abstract class BooleanArray < ArrayExpression
end

class IntegerArrayLiteral < IntegerArray
    def initialize(@array : Array(IntegerExpression), @line) end

    def evaluate(env)
        value = [] of Int32
        @array.each do |element|
            value << element.evaluate env
        end
        value
    end
end

class BooleanArrayLiteral < BooleanArray
    def initialize(@array : Array(BooleanExpression), @line) end

    def evaluate(env)
        value = [] of Bool
        @array.each do |element|
            value << element.evaluate env
        end
        value
    end
end

class IntegerArrayVariable < IntegerArray
    getter id

    def initialize(@id : String, @line) end

    def evaluate(env)
        value = env.variables[@id].value
        unless value.is_a? Array(Int32)
            STDERR.puts "Line #{@line} -> IntegerArray variable error"
            exit 1
        end
        value
    end
end

class BooleanArrayVariable < BooleanArray
    getter id

    def initialize(@id : String, @line) end

    def evaluate(env)
        value = env.variables[@id].value
        unless value.is_a? Array(Bool)
            STDERR.puts "Line #{@line} -> BooleanArray variable error"
            exit 1
        end
        value
    end
end

class IntegerArrayCall < IntegerArray
    def initialize(
        @id : String,
        @actuals : Array(Expression | PlaceholderCall),
        @line
    ) end

    def evaluate(env)
        func = env.functions[@id]

        unless func.returnType == Function::ReturnType::IntegerArray
            STDERR.puts "IntegerArrayCall error"
            exit 1
        end

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
        @actuals.each_with_index do |actual, i|
            if actual.is_a? IntegerExpression
                t = Variable::VariableType::Integer
            elsif actual.is_a? BooleanExpression
                t = Variable::VariableType::Boolean
            elsif actual.is_a? IntegerArray
                t = Variable::VariableType::IntegerArray
            elsif actual.is_a? BooleanArray
                t = Variable::VariableType::BooleanArray
            else
                STDERR.puts "Actual type error"
                exit 1
            end

            id = func.formals[i].id
            scope.variables[id] = Variable.new t, actual.evaluate env
        end

        value = func.body.evaluate scope
        unless value.is_a? Array(Int32)
            STDERR.puts "IntegerArrayCall return error: #{@id}"
            exit 1
        end

        value
    end
end

class BooleanArrayCall < BooleanArray
    def initialize(
        @id : String,
        @actuals : Array(Expression | PlaceholderCall),
        @line
    ) end

    def evaluate(env)
        func = env.functions[@id]

        unless func.returnType == Function::ReturnType::BooleanArray
            STDERR.puts "BooleanArrayCall error"
            exit 1
        end

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
        @actuals.each_with_index do |actual, i|
            if actual.is_a? IntegerExpression
                t = Variable::VariableType::Integer
            elsif actual.is_a? BooleanExpression
                t = Variable::VariableType::Boolean
            elsif actual.is_a? IntegerArray
                t = Variable::VariableType::IntegerArray
            elsif actual.is_a? BooleanArray
                t = Variable::VariableType::BooleanArray
            else
                STDERR.puts "Actual type error"
                exit 1
            end

            id = func.formals[i].id
            scope.variables[id] = Variable.new t, actual.evaluate env
        end

        value = func.body.evaluate scope
        unless value.is_a? Array(Bool)
            STDERR.puts "BooleanArrayCall return error: #{@id}"
            exit 1
        end

        value
    end
end
