import 'dart:convert';
import 'dart:io';

import 'package:driver_diary_server/driver_diary_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const almaty = Duration(hours: 5);

Map<String, Object?> tripJson({
  String id = 't1',
  String start = '2026-10-01T08:10:00+05:00',
  String end = '2026-10-01T08:32:00+05:00',
  Object? amount = 2400,
  Object? payment = 'card',
  Object? commission = 360,
}) =>
    {
      'id': id,
      'start': start,
      'end': end,
      'amount': amount,
      'payment': payment,
      'commission': commission,
    };

void main() {
  late TripStore store;
  late Handler api;

  setUp(() {
    store = TripStore(offset: almaty);
    api = buildApi(store);
  });

  Future<(int, Map<String, Object?>)> call(String method, String path,
      [Object? body]) async {
    final res = await api(Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
    ));
    return (
      res.statusCode,
      jsonDecode(await res.readAsString()) as Map<String, Object?>
    );
  }

  group('Защита от дублей', () {
    test('повторная отправка той же поездки не создаёт дубль', () async {
      final (s1, b1) = await call('POST', '/api/trips', tripJson());
      final (s2, b2) = await call('POST', '/api/trips', tripJson());

      expect(s1, 201);
      expect(b1['created'], true);
      expect(s2, 200);
      expect(b2['created'], false);
      expect(store.length, 1);

      final (_, day) = await call('GET', '/api/days/2026-10-01');
      expect(day['trips'], hasLength(1));
      expect((day['summary'] as Map)['revenue'], 2400);
    });

    test('тот же момент в другой записи (UTC) — тоже дубль', () async {
      await call('POST', '/api/trips', tripJson());
      final (s, b) = await call('POST', '/api/trips',
          tripJson(start: '2026-10-01T03:10:00Z', end: '2026-10-01T03:32:00Z'));
      expect(s, 200);
      expect(b['created'], false);
      expect(store.length, 1);
    });

    test('одновременные одинаковые запросы создают одну запись', () async {
      final results = await Future.wait(
          List.generate(10, (_) => call('POST', '/api/trips', tripJson())));
      expect(results.where((r) => r.$1 == 201), hasLength(1));
      expect(results.where((r) => r.$1 == 200), hasLength(9));
      expect(store.length, 1);
    });

    test('тот же id с другими данными — 409, старая запись не меняется',
        () async {
      await call('POST', '/api/trips', tripJson());
      final (s, _) = await call('POST', '/api/trips', tripJson(amount: 9999));
      expect(s, 409);
      expect(store.byId('t1')!.amount, 2400);
    });

    test('та же поездка под новым id ловится по пересечению времени', () async {
      await call('POST', '/api/trips', tripJson());
      final (s, b) = await call('POST', '/api/trips', tripJson(id: 't1-copy'));
      expect(s, 409);
      expect(b['error'], contains('t1'));
      expect(store.length, 1);
    });

    test('стык поездок (конец = начало следующей) — не пересечение', () async {
      await call('POST', '/api/trips', tripJson());
      final (s, _) = await call(
          'POST',
          '/api/trips',
          tripJson(
              id: 't2',
              start: '2026-10-01T08:32:00+05:00',
              end: '2026-10-01T08:50:00+05:00'));
      expect(s, 201);
    });

    test('дубль ловится и после перезапуска сервера', () async {
      final dir = await Directory.systemTemp.createTemp('trips');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/trips.json');

      final first = await TripStore.open(file, offset: almaty);
      expect((await first.add(parseTrip(tripJson()).trip!)).status,
          AddStatus.created);

      final reopened = await TripStore.open(file, offset: almaty);
      expect((await reopened.add(parseTrip(tripJson()).trip!)).status,
          AddStatus.duplicate);
      expect(reopened.length, 1);
    });
  });

  group('Валидация', () {
    Future<Map<String, Object?>> fieldErrors(Object? body) async {
      final (s, b) = await call('POST', '/api/trips', body);
      expect(s, 422);
      expect(store.length, 0);
      return (b['fields'] as Map).cast();
    }

    test('сумма должна быть > 0', () async {
      expect(await fieldErrors(tripJson(amount: 0, commission: 0)),
          contains('amount'));
      expect(await fieldErrors(tripJson(amount: -100, commission: 0)),
          contains('amount'));
    });

    test('окончание должно быть позже начала', () async {
      expect(await fieldErrors(tripJson(end: '2026-10-01T08:00:00+05:00')),
          contains('end'));
      // Равное время — тоже ошибка.
      expect(await fieldErrors(tripJson(end: '2026-10-01T08:10:00+05:00')),
          contains('end'));
    });

    test('сравнение времени учитывает часовой пояс', () async {
      // 08:20+05:00 == 03:20Z — позже 03:10Z, поездка корректна.
      final (s, _) = await call(
          'POST',
          '/api/trips',
          tripJson(
              start: '2026-10-01T08:10:00+05:00', end: '2026-10-01T03:20:00Z'));
      expect(s, 201);
    });

    test('время без часового пояса отклоняется', () async {
      expect(await fieldErrors(tripJson(start: '2026-10-01T08:10:00')),
          contains('start'));
    });

    test('остальные поля и сбор всех ошибок сразу', () async {
      final errors = await fieldErrors({
        'id': '',
        'start': 'вчера',
        'end': '2026-10-01T08:32:00+05:00',
        'amount': 10.5,
        'payment': 'crypto',
      });
      expect(errors.keys,
          containsAll(['id', 'start', 'amount', 'payment', 'commission']));
    });

    test('комиссия не больше суммы и не отрицательная', () async {
      expect(await fieldErrors(tripJson(commission: 2500)),
          contains('commission'));
      expect(
          await fieldErrors(tripJson(commission: -1)), contains('commission'));
    });

    test('битый JSON — 400', () async {
      final (s, _) = await call('POST', '/api/trips', '{not json');
      expect(s, 400);
    });
  });

  group('Чтение', () {
    test('день: сводка и поездки по порядку', () async {
      await call(
          'POST',
          '/api/trips',
          tripJson(
              id: 'b',
              start: '2026-10-01T09:05:00+05:00',
              end: '2026-10-01T09:20:00+05:00',
              amount: 1500,
              payment: 'cash',
              commission: 225));
      await call('POST', '/api/trips', tripJson(id: 'a'));

      final (s, b) = await call('GET', '/api/days/2026-10-01');
      expect(s, 200);
      expect(
          [for (final t in b['trips'] as List) (t as Map)['id']], ['a', 'b']);
      expect(b['summary'], {
        'tripCount': 2,
        'revenue': 3900,
        'commission': 585,
        'net': 3315,
        'cash': {'count': 1, 'amount': 1500},
        'card': {'count': 1, 'amount': 2400},
        'driveMinutes': 37,
      });

      final (_, days) = await call('GET', '/api/days');
      expect(days['days'], [
        {'date': '2026-10-01', 'tripCount': 2}
      ]);
    });

    test('некорректная дата — 400', () async {
      expect((await call('GET', '/api/days/2026-02-31')).$1, 400);
      expect((await call('GET', '/api/days/01.10.2026')).$1, 400);
    });
  });
}
