// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

const _eol = '\n';
Function _listEq = const ListEquality().equals;
typedef String CodeTransformer(String code);

CodeTransformer compose(CodeTransformer f, CodeTransformer g) =>
    f == null ? g : g == null ? f : (String s) => g(f(s));

/// A simple line-based updater for markdown code-blocks. It processes given
/// files line-by-line, looking for matches to [procInstrRE] contained within
/// markdown code blocks.
///
/// Returns, as a string, a version of the given file source, with the
/// `<?code-excerpt...?>` code fragments updated. Fragments are read from the
/// [fragmentDirPath] directory, and diff sources from [srcDirPath].
class Updater {
  final Logger _log = new Logger('CEU');
  final Stdout _stderr;
  final String fragmentDirPath;
  final String srcDirPath;
  final int defaultIndentation;
  final bool escapeNgInterpolation;

  String _pathBase = ''; // init from <?code-excerpt path-base="..."?>

  String _filePath = '';
  int _origNumLines = 0;
  List<String> _lines = [];

  int _numSrcDirectives = 0, _numUpdatedFrag = 0;

  /// [err] defaults to [_stderr].
  Updater(this.fragmentDirPath, this.srcDirPath,
      {this.defaultIndentation = 0,
      this.escapeNgInterpolation = true,
      Stdout err})
      : _stderr = err ?? stderr {
    Logger.root.level = Level.OFF;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
  }

  int get numSrcDirectives => _numSrcDirectives;
  int get numUpdatedFrag => _numUpdatedFrag;

  int get lineNum => _origNumLines - _lines.length;

  /// Returns the content of the file at [path] with code blocks updated.
  /// Missing fragment files are reported via `err`.
  /// If [path] cannot be read then an exception is thrown.
  String generateUpdatedFile(String path) {
    _filePath = path == null || path.isEmpty ? 'unnamed-file' : path;
    return _updateSrc(new File(path).readAsStringSync());
  }

  String _updateSrc(String dartSource) {
    _pathBase = '';
    _lines = dartSource.split(_eol);
    _origNumLines = _lines.length;
    return _processLines();
  }

  /// Regex matching code-excerpt processing instructions
  final RegExp procInstrRE = new RegExp(
      r'^(\s*(///?\s*)?)?<\?code-excerpt\s*("([^"]+)")?((\s+[-\w]+(\s*=\s*"[^"]*")?\s*)*)\??>');

  String _processLines() {
    final List<String> output = [];
    while (_lines.isNotEmpty) {
      final line = _lines.removeAt(0);
      output.add(line);
      if (!line.contains('<?code-excerpt')) continue;
      final match = procInstrRE.firstMatch(line);
      if (match == null) {
        _reportError('invalid processing instruction: $line');
        continue;
      }
      final info = _extractAndNormalizeArgs(match);

      if (info.unnamedArg == null) {
        _processSetPath(info);
      } else {
        output.addAll(_getUpdatedCodeBlock(info));
      }
    }
    return output.join(_eol);
  }

  void _processSetPath(InstrInfo info) {
    if (info.args['path-base'] == null) {
      if (info.args.keys.length == 0) {
        // Empty instruction is ok.
      } else if (info.args.keys.length == 1 && info.args['title'] != null) {
        // Only asking for a title is ok.
      } else {
        // _warn('instruction ignored: ${info.instruction}');
      }
    } else {
      _pathBase = info.args['path-base'];
      if (info.args.keys.length > 1) {
        _reportError(
            '"path-base" should be the only argument in the instruction:  ${info.instruction}');
      }
    }
  }

