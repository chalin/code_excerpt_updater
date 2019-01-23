import 'instr_info.dart';
import 'issue_reporter.dart';
import 'logger.dart';

class ArgProcessor {
  ArgProcessor(this._reporter);

  final IssueReporter _reporter;

  InstrInfo extractAndNormalizeArgs(Match procInstrMatch) {
    final info = new InstrInfo(procInstrMatch[0]);
    log.finer(
        '>>> pIMatch: ${procInstrMatch.groupCount} - [${info.instruction}]');
    var i = 1;
    info.linePrefix = procInstrMatch[i++] ?? '';
    // The instruction is the first line in a markdown list.
    for (var c in ['-', '*']) {
      if (!info.linePrefix.contains(c)) continue;
      info.linePrefix = info.linePrefix.replaceFirst(c, ' ');
      break; // It can't contain both characters
    }
    i++; // final commentToken = match[i++];
    i++; // optional path+region
    final pathAndOptRegion = procInstrMatch[i++];
    info.unnamedArg = pathAndOptRegion;
    _extractAndNormalizeNamedArgs(info, procInstrMatch[i]);
    return info;
  }

  RegExp supportedArgs = new RegExp(
      r'^(class|diff-with|diff-u|from|indent-by|path-base|plaster|region|replace|remove|retain|title|to)$');
  RegExp argRegExp = new RegExp(r'^([-\w]+)\s*(=\s*"(.*?)"\s*|\b)\s*');

  void _extractAndNormalizeNamedArgs(InstrInfo info, String argsAsString) {
    if (argsAsString == null) return;
    String restOfArgs = argsAsString.trim();
    log.fine('>> __extractAndNormalizeNamedArgs: [$restOfArgs]');
    while (restOfArgs.isNotEmpty) {
      final match = argRegExp.firstMatch(restOfArgs);
      if (match == null) {
        _reporter.error(
            'instruction argument parsing failure at/around: $restOfArgs');
        break;
      }
      final argName = match[1];
      final argValue = match[3];
      info.args[argName] = argValue;
      log.finer(
          '  >> arg: $argName = ${argValue == null ? argValue : '"$argValue"'}');
      restOfArgs = restOfArgs.substring(match[0].length);
    }
    _processPathAndRegionArgs(info);
    _expandDiffPathBraces(info);
  }

  final RegExp pathBraces = new RegExp(r'^(.*?)\{(.*?),(.*?)\}(.*?)$');

  void _expandDiffPathBraces(InstrInfo info) {
    final match = pathBraces.firstMatch(info.path);
    if (match == null) return;
    if (info.args['diff-with'] != null) {
      final msg = "You can't use both the brace syntax and the diff-with "
          "argument; choose one or the other.";
      _reporter.error(msg);
    }
    info.path = match[1] + match[2] + match[4];
    info.args['diff-with'] = match[1] + match[3] + match[4];
  }

  final RegExp regionInPath = new RegExp(r'\s*\((.+)\)\s*$');
  final RegExp nonWordChars = new RegExp(r'[^\w]+');

  void _processPathAndRegionArgs(InstrInfo info) {
    final path = info.unnamedArg;
    if (path == null) return;
    final match = regionInPath.firstMatch(path);
    if (match == null) {
      info.path = path;
    } else {
      // Remove region from path
      info.path = path.substring(0, match.start);
      info.region = match[1]?.replaceAll(nonWordChars, '-');
    }
    log.finer('>>> path="${info.path}", region="${info.region}"');
  }
}
