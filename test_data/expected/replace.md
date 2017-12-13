## Test replace attribute

<?code-excerpt "basic.dart" replace="/hello/bonjour/g"?>
```
var greeting = 'bonjour';
var scope = 'world';

void main() => print('$greeting $scope');
```

<?code-excerpt "basic.dart" replace="/hell(o)/b$1nj$1ur$$1$2/g"?>
```
var greeting = 'bonjour$1$2';
var scope = 'world';

void main() => print('$greeting $scope');
```

<?code-excerpt "basic.dart" replace="/hel*o/$& $&/g"?>
```
var greeting = 'hello hello';
var scope = 'world';

void main() => print('$greeting $scope');
```

<?code-excerpt "basic.dart" replace="/hello/$&\/bonjour/g"?>
```
var greeting = 'hello/bonjour';
var scope = 'world';

void main() => print('$greeting $scope');
```

<?code-excerpt "basic.dart" replace="/;/; \/\/!/g;/hello/bonjour/g;/(bonjour.*?)!/$1?/g"?>
```
var greeting = 'bonjour'; //?
var scope = 'world'; //!

void main() => print('$greeting $scope'); //!
```

Regression: support `}` in regexp.

<?code-excerpt "basic.dart" replace="/([\)\}]);/$1; \/\/!/g"?>
```
var greeting = 'hello';
var scope = 'world';

void main() => print('$greeting $scope'); //!
```