  /// Expects the next lines to be a markdown code block.
  /// Side-effect: consumes code-block lines.
  Iterable<String> _getUpdatedCodeBlock(InstrInfo info) {
    final args = info.args;
    final infoPath = info.path;

    // TODO: only match on same prefix.
    final codeBlockMarker = new RegExp(
        r'^\s*(///?)?\s*(```|\{%\s*(:?end)?prettify\s*(\w*)\s*%\})?');
    final currentCodeBlock = <String>[];
    if (_lines.isEmpty) {
      _reportError('reached end of input, expect code block - "$infoPath"');
      return currentCodeBlock;
    }
    var line = _lines.removeAt(0);
    final openingCodeBlockLine = line;
    final firstLineMatch = codeBlockMarker.firstMatch(line);
    if (firstLineMatch == null || firstLineMatch[2] == null) {
      _reportError('code block should immediately follow <?code-excerpt?> - '
          '"$infoPath"\n  not: $line');
      return <String>[openingCodeBlockLine];
    }

    final newCodeBlockCode = args['diff-with'] == null
        ? _getExcerpt(infoPath, info.region,
            stringReplaceCodeTransformer(args['replace']))
        : _getDiff(infoPath, args);
    _log.finer('>>> new code block code: $newCodeBlockCode');
    if (newCodeBlockCode == null) {
      // Error has been reported. Return while leaving existing code.
      // We could skip ahead to the end of the code block but that
      // will be handled by the outer loop.
      return <String>[openingCodeBlockLine];
    }
    String closingCodeBlockLine;
    while (_lines.isNotEmpty) {
      line = _lines[0];
      final match = codeBlockMarker.firstMatch(line);
      if (match == null) {
        // TODO: it would be nice if we could print a line number too.
        _reportError('unterminated markdown code block '
            'for <?code-excerpt "$infoPath"?>');
        return <String>[openingCodeBlockLine]..addAll(currentCodeBlock);
      } else if (match[2] != null) {
        // We've found the closing code-block marker.
        closingCodeBlockLine = line;
        _lines.removeAt(0);
        break;
      }
      currentCodeBlock.add(line);
      _lines.removeAt(0);
    }
    if (closingCodeBlockLine == null) {
      _reportError('unterminated markdown code block '
          'for <?code-excerpt "$infoPath"?>');
      return <String>[openingCodeBlockLine]..addAll(currentCodeBlock);
    }
    _numSrcDirectives++;
    final linePrefix = info.linePrefix;
    final indentBy =
        args['diff-with'] == null ? getIndentBy(args['indent-by']) : 0;
    final indentation = ' ' * indentBy;
    final prefixedCodeExcerpt = newCodeBlockCode.map((line) {
      final _line =
          '$linePrefix$indentation$line'.replaceFirst(new RegExp(r'\s+$'), '');
      return this.escapeNgInterpolation
          ? _line.replaceAllMapped(
              new RegExp(r'({){|(})}'), (m) => '${m[1]??m[2]}!${m[1]??m[2]}')
          : _line;
    }).toList();
    if (!_listEq(currentCodeBlock, prefixedCodeExcerpt)) _numUpdatedFrag++;
    final result = <String>[openingCodeBlockLine]
      ..addAll(prefixedCodeExcerpt)
      ..add(closingCodeBlockLine);
    _log.finer('>>> result: $result');
    return result;
  }

  InstrInfo _extractAndNormalizeArgs(Match procInstrMatch) {
    final info = new InstrInfo(procInstrMatch[0]);
    _log.finer(
        '>>> pIMatch: ${procInstrMatch.groupCount} - [${info.instruction}]');
    var i = 1;
    info.linePrefix = procInstrMatch[i++] ?? '';
    i++; // final commentToken = match[i++];
    i++; // optional path+region
    final pathAndOptRegion = procInstrMatch[i++];
    info.unnamedArg = pathAndOptRegion;
    __extractAndNormalizeNamedArgs(info, procInstrMatch[i]);
    return info;
  }

  void __extractAndNormalizeNamedArgs(InstrInfo info, String argsAsString) {
    if (argsAsString == null) return;

    final RegExp procInstrArgRE = new RegExp(r'(\s*([-\w]+)=")(.*?)"\s*');
    final matches = procInstrArgRE.allMatches(argsAsString);
    _log.finer('>>> ${matches.length} args with values in $argsAsString');

    for (final match in matches) {
      _log.finer('>>> arg: "${match[0]}"');
      final argName = match[2];
      final argValue = match[3];
      if (argName == null) continue;
      info.args[argName] = argValue ?? '';
      _log.finer('>>> arg: $argName = "${info.args[argName]}"');
    }
    _processPathAndRegionArgs(info);
  }

