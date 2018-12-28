import '../nullable.dart';
import 'hunk.dart';

/// Representation of a unified diff
class Diff {
  String _rawText;
  bool parsed = false;

  List<String> fileInfo;
  List<Hunk> hunks;

  Diff(this._rawText);

  /// Drop non-header hunk lines until a line matching [from] is found. Then
  /// keep all lines until a line matching [to] is found; drop any
  /// remaining lines. Returns true iff [from] was matched.
  bool dropLines({RegExp from, RegExp to}) {
    if (!parsed) parse();
    var matchFound = false;
    if (from != null) {
      while (hunks.isNotEmpty) {
        final hunk = hunks.first;
        if (hunk.dropLinesUntil(from)) {
          matchFound = true;
          break;
        }
        hunks.removeAt(0);
      }
    }
    if (to == null) return matchFound;

    for (var i = 0; i < hunks.length; i++) {
      final hunk = hunks[i];
      if (hunk.dropLinesAfter(to)) {
        hunks = hunks.take(i + 1).toList();
        return true;
      }
    }
    return false;
  }

  bool dropLinesUntil(RegExp regExp) {
    if (!parsed) parse();
    while (hunks.isNotEmpty) {
      final hunk = hunks.first;
      if (hunk.dropLinesUntil(regExp)) return true;
      hunks.removeAt(0);
    }
    return false;
  }

  bool dropLinesAfter(RegExp regExp) {
    if (!parsed) parse();
    for (final hunk in hunks) {
      if (hunk.dropLinesAfter(regExp)) return true;
    }
    return false;
  }

  void parse() {
    if (parsed || _rawText.isEmpty) return;
    parsed = true;

    final lines = _rawText.split(eol);
    var i = 0;
    fileInfo = [lines[i++], lines[i++]];

    hunks = [];
    while (i < lines.length) {
      if (!lines[i].startsWith('@@')) throw _invalidHunk(i);
      var start = i++;
      // Look for the start of the next hunk or the end of the diff
      while (i < lines.length && !lines[i].startsWith('@@')) i++;
      hunks.add(new Hunk(lines.skip(start).take(i - start).join(eol)));
    }
  }

  @override
  String toString() => !parsed
      ? _rawText
      : hunks.isEmpty
          ? fileInfo.join(eol)
          : '${fileInfo.join(eol)}\n${hunks.join(eol)}';

  Exception _invalidHunk(int lineNum) =>
      new Exception('Invalid hunk syntax. Expected "@@" at line $lineNum.');
}
