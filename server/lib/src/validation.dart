import 'trip.dart';

/// Результат разбора входящей поездки: либо [trip], либо ошибки по полям.
class TripParseResult {
  TripParseResult.ok(Trip this.trip) : errors = const {};
  TripParseResult.invalid(this.errors) : trip = null;

  final Trip? trip;
  final Map<String, String> errors;

  bool get isValid => trip != null;
}

// Требуем явный часовой пояс: «08:10» без зоны неоднозначно.
final _isoWithZone = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$',
);

/// Проверяет JSON поездки и собирает все ошибки сразу, а не только первую.
TripParseResult parseTrip(Object? json) {
  if (json is! Map<String, Object?>) {
    return TripParseResult.invalid({'_': 'Ожидается JSON-объект поездки'});
  }
  final errors = <String, String>{};

  final id = json['id'];
  if (id is! String || id.trim().isEmpty) {
    errors['id'] = 'Нужен непустой строковый id';
  } else if (id.length > 100) {
    errors['id'] = 'id длиннее 100 символов';
  }

  final start = _parseTime(json['start'], 'start', errors);
  final end = _parseTime(json['end'], 'end', errors);
  if (start != null && end != null && !end.isAfter(start)) {
    errors['end'] = 'Окончание должно быть позже начала';
  }

  final amount = _parseMoney(json['amount'], 'amount', errors);
  if (amount != null && amount <= 0) {
    errors['amount'] = 'Сумма должна быть больше 0';
  }

  final commission = _parseMoney(json['commission'], 'commission', errors);
  if (commission != null) {
    if (commission < 0) {
      errors['commission'] = 'Комиссия не может быть отрицательной';
    } else if (amount != null && amount > 0 && commission > amount) {
      errors['commission'] = 'Комиссия не может превышать сумму поездки';
    }
  }

  final payment = Payment.tryParse(json['payment']);
  if (payment == null) {
    errors['payment'] = 'Способ оплаты: "cash" или "card"';
  }

  if (errors.isNotEmpty) return TripParseResult.invalid(errors);
  return TripParseResult.ok(Trip(
    id: (id as String).trim(),
    start: start!,
    end: end!,
    amount: amount!,
    payment: payment!,
    commission: commission!,
  ));
}

DateTime? _parseTime(Object? v, String field, Map<String, String> errors) {
  if (v is! String || !_isoWithZone.hasMatch(v)) {
    errors[field] =
        'Время в ISO 8601 с часовым поясом, например 2026-10-01T08:10:00+05:00';
    return null;
  }
  final parsed = DateTime.tryParse(v);
  if (parsed == null) {
    errors[field] = 'Некорректная дата/время';
    return null;
  }
  return parsed.toUtc();
}

/// Деньги — целые числа. `2400.0` допускаем, `2400.5` — нет.
int? _parseMoney(Object? v, String field, Map<String, String> errors) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.roundToDouble()) return v.toInt();
  errors[field] = v == null ? 'Обязательное поле' : 'Ожидается целое число';
  return null;
}
