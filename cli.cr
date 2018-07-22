#!/usr/bin/crystal

require "./lexer.cr"
require "./parser.cr"
require "./ast.cr"

FAIL = 1

if ARGV.empty?
    STDERR.puts "usage: slang <source file>"
    exit FAIL
end

filename = ARGV[0]
argv = ARGV[1..-1]

unless File.file? filename
    STDERR.puts "Source file not found: #{filename}"
    exit FAIL
end

file = File.open filename

lexer = Lexer.new file
tokens = lexer.lex

parser = Parser.new tokens

variables = {} of String => Variable
variables["ARGC"] = Variable.new(
    Variable::VariableType::Integer,
    argv.size,
    true  # global variable
)

# Get command line arguments
argv.each_with_index do |arg, i|
    # Arguments must be digits, optionally negative (until support for strings)
    if arg =~ /^-?\d+$/
        variables["ARG#{i}"] = Variable.new(
            Variable::VariableType::Integer,
            arg.to_i,
            true  # global variable
        )
    else
        STDERR.puts "Invalid argument: #{arg}"
        exit FAIL
    end
end

program = parser.parse Environment.new variables

program.evaluate Environment.new variables
