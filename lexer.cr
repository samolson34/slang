class Token
    enum TokenType
        And
        Assign
        Bang
        Boolean
        Comma
        Define
        End
        EOF
        Equal
        If
        Greater
        GreaterOrEqual
        Identifier
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

    getter tokenType, code, line

    def initialize(
        @tokenType : TokenType,
        @code : String,
        @line : Int32
    ) end
end

class Lexer
    private alias TT = Token::TokenType

    FAIL = 1

    @tokens = [] of Token
    @token = ""
    @i = 0
    @src : String
    @line = 1

    def initialize(file)
        @src = file.gets_to_end.chomp
    end

    def take
        @token += curChar
        @i += 1
    end

    def append(tokenType)
        @tokens << Token.new tokenType, @token, @line
        @token = ""
    end

    def curChar
        @src[@i]
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
                append TT::Star

            # Slash
            elsif curChar == '/'
                take
                append TT::Slash

            # Percent
            elsif curChar == '%'
                take
                append TT::Percent

            # Plus
            elsif curChar == '+'
                take
                append TT::Plus

            # Minus
            elsif curChar == '-'
                take
                append TT::Minus

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
                else
                    STDERR.puts "Bitwise operations not supported. #{@i}"
                    exit FAIL
                end

            # And
            elsif curChar == '&'
                take
                if curChar == '&'
                    take
                    append TT::And
                else
                    STDERR.puts "Bitwise operations not supported. #{@i}"
                    exit FAIL
                end

            # Comma
            elsif curChar == ','
                take
                append TT::Comma

            # Number
            elsif curChar.ascii_number?
                while @i < @src.size && curChar.ascii_number?
                    take
                end
                append TT::Integer

            # Identifier
            elsif curChar.letter?
                while @i < @src.size && (
                        curChar.alphanumeric? ||
                        curChar.in_set? "!@%$^&|*\\-_+/?"
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
                STDERR.puts "Unidentified character: #{curChar} #{@i}"
                exit FAIL
            end
        end

        @tokens << Token.new TT::EOF, @token, @line
    end
end
