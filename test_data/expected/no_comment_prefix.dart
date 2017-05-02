/// @source without a comment prefix; i.e. lines start with `/// {@source...}`.

/// Test: no code in code block, @source directive w/o indentation
/// ```
/// {@source "quote.md"}
/// This is a **markdown** fragment.
/// ```
var basic1;

/// Test: no code in code block, @source directive with indentation
/// ```
///   {@source "quote.md"}
///   This is a **markdown** fragment.
/// ```
var basic2;

/// Test: out-of-date code in code block, @source directive with indentation
/// ```
///   {@source "quote.md"}
///   This is a **markdown** fragment.
/// ```
var basic3;
