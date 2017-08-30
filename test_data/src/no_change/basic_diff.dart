/// Test: multi line
/// <?code-excerpt "0-base/basic.dart" diff-with="1-step/basic.dart"?>
/// ```diff
/// --- 0-base/basic.dart	2017-08-30 07:49:24.000000000 -0400
/// +++ 1-step/basic.dart	2017-08-30 07:48:18.000000000 -0400
/// @@ -1,4 +1,4 @@
/// -var _greeting = 'hello';
/// +var _greeting = 'bonjour';
///  var _scope = 'world';
///
///  void main() => print('$_greeting $_scope');
/// ```
class C {}
