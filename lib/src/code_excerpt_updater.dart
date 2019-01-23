// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'args.dart';
import 'code_transformer/core.dart';
import 'code_transformer/plaster.dart';
import 'code_transformer/replace.dart';
import 'constants.dart';
import 'differ.dart';
import 'excerpt_getter.dart';
import 'instr_info.dart';
import 'issue_reporter.dart';
import 'logger.dart';

Function _listEq = const ListEquality().equals;

/// A simple line-based updater for markdown code-blocks. It processes given
/// files line-by-line, looking for matches to [procInstrRE] contained within
/// markdown code blocks.
///
/// Returns, as a string, a version of the given file source, with the
/// `<?code-excerpt...?>` code fragments updated. Fragments are read from the
/// [fragmentDirPath] directory, and diff sources from [srcDirPath].
class Updater {
  final RegExp codeBlockStartMarker =
      new RegExp(r'^\s*(///?)?\s*(```|{%-?\s*\w+\s*(\w*)(\s+.*)?-?%})?');
  final RegExp codeBlockEndMarker = new RegExp(r'^\s*(///?)?\s*(```)?');
  final RegExp codeBlockEndPrettifyMarker =
      new RegExp(r'^\s*(///?)?\s*({%-?\s*end\w+\s*-?%})?');

  final String fragmentDirPath;
  final int defaultIndentation;
  final bool escapeNgInterpolation;
  final String globalReplaceExpr;
  final String globalPlasterTemplate;
  String filePlasterTemplate;

  ArgProcessor _argProcessor;
  Differ _differ;
  ExcerptGetter _getter;
  IssueReporter _reporter;

  CodeTransformer _appGlobalCodeTransformer;
  CodeTransformer _fileGlobalCodeTransformer;
  PlasterCodeTransformer _plaster;
  ReplaceCodeTransformer _replace;

  String _filePath = '';
  int _origNumLines = 0;
  List<String> _lines = [];

  int _numSrcDirectives = 0, _numUpdatedFrag = 0;

  /// [err] defaults to [stderr].
  Updater(
    this.fragmentDirPath,
    srcDirPath, {
    this.defaultIndentation = 0,
    excerptsYaml = false,
    this.escapeNgInterpolation = true,
    this.globalReplaceExpr = '',
    this.globalPlasterTemplate,
    Stdout err,
  }) {
    initLogger();
    _reporter = new IssueReporter(
        new IssueContext(() => _filePath, () => lineNum), err);
    _replace = new ReplaceCodeTransformer(_reporter);
    _plaster = new PlasterCodeTransformer(excerptsYaml, _replace);

    if (globalReplaceExpr.isNotEmpty) {
      _appGlobalCodeTransformer = _replace.codeTransformer(globalReplaceExpr);
      if (_appGlobalCodeTransformer == null) {
        // Error details have already been reported, now throw.
        final msg =
            'Command line replace expression is invalid: $globalReplaceExpr';
        throw new Exception(msg);
      }
    }
    _argProcessor = new ArgProcessor(_reporter);
    _getter =
        new ExcerptGetter(excerptsYaml, fragmentDirPath, srcDirPath, _reporter);
    _differ = new Differ(
        (path, region) => _getter.getExcerpt(path, region, null),
        log,
        _reporter.error);
  }

  int get numErrors => _reporter.numErrors;
  int get numSrcDirectives => _numSrcDirectives;
  int get numUpdatedFrag => _numUpdatedFrag;
  int get numWarnings => _reporter.numWarnings;

  int get lineNum => _origNumLines - _lines.length;

  CodeTransformer get fileAndCmdLineCodeTransformer =>
      compose(_fileGlobalCodeTransformer, _appGlobalCodeTransformer);

  /// Returns the content of the file at [path] with code blocks updated.
  /// Missing fragment files are reported via `err`.
  /// If [path] cannot be read then an exception is thrown.
  String generateUpdatedFile(String path) {
    _filePath = path == null || path.isEmpty ? 'unnamed-file' : path;
    return _updateSrc(new File(path).readAsStringSync());
  }

  String _updateSrc(String dartSource) {
    _getter.pathBase = '';
    _lines = dartSource.split(eol);
    _origNumLines = _lines.length;
    return _processLines();
  }

  /// Regex matching code-excerpt processing instructions
  final RegExp procInstrRE = new RegExp(
      r'^(\s*((?:///?|-|\*)\s*)?)?<\?code-excerpt\s*("([^"]+)")?((\s+[-\w]+(\s*=\s*"[^"]*")?\s*)*)\??>');

  String _processLines() {
    final List<String> output = [];
    while (_lines.isNotEmpty) {
      final line = _lines.removeAt(0);
      output.add(line);
      if (!line.contains('<?code-excerpt')) continue;
      final match = procInstrRE.firstMatch(line);
      if (match == null) {
        _reporter.error('invalid processing instruction: $line');
        continue;
      }
      if (!match[0].endsWith('?>')) {
        _reporter
            .warn('processing instruction must be closed using "?>" syntax');
      }
      final info = _argProcessor.extractAndNormalizeArgs(match);

      if (info.unnamedArg == null) {
        _processSetInstruction(info);
      } else {
        output.addAll(_getUpdatedCodeBlock(info));
      }
    }
    return output.join(eol);
  }

  void _processSetInstruction(InstrInfo info) {
    void _checkForMoreThan1ArgErr() {
      if (info.args.keys.length > 1) {
        _reporter.error(
            'set instruction should have at most one argument: ${info.instruction}');
      }
    }

    if (info.args.containsKey('path-base')) {
      _getter.pathBase = info.args['path-base'] ?? '';
      _checkForMoreThan1ArgErr();
    } else if (info.args.containsKey('replace')) {
      _fileGlobalCodeTransformer = info.args['replace']?.isNotEmpty ?? false
          ? _replace.codeTransformer(info.args['replace'])
          : null;
      _checkForMoreThan1ArgErr();
    } else if (info.args.containsKey('plaster')) {
      filePlasterTemplate = info.args['plaster'];
      _checkForMoreThan1ArgErr();
    } else if (info.args.keys.length == 0 ||
        info.args.keys.length == 1 && info.args['class'] != null) {
      // Ignore empty instruction, other tools process them.
    } else if (info.args.keys.length == 1 && info.args.containsKey('title')) {
      // Only asking for a title is ok.
    } else {
      _reporter
          .warn('instruction ignored: unrecognized set instruction argument: '
              '${info.instruction}');
    }
  }

  /// Expects the next lines to be a markdown code block.
  /// Side-effect: consumes code-block lines.
  Iterable<String> _getUpdatedCodeBlock(InstrInfo info) {
    final args = info.args;
    final infoPath = info.path;
    final currentCodeBlock = <String>[];
    if (_lines.isEmpty) {
      _reporter.error('reached end of input, expect code block - "$infoPath"');
      return currentCodeBlock;
    }
    var line = _lines.removeAt(0);
    final openingCodeBlockLine = line;
    final firstLineMatch = codeBlockStartMarker.firstMatch(line);
    if (firstLineMatch == null || firstLineMatch[2] == null) {
      _reporter.error('code block should immediately follow <?code-excerpt?> - '
          '"$infoPath"\n  not: $line');
      return <String>[openingCodeBlockLine];
    }

    final newCodeBlockCode = args['diff-with'] == null
        ? _getter.getExcerpt(
            infoPath,
            info.region,
            [
              _plaster.codeTransformer(
                  args.containsKey('plaster')
                      ? args['plaster']
                      : filePlasterTemplate ?? globalPlasterTemplate,
                  _determineCodeLang(openingCodeBlockLine, info.path)),
              removeCodeTransformer(args['remove']),
              retainCodeTransformer(args['retain']),
              _replace.codeTransformer(args['replace']),
              fileAndCmdLineCodeTransformer,
            ].fold(null, compose),
          )
        : _differ.getDiff(infoPath, info.region, args,
            p.join(_getter.srcDirPath, _getter.pathBase));
    log.finer('>>> new code block code: $newCodeBlockCode');
    if (newCodeBlockCode == null) {
      // Error has been reported. Return while leaving existing code.
      // We could skip ahead to the end of the code block but that
      // will be handled by the outer loop.
      return <String>[openingCodeBlockLine];
    }

    final _codeBlockEndMarker = firstLineMatch[2].startsWith('`')
        ? codeBlockEndMarker
        : codeBlockEndPrettifyMarker;
    String closingCodeBlockLine;
    while (_lines.isNotEmpty) {
      line = _lines[0];
      final match = _codeBlockEndMarker.firstMatch(line);
      if (match == null) {
        _reporter.error('unterminated markdown code block '
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
      _reporter.error('unterminated markdown code block '
          'for <?code-excerpt "$infoPath"?>');
      return <String>[openingCodeBlockLine]..addAll(currentCodeBlock);
    }
    _numSrcDirectives++;
    final linePrefix = info.linePrefix;
    final indentBy =
        args['diff-with'] == null ? _getIndentBy(args['indent-by']) : 0;
    final indentation = ' ' * indentBy;
    final prefixedCodeExcerpt = newCodeBlockCode.map((line) {
      final _line =
          '$linePrefix$indentation$line'.replaceFirst(new RegExp(r'\s+$'), '');
      return this.escapeNgInterpolation
          ? _line.replaceAllMapped(new RegExp(r'({){|(})}'),
              (m) => '${m[1] ?? m[2]}!${m[1] ?? m[2]}')
          : _line;
    }).toList();
    if (!_listEq(currentCodeBlock, prefixedCodeExcerpt)) _numUpdatedFrag++;
    final result = <String>[openingCodeBlockLine]
      ..addAll(prefixedCodeExcerpt)
      ..add(closingCodeBlockLine);
    log.finer('>>> result: $result');
    return result;
  }

  int _getIndentBy(String indentByAsString) {
    if (indentByAsString == null) return defaultIndentation;
    String errorMsg = '';
    var result = 0;
    try {
      result = int.parse(indentByAsString);
    } on FormatException {
      errorMsg = 'error parsing integer value: $indentByAsString';
    }
    if (result < 0 || result > 100) {
      errorMsg = 'integer out of range: $result';
      result = 0;
    }
    if (errorMsg.isNotEmpty) {
      _reporter.error('<?code-excerpt?> indent-by: $errorMsg');
    }
    return result;
  }

  final RegExp _codeBlockLangSpec = new RegExp(r'(?:```|prettify\s+)(\w+)');

  String _determineCodeLang(String openingCodeBlockLine, String path) {
    final match = _codeBlockLangSpec.firstMatch(openingCodeBlockLine);
    if (match != null) return match[1];

    var ext = p.extension(path);
    if (ext.startsWith('.')) ext = ext.substring(1);
    return ext;
  }
}
