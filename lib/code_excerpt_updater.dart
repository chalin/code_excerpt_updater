// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

const _eol = '\n';
Function _listEq = const ListEquality().equals;

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
    // Logger.root.level = Level.ALL;
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
        _warn('instruction ignored: ${info.instruction}');
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
    final codeBlockMarker = new RegExp(r'^\s*(///?)?\s*(```)?');
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
        ? _getExcerpt(infoPath, info.region)
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

    final RegExp procInstrArgRE = new RegExp(r'(\s*([-\w]+)=")([^"}]*)"\s*');
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

    // Fix file id lines by removing:
    // - [pathPrefix] from the start of the file paths so that paths are relative
    // - timestamp (because file timestamps are not relevant in the git world)
    result[0] = _adjustDiffFileIdLine(pathPrefix, result[0]);
    result[1] = _adjustDiffFileIdLine(pathPrefix, result[1]);

    // Only return diff until 'to' pattern, if given
    final to = args['to'];
    if (to != null) {
      var foundIndex = -1;
      final toRe = new RegExp(to);
      for (var i = 0; i < result.length; i++) {
        if (!toRe.hasMatch(result[i])) continue;
        foundIndex = i;
        break;
      }
      if (foundIndex > -1) {
        result = result.getRange(0, foundIndex + 1).toList();
      }
    }
    return result;
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
  Iterable<String> _getExcerpt(String relativePath, String region) {
    final fragExtension = '.txt';
    var file = relativePath + fragExtension;
    if (region.isNotEmpty) {
      final dir = p.dirname(relativePath);
      final basename = p.basenameWithoutExtension(relativePath);
      final ext = p.extension(relativePath);
      file = p.join(dir, '$basename-$region$ext$fragExtension');
    }

    final String fullPath = p.join(fragmentDirPath, _pathBase, file);
    try {
      final result = new File(fullPath).readAsStringSync().split(_eol);
      // All excerpts are [_eol] terminated, so drop trailing blank lines
      while (result.length > 0 && result.last == '') result.removeLast();
      return _trimMinLeadingSpace(result);
    } on FileSystemException catch (e) {
      _reportError('cannot read fragment file "$fullPath"\n$e');
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

  void _warn(String msg) =>
      _stderr.writeln('Warning: $_filePath:$lineNum $msg');
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
