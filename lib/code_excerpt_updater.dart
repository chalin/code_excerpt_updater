// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

const _eol = '\n';
Function _listEq = const ListEquality().equals;

/// A simple line-based updater for markdown code-blocks. It processes given
/// files line-by-line, looking for matches to [procInstrRE] contained within
/// markdown code blocks.
///
/// Returns, as a string, a version of the given file source, with the
/// `<?code-excerpt...?>` code fragments updated. Fragments are read from the
/// [fragmentPathPrefix] directory.
class Updater {
  final String fragmentPathPrefix;

  String _filePath = '';
  List<String> _lines = [];

  int _numSrcDirectives = 0, _numUpdatedFrag = 0;

  Updater(this.fragmentPathPrefix);

  int get numSrcDirectives => _numSrcDirectives;
  int get numUpdatedFrag => _numUpdatedFrag;

  /// Returns the content of the file at [path] with code blocks updated.
  /// Missing fragment files are reported via stderr.
  /// If [path] cannot be read then an exception is thrown.
  String generateUpdatedFile(String path) {
    _filePath = path == null || path.isEmpty ? 'unnamed-file' : path;
    return _updateSrc(new File(path).readAsStringSync());
  }

  String _updateSrc(String dartSource) {
    _lines = dartSource.split(_eol);
    return _processLines();
  }

  /// Regex matching code-excerpt processing instructions
  final RegExp procInstrRE = new RegExp(
      r'^(\s*(///?\s*)?)?<\?code-excerpt\s+"([^"]+)"((\s+[-\w]+="[^"]+"\s*)*)\??>');

  /// Regex matching @source lines
  final RegExp sourceRE = new RegExp(
      r'^(///\s*)((<!--|///?)\s*)?{@source\s+"([^"}]+)"((\s+region=")([^"}]+)"\s*)?}');

  String _processLines() {
    final List<String> output = [];
    while (_lines.isNotEmpty) {
      final line = _lines.removeAt(0);
      output.add(line);
      var match = sourceRE.firstMatch(line);
      if (match != null) {
        output.addAll(_getUpdatedCodeBlock(match));
        continue;
      }
      match = procInstrRE.firstMatch(line);
      if (match == null) continue;
      output.addAll(_getUpdatedCodeBlock2(match));
    }
    return output.join(_eol);
  }

  /// Expects the next lines to be a markdown code block.
  /// Side-effect: consumes code-block lines.
  Iterable<String> _getUpdatedCodeBlock2(Match procInstrMatch) {
    // stderr.writeln('>>> pIMatch: ${procInstrMatch.groupCount} - [${procInstrMatch[0]}]');
    var i = 1;
    final linePrefix = procInstrMatch[i++] ?? '';
    i++; // final commentToken = match[i++];
    final pathAndOptRegion = procInstrMatch[i++];
    final args = {'path': pathAndOptRegion};
    _extractAndNormalizeArgs(args, procInstrMatch[i]);
    final pathToCodeExcerpt = args['path'];
    final region = args['region'];
    // stderr.writeln('>>> arg: region = "${region}"');

    // TODO: only match on same prefix.
    final codeBlockMarker = new RegExp(r'^\s*(///?)?\s*(```)?');
    final currentCodeBlock = <String>[];
    if (_lines.isEmpty) {
      stderr.writeln('Error: $_filePath: reached end of input, '
          'expect code block - "$pathToCodeExcerpt"');
      return currentCodeBlock;
    }
    var line = _lines.removeAt(0);
    final openingCodeBlockLine = line;
    final firstLineMatch = codeBlockMarker.firstMatch(line);
    if (firstLineMatch == null || firstLineMatch[2] == null) {
      stderr.writeln('Error: $_filePath: '
          'code block should immediately follow <?code-excerpt?> - '
          '"$pathToCodeExcerpt"\n  not: $line');
      return <String>[openingCodeBlockLine];
    }

    final newCodeExcerpt = _getExcerpt(pathToCodeExcerpt, region);
    // stderr.writeln('>>> got new excerpt: $newCodeExcerpt');
    if (newCodeExcerpt == null) {
      // Error has been reported. Return while leaving existing code.
      // We could skip ahead to the end of the code block but that
      // will be handled by the outer loop.
      return <String>[openingCodeBlockLine];
    }
    String closingCodeBlockLine;
    while (_lines.isNotEmpty) {
      line = _lines[0];
      // stderr.writeln('>>> looking for closing got line: $line');
      final match = codeBlockMarker.firstMatch(line);
      if (match == null) {
        // TODO: it would be nice if we could print a line number too.
        stderr.writeln('Error: $_filePath: unterminated markdown code block '
            'for <?code-excerpt "$pathToCodeExcerpt"?>');
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
      return <String>[openingCodeBlockLine]..addAll(currentCodeBlock);
    }
    _numSrcDirectives++;
    final indentation = ' ' * getIndentBy(args['indent-by']);
    final prefixedCodeExcerpt = newCodeExcerpt
        .map((line) => '$linePrefix$indentation$line'
            .replaceFirst(new RegExp(r'\s+$'), ''))
        .toList();
    if (!_listEq(currentCodeBlock, prefixedCodeExcerpt)) _numUpdatedFrag++;
    final result = <String>[openingCodeBlockLine]
      ..addAll(prefixedCodeExcerpt)
      ..add(closingCodeBlockLine);
    // stderr.writeln('>>> result: $result');
    return result;
  }

  void _extractAndNormalizeArgs(Map<String, String> args, String argsAsString) {
    if (argsAsString == null) return;

    final RegExp procInstrArgRE = new RegExp(r'(\s*([-\w]+)=")([^"}]+)"\s*');
    final matches = procInstrArgRE.allMatches(argsAsString);
    // stderr.writeln('>>> arg ${matches.length} from $argsAsString');

    for (final match in matches) {
      // stderr.writeln('>>> arg: "${match[0]}"');
      final argName = match[2];
      final argValue = match[3];
      if (argName == null) continue;
      args[argName] = argValue ?? '';
      // stderr.writeln('>>> arg: $argName = "${args[argName]}"');
    }
    _processPathAndRegionArgs(args);
  }

  final RegExp regionInPath = new RegExp(r'\s*\((.+)\)\s*$');
  final RegExp nonWordChars = new RegExp(r'[^\w]+');

  void _processPathAndRegionArgs(Map<String, String> args) {
    final path = args['path'];
    final match = regionInPath.firstMatch(path);
    String region;
    if (match != null) {
      // Remove region spec from path
      args['path'] = path.substring(0, match.start);
      region = match[1]?.replaceAll(nonWordChars, '-');
    }
    args.putIfAbsent('region', () => region ?? '');
    // stderr.writeln('>>> path="${args['path']}", region="${args['region']}"');
  }

  int getIndentBy(String indentByAsString) {
    if (indentByAsString == null) return 0;
    String errorMsg = '';
    final result = int.parse(indentByAsString, onError: (s) {
      errorMsg = 'error parsing integer value: $s';
      return 0;
    });
    if (result < 0 || result > 100) errorMsg = 'integer out of range: $result';
    if (errorMsg.isNotEmpty) {
      stderr
          .writeln('Error: $_filePath: <?code-excerpt?> indent-by: $errorMsg');
    }
    return result;
  }

  /// Side-effect: consumes code-block lines of [_lines].
  Iterable<String> _getUpdatedCodeBlock(Match match) {
    var i = 1;
    final linePrefix = match[i++];
    i++; // final commentTokenWithSapce = match[i++];
    i++; // final commentTokenWith = match[i++];
    final relativePath = match[i++];
    i++; // final regionArgWithSpaceAndArg = match[i++]; // e.g., '  region="abc"  '
    i++; // final regionArgWithSpace = match[i++]; // e.g., '  region='
    final region = match[i++] ?? ''; // e.g., 'abc'

    final newCodeExcerpt = _getExcerpt(relativePath, region);
    if (newCodeExcerpt == null) {
      // Error has been reported. Return while leaving existing code.
      // We could skip ahead to the end of the code block but that
      // will be handled by the outer loop.
      return <String>[];
    }
    var line;
    final currentCodeBlock = <String>[];
    final publicApiRegEx = new RegExp(r'^///\s*(```)?');
    while (_lines.isNotEmpty) {
      line = _lines[0];
      final match = publicApiRegEx.firstMatch(line);
      if (match == null) {
        // TODO: it would be nice if we could print a line number too.
        stderr.writeln(
            'Error: $_filePath: unterminated markdown code block for @source "$relativePath"');
        return <String>[];
      } else if (match[1] != null) {
        // We've found the closing code-block marker.
        break;
      }
      currentCodeBlock.add(line);
      _lines.removeAt(0);
    }
    _numSrcDirectives++;
    final prefixedCodeExcerpt =
        newCodeExcerpt.map((line) => '$linePrefix$line'.trim()).toList();
    if (!_listEq(currentCodeBlock, prefixedCodeExcerpt)) _numUpdatedFrag++;
    return prefixedCodeExcerpt;
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

    final String fullPath = p.join(fragmentPathPrefix, file);
    try {
      final result = new File(fullPath).readAsStringSync().split(_eol);
      // All excerpts are [_eol] terminated, so drop the last blank line
      while (result.length > 0 && result.last == '') result.removeLast();
      return result;
    } on FileSystemException catch (e) {
      stderr.writeln(
          'Error: $_filePath: cannot read fragment file "$fullPath"\n$e');
      return null;
    }
  }
}
