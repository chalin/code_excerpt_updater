# Markdown code-block updater

This is the repo for a simple _line-based_ updater for markdown code-blocks preceded by XML
processor instructions of the form `<?code-excerpt ...?>`. Dart (`.dart'), markdown (`.md`), and 
Jade (`.jade`) files are processed. For Dart source files, code blocks in API comments are updated.

## Usage

```
Usage: code_excerpt_updater [OPTIONS] file_or_directory...

-p, --fragment-dir-path               Path to the directory containing code fragment files
                                      (defaults to "", that is, the current working directory)

-h, --help                            Show command help
-i, --indentation                     Default number of spaces to use as indentation for code inside code blocks
                                      (defaults to "0")

-w, --write-in-place                  Write updates to files in-place
    --[no-]escape-ng-interpolation    Escape Angular interpolation syntax {{...}} as {!{...}!}
                                      (defaults to on)
```

For example, you can run the updater over 
[AngularDart](https://github.com/dart-lang/angular2) sources as follows:

`angular2> dart ../code_excerpt_updater/bin/code_excerpt_updater.dart -p ../site-webdev/tmp/_fragments/_api -w lib`

## `<?code-excerpt?>` syntax

The instruction comes in two forms. The first (and most common) form must immediately precede a markdown code block:


    <?code-excerpt "path/file.ext (optional-region-name)" arg0="value0" ...?>
    ```
      ...
    ```

The first (unnamed) argument defines a path to a fragment file. The argument can optionally
name a code fragment region&mdash;any non-word character sequences (`\w+`) in the region name are converted to a hyphen.

Recognized arguments are:
- `region`, a code fragment region name.
- `indent-by`, define the number of spaces to be used to indent the code in the code block.
   (Default is no indentation.)
- `path-base`, when provided, must be the only argument. Its use is described below in the second instruction form.

Notes:
- The `<?code-excerpt?>` instruction can optionally be preceded by an single-line comment
  token. Namely either `//` or `///`.
- Path, and arguments if given, must be enclosed in double quotes.

The second form of the instruction is:

```
<?code-excerpt path-base="subdirPath"?>
```

Following this instruction, the paths to file fragments will be interpreted relative to the `path-base` argument.

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
fragment file line as specified by the `indent-by` argument.

For example, if `hello.dart.txt` contains the line "print('Hi');" then

```
/// <?code-excerpt "hello.dart" indent-by="2"?>
/// ```dart
///   print('Bonjour');
/// ```
```

will be updated to

```
/// <?code-excerpt "hello.dart" indent-by="2"?>
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
