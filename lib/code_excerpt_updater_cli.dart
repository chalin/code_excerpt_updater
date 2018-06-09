// Copyright (c) 2017. All rights reserved. Use of this source code
// is governed by a MIT-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:code_excerpt_updater/src/code_excerpt_updater.dart';
import 'package:args/args.dart';

const _commandName = 'code_excerpt_updater';
final _validExt = new RegExp(r'\.(dart|jade|md)$');

/// Processes `.dart` and `.md` files, recursively traverses directories
/// using [Updater]. See this command's help for CLI argument details.
class UpdaterCLI {
  static final _escapeNgInterpolationFlagName = 'escape-ng-interpolation';
  static final _fragmentDirPathFlagName = 'fragment-dir-path';
  static final _inPlaceFlagName = 'write-in-place';
  static final _indentFlagName = 'indentation';
  static final _plasterFlagName = 'plaster';
  static final _srcDirPathFlagName = 'src-dir-path';
  static final _yamlFlagName = 'yaml';

  static final _defaultPath =
      '(defaults to "", that is, the current working directory)';
  static final _replaceName = 'replace';

  final _parser = new ArgParser()
    ..addOption(_fragmentDirPathFlagName,
        abbr: 'p',
        help: 'PATH to directory containing code fragment files\n$_defaultPath.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.')
    ..addOption(_indentFlagName,
        abbr: 'i',
        defaultsTo: '0',
        help:
            'NUMBER. Default number of spaces to use as indentation for code inside code blocks.')
    ..addOption(_srcDirPathFlagName,
        abbr: 'q',
        help: 'PATH to directory containing code used in diffs\n$_defaultPath.')
    ..addFlag(_inPlaceFlagName,
        abbr: 'w',
        defaultsTo: false,
        negatable: false,
        help: 'Write updates to files in-place.')
    ..addFlag(_escapeNgInterpolationFlagName,
        defaultsTo: true,
        help: 'Escape Angular interpolation syntax {{...}} as {!{...}!}.')
    ..addOption(_plasterFlagName,
        help: 'TEMPLATE. Default plaster template to use for all files.\n'
        'For example, "// Insert your code here"; use "none" to remove plasters.'
    )
    ..addOption(_replaceName,
        help:
            'REPLACE-EXPRESSIONs. Global replace argument. See README for syntax.')
    ..addFlag(_yamlFlagName,
        negatable: false, help: 'Read excerpts from *.excerpt.yaml files.');

  bool escapeNgInterpolation;
  bool excerptsYaml;
  String fragmentDirPath, plasterTemplate, replaceExpr, srcDirPath;
  bool inPlaceFlag;
  int indentation;
  List<String> pathsToFileOrDir = [];

  bool argsAreValid = false;

  int numFiles = 0;
  int numSrcDirectives = 0;
  int numUpdatedFrag = 0;

  UpdaterCLI();

  void setArgs(List<String> argsAsStrings) {
    ArgResults args;
    try {
      args = _parser.parse(argsAsStrings);
    } on FormatException catch (e) {
      print('${e.message}\n');
      _printUsageAndExit(_parser, exitCode: 64);
    }
    pathsToFileOrDir = args.rest;

    if (args['help']) _printHelpAndExit(_parser);

    int i = 0;
    if (args[_indentFlagName] != null) {
      try {
        i = int.parse(args[_indentFlagName]);
      } on FormatException {
        _printUsageAndExit(_parser,
            msg: '$_indentFlagName: invalid value  "${args[_indentFlagName]}"');
      }
    }
    indentation = i;

    if (pathsToFileOrDir.length < 1)
      _printUsageAndExit(_parser, msg: 'Expecting one or more path arguments');

    escapeNgInterpolation = args[_escapeNgInterpolationFlagName];
    excerptsYaml = args[_yamlFlagName] ?? false;
    fragmentDirPath = args[_fragmentDirPathFlagName] ?? '';
    inPlaceFlag = args[_inPlaceFlagName];
    plasterTemplate = args[_plasterFlagName];
    replaceExpr = args[_replaceName] ?? '';
    srcDirPath = args[_srcDirPathFlagName] ?? '';

    argsAreValid = true;
  }

  /// Process files/directories given as CLI arguments.
  Future<Null> processArgs() async {
    if (!argsAreValid)
      throw new Exception('Cannot proceed without valid arguments');

    for (final entityPath in pathsToFileOrDir) {
      await _processEntity(entityPath, warnAboutNonDartFile: true);
    }
  }

  Future _processEntity(String path, {bool warnAboutNonDartFile: false}) async {
    final type = await FileSystemEntity.type(path);
    switch (type) {
      case FileSystemEntityType.DIRECTORY:
        return _processDirectory(path);
      case FileSystemEntityType.FILE:
        if (_validExt.hasMatch(path)) return _processFile(path);
    }
    if (warnAboutNonDartFile) {
      final kind =
          type == FileSystemEntityType.NOT_FOUND ? 'existent' : 'Dart/Markdown';
      stderr.writeln('Warning: skipping non-$kind file "$path" ($type)');
    }
  }

  final _dotPubPathRe = new RegExp(r'(^|/).pub($|/)');

  /// Process (recursively) the entities in the directory [path], ignoring
  /// non-Dart and non-directory entities.
  Future _processDirectory(String path) async {
    final dir = new Directory(path);
    final entityList = dir.list(recursive: true, followLinks: false);
    await for (FileSystemEntity entity in entityList) {
      final filePath = entity.path;
      if (filePath.contains(_dotPubPathRe)) continue;
      if (!_validExt.hasMatch(filePath)) continue;
      // Not testing for entity type as it is almost certainly a file. Only warn
      // about files with invalid extensions when explicitly listed on cmd line.
      await _processFile(filePath);
    }
  }

  Future _processFile(String filePath) async {
    try {
      await _updateFile(filePath);
      numFiles++;
    } catch (e) {
      stderr.writeln('Error processing "$filePath": $e');
      exitCode = 2;
    }
  }

  Future _updateFile(String filePath) async {
    final updater = new Updater(
      fragmentDirPath,
      srcDirPath,
      defaultIndentation: indentation,
      escapeNgInterpolation: escapeNgInterpolation,
      globalPlasterTemplate: plasterTemplate,
      globalReplaceExpr: replaceExpr,
      excerptsYaml: excerptsYaml,
    );
    final result = updater.generateUpdatedFile(filePath);

    numSrcDirectives += updater.numSrcDirectives;
    numUpdatedFrag += updater.numUpdatedFrag;

    if (!inPlaceFlag) {
      print(result);
    } else if (updater.numUpdatedFrag > 0) {
      await new File(filePath).writeAsString(result);
    }
  }

  void _printHelpAndExit(ArgParser parser) {
    print('Use $_commandName to update code fragments within markdown '
        'code blocks preceded with <?code-excerpt?> directives. '
        '(See the tool\'s GitHub repo README for details.)\n');
    _printUsageAndExit(parser);
  }

  void _printUsageAndExit(ArgParser parser, {String msg, int exitCode: 1}) {
    if (msg != null) print('\n$msg\n');
    print('Usage: $_commandName [OPTIONS] file_or_directory...\n');
    print(parser.usage);
    exit(exitCode);
  }
}
