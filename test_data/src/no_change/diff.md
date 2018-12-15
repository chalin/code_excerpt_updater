## Test of Jekyll diff plugin

<?code-excerpt "0-base/basic.dart" diff-with="1-step/basic.dart"?>
{% diff %}
--- 0-base/basic.dart
+++ 1-step/basic.dart
@@ -1,4 +1,4 @@
-var _greeting = 'hello';
+var _greeting = 'bonjour';
 var _scope = 'world';

 void main() => print('$_greeting $_scope');
{% enddiff %}
