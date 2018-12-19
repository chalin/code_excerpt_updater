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

### Files with docregion tags

<?code-excerpt "0-base/docregion.dart" diff-with="1-step/docregion.dart"?>
{% diff %}
--- 0-base/docregion.dart
+++ 1-step/docregion.dart
@@ -1,4 +1,4 @@
-var _greeting = 'hello';
+var _greeting = 'bonjour';
 var _scope = 'world';

 /// Some
@@ -12,4 +12,4 @@
 /// two
 /// diff
 /// hunks
-void main() => print('$_greeting $_scope');
+void main() => print('$_greeting $_scope!');
{% enddiff %}

### Diff region

<?code-excerpt "0-base/docregion.dart (main)" diff-with="1-step/docregion.dart"?>
{% diff %}
--- 0-base/docregion.dart (main)
+++ 1-step/docregion.dart (main)
@@ -1 +1 @@
-void main() => print('$_greeting $_scope');
+void main() => print('$_greeting $_scope!');
{% enddiff %}
