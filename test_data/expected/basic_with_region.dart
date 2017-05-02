/// Test: no code in code block, @source directive w/o indentation
/// ```dart
/// // {@source "basic.dart" region="greeting"}
/// var greeting = 'hello';
/// var scope = 'world';
/// ```
var v;

/// Test: no code in code block, @source directive with indentation
/// ```dart
///   // {@source "basic.dart" region="greeting"}
///   var greeting = 'hello';
///   var scope = 'world';
/// ```
void f() {}

/// Test: out-of-date code in code block, @source directive with indentation
/// ```dart
///   // {@source "basic.dart" region="greeting"}
///   var greeting = 'hello';
///   var scope = 'world';
/// ```
class C {}
