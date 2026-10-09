import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'summary.dart';
import 'trip.dart';
import 'trip_store.dart';
import 'validation.dart';

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// HTTP API:
///   GET  /api/days               — дни, в которые были поездки
///   GET  /api/days/<YYYY-MM-DD>  — сводка и список поездок за день
///   POST /api/trips              — добавить поездку (идемпотентно по id)
Handler buildApi(TripStore store) {
  final router = Router()
    ..get('/api/days', (Request _) {
      return _json(200, {
        'utcOffset': formatOffset(store.offset),
        'days': [
          for (final e in store.days().entries)
            {'date': e.key, 'tripCount': e.value},
        ],
      });
    })
    ..get('/api/days/<date>', (Request _, String date) {
      if (!_isRealDate(date)) {
        return _error(400, 'Дата в формате YYYY-MM-DD');
      }
      final trips = store.forDay(date);
      return _json(200, {
        'date': date,
        'utcOffset': formatOffset(store.offset),
        'summary': DaySummary.of(trips).toJson(),
        'trips': [for (final t in trips) t.toJson(store.offset)],
      });
    })
    ..post('/api/trips', (Request req) async {
      final Object? body;
      try {
        body = jsonDecode(await req.readAsString());
      } on FormatException {
        return _error(400, 'Тело запроса — не JSON');
      }
      final parsed = parseTrip(body);
      if (!parsed.isValid) {
        return _json(
            422, {'error': 'Ошибка в данных', 'fields': parsed.errors});
      }
      final result = await store.add(parsed.trip!);
      final trip = result.trip.toJson(store.offset);
      return switch (result.status) {
        AddStatus.created => _json(201, {'created': true, 'trip': trip}),
        // Повтор той же поездки — успех без создания дубля.
        AddStatus.duplicate => _json(200, {'created': false, 'trip': trip}),
        AddStatus.idConflict => _json(409, {
            'error':
                'Поездка с id "${result.trip.id}" уже есть с другими данными',
            'existing': trip,
          }),
        AddStatus.overlap => _json(409, {
            'error': 'Пересекается по времени с поездкой "${result.trip.id}"',
            'existing': trip,
          }),
      };
    });

  return const Pipeline().addMiddleware(_cors()).addHandler(router.call);
}

/// DateTime.parse снисходителен («2026-02-31» → 3 марта), поэтому сверяем
/// дату с её нормализованной формой.
bool _isRealDate(String s) {
  if (!_dateRe.hasMatch(s)) return false;
  final d = DateTime.tryParse('${s}T00:00:00Z');
  return d != null && localDate(d, Duration.zero) == s;
}

Response _json(int status, Object body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Response _error(int status, String message) =>
    _json(status, {'error': message});

/// Клиент на Flutter Web ходит с другого origin — разрешаем CORS.
Middleware _cors() {
  const headers = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
  };
  return (inner) => (req) async {
        if (req.method == 'OPTIONS') return Response.ok(null, headers: headers);
        final res = await inner(req);
        return res.change(headers: headers);
      };
}
