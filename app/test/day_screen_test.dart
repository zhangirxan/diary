import 'dart:convert';

import 'package:driver_diary_app/api.dart';
import 'package:driver_diary_app/format.dart';
import 'package:driver_diary_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, Object?> dayJson(String date, List<Map<String, Object?>> trips) {
  int sum(String k, [String? payment]) => trips
      .where((t) => payment == null || t['payment'] == payment)
      .fold(0, (a, t) => a + (t[k] as int));
  return {
    'date': date,
    'utcOffset': '+05:00',
    'summary': {
      'tripCount': trips.length,
      'revenue': sum('amount'),
      'commission': sum('commission'),
      'net': sum('amount') - sum('commission'),
      'cash': {
        'count': trips.where((t) => t['payment'] == 'cash').length,
        'amount': sum('amount', 'cash'),
      },
      'card': {
        'count': trips.where((t) => t['payment'] == 'card').length,
        'amount': sum('amount', 'card'),
      },
      'driveMinutes': 37,
    },
    'trips': trips,
  };
}

const t1 = {
  'id': 't1',
  'start': '2026-10-01T08:10:00+05:00',
  'end': '2026-10-01T08:32:00+05:00',
  'amount': 2400,
  'payment': 'card',
  'commission': 360,
};
const t2 = {
  'id': 't2',
  'start': '2026-10-01T09:05:00+05:00',
  'end': '2026-10-01T09:20:00+05:00',
  'amount': 1500,
  'payment': 'cash',
  'commission': 225,
};

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  late List<String> requested;

  DiaryApi fakeApi() {
    requested = [];
    return DiaryApi(
      baseUrl: 'http://test',
      client: MockClient((req) async {
        requested.add(req.url.path);
        final body = switch (req.url.path) {
          '/api/days' => {
            'utcOffset': '+05:00',
            'days': [
              {'date': '2026-10-01', 'tripCount': 2},
            ],
          },
          '/api/days/2026-10-01' => dayJson('2026-10-01', [t1, t2]),
          final p => dayJson(p.split('/').last, []),
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  testWidgets('открывается последний день с поездками: сводка и список', (
    tester,
  ) async {
    await tester.pumpWidget(DiaryApp(api: fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text(dayTitle('2026-10-01')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('net'))).data, money(3315));
    expect(find.text(money(3900)), findsOneWidget); // выручка
    expect(find.text(money(585)), findsOneWidget); // комиссия
    expect(find.text('08:10 – 08:32'), findsOneWidget);
    expect(find.text('09:05 – 09:20'), findsOneWidget);
  });

  testWidgets('стрелка переключает на следующий день', (tester) async {
    await tester.pumpWidget(DiaryApp(api: fakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Следующий день'));
    await tester.pumpAndSettle();

    expect(requested.last, '/api/days/2026-10-02');
    expect(find.text(dayTitle('2026-10-02')), findsOneWidget);
    expect(find.text('В этот день поездок не было'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('net'))).data, money(0));
  });
}
