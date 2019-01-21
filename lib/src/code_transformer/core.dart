/// Collected code transformer and predicate declarations

import '../constants.dart';
import '../nullable.dart';
import '../matcher.dart';

typedef CodeTransformer = String Function(String code);

CodeTransformer compose(CodeTransformer f, CodeTransformer g) =>
    f == null ? g : g == null ? f : (String s) => g(f(s));

CodeTransformer lineMatcherToCodeTransformer(Matcher p) => (String code) {
      final lines = code.split(eol)..retainWhere(p);
      return lines.join(eol);
    };

//---
// Specific transformers
//---

@nullable
CodeTransformer removeCodeTransformer(String arg) {
  final matcher = patternArgToMatcher(arg, 'remove');
  return matcher == null ? null : lineMatcherToCodeTransformer(not(matcher));
}

@nullable
CodeTransformer retainCodeTransformer(String arg) {
  final matcher = patternArgToMatcher(arg, 'retain');
  return matcher == null ? null : lineMatcherToCodeTransformer(matcher);
}
