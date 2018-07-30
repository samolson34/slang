class Token
    enum TokenType
        And
        Assign
        AssignAdd
        AssignAnd
        AssignDivide
        AssignMod
        AssignMultiply
        AssignOr
        AssignSubtract
        Bang
        Boolean
        Comma
        Define
        EOF
        Elf
        Else
        End
        Equal
        Greater
        GreaterOrEqual
        Identifier
        If
        Integer
        Less
        LessOrEqual
        Minus
        NotEqual
        Or
        ParenthesisL
        ParenthesisR
        Percent
        Plus
        Print
        Println
        Slash
        Star
        Type
        While
    end

    getter type, code, line

    def initialize(
        @type : TokenType,
        @code : String,

        # Track line number for error messages
        @line : Int32
    ) end
end

# Usage:
# lexer = Lexer.new file
# tokens = lexer.lex
class Lexer
    private alias TT = Token::TokenType

    # For exit status
    FAIL = 1

    @tokens = [] of Token
    @token = ""

    # Character index in file
    @i = 0

    # Line number in file
    @line = 1

    @src : String

    def initialize(file)
        @src = file.gets_to_end.chomp
    end

    private def take
        @token += curChar
        @i += 1
    end

    private def append(type)
        @tokens << Token.new type, @token, @line
        @token = ""
    end

    private def curChar
        @src[@i]
    end

    # For error messages
    private def lineMsg
        "Line #{@line} -> "
    end

    def lex
        while @i < @src.size

            # Comment
            if curChar == '#'
                while @i < @src.size && curChar != '\n'
                    @i += 1
                end
                token = ""

            # Parentheses
            elsif curChar == '('
                take
                append TT::ParenthesisL
            elsif curChar == ')'
                take
                append TT::ParenthesisR

            # Star
            elsif curChar == '*'
                take
                if curChar == '='
                    take
                    append TT::AssignMultiply
                else
                    append TT::Star
                end

            # Slash
            elsif curChar == '/'
                take
                if curChar == '='
                    take
                    append TT::AssignDivide
                else
                    append TT::Slash
                end

            # Percent
            elsif curChar == '%'
                take
                if curChar == '='
                    take
                    append TT::AssignMod
                else
                    append TT::Percent
                end

            # Plus
            elsif curChar == '+'
                take
                if curChar == '='
                    take
                    append TT::AssignAdd
                else
                    append TT::Plus
                end

            # Minus
            elsif curChar == '-'
                take
                if curChar == '='
                    take
                    append TT::AssignSubtract
                else
                    append TT::Minus
                end

            # Equal
            elsif curChar == '='
                take
                if curChar == '='
                    take
                    append TT::Equal
                else
                    append TT::Assign
                end

            # Bang
            elsif curChar == '!'
                take
                if curChar == '='
                    take
                    append TT::NotEqual
                else
                    append TT::Bang
                end

            # Greater
            elsif curChar == '>'
                take
                if curChar == '='
                    take
                    append TT::GreaterOrEqual
                else
                    append TT::Greater
                end

            # Less
            elsif curChar == '<'
                take
                if curChar == '='
                    take
                    append TT::LessOrEqual
                else
                    append TT::Less
                end

            # Or
            elsif curChar == '|'
                take
                if curChar == '|'
                    take
                    append TT::Or
                elsif curChar == '='
                    take
                    append TT::AssignOr
                else
                    STDERR.puts "#{lineMsg}Bitwise operations not supported"
                    exit FAIL
                end

            # And
            elsif curChar == '&'
                take
                if curChar == '&'
                    take
                    append TT::And
                elsif curChar == '='
                    take
                    append TT::AssignAnd
                else
                    STDERR.puts "#{lineMsg}Bitwise operations not supported"
                    exit FAIL
                end

            # Comma
            elsif curChar == ','
                take
                append TT::Comma

            # Number
            # Only ASCII numbers recognized as integers
            elsif curChar.ascii_number?
                while @i < @src.size && curChar.ascii_number?
                    take
                end
                append TT::Integer

            # Identifier
            # Must start with letter, not just ASCII. Follow with any letter
            # or number or symbol in set: !@%$^&|*i\-_=+/?<>`~
            elsif curChar.letter?
                while @i < @src.size && (
                        curChar.alphanumeric? ||
                        curChar.in_set? "!@%$^&|*\\-_=+/?<>`~"
                )
                    take
                end

                if @token == "true" || @token == "false"
                    append TT::Boolean
                elsif @token == "print"
                    append TT::Print
                elsif @token == "println"
                    append TT::Println
                elsif @token == "if"
                    append TT::If
                elsif @token == "else"
                    append TT::Else
                elsif @token == "elf"
                    append TT::Elf
                elsif @token == "while"
                    append TT::While
                elsif @token == "def"
                    append TT::Define
                elsif @token == "end"
                    append TT::End
                elsif @token == "int" || @token == "bool"
                    append TT::Type
                else
                    append TT::Identifier
                end

            # New line
            elsif curChar == '\n'
                @token = ""
                @i += 1
                @line += 1

            # Whitespace
            elsif curChar.whitespace? && curChar != '\n'
                @token = ""
                @i += 1

            # Anything else
            else
                STDERR.puts "#{lineMsg}Unidentified character: #{curChar}"
                exit FAIL
            end
        end

        @tokens << Token.new TT::EOF, "EOF", @line
    end
end
