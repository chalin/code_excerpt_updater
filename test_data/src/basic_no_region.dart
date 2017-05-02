/// No region arguments in this file.

/// Test: no code in code block, @source directive w/o indentation
/// ```html
/// <!-- {@source "no_region.html"} -->
/// ```
var basic1;

/// Test: no code in code block, @source directive with indentation
/// ```dart
///   // {@source "no_region.dart"}
/// ```
var basic2;

/// Test: out-of-date code in code block, @source directive with indentation
/// ```dart
///   // {@source "no_region.dart"}
///   we don't care what this text is since it will be replaced
/// misindented text that we don't care about
/// ```
var basic3;
