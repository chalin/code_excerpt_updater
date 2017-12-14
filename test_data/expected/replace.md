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

### Global/shared replace

<?code-excerpt replace="/bonjour/hola/g"?>

<?code-excerpt "basic.dart" replace="/hello/bonjour/g;/world/mundo/g"?>
```
var greeting = 'hola';
var scope = 'mundo';

void main() => print('$greeting $scope');
```

### Reset global replace

<?code-excerpt replace=""?>
<?code-excerpt "basic.dart" replace="/hello/bonjour/g"?>
```
var greeting = 'bonjour';
var scope = 'world';

void main() => print('$greeting $scope');
```

### Regression: support `}` in regexp.

<?code-excerpt "basic.dart" replace="/([\)\}]);/$1; \/\/!/g"?>
```
var greeting = 'hello';
var scope = 'world';

void main() => print('$greeting $scope'); //!
```
