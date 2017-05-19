// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_excerpt_updater/code_excerpt_updater.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

const _testDir = 'test_data';

// TODO: enhance tests so that we can inspect the generated error messages.
// It might be easier to modify the updater to use an IOSink than to try to read stderr.

Updater updater;

String _readFile(String path) => new File(path).readAsStringSync();

String _srcFileName2Path(String fileName) => p.join(_testDir, 'src', fileName);

String getSrc(String relPath) => _readFile(_srcFileName2Path(relPath));
String getExpected(String relPath) =>
    _readFile(p.join(_testDir, 'expected', relPath));

void _stdFileTest(String testFileName) {
  test(testFileName, () {
    final testFileRelativePath = testFileName;
    // var originalSrc = getSrc(testFileRelativePath);
    final updatedDocs =
        updater.generateUpdatedFile(_srcFileName2Path(testFileRelativePath));
    expect(updatedDocs, getExpected(testFileName));
  });
}

void main() {
  group('Basic:', testsFromDefaultDir);
  group('Set path:', testSetPath);
}

void testsFromDefaultDir() {
  setUp(() {
    updater = new Updater(p.join(_testDir, 'frag'));
  });

  group('No change to doc;', () {
    final _testFileNames = [
      'no_src.dart',
      'no_comment_prefix.md',
      'basic_no_region.dart',
      'basic_with_region.dart',
      'frag_not_found.dart',
      'invalid_code_block.dart'
    ];

    _testFileNames.forEach((testFileName) {
      test(testFileName, () {
        final testFileRelativePath = p.join('no_change', testFileName);
        final originalSrc = getSrc(testFileRelativePath);
        final updatedDocs = updater
            .generateUpdatedFile(_srcFileName2Path(testFileRelativePath));
        expect(updatedDocs, originalSrc);
      });
    });
  });

  group('Code updates;', () {
    final _testFileNames = [
      'no_comment_prefix.md',
      'basic_no_region.dart',
      'basic_with_region.dart'
    ];

    _testFileNames.forEach(_stdFileTest);
  });

  group('Handle trailing space;', () {
    test('test input file has expected trailing whitespace', () {
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
    updater = new Updater(p.join(_testDir, ''));
  });

  _stdFileTest('set_path.md');
}
