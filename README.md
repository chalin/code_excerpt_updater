# Markdown code-block updater

This is the repo for a simple _line-based_ updater for markdown code-blocks preceded by XML
processor instructions of the form `<?code-excerpt ...?>`. Both markdown (`.md`) and Dart
source files are processed. For Dart source files, code blocks in API comments are updated.

## Usage

```
Usage: code_excerpt_updater [OPTIONS] file_or_directory...

-p, --fragment-path-prefix    Path prefix to directory containing code fragment files.
                              (Default is current working directory.)

-h, --help                    Show command help.
-i, --in-place                Update files in-place.
```

For example, you can run the updater over 
[AngularDart](https://github.com/dart-lang/angular2) sources as follows:

`angular2> dart ../code_excerpt_updater/bin/code_excerpt_updater.dart -p doc/api/_fragments/ -i lib`

## `<?code-exceprt?>` syntax

```
<?code-excerpt "relative/path/to/fragment/file.ext" arg0="value0"...}
```

Recognized arguments are:
- `region`, optionally defining a code fragment region name.
- `indent`, optionally defining the string to be used to indent the code in the code block.
   By default this argument's value is the empty string.

Notes:
- The `<?code-excerpt?>` instruction can optionally be preceded by an single-line comment
  token. Namely either `//` or `///`.
- Path, and arguments if given, must be enclosed in double quotes.
- The <?code-excerpt?> instruction must immediately precede a code block.

## Code fragment updating

The updater does not create code fragment files. It does expect such files to 
exist and be named following the conventions described below.

For a directive like `<?code-excerpt "dir/file.ext" region="rname"?>`, the updater will search the
fragment folder, for a file named:

- `dir/file-rname.ext.txt`<br>
   or
- `dir/file.ext.txt`<br>
   if the region is omitted

If the updater can find the fragment file, it will replace the lines contained within
the markdown code block with those from the fragment file, indenting each
fragment file line as specified by the `indent` argument.

For example, if `hello.dart.txt` contains the line "print('Hi');" then

```
/// <?code-excerpt "hello.dart" indent="  "?>
/// ```dart
///   print('Bonjour');
/// ```
```

will be updated to

```
/// <?code-excerpt "hello.dart" indent="  "?>
/// ```dart
///   print('Hi');
/// ```
```

## Example

Consider the following API doc excerpt from the
[NgStyle](https://webdev.dartlang.org/angular/api/angular2.common/NgStyle-class) class.

```dart
    /// ### Examples
    ///
    /// Try the [live example][ex] from the [Template Syntax][guide] page. Here are
    /// the relevant excerpts from the example's template and the corresponding
    /// component class:
    ///
    /// <?code-excerpt "docs/template-syntax/lib/app_component.html" region="NgStyle"?>
    /// ```html
    /// ```
    ///
    /// <?code-excerpt "docs/template-syntax/lib/app_component.dart" region="NgStyle"?>
    /// ```dart
    /// ```
```

Given an appropriate path to the folder containing code fragment files, this
update tool would generate:

```dart
    /// ### Examples
    ///
    /// Try the [live example][ex] from the [Template Syntax][guide] page. Here are
    /// the relevant excerpts from the example's template and the corresponding
    /// component class:
    ///
    /// <?code-excerpt "docs/template-syntax/lib/app_component.html" region="NgStyle"?>
    /// ```html
    /// <div>
    ///   <p [ngStyle]="setStyle()" #styleP>Change style of this text!</p>
    /// 
    ///   <label>Italic: <input type="checkbox" [(ngModel)]="isItalic"></label> |
    ///   <label>Bold: <input type="checkbox" [(ngModel)]="isBold"></label> |
    ///   <label>Size: <input type="text" [(ngModel)]="fontSize"></label>
    /// 
    ///   <p>Style set to: <code>'{{styleP.style.cssText}}'</code></p>
    /// </div>
    /// ```
    ///
    /// <?code-excerpt "docs/template-syntax/lib/app_component.dart" region="NgStyle"?>
    /// ```dart
    /// bool isItalic = false;
    /// bool isBold = false;
    /// String fontSize = 'large';
    /// String fontSizePx = '14';
    /// 
    /// Map<String, String> setStyle() {
    ///   return {
    ///     'font-style': isItalic ? 'italic' : 'normal',
    ///     'font-weight': isBold ? 'bold' : 'normal',
    ///     'font-size': fontSize
    ///   };
    /// }
    /// ```
```

## Tests

Repo tests can be launched from `test/main.dart`.