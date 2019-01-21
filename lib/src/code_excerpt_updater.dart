// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'code_transformer/core.dart';
import 'code_transformer/plaster.dart';
import 'code_transformer/replace.dart';
import 'constants.dart';
import 'differ.dart';
import 'issue_reporter.dart';
import 'logger.dart';
import 'util.dart';
import 'nullable.dart';

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
  final String srcDirPath;
  final int defaultIndentation;
  final bool escapeNgInterpolation;
  final bool excerptsYaml;
  final String globalReplaceExpr;
  final String globalPlasterTemplate;
  String filePlasterTemplate;
  Differ _differ;

  String _pathBase = ''; // init from <?code-excerpt path-base="..."?>
  CodeTransformer _appGlobalCodeTransformer;
  CodeTransformer _fileGlobalCodeTransformer;
  PlasterCodeTransformer _plaster;
  ReplaceCodeTransformer _replace;

  String _filePath = '';
  int _origNumLines = 0;
  List<String> _lines = [];

  int _numSrcDirectives = 0, _numUpdatedFrag = 0;

  IssueReporter _reporter;

  /// [err] defaults to [stderr].
  Updater(
    this.fragmentDirPath,
    this.srcDirPath, {
    this.defaultIndentation = 0,
    this.excerptsYaml = false,
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
    _differ = new Differ((path, region) => _getExcerpt(path, region, null), log,
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
    _pathBase = '';
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
      final info = _extractAndNormalizeArgs(match);

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
      _pathBase = info.args['path-base'] ?? '';
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
        ? _getExcerpt(
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
        : _differ.getDiff(
            infoPath, info.region, args, p.join(srcDirPath, _pathBase));
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
        args['diff-with'] == null ? getIndentBy(args['indent-by']) : 0;
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

  InstrInfo _extractAndNormalizeArgs(Match procInstrMatch) {
    final info = new InstrInfo(procInstrMatch[0]);
    log.finer(
        '>>> pIMatch: ${procInstrMatch.groupCount} - [${info.instruction}]');
    var i = 1;
    info.linePrefix = procInstrMatch[i++] ?? '';
    // The instruction is the first line in a markdown list.
    for (var c in ['-', '*']) {
      if (!info.linePrefix.contains(c)) continue;
      info.linePrefix = info.linePrefix.replaceFirst(c, ' ');
      break; // It can't contain both characters
    }
    i++; // final commentToken = match[i++];
    i++; // optional path+region
    final pathAndOptRegion = procInstrMatch[i++];
    info.unnamedArg = pathAndOptRegion;
    _extractAndNormalizeNamedArgs(info, procInstrMatch[i]);
    return info;
  }

  RegExp supportedArgs = new RegExp(
      r'^(class|diff-with|diff-u|from|indent-by|path-base|plaster|region|replace|remove|retain|title|to)$');
  RegExp argRegExp = new RegExp(r'^([-\w]+)\s*(=\s*"(.*?)"\s*|\b)\s*');

  void _extractAndNormalizeNamedArgs(InstrInfo info, String argsAsString) {
    if (argsAsString == null) return;
    String restOfArgs = argsAsString.trim();
    log.fine('>> __extractAndNormalizeNamedArgs: [$restOfArgs]');
    while (restOfArgs.isNotEmpty) {
      final match = argRegExp.firstMatch(restOfArgs);
      if (match == null) {
        _reporter.error(
            'instruction argument parsing failure at/around: $restOfArgs');
        break;
      }
      final argName = match[1];
      final argValue = match[3];
      info.args[argName] = argValue;
      log.finer(
          '  >> arg: $argName = ${argValue == null ? argValue : '"$argValue"'}');
      restOfArgs = restOfArgs.substring(match[0].length);
    }
    _processPathAndRegionArgs(info);
    _expandDiffPathBraces(info);
  }

  final RegExp pathBraces = new RegExp(r'^(.*?)\{(.*?),(.*?)\}(.*?)$');

  void _expandDiffPathBraces(InstrInfo info) {
    final match = pathBraces.firstMatch(info.path);
    if (match == null) return;
    info.path = match[1] + match[2] + match[4];
    info.args['diff-with'] = match[1] + match[3] + match[4];
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
    log.finer('>>> path="${info.path}", region="${info.region}"');
  }

  int getIndentBy(String indentByAsString) {
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

  @nullable
  Iterable<String> _getExcerpt(
      String relativePath, String region, CodeTransformer t) {
    String excerpt = _getExcerptAsString(relativePath, region);
    if (excerpt == null) return null; // Errors have been reported
    log.fine('>> excerpt before xform: "$excerpt"');
    if (t != null) excerpt = t(excerpt);
    final result = excerpt.split(eol);
    // All excerpts are [eol] terminated, so drop trailing blank lines
    while (result.length > 0 && result.last == '') result.removeLast();
    return trimMinLeadingSpace(result);
  }

  /// Look for a fragment file under [fragmentDirPath], failing that look for a
  /// source file under [srcDirPath]. If a file is found return its content as
  /// a string. Otherwise, report an error and return null.
  @nullable
  String _getExcerptAsString(String relativePath, String region) => excerptsYaml
      ? _getExcerptAsStringFromYaml(relativePath, region)
      : _getExcerptAsStringLegacy(relativePath, region);

  @nullable
  String _getExcerptAsStringFromYaml(String relativePath, String region) {
    final ext = '.excerpt.yaml';
    final excerptYamlPath =
        p.join(fragmentDirPath, _pathBase, relativePath + ext);
    YamlMap excerptsYaml;
    try {
      final contents = new File(excerptYamlPath).readAsStringSync();
      excerptsYaml = loadYaml(contents, sourceUrl: excerptYamlPath);
    } on FileSystemException {
      // Fall through
    }
    if (region.isEmpty && excerptsYaml == null) {
      // Continue: search for source file.
    } else if (excerptsYaml == null) {
      _reporter.error('cannot read file "$excerptYamlPath"');
      return null;
    } else if (excerptsYaml[region] == null) {
      _reporter.error('cannot read file "$excerptYamlPath"');
      return null;
    } else {
      return excerptsYaml[region].trimRight();
    }

    // ...
    final filePath = p.join(fragmentDirPath, _pathBase, relativePath);
    try {
      return new File(filePath).readAsStringSync();
    } on FileSystemException {
      _reporter.error('excerpt not found for "$relativePath"');
      return null;
    }
  }

  @nullable
  String _getExcerptAsStringLegacy(String relativePath, String region) {
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
        _reporter.error('cannot read fragment file "$fragPath"');
        return null;
      }
      // Fall through
    }

    // No fragment file file. Look for a source file with a matching file name.
    final String srcFilePath = p.join(srcDirPath, _pathBase, relativePath);
    try {
      return new File(srcFilePath).readAsStringSync();
    } on FileSystemException {
      _reporter.error('cannot find a source file "$srcFilePath", '
          'nor fragment file "$fragPath"');
      return null;
    }
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

  @override
  String toString() => 'InstrInfo: $linePrefix$instruction; args=$args';
}
