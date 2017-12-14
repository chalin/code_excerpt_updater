## Test replace attribute

<?code-excerpt "basic.dart" replace="/hello/bonjour/g"?>
```
```

<?code-excerpt "basic.dart" replace="/hell(o)/b$1nj$1ur$$1$2/g"?>
```
```

<?code-excerpt "basic.dart" replace="/hel*o/$& $&/g"?>
```
```

<?code-excerpt "basic.dart" replace="/hello/$&\/bonjour/g"?>
```
```

<?code-excerpt "basic.dart" replace="/;/; \/\/!/g;/hello/bonjour/g;/(bonjour.*?)!/$1?/g"?>
```
```

### Global/shared replace

<?code-excerpt replace="/bonjour/hola/g"?>

<?code-excerpt "basic.dart" replace="/hello/bonjour/g;/world/mundo/g"?>
```
```

### Reset global replace

<?code-excerpt replace=""?>
<?code-excerpt "basic.dart" replace="/hello/bonjour/g"?>
```
```

### Regression: support `}` in regexp.

<?code-excerpt "basic.dart" replace="/([\)\}]);/$1; \/\/!/g"?>
```
```
