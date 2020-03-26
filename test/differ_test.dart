import 'package:code_excerpt_updater/src/constants.dart';
import 'package:code_excerpt_updater/src/differ.dart';
import 'package:code_excerpt_updater/src/excerpt_getter.dart';
import 'package:code_excerpt_updater/src/issue_reporter.dart';
import 'package:code_excerpt_updater/src/logger.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

const _testDir = 'test_data';

void main() {
  final excerptsYaml = false;
  final fragmentDirPath = '$_testDir/diff_src';
  final srcDirPath = fragmentDirPath;
  final _reporter =
      IssueReporter(IssueContext(() => 'unused/path/to/file', () => 1));
  final _getter =
      ExcerptGetter(excerptsYaml, fragmentDirPath, srcDirPath, _reporter);
  final _differ = Differ(
      (path, region) => _getter.getExcerpt(path, region), log, _reporter.error);

  initLogger(Level.WARNING);

  test('layout_lakes', () {
    final args = {
      'diff-with': 'layout_lakes/interactive_main.dart',
      'remove': '*3*',
      'from': 'class MyApp',
      'to': '}',
    };
    var diff =
        _differ.getDiff('layout_lakes/step6_main.dart', '', args, srcDirPath);
    expect(diff.join(eol), expected_diff);
  });
}

final expected_diff = '''
--- layout_lakes/step6_main.dart
+++ layout_lakes/interactive_main.dart
@@ -10,2 +5,2 @@
 class MyApp extends StatelessWidget {
   @override
@@ -38,11 +33,7 @@
               ],
             ),
           ),
-          Icon(
-            Icons.star,
-            color: Colors.red[500],
-          ),
-          Text('41'),
+          FavoriteWidget(),
         ],
       ),
     );
@@ -117,2 +108,2 @@
     );
   }
'''
    .trim();
