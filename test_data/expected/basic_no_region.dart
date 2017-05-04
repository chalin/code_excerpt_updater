/// No region arguments in this file.

/// Test: no code in code block, directive w/o indentation
/// <?code-excerpt "no_region.html"?>
/// ```html
/// <div>
///   <h1>Hello World!</h1>
/// </div>
/// ```
var basic1;

/// Test: no code in code block, directive with indentation
/// <?code-excerpt "no_region.dart" indent="  "?>
/// ```dart
///   var greeting = 'hello';
///   var scope = 'world';
/// ```
var basic2;

/// Test: out-of-date code in code block, directive with indentation
/// <?code-excerpt "no_region.dart" indent="  "?>
/// ```dart
///   var greeting = 'hello';
///   var scope = 'world';
/// ```
var basic3;
