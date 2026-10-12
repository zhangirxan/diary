import 'dart:io';

import 'package:driver_diary_server/driver_diary_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Настройки через переменные окружения:
///   PORT       — порт (по умолчанию 8095)
///   DATA_FILE  — JSON с поездками (по умолчанию data/trips.json)
///   TZ_OFFSET  — часовой пояс водителя (по умолчанию +05:00)
Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['PORT'] ?? '8095');
  final offset = parseOffset(env['TZ_OFFSET'] ?? '+05:00');
  final file = File(env['DATA_FILE'] ?? 'data/trips.json');
  // Рабочий файл не в git: при первом запуске копируем пример.
  final sample = File('data/trips.sample.json');
  if (!await file.exists() && await sample.exists()) {
    await sample.copy(file.path);
  }

  final store = await TripStore.open(file, offset: offset);
  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(buildApi(store));

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Загружено поездок: ${store.length} из ${file.path}');
  stdout.writeln('API: http://localhost:${server.port}/api/days');
}
