# Dart API doc source-code-fragment updater

This is the repo for a simple _line-based_ **Dart API doc** updater for `{@source}` code fragment directives.
That is, the updater processes input source files line-by-line, looking for `{@source}` 
directives contained within public API markdown code blocks.

## Usage

Use the `code_excerpt_updater` tool to update code fragments marked with `{@source}` directives in Dart API docs.

```
Usage: code_excerpt_updater [OPTIONS] dart_file_or_directory...

-p, --fragment-path-prefix    Path prefix to directory containing code fragment files.
                              (Default is current working directory.)

-h, --help                    Show command help.
-i, --in-place                Update files in-place.
```

For example, you could run the updater over [AngularDart](https://github.com/dart-lang/angular2) source as follows:

`angular2> dart ../code_excerpt_updater/bin/code_excerpt_updater.dart -p doc/api/_fragments/ -i lib`

## @source syntax

Because this is a simple line-based processing tool, the `{@source}` directive syntax
is strict to avoid misinterpreting occurrences of `@source` in Dart
code (vs. public API doc comments), that are not `{@source}` code fragment directives.

The updater only processes `{@source}` directives **in public API
doc comments**; these are _expected_ to be **contained in code markdown blocks** like this:

```
/// ```lang
/// {@source "relative/path/to/fragment/file.ext" region="region-name"}
/// ...
/// ```
```

Notes:
- The `{@source` token can optionally be preceded by an (open) comment token such as
  `//` or `<!--`.
- Path, and region name if given, must be enclosed in double quotes.
- `region` is optional.
- Whitespace is significant: for example, the opening token has no space between the
  `{` and the `@source`.

## Code fragment updating

The updater does not create code fragment files, but it does expect such files to 
exist and be named following the conventions described below.

For a directive like `{@source "dir/file.ext" region="rname"}`, the updater will search the
fragment folder, for a file named:

- `dir/file-rname.ext.txt`<br>
   or
- `dir/file.ext.txt`<br>
   if the region is omitted

If the updater can find the fragment file, it will replace the lines contained within
the directive's markdown code block with those from the fragment file, indenting each
fragment file line with the same indentation as the `{@source}` directive itself.
For example, if `hello.dart.txt` contains the line "print('Hi');" then

```
/// ```dart
///   // {@source "hello.dart"}
///   print('Bonjour');
/// ```
```

will be updated to

```
/// ```dart
///   // {@source "hello.dart"}
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
    /// ```html
    /// <!-- {@source "docs/template-syntax/lib/app_component.html" region="NgStyle"} -->
    /// ```
    ///
    /// ```dart
    /// // {@source "docs/template-syntax/lib/app_component.dart" region="NgStyle"}
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
    /// ```html
    /// <!-- {@source "docs/template-syntax/lib/app_component.html" region="NgStyle"} -->
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
    /// ```dart
    /// // {@source "docs/template-syntax/lib/app_component.dart" region="NgStyle"}
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