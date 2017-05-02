// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

const _eol = '\n';
Function _listEq = const ListEquality().equals;

/// A simple line-based API doc updater for `{@source}` directives. It
/// processes the given Dart source file line-by-line, looking for matches to
/// [sourceRE] contained within markdown code blocks.
///
/// Returns, as a string, a version of the given file source, with the
/// `{@source ...}` code fragments updated. Fragments are read from the
/// [fragmentPathPrefix] directory.
class Updater {
  final String fragmentPathPrefix;

  String _filePath = '';
  List<String> _lines = [];

  int _numSrcDirectives = 0, _numUpdatedFrag = 0;

  Updater(this.fragmentPathPrefix);

  int get numSrcDirectives => _numSrcDirectives;
  int get numUpdatedFrag => _numUpdatedFrag;

  /// Returns the content of the file at [path] with the `{@source}` fragments updated.
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

  /// Regex matching @source lines
  final RegExp sourceRE = new RegExp(
      r'^(///\s*)((<!--|///?)\s*)?{@source\s+"([^"}]+)"((\s+region=")([^"}]+)"\s*)?}');

  String _processLines() {
    final List<String> output = [];
    while (_lines.isNotEmpty) {
      final line = _lines.removeAt(0);
      final match = sourceRE.firstMatch(line);
      output.add(line);
      if (match == null) continue;
      output.addAll(_getUpdatedCodeBlock(match));
    }
    return output.join(_eol);
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
