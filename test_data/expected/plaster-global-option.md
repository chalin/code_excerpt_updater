## Test plaster feature

### Globally set default plaster

<?code-excerpt "plaster.dart"?>
```
var greeting = 'hello';
// Insert your code here ···
var scope = 'world';
```

### Remove plaster

<?code-excerpt "plaster.txt" plaster="none"?>
```
abc
def
```

### Custom template

<?code-excerpt "plaster.dart" plaster="/*...*/"?>
```
var greeting = 'hello';
/*...*/
var scope = 'world';
```

<?code-excerpt "plaster.dart" plaster="/* $defaultPlaster */"?>
```
var greeting = 'hello';
/* ··· */
var scope = 'world';
```
