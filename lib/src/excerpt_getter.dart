import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'code_transformer/core.dart';
import 'constants.dart';
import 'issue_reporter.dart';
import 'logger.dart';
import 'nullable.dart';
import 'util.dart';

class ExcerptGetter {
  ExcerptGetter(
      this.excerptsYaml, this.fragmentDirPath, this.srcDirPath, this._reporter);

  final bool excerptsYaml;
  final String fragmentDirPath;
  final String srcDirPath;
  final IssueReporter _reporter;

  String pathBase;

  @nullable
  Iterable<String> getExcerpt(
      // String pathBase,
      String relativePath,
      String region,
      CodeTransformer t) {
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
        p.join(fragmentDirPath, pathBase, relativePath + ext);
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
    final filePath = p.join(fragmentDirPath, pathBase, relativePath);
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
    final String fragPath = p.join(fragmentDirPath, pathBase, file);
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
    final String srcFilePath = p.join(srcDirPath, pathBase, relativePath);
    try {
      return new File(srcFilePath).readAsStringSync();
    } on FileSystemException {
      _reporter.error('cannot find a source file "$srcFilePath", '
          'nor fragment file "$fragPath"');
      return null;
    }
  }
}
