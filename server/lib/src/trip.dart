/// Способ оплаты поездки.
enum Payment {
  cash,
  card;

  static Payment? tryParse(Object? value) {
    for (final p in Payment.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// Поездка. Время хранится как момент (UTC), деньги — в целых единицах валюты.
class Trip {
  Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final int amount;
  final Payment payment;
  final int commission;

  Duration get duration => end.difference(start);

  /// Совпадает ли содержимое поездки (без учёта формы записи времени:
  /// `08:10+05:00` и `03:10Z` — один и тот же момент).
  bool sameContentAs(Trip other) =>
      id == other.id &&
      start.isAtSameMomentAs(other.start) &&
      end.isAtSameMomentAs(other.end) &&
      amount == other.amount &&
      payment == other.payment &&
      commission == other.commission;

  bool overlaps(Trip other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  Map<String, Object?> toJson(Duration offset) => {
        'id': id,
        'start': formatWithOffset(start, offset),
        'end': formatWithOffset(end, offset),
        'amount': amount,
        'payment': payment.name,
        'commission': commission,
      };
}

/// Календарная дата момента [instant] в часовом поясе водителя, `YYYY-MM-DD`.
String localDate(DateTime instant, Duration offset) {
  final local = instant.toUtc().add(offset);
  return '${_pad(local.year, 4)}-${_pad(local.month)}-${_pad(local.day)}';
}

/// ISO 8601 с явным смещением: `2026-10-01T08:10:00+05:00`.
String formatWithOffset(DateTime instant, Duration offset) {
  final l = instant.toUtc().add(offset);
  return '${localDate(instant, offset)}T'
      '${_pad(l.hour)}:${_pad(l.minute)}:${_pad(l.second)}'
      '${formatOffset(offset)}';
}

String formatOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final m = offset.inMinutes.abs();
  return '$sign${_pad(m ~/ 60)}:${_pad(m % 60)}';
}

/// Разбирает смещение вида `+05:00` / `-03:30`.
Duration parseOffset(String s) {
  final m = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) throw FormatException('Ожидается смещение вида +05:00', s);
  final d = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
  return m[1] == '-' ? -d : d;
}

String _pad(int v, [int width = 2]) => v.toString().padLeft(width, '0');
