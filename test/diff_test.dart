import 'package:code_excerpt_updater/src/diff/diff.dart';
import 'package:test/test.dart';

import 'hunk_test.dart';

final diff1head = '''
--- 1-base/lib/main.dart
+++ 2-use-package/lib/main.dart
'''
    .trim();

final diff1 = '$diff1head\n$hunk1';

final diff1TrimmedBefore = '$diff1head\n$hunk1TrimmedBefore';
final diff1TrimmedBeforeAndAfter = '$diff1head\n$hunk1TrimmedBeforeAndAfter';

/// A diff with two hunks
final diff2 = '$diff1\n$hunk2';

void main() {
  final classRE = new RegExp('^ class');
  final returnRE = new RegExp(r'^\s+return');
  final wontMatchRE = new RegExp('will not match');

  group('Idempotence on src', () {
    test('Empty diff', () {
      expect(new Diff('').toString(), '');
    });

    test('Diff with one hunk', () {
      final d = new Diff(diff1);
      expect(d.toString(), diff1);
    });

    test('Diff with more than one hunk', () {
      final d = new Diff(diff2);
      expect(d.toString(), diff2);
    });
  });

  group('Diff with one hunk:', () {
    Diff d;

    setUp(() => d = new Diff(diff1));

    group('Skip before "class":', () {
      test('dropLinesUntil', () {
        expect(d.dropLinesUntil(classRE), true);
        expect(d.toString(), diff1TrimmedBefore);
      });

      test('dropLines', () {
        expect(d.dropLines(from: classRE), true);
        expect(d.toString(), diff1TrimmedBefore);
      });
    });

    group('Skip before "class" until "return":', () {
      test('dropLinesUntil/dropLinesAfter', () {
        expect(d.dropLinesUntil(classRE), true);
        expect(d.dropLinesAfter(returnRE), true);
        expect(d.toString(), diff1TrimmedBeforeAndAfter);
      });

      test('dropLines', () {
        expect(d.dropLines(from: classRE, to: returnRE), true);
        expect(d.toString(), diff1TrimmedBeforeAndAfter);
      });
    });

    group('Skip all:', () {
      test('dropLinesUntil', () {
        expect(d.dropLinesUntil(wontMatchRE), false);
        expect(d.toString(), diff1head);
      });

      test('dropLines', () {
        expect(d.dropLines(from: wontMatchRE), false);
        expect(d.toString(), diff1head);
      });
    });
  });

  group('Diff with 2 hunks:', () {
    final d = new Diff(diff2);

    group('Skip before "class":', () {
      test('dropLinesUntil', () {
        expect(d.dropLinesUntil(classRE), true);
        expect(d.toString(), '$diff1TrimmedBefore\n$hunk2');
      });

      test('dropLines', () {
        expect(d.dropLines(from: classRE), true);
        expect(d.toString(), '$diff1TrimmedBefore\n$hunk2');
      });
    });

    test('Diff2: Skip before "class" until "return"', () {
      expect(d.dropLines(from: classRE, to: returnRE), true);
      expect(d.toString(), diff1TrimmedBeforeAndAfter);
    });
  });

  test('Diff using to regexp but no from regexp', () {
    var d = new Diff('$diff1head\n$hunk2');
    expect(d.dropLines(to: new RegExp(r'^\+\s+child:')), true);
    expect(d.toString(), '$diff1head\n$hunk2Trimmed');
  });
}

final hunk2Trimmed = '''
@@ -12,4 +14,4 @@
           title: Text('Welcome to Flutter'),
         ),
         body: Center(
-          child: Text('Hello World'),
+          child: Text(wordPair.asPascalCase),
'''
    .trim();
