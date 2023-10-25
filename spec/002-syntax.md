# Syntax

The syntax can be neatly represented as follows:

```
IR ::= Decl*

Type ::= "int" | "float" | "boolean" | "none"

ID ::= (Letter | "_") (Letter | Digit | "_")*
Letter ::= "a"-"z" | "A"-"Z"
Digit ::= "0"-"9"

Decl ::= FunctionDecl | VarDecl
FunctionDecl ::= "func" ID "(" ParamList ")" "->" Type "{" Stmt* "}"
ParamList ::= (Param ("," Param)*)?
Param ::= ID ":" Type

Label ::= "@" ID
Stmt ::= Label? (Debug | Let | Ret | Branch | ExprStmt)
Debug ::= "debug" "(" Expr ")"
Let ::= ID (LetWithTypePart | LetWithoutTypePart)
LetWithTypePart ::= ":" Type ("=" Expr)?
LetWithoutTypePart ::= "=" Expr
Ret ::= "ret" Expr?
Branch ::= UnconditionalBranch | ConditionalBranch
UnconditionalBranch ::= "br" ID
ConditionalBranch ::= "brc" Expr ID
ExprStmt ::= Expr

Expr ::= Grouping | FuncCall | ID | Unary | Literal | Binary
Grouping ::= "(" Expr ")"
FuncCall ::= ID "(" ArgList ")"
Unary ::= "!" Expr
Literal ::= "true" | "false" | "undefined" | Number
Number ::= Int | Float
Int ::= Digit+
Float ::= Digit+ "." Digit+
Binary ::= Expr BinaryOp Expr
BinaryOp ::= "=" | "==" | "+" | "-" | "*" | "/" | "&&" | "||" | "<" | "<=" | ">" | ">="
```
