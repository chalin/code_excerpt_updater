/// No region arguments in this file.

/// Test: no code in code block, directive w/o indentation
/// <?code-excerpt "no_region.html"?>
/// ```html
/// ```
var basic1;

/// Test: no code in code block, directive with indentation
/// <?code-excerpt "no_region.dart" indent="  "?>
/// ```dart
/// ```
var basic2;

/// Test: out-of-date code in code block, directive with indentation
/// <?code-excerpt "no_region.dart" indent="  "?>
/// ```dart
///   we don't care what this text is since it will be replaced
/// misindented text that we don't care about
/// ```
var basic3;
