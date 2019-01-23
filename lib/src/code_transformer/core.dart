/// Collected code transformer and predicate declarations

import '../constants.dart';
import '../nullable.dart';
import '../matcher.dart';

typedef CodeTransformer = String Function(String code);

CodeTransformer compose(CodeTransformer f, CodeTransformer g) =>
    f == null ? g : g == null ? f : (String s) => g(f(s));

CodeTransformer _retain(Matcher p) => (String code) {
      final lines = code.split(eol)..retainWhere(p);
      return lines.join(eol);
    };

//---
// Specific transformers
//---

@nullable
CodeTransformer fromCodeTransformer(String arg) {
  final matcher = patternArgToMatcher(arg, 'from');
  if (matcher == null) return null;
  return (String code) {
    final lines = code.split(eol).skipWhile(not(matcher));
    return lines.join(eol);
  };
}

@nullable
CodeTransformer removeCodeTransformer(String arg) {
  final matcher = patternArgToMatcher(arg, 'remove');
  return matcher == null ? null : _retain(not(matcher));
}

@nullable
CodeTransformer retainCodeTransformer(String arg) {
  final matcher = patternArgToMatcher(arg, 'retain');
  return matcher == null ? null : _retain(matcher);
}

@nullable
CodeTransformer toCodeTransformer(String arg) {
  final matcher = patternArgToMatcher(arg, 'to');
  if (matcher == null) return null;
  return (String code) {
    final lines = code.split(eol);
    final i = _indexWhere(lines, matcher); // lines.indexWhere(matcher)
    if (i < 0) return code;
    return lines.take(i + 1).join(eol);
  };
}

/// Patch: 1.24.3 doesn't have Iterable.indexWhere(). Drop this once we drop 1.x
int _indexWhere(List<String> list, bool test(String s)) {
  for (var i = 0; i < list.length; i++) {
    if (test(list[i])) return i;
  }
  return -1;
}
