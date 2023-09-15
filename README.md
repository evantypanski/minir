# Minir

A "horizontally" scaled compiler intermediate representation (IR). Instead of developing new language features, the feature set of the language will remain relatively small. The focus is instead on developer tooling. This allows using minir as a playground for developer tools and optimizations.

## Building

Make sure you have Zig 0.11 in your `PATH`. In this directory, use `zig build`. Easy.

## Usage

Call the built `minir` without any arguments for help.

## The language

Here's a slightly convoluted program that prints from `42` to `59`:

```
func main() -> none {
  let i: int = 42
@loop
  test(i)
  i = addone(i)
  brc loop !(i == 60)
  ret
}

func addone(i: int) -> int {
  ret i + 1
}

func test(k: int) -> none {
  debug(k)
  ret
}
```

 - Printing is a simple builtin `debug` function
 - There are no high level control flow operators, just branches and labels
 - That's about it

## How?

Minir uses a simple frontend and a bytecode interpreter for execution. The tree walking interpreter might work?

## The future

Here's a wishlist of things I want to work on.

Near term:
 - Heap memory
 - Slightly better formatting
 - More optimizations
 - A language specification (or just docs)
 - JSON format
 - Hard limits rather than relying on Zig builtins (eg the casts when interpreting)
 - More utilities for casting/working between types
 - A few more types for different size int etc.

Would be nice to have in like 80 years:
 - JIT
 - Garbage collection
 - Static analyses that could have false positives
 - Microbenchmarks
 - Crazy good testing infrastructure
 - Custom passes by passing in a library (or executable or something)
 - A bytecode format that can actually go in a file
