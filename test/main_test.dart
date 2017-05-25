// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_excerpt_updater/code_excerpt_updater.dart';
import 'package:path/path.dart' as p;
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

const _testDir = 'test_data';

// TODO: enhance tests so that we can inspect the generated error messages.
// It might be easier to modify the updater to use an IOSink than to try to read stderr.

Updater updater;
Stdout _stderr;

String _readFile(String path) => new File(path).readAsStringSync();

String _srcFileName2Path(String fileName) => p.join(_testDir, 'src', fileName);
String _expectedFn2Path(String relPath) =>
    p.join(_testDir, 'expected', relPath);

String getSrc(String relPath) => _readFile(_srcFileName2Path(relPath));
String getExpected(String relPath) => _readFile(_expectedFn2Path(relPath));

final _errMsgs = {
  'no_change/frag_not_found.dart':
      'Error: test_data/src/no_change/frag_not_found.dart: '
      'cannot read fragment file "test_data/frag/dne.xzy.txt"\n'
      "FileSystemException: Cannot open file, path = "
      "'test_data/frag/dne.xzy.txt' "
      "(OS Error: No such file or directory, errno = 2)",
  'no_change/invalid_code_block.dart':
      'Error: test_data/src/no_change/invalid_code_block.dart: '
      'unterminated markdown code block for <?code-excerpt "quote.md"?>',
  'no_change/missing_code_block.dart':
      'Error: test_data/src/no_change/missing_code_block.dart: '
      'code block should immediately follow <?code-excerpt?> - "quote.md"\n'
      '  not: int x = 0;',
  'no_change/no_path.md':
      'Warning: test_data/src/no_change/no_path.md: instruction ignored: <?code-excerpt title="abc"?>;'
      'Warning: test_data/src/no_change/no_path.md: instruction ignored: <?code-excerpt?>',
};

void _stdFileTest(String testFilePath) {
  // print('>> testing $testFilePath');
  final testFileName = p.basename(testFilePath);
  test(testFileName, () {
    final testFileRelativePath = testFilePath;
    // var originalSrc = getSrc(testFileRelativePath);
    final updatedDocs =
        updater.generateUpdatedFile(_srcFileName2Path(testFileRelativePath));

    final expectedErr = _errMsgs[testFilePath];
    if (expectedErr == null) {
      verifyZeroInteractions(_stderr);
    } else {
      final vr = verify(_stderr.writeln(captureAny));
      expect(vr.captured.join(';'), expectedErr);
    }

    final expectedDoc = new File(_expectedFn2Path(testFilePath)).existsSync()
        ? getExpected(testFilePath)
        : getSrc(testFilePath);
    expect(updatedDocs, expectedDoc);
  });
}

class MockStderr extends Mock implements Stdout {}

void main() {
  group('Basic:', testsFromDefaultDir);
  group('Set path:', testSetPath);
  group('Default indentation:', testDefaultIndentation);
}

void testsFromDefaultDir() {
  setUp(() {
    _stderr = new MockStderr();
    updater = new Updater(p.join(_testDir, 'frag'), err: _stderr);
  });

  group('No change to doc;', () {
    setUp(() => clearInteractions(_stderr));

    final _testFileNames = [
      'basic_no_region.dart',
      'basic_with_region.dart',
      'frag_not_found.dart',
      'invalid_code_block.dart',
      'missing_code_block.dart',
      'no_comment_prefix.md',
      'no_path.md',
      'no_src.dart',
    ].map((fn) => p.join('no_change', fn));

    _testFileNames.forEach(_stdFileTest);
  });

  group('Code updates;', () {
    final _testFileNames = [
      'no_comment_prefix.md',
      'basic_no_region.dart',
      'basic_with_region.dart',
    ];

    _testFileNames.forEach(_stdFileTest);
  });

  group('Handle trailing space;', () {
    test('ensure input file has expected trailing whitespace', () {
      final fragPath = p.join(
          updater.fragmentDirPath, 'frag_with_trailing_whitespace.dart.txt');
      final frag = _readFile(fragPath);
      expect(frag.endsWith('\t \n\n'), isTrue);
    });

    _stdFileTest('trim.dart');
  });
}

void testSetPath() {
  setUp(() {
    updater = new Updater(p.join(_testDir, ''), err: _stderr);
  });

  _stdFileTest('set_path.md');
}

void testDefaultIndentation() {
  setUp(() {
    updater = new Updater(p.join(_testDir, 'frag'),
        defaultIndentation: 2, err: _stderr);
  });

  _stdFileTest('basic_with_region.jade');
}
