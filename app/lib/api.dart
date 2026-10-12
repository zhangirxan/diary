import 'dart:convert';

import 'package:http/http.dart' as http;

/// Адрес сервера задаётся при сборке:
/// `flutter run --dart-define=API_URL=http://10.0.2.2:8095`.
const defaultApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8095',
);

class Trip {
  const Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
  });

  final String id;

  /// Строки ISO 8601 в часовом поясе водителя, как их отдал сервер.
  final String start;
  final String end;
  final int amount;
  final String payment;
  final int commission;

  bool get isCash => payment == 'cash';

  /// «08:10» — берём из строки, а не через DateTime, чтобы часовой пояс
  /// телефона не сдвигал время смены.
  String get startTime => start.substring(11, 16);
  String get endTime => end.substring(11, 16);

  Duration get duration =>
      DateTime.parse(end).difference(DateTime.parse(start));

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
    id: j['id'] as String,
    start: j['start'] as String,
    end: j['end'] as String,
    amount: j['amount'] as int,
    payment: j['payment'] as String,
    commission: j['commission'] as int,
  );
}

class PaymentBreakdown {
  const PaymentBreakdown(this.count, this.amount);

  final int count;
  final int amount;

  factory PaymentBreakdown.fromJson(Map<String, dynamic> j) =>
      PaymentBreakdown(j['count'] as int, j['amount'] as int);
}

class DaySummary {
  const DaySummary({
    required this.tripCount,
    required this.revenue,
    required this.commission,
    required this.net,
    required this.cash,
    required this.card,
    required this.driveMinutes,
  });

  final int tripCount;
  final int revenue;
  final int commission;
  final int net;
  final PaymentBreakdown cash;
  final PaymentBreakdown card;
  final int driveMinutes;

  factory DaySummary.fromJson(Map<String, dynamic> j) => DaySummary(
    tripCount: j['tripCount'] as int,
    revenue: j['revenue'] as int,
    commission: j['commission'] as int,
    net: j['net'] as int,
    cash: PaymentBreakdown.fromJson(j['cash'] as Map<String, dynamic>),
    card: PaymentBreakdown.fromJson(j['card'] as Map<String, dynamic>),
    driveMinutes: j['driveMinutes'] as int,
  );
}

class DayReport {
  const DayReport({
    required this.date,
    required this.utcOffset,
    required this.summary,
    required this.trips,
  });

  final String date;
  final String utcOffset;
  final DaySummary summary;
  final List<Trip> trips;

  factory DayReport.fromJson(Map<String, dynamic> j) => DayReport(
    date: j['date'] as String,
    utcOffset: j['utcOffset'] as String,
    summary: DaySummary.fromJson(j['summary'] as Map<String, dynamic>),
    trips: [
      for (final t in j['trips'] as List)
        Trip.fromJson(t as Map<String, dynamic>),
    ],
  );
}

class ActiveDays {
  const ActiveDays(this.utcOffset, this.days);

  final String utcOffset;

  /// Дни с поездками, `YYYY-MM-DD` по возрастанию.
  final List<String> days;
}

class ApiException implements Exception {
  ApiException(this.message, {this.fields = const {}});

  final String message;

  /// Ошибки валидации по полям: `amount` → «Сумма должна быть больше 0».
  final Map<String, String> fields;

  @override
  String toString() => message;
}

class AddTripResult {
  const AddTripResult({required this.created, required this.trip});

  /// false — сервер узнал повторную отправку и дубль не создал.
  final bool created;
  final Trip trip;
}

class DiaryApi {
  DiaryApi({String baseUrl = defaultApiUrl, http.Client? client})
    : _base = Uri.parse(baseUrl),
      _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;

  Future<ActiveDays> fetchDays() async {
    final j = await _send(() => _client.get(_base.resolve('/api/days')));
    return ActiveDays(j['utcOffset'] as String, [
      for (final d in j['days'] as List) (d as Map)['date'] as String,
    ]);
  }

  Future<DayReport> fetchDay(String date) async {
    final j = await _send(() => _client.get(_base.resolve('/api/days/$date')));
    return DayReport.fromJson(j);
  }

  Future<AddTripResult> addTrip(Map<String, Object?> trip) async {
    final j = await _send(
      () => _client.post(
        _base.resolve('/api/trips'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(trip),
      ),
    );
    return AddTripResult(
      created: j['created'] as bool,
      trip: Trip.fromJson(j['trip'] as Map<String, dynamic>),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response res;
    try {
      res = await request().timeout(const Duration(seconds: 10));
    } catch (_) {
      throw ApiException('Сервер недоступен ($_base)');
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Неожиданный ответ сервера (${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        body['error'] as String? ?? 'Ошибка ${res.statusCode}',
        fields: {
          for (final e in (body['fields'] as Map? ?? {}).entries)
            e.key as String: e.value as String,
        },
      );
    }
    return body;
  }
}
