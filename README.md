### slang (Sam's Language)
Written in Crystal.

[Install Crystal](https://crystal-lang.org/docs/installation/)

Then, build slang by running command in `$REPO/terp/`:

    crystal build cli.cr -o slang

Run source file with:

    ./slang src.sa

----
~ general purpose  
~ more in the future?

This project supports integer literals, boolean literals, integer
variables, boolean variables, integer arithmetic (`+-*/%`), equality
(`== !=`), integer comparison (`< > <= >=`), boolean logic (`&& || !`),
"quick assignment" (`*= += &=` etc), functions, parentheses, print
statements, and comments.

* Identifiers can have hyphens and more.  
* Write everything in one line if you want.  
* No def inside a def.  
* The primary goal is to be a learning vehicle.  

----
```
program  
: statement\* EOF

statement  
: PRINT expr  
| PRINTLN expr  
| IDENTIFIER ASSIGN expr  
| DEF IDENTIFIER LEFT\_PARENTHESIS IDENTIFIER\* COMMA RIGHT\_PARENTHESIS statement\* END  
| IDENTIFIER [LEFT\_PARENTHESIS expr+ RIGHT\_PARENTHESIS]  

expr  
: INTEGER  
| BOOLEAN  
| NEGATE expr  
| NOT expr  
| expr (ASTERISK|DIVIDE|MOD) expr  
| expr (PLUS|MINUS) expr  
| expr (MORE|MORE\_OR\_EQUAL|LESS|LESS\_OR\_EQUAL|EQUAL|NOT\_EQUAL) expr  
| expr (AND|OR) expr  
```
