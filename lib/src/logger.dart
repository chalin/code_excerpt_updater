import 'package:logging/logging.dart';

final Logger log = new Logger('CEU');

bool _loggerInitialized = false;

void initLogger([Level defaultLevel = Level.WARNING]) {
  if (_loggerInitialized) return;
  Logger.root.level = defaultLevel;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });
  _loggerInitialized = true;
}
