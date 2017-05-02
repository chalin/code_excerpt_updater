/// No region arguments in this file.

/// Test: no code in code block, @source directive w/o indentation
/// ```html
/// <!-- {@source "no_region.html"} -->
/// <div>
///   <h1>Hello World!</h1>
/// </div>
/// ```
var basic1;

/// Test: no code in code block, @source directive with indentation
/// ```dart
///   // {@source "no_region.dart"}
///   var greeting = 'hello';
///   var scope = 'world';
/// ```
var basic2;

/// Test: out-of-date code in code block, @source directive with indentation
/// ```dart
///   // {@source "no_region.dart"}
///   var greeting = 'hello';
///   var scope = 'world';
/// ```
var basic3;
