/// @source without a comment prefix; i.e. lines start with `/// {@source...}`.

/// Test: no code in code block, @source directive w/o indentation
/// ```
/// {@source "quote.md"}
/// ```
var basic1;

/// Test: no code in code block, @source directive with indentation
/// ```
///   {@source "quote.md"}
/// ```
var basic2;

/// Test: out-of-date code in code block, @source directive with indentation
/// ```
///   {@source "quote.md"}
///   we don't care what this text is since it will be replaced
/// misindented text that we don't care about
/// ```
var basic3;
