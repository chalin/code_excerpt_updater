import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'nullable.dart';

const _eol = '\n';
typedef ErrorReporter = void Function(String msg);

class Differ {
  final ErrorReporter _reportError;
  final Logger _log;

  Differ(this._log, this._reportError);

  @nullable
  Iterable<String> getDiff(
      String relativeSrcPath1, Map<String, String> args, String pathPrefix) {
    final relativeSrcPath2 = args['diff-with'];
    final path1 = p.join(pathPrefix, relativeSrcPath1);
    final path2 = p.join(pathPrefix, relativeSrcPath2);
    final r = Process.runSync('diff', ['-u', path1, path2]);
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

    // Trim shredder docregion tag lines (it would probably be better to first
    // filter the files and then do the time, but this is good enough for now):
    final docregionRe = new RegExp(r'#(end)?docregion\b');
    result.removeWhere((line) => docregionRe.hasMatch(line));

    // Fix file id lines by removing:
    // - [pathPrefix] from the start of the file paths so that paths are relative
    // - timestamp (because file timestamps are not relevant in the git world)
    result[0] = _adjustDiffFileIdLine(pathPrefix, result[0]);
    result[1] = _adjustDiffFileIdLine(pathPrefix, result[1]);

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

  int _indexOfFirstMatch(List a, int startingIdx, RegExp re) {
    var i = startingIdx;
    while (i < a.length && !re.hasMatch(a[i])) i++;
    return i;
  }

  final _diffFileIdRegEx = new RegExp(r'^(---|\+\+\+) ([^\t]+)\t(.*)$');

  String _adjustDiffFileIdLine(String pathPrefix, String diffFileIdLine) {
    final line = diffFileIdLine;
    final match = _diffFileIdRegEx.firstMatch(line);
    if (match == null) {
      _log.warning('Warning: unexpected file Id line: $diffFileIdLine');
      return diffFileIdLine;
    }
    String path = match[2];
    final pp = pathPrefix + p.separator;
    if (path.startsWith(pp)) path = path.substring(pp.length);
    return '${match[1]} $path';
  }
}
