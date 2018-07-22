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
    end

    property type, value
    getter global

    def initialize(
        @type : VariableType,
        @value : Int32 | Bool,
        @global = false
    ) end
end

# This class is only used in Environment, not as a type of expression
class Function
    enum ReturnType
        Boolean
        Integer
        Void
    end

    # Formals are the formal parameter variables:
    # def function(int formal1, bool formal2) end
    # Used in Definition and Parser::define
    class Formal
        getter name, type

        def initialize(
            @name : String,
            @type : Variable::VariableType
        ) end
    end

    getter formals, body, returnType

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
    def initialize(@statements : Array(Statement)) end

    def evaluate(env : Environment)
        value = 0
        @statements.each do |statement|
            value = statement.evaluate env
        end

        # The last statement in the block is the return value
        value
    end
end

abstract class Statement
    getter line = 0

    abstract def evaluate(env : Environment)
end

class Print < Statement
    def initialize(@message : Expression, @line) end

    def evaluate(env)
        print @message.evaluate env
    end
end

class Println < Print
    def evaluate(env)
        puts @message.evaluate env
    end
end

class Assignment < Statement
    def initialize(
        @name : String,
        @type : Variable::VariableType,
        @expression : Expression,
        @line
    ) end

    def evaluate(env)
        if env.variables.has_key? @name
            env.variables[@name].type = @type
            env.variables[@name].value = @expression.evaluate env
        else
            env.variables[@name] =
                Variable.new(
                    @type,
                    @expression.evaluate env
                )
        end
    end
end

class If < Statement
    def initialize(
        @ifCondition : BooleanExpression,
        @ifBody : Block,
        @elfBodies : Array(Tuple(BooleanExpression, Block)),
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
            # Loop allows for infinite elfs
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

class Definition < Statement
    def initialize(
        @name : String,
        @formals : Array(Function::Formal),
        @body : Block,
        @returnType : Function::ReturnType,
        @line
    ) end

    def evaluate(env)
        if env.level > 1
            STDERR.puts "Line #{@line} -> Must define function at global \
                scope."
            exit 1
        end

        env.functions[@name] = Function.new @formals, @body, @returnType
    end
end

# Function call which returns void
class VoidCall < Statement
    def initialize(@name : String, @actuals : Array(Expression), @line) end

    def evaluate(env)
        func = env.functions[@name]

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
            else
                t = Variable::VariableType::Boolean
            end

            name = func.formals[i].name
            scope.variables[name] = Variable.new t, actual.evaluate env
        end

        func.body.evaluate scope
    end
end

abstract class Expression < Statement end

abstract class IntegerExpression < Expression
    abstract def evaluate(env) : Int32
end

class IntegerVariable < IntegerExpression
    getter name

    def initialize(@name : String, @line) end

    def evaluate(env)
        value = env.variables[@name].value
        unless value.is_a? Int32
            STDERR.puts "Line #{@line} -> Integer variable error."
            exit 1
        end
        value
    end
end

class IntegerCall < Expression
    def initialize(@name : String, @actuals : Array(Expression), @line) end

    def evaluate(env)
        func = env.functions[@name]

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
            else
                t = Variable::VariableType::Boolean
            end

            name = func.formals[i].name
            scope.variables[name] = Variable.new t, actual.evaluate env
        end

        value = func.body.evaluate scope
        unless value.is_a? Int32
            STDERR.puts "IntegerCall return error: #{@name}"
            exit 1
        end

        value
    end
end

class Integer < IntegerExpression
    def initialize(@value : Int32, @line) end

    def evaluate(env)
        @value
    end
end

abstract class ArithmeticOperator < IntegerExpression
    def initialize(@a : IntegerExpression, @line) end
end

abstract class UnaryArithmetic < ArithmeticOperator end

class Negate < UnaryArithmetic
    def evaluate(env)
        -@a.evaluate env
    end
end

abstract class BinaryArithmetic < ArithmeticOperator
    def initialize(@a : IntegerExpression, @b : IntegerExpression, @line) end
end

class Multiply < BinaryArithmetic
    def evaluate(env)
        @a.evaluate(env) * @b.evaluate(env)
    end
end

class Divide < BinaryArithmetic
    def evaluate(env)
        b = @b.evaluate env
        if b == 0
            STDERR.puts "Line #{@line} -> Division by zero not supported."
            exit 1
        end
        @a.evaluate(env) / b
    end
end

class Mod < BinaryArithmetic
    def evaluate(env)
        b = @b.evaluate env
        if b == 0
            STDERR.puts "Line #{@line} -> Modulus zero not supported."
            exit 1
        end
        @a.evaluate(env) % b
    end
end

class Add < BinaryArithmetic
    def evaluate(env)
        @a.evaluate(env) + @b.evaluate(env)
    end
end

class Subtract < BinaryArithmetic
    def evaluate(env)
        @a.evaluate(env) - @b.evaluate(env)
    end
end

abstract class BooleanExpression < Expression
    abstract def evaluate(env) : Bool
end

class BooleanVariable < BooleanExpression
    getter name

    def initialize(@name : String, @line) end

    def evaluate(env)
        value = env.variables[@name].value
        unless value.is_a? Bool
            STDERR.puts "Line #{@line} -> Boolean variable error."
            exit 1
        end
        value
    end
end

class BooleanCall < BooleanExpression
    def initialize(@name : String, @actuals : Array(Expression), @line) end

    def evaluate(env)
        func = env.functions[@name]

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
            else
                t = Variable::VariableType::Boolean
            end

            name = func.formals[i].name
            scope.variables[name] = Variable.new t, actual.evaluate env
        end

        value = func.body.evaluate scope
        unless value.is_a? Bool
            STDERR.puts "BooleanCall return error: #{@name}"
            exit 1
        end

        value
    end
end

class Boolean < BooleanExpression
    def initialize(@value : Bool, @line) end

    def evaluate(env)
        @value
    end
end

class Not < BooleanExpression
    def initialize(@a : BooleanExpression, @line) end

    def evaluate(env)
        !@a.evaluate env
    end
end

abstract class RelationalOperator < BooleanExpression
    def initialize(@a : Expression, @b : Expression, @line) end
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
end

class Greater < ComparisonOperator
    def evaluate(env)
        # No clue why crystal doesn't realize they already are Int32s
        #@a.evaluate(env) > @b.evaluate(env)
        @a.evaluate(env).as(Int32) > @b.evaluate(env).as(Int32)
    end
end

class GreaterOrEqual < ComparisonOperator
    def evaluate(env)
        #@a.evaluate(env) >= @b.evaluate(env)
        @a.evaluate(env).as(Int32) >= @b.evaluate(env).as(Int32)
    end
end

class Less < ComparisonOperator
    def evaluate(env)
        #@a.evaluate(env) < @b.evaluate(env)
        @a.evaluate(env).as(Int32) < @b.evaluate(env).as(Int32)
    end
end

class LessOrEqual < ComparisonOperator
    def evaluate(env)
        #@a.evaluate(env) <= @b.evaluate(env)
        @a.evaluate(env).as(Int32) <= @b.evaluate(env).as(Int32)
    end
end

abstract class LogicalOperator < BooleanExpression
    def initialize(@a : BooleanExpression, @b : BooleanExpression, @line) end
end

class Or < LogicalOperator
    def evaluate(env)
        @a.evaluate(env) || @b.evaluate(env)
    end
end

class And < LogicalOperator
    def evaluate(env)
        @a.evaluate(env) && @b.evaluate(env)
    end
end
