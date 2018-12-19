import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'nullable.dart';
import 'util.dart';

const _eol = '\n';
typedef ErrorReporter = void Function(String msg);
typedef ExcerptFetcher = Iterable<String> Function(String path, String region);

class Differ {
  Differ(this._excerptFetcher, this._log, this._reportError);

  final docregionRe = new RegExp(r'#(end)?doc(plaster|region)\b');
  final ExcerptFetcher _excerptFetcher;
  final ErrorReporter _reportError;
  final Logger _log;

  @nullable
  Directory _tmpDir;

  @nullable
  Iterable<String> getDiff(String relativeSrcPath1, String region,
      Map<String, String> args, String pathPrefix) {
    final relativeSrcPath2 = args['diff-with'];
    final path1 = region.isEmpty
        ? filteredFile(p.join(pathPrefix, relativeSrcPath1))
        : _writeExcerpt(relativeSrcPath1, region);
    final path2 = region.isEmpty
        ? filteredFile(p.join(pathPrefix, relativeSrcPath2))
        : _writeExcerpt(relativeSrcPath2, region);

    final diffArgs = args['diff-u'] == null ? ['-u'] : ['-U', args['diff-u']];
    diffArgs.addAll([path1.path, path2.path]);
    final r = Process.runSync('diff', diffArgs);

    try {
      path1.deleteSync();
      path2.deleteSync();
    } on FileSystemException catch (e) {
      _log.info(
          'Ignored exception while attempting to delete temporary files: $e');
    }

    if (r.exitCode > 1) {
      _reportError(r.stderr);
      return null;
    }
    if (r.stdout.isEmpty) return []; // no differences between files

    /* Sample diff output:
    --- examples/acx/lottery/1-base/lib/lottery_simulator.html	2017-08-25 07:45:24.000000000 -0400
    +++ examples/acx/lottery/2-starteasy/lib/lottery_simulator.html	2017-08-25 07:45:24.000000000 -0400
    @@ -23,35 +23,39 @@
         <div class="clear-floats"></div>
       </div>

    -  Progress: <strong>{{progress}}%</strong> <br>
    -  <progress max="100" [value]="progress"></progress>
    +  <material-progress  [activeProgress]="progress" class="life-progress">
    +  </material-progress>

       <div class="controls">
    ...
    */

    List<String> result = r.stdout.split(_eol);

    // Trim trailing blank lines
    while (result.length > 0 && result.last == '') result.removeLast();

    // Fix file id lines by removing:
    // - [pathPrefix] from the start of the file paths so that paths are relative
    // - timestamp (because file timestamps are not relevant in the git world)
    result[0] = _adjustDiffFileIdLine(
        relativeSrcPath1 + (region.isEmpty ? '' : ' ($region)'), result[0]);
    result[1] = _adjustDiffFileIdLine(
        relativeSrcPath2 + (region.isEmpty ? '' : ' ($region)'), result[1]);

    final from = args['from'], to = args['to'];
    // TODO: trim diff output to contain only lines between those that (first)
    // match `from` and `to`. For now we only trim after `to`.
    // Only return diff until 'to' pattern, if given
    final startingIdx =
        from == null ? 0 : _indexOfFirstMatch(result, 2, new RegExp(from));
    if (to != null) {
      final lastIdx = _indexOfFirstMatch(result, startingIdx, new RegExp(to));
      if (lastIdx < result.length) {
        result = result.getRange(0, lastIdx + 1).toList();
      }
    }
    return result;
  }

  /// Read the file at [filePath], strip out any docregion tags (lines matching
  /// [docregionRe]), write the result to a temporary file and return the
  /// corresponding [File] object.
  ///
  /// Lets [FileSystemException]s through.
  File filteredFile(String filePath) {
    final file = new File(filePath);
    final src = file.readAsStringSync();
    final lines = src.split(_eol);
    lines.removeWhere((line) => docregionRe.hasMatch(line));

    return _writeTmp(filePath, lines.join(_eol));
  }

  /// Write the named region of [filePath] to a temporary file whose filename
  /// is derived from [filePath]. Returns the [File] instance of the temp file.
  File _writeExcerpt(String filePath, String region) {
    var excerpt = _excerptFetcher(filePath, region)?.join(_eol) ?? '';
    // To avoid "No newline at end of file" messages from the diff tool,
    // ensure that the excerpt ends with an EOL (since all trailing blank lines
    // are usually stripped out).
    if (excerpt.isNotEmpty) excerpt += _eol;
    return _writeTmp(filePath, excerpt);
  }

  /// Write [content] to a temporary file whose filename is derived
  /// from [filePath]. Returns the temporary [File] instance.
  File _writeTmp(String filePath, String content) {
    final ext = p.extension(filePath);
    final tmpFilePath =
        p.join(getTmpDir().path, 'differ_src_${filePath.hashCode}$ext');
    final tmpFile = new File(tmpFilePath);
    tmpFile.writeAsStringSync(content);
    return tmpFile;
  }

  int _indexOfFirstMatch(List a, int startingIdx, RegExp re) {
    var i = startingIdx;
    while (i < a.length && !re.hasMatch(a[i])) i++;
    return i;
  }

  final _diffFileIdRegEx = new RegExp(r'^(---|\+\+\+) ([^\t]+)\t(.*)$');

  String _adjustDiffFileIdLine(String relativePath, String diffFileIdLine) {
    final line = diffFileIdLine;
    final match = _diffFileIdRegEx.firstMatch(line);
    if (match == null) {
      _log.warning('Warning: unexpected file Id line: $diffFileIdLine');
      return diffFileIdLine;
    }
    return '${match[1]} $relativePath';
  }

  Directory getTmpDir() =>
      _tmpDir ??= Directory.systemTemp; // .createTempSync();
}
