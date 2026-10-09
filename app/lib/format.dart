import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('ru');

/// 12400 → «12 400 тг» (неразрывный пробел, чтобы «тг» не уезжал на новую строку).
String money(int value) => '${_money.format(value)} тг';

/// 95 → «1 ч 35 мин».
String minutes(int total) {
  final h = total ~/ 60, m = total % 60;
  if (h == 0) return '$m мин';
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

/// Дни храним строками `YYYY-MM-DD` — это календарные даты водителя,
/// не привязанные к часовому поясу устройства.
DateTime parseDay(String day) => DateTime.utc(
  int.parse(day.substring(0, 4)),
  int.parse(day.substring(5, 7)),
  int.parse(day.substring(8, 10)),
);

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String shiftDay(String day, int delta) =>
    dayKey(parseDay(day).add(Duration(days: delta)));

/// «Чт, 1 октября 2026».
String dayTitle(String day) {
  final s = DateFormat('EE, d MMMM y', 'ru').format(parseDay(day));
  return s[0].toUpperCase() + s.substring(1);
}
