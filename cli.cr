#!/usr/bin/crystal

require "./lexer.cr"
require "./parser.cr"
require "./ast.cr"

FAIL = 1

if ARGV.empty?
    STDERR.puts "usage: slang <source file>"
    exit FAIL
else
    filename = ARGV[0]

    unless File.file? filename
        STDERR.puts "Source file not found: #{filename}"
        exit FAIL
    else
        file = File.open filename

        lexer = Lexer.new file
        tokens = lexer.lex

        parser = Parser.new tokens
        program = parser.parse
        program.evaluate Environment.new
    end
end
