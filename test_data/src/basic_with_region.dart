/// Test: no code in code block, @source directive w/o indentation
/// ```dart
/// // {@source "basic.dart" region="greeting"}
/// ```
var v;

/// Test: no code in code block, @source directive with indentation
/// ```dart
///   // {@source "basic.dart" region="greeting"}
/// ```
void f() {}

/// Test: out-of-date code in code block, @source directive with indentation
/// ```dart
///   // {@source "basic.dart" region="greeting"}
///   var greeting = 'bonjour';
///   var scope = 'le monde';
/// ```
class C {}