  final RegExp regionInPath = new RegExp(r'\s*\((.+)\)\s*$');
  final RegExp nonWordChars = new RegExp(r'[^\w]+');

  void _processPathAndRegionArgs(InstrInfo info) {
    final path = info.unnamedArg;
    if (path == null) return;
    final match = regionInPath.firstMatch(path);
    if (match == null) {
      info.path = path;
    } else {
      // Remove region from path
      info.path = path.substring(0, match.start);
      info.region = match[1]?.replaceAll(nonWordChars, '-');
    }
    _log.finer('>>> path="${info.path}", region="${info.region}"');
  }

  int getIndentBy(String indentByAsString) {
    if (indentByAsString == null) return defaultIndentation;
    String errorMsg = '';
    final result = int.parse(indentByAsString, onError: (s) {
      errorMsg = 'error parsing integer value: $s';
      return 0;
    });
    if (result < 0 || result > 100) errorMsg = 'integer out of range: $result';
    if (errorMsg.isNotEmpty) {
      _reportError('<?code-excerpt?> indent-by: $errorMsg');
    }
    return result;
  }

  /*@nullable*/
  Iterable<String> _getDiff(String relativeSrcPath1, Map<String, String> args) {
    final relativeSrcPath2 = args['diff-with'];
    final pathPrefix = p.join(srcDirPath, _pathBase);
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

  /*@nullable*/
  Iterable<String> _getExcerpt(
      String relativePath, String region, CodeTransformer t) {
    String excerpt = _getExcerptAsString(relativePath, region);
    if (excerpt == null) return null; // Errors have been reported
    if (t != null) excerpt = t(excerpt);
    final result = excerpt.split(_eol);
    // All excerpts are [_eol] terminated, so drop trailing blank lines
    while (result.length > 0 && result.last == '') result.removeLast();
    return _trimMinLeadingSpace(result);
  }

  /// Look for a fragment file under [fragmentDirPath], failing that look for a
  /// source file under [srcDirPath]. If a file is found return its content as
  /// a string. Otherwise, report an error and return null.
  /*@nullable*/
  String _getExcerptAsString(String relativePath, String region) {
    final fragExtension = '.txt';
    var file = relativePath + fragExtension;
    if (region.isNotEmpty) {
      final dir = p.dirname(relativePath);
      final basename = p.basenameWithoutExtension(relativePath);
      final ext = p.extension(relativePath);
      file = p.join(dir, '$basename-$region$ext$fragExtension');
    }

    // First look for a matching fragment
    final String fragPath = p.join(fragmentDirPath, _pathBase, file);
    try {
      return new File(fragPath).readAsStringSync();
    } on FileSystemException {
      if (region != '') {
        _reportError('cannot read fragment file "$fragPath"');
        return null;
      }
      // Fall through
    }

    // No fragment file file. Look for a source file with a matching file name.
    final String srcFilePath = p.join(srcDirPath, _pathBase, relativePath);
    try {
      return new File(srcFilePath).readAsStringSync();
    } on FileSystemException {
      _reportError('cannot find a source file "$srcFilePath", '
          'nor fragment file "$fragPath"');
      return null;
    }
  }

  final _blankLineRegEx = new RegExp(r'^\s*$');
  final _leadingWhitespaceRegEx = new RegExp(r'^[ \t]*');

  Iterable<String> _trimMinLeadingSpace(List<String> lines) {
    final nonblankLines = lines.where((s) => !_blankLineRegEx.hasMatch(s));
    // Length of leading spaces to be trimmed
    final lengths = nonblankLines.map((s) {
      final match = _leadingWhitespaceRegEx.firstMatch(s);
      return match == null ? 0 : match[0].length;
    });
    if (lengths.isEmpty) return lines;
    final len = lengths.reduce(min);
    return len == 0
        ? lines
        : lines.map((line) => line.length < len ? line : line.substring(len));
  }

  final _matchDollarNumRE = new RegExp(r'(\$+)(&|\d*)');
  final _escapedSlashRE = new RegExp(r'\\/');
  final _zeroChar = '\u{0}';
  final _endRE = new RegExp(r'^g;?\s*$');

  /*@nullable*/
  CodeTransformer stringReplaceCodeTransformer(String replaceExp) {
    dynamic _reportErr([String extraInfo = '']) =>
        _reportError('invalid replace attribute ("$replaceExp"); ' +
            (extraInfo.isEmpty ? '' : '$extraInfo; ') +
            'supported syntax is 1 or more semi-colon-separated: /regexp/replacement/g');

    if (replaceExp == null) return null;
    final replaceExpParts = replaceExp
        .replaceAll(_escapedSlashRE, _zeroChar)
        .split('/')
        .map((s) => s.replaceAll(_zeroChar, '/'))
        .toList();

    // replaceExpParts = [''] + n x [re, replacement, end] where n >= 1 and
    // end matches _endRE.

    final start = replaceExpParts[0];
    final len = replaceExpParts.length;
    if (len < 4 || len % 3 != 1)
      return _reportErr('argument has missing parts ($len)');

    if (start != '')
      return _reportErr('argument should start with "/", not  "$start"');

    final transformers = <CodeTransformer>[];
    for (int i = 1; i < replaceExpParts.length; i += 3) {
      final re = replaceExpParts[i];
      final replacement = replaceExpParts[i + 1];
      final end = replaceExpParts[i + 2];
      if (!_endRE.hasMatch(end)) {
        _reportErr(
            'expected argument end syntax of "g" or "g;" but found "$end"');
        return null;
      }
      final transformer = _stringReplaceCodeTransformer(re, replacement);
      if (transformer != null) transformers.add(transformer);
    }

    return transformers.fold(null, compose);
  }

  /*@nullable*/
  CodeTransformer _stringReplaceCodeTransformer(String re, String replacement) {
    if (!_matchDollarNumRE.hasMatch(replacement))
      return (String code) => code.replaceAll(new RegExp(re), replacement);

    return (String code) => code.replaceAllMapped(
        new RegExp(re),
        (Match m) => replacement.replaceAllMapped(_matchDollarNumRE, (_m) {
              // In JS, $$ becomes $ in a replacement string.
              final numDollarChar = _m[1].length;
              // Escaped dollar characters, if any:
              final dollars = r'$' * (numDollarChar ~/ 2);

              // Even number of $'s, e.g. $$1?
              if (numDollarChar.isEven || _m[2].isEmpty)
                return '$dollars${_m[2]}';

              if (_m[2] == '&') return '$dollars${m[0]}';

              final argNum = _toInt(_m[2]);
              // No corresponding group? Return the arg, like in JavaScript.
              if (argNum > m.groupCount) return '$dollars\$${_m[2]}';

              return '$dollars${m[argNum]}';
            }));
  }

  // void _warn(String msg) =>
  //    _stderr.writeln('Warning: $_filePath:$lineNum $msg');
  void _reportError(String msg) =>
      _stderr.writeln('Error: $_filePath:$lineNum $msg');
}

class InstrInfo {
  final String instruction;
  String linePrefix = '';

  InstrInfo(this.instruction);

  /// Optional. Currently represents a path + optional region
  String unnamedArg;

  String _path;
  String get path => _path ?? args['path'] ?? '';
  set path(String p) {
    _path = p;
  }

  String _region;
  set region(String r) {
    _region = r;
  }

  String get region => args['region'] ?? _region ?? '';

  final Map<String, String> args = {};
}

int _toInt(String s) => int.parse(s, onError: (_) => 99999);
