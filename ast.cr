class Environment
    getter variables, functions, level

    def initialize(
        @variables = {} of String => Variable,
        @functions = {} of String => Function,
        @level = 0
    ) end
end

class Variable
    enum VariableType
        Boolean
        Integer
    end

    property type, value

    def initialize(@type : VariableType, @value : Int32 | Bool) end
end

class Function
    enum ReturnType
        Boolean
        Integer
        Void
    end

    class Formal
        getter name, type

        def initialize(
            @name : String,
            @type : Variable::VariableType
        ) end
    end

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

class Block
    def initialize(@statements : Array(Statement)) end

    def evaluate(env : Environment)
        @statements.each do |statement|
            statement.evaluate(env)
        end
    end
end

abstract class Statement
    abstract def evaluate(env : Environment)
end

class Print < Statement
    def initialize(@message : Expression) end

    def evaluate(env)
        print @message.evaluate(env)
    end
end

class Println < Print
    def evaluate(env)
        puts @message.evaluate(env)
    end
end

class Assignment < Statement
    def initialize(
        @name : String,
        @type : Variable::VariableType,
        @expression : Expression
    ) end

    def evaluate(env)
        env.variables[@name] =
            Variable.new(
                @type,
                @expression.evaluate(env)
            )
    end
end

class If < Statement
    def initialize(
        @condition : BooleanExpression,
        @body : Block
    ) end

    def evaluate(env)
        if @condition.evaluate(env)
            @body.evaluate(env)
        end
    end
end

class While < Statement
    def initialize(
        @condition : BooleanExpression,
        @body : Block
    ) end

    def evaluate(env)
        while @condition.evaluate(env)
            @body.evaluate(env)
        end
    end
end

class Definition < Statement
    def initialize(
        @name : String,
        @formals : Array(Function::Formal),
        @body : Block,
        @returnType : Function::ReturnType
    ) end

    def evaluate(env)
        env.functions[@name] = Function.new(@formals, @body, @returnType)
    end
end

class Call < Statement
    def initialize(@name : String, @actuals : Array(Expression)) end

    def evaluate(env)
        func = env.functions[@name]

        scope = Environment.new(
            {} of String => Variable,
            env.functions
        )

        @actuals.each_with_index do |actual, i|
            if actual.is_a? IntegerExpression
                t = Variable::VariableType::Integer
            else
                t = Variable::VariableType::Boolean
            end

            name = func.formals[i].name
            scope.variables[name] = Variable.new(t, actual.evaluate env)
        end

        func.body.evaluate scope
    end
end

abstract class Expression
    abstract def evaluate(env : Environment)
end

abstract class IntegerExpression < Expression
    abstract def evaluate(env) : Int32
end

class IntegerVariable < IntegerExpression
    def initialize(@name : String) end

    def evaluate(env)
        value = env.variables[@name].value
        unless value.is_a? Int32
            raise "Integer variable error."
        end
        value
    end
end

class Integer < IntegerExpression
    def initialize(@value : Int32) end

    def evaluate(env)
        @value
    end
end

abstract class ArithmeticOperator < IntegerExpression
    def initialize(@a : IntegerExpression) end
end

abstract class UnaryArithmetic < ArithmeticOperator end

class Negate < UnaryArithmetic
    def evaluate(env)
        -@a.evaluate(env)
    end
end

abstract class BinaryArithmetic < ArithmeticOperator
    def initialize(@a : IntegerExpression, @b : IntegerExpression) end
end

class Multiply < BinaryArithmetic
    def evaluate(env)
        @a.evaluate(env) * @b.evaluate(env)
    end
end

class Divide < BinaryArithmetic
    def initialize(@a : IntegerExpression, @b : IntegerExpression) end

    def evaluate(env)
        b = @b.evaluate(env)
        if b == 0
            STDERR.puts "Division by zero not supported."
            exit FAIL
        end
        @a.evaluate(env) / b
    end
end

class Mod < BinaryArithmetic
    def initialize(@a : IntegerExpression, @b : IntegerExpression) end

    def evaluate(env)
        b = @b.evaluate(env)
        if b == 0
            STDERR.puts "Modulus zero not supported."
            exit FAIL
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
    def initialize(@name : String) end

    def evaluate(env)
        value = env.variables[@name].value
        unless value.is_a? Bool
            raise "Boolean variable error."
        end
        value
    end
end

class Boolean < BooleanExpression
    def initialize(@value : Bool) end

    def evaluate(env)
        @value
    end
end

class Not < BooleanExpression
    def initialize(@a : BooleanExpression) end

    def evaluate(env)
        !@a.evaluate(env)
    end
end

abstract class RelationalOperator < BooleanExpression
    def initialize(@a : Expression, @b : Expression) end
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
    def initialize(@a : IntegerExpression, @b : IntegerExpression) end
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
    def initialize(@a : BooleanExpression, @b : BooleanExpression) end
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
