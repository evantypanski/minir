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
Stmt ::= Label? (Let | Ret | Branch | ExprStmt)
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
Unary ::= UnaryOp Expr
UnaryOp ::= "!" | "*" | "-"
Literal ::= "true" | "false" | "undefined" | Number
Number ::= Int | Float
Int ::= Digit+
Float ::= Digit+ "." Digit+
Binary ::= Expr BinaryOp Expr
BinaryOp ::= "=" | "==" | "+" | "-" | "*" | "/" | "&&" | "||" | "<" | "<=" | ">" | ">="
```

## Precedence

The expressions above are not grouped by precedence for simplicity. The precedence is ranked with highest precedence (least binding) first as follows:

1) Assignment (`=`)
2) Or (`||`)
3) And (`&&`)
4) Equality (`==`)
5) Comparisons (`<` etc.)
6) Term (`+` and `-`)
7) Factor (`*` and `/`)
8) Unary (`!`, `*`, `-`)
9) Function calls (`ID()`)
10) Groupings (`( Expr )`)
11) Primary expressions or literals (`true` or `123`)

## Reserved words

All keywords are reserved words. You cannot use the reserved words as identifiers (`let func = 0` should error).
