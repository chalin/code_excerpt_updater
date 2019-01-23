## Test `skip`

<?code-excerpt "basic.dart" skip="3"?>
```dart
void main() => print('$greeting $scope');
```

Negative arg:

<?code-excerpt "basic.dart" skip="-2"?>
```dart
var greeting = 'hello';
var scope = 'world';
```
