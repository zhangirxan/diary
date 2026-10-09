import 'dart:convert';
import 'dart:io';

import 'trip.dart';
import 'validation.dart';

enum AddStatus {
  /// Новая поездка сохранена.
  created,

  /// Поездка с этим id и тем же содержимым уже есть — повторная отправка,
  /// ничего не меняем.
  duplicate,

  /// id уже занят поездкой с другими данными.
  idConflict,

  /// Пересекается по времени с другой поездкой: водитель не может быть
  /// в двух поездках сразу. Ловит и повтор той же поездки под новым id.
  overlap,
}

class AddResult {
  const AddResult(this.status, this.trip);

  final AddStatus status;

  /// Сохранённая поездка (для [AddStatus.created]/[AddStatus.duplicate])
  /// или та, с которой случился конфликт.
  final Trip trip;
}

/// Хранилище поездок в памяти с сохранением в JSON-файл.
///
/// Проверка на дубль и вставка выполняются синхронно, без `await` между ними,
/// поэтому два одновременных одинаковых запроса не создадут две записи.
class TripStore {
  TripStore({required this.offset, this.file});

  /// Часовой пояс водителя — по нему поездка относится к календарному дню.
  final Duration offset;
  final File? file;

  final _byId = <String, Trip>{};
  Future<void> _pendingWrite = Future.value();

  static Future<TripStore> open(File file, {required Duration offset}) async {
    final store = TripStore(offset: offset, file: file);
    if (await file.exists()) {
      final text = await file.readAsString();
      final raw = text.trim().isEmpty ? <Object?>[] : jsonDecode(text);
      if (raw is! List) {
        throw FormatException('${file.path}: ожидается JSON-массив поездок');
      }
      for (var i = 0; i < raw.length; i++) {
        final r = parseTrip(raw[i]);
        if (!r.isValid) {
          throw FormatException('${file.path}: поездка #$i: ${r.errors}');
        }
        store._byId[r.trip!.id] = r.trip!;
      }
    }
    return store;
  }

  int get length => _byId.length;

  Trip? byId(String id) => _byId[id];

  Future<AddResult> add(Trip trip) async {
    final existing = _byId[trip.id];
    if (existing != null) {
      return existing.sameContentAs(trip)
          ? AddResult(AddStatus.duplicate, existing)
          : AddResult(AddStatus.idConflict, existing);
    }
    for (final other in _byId.values) {
      if (other.overlaps(trip)) return AddResult(AddStatus.overlap, other);
    }
    _byId[trip.id] = trip;
    await _save();
    return AddResult(AddStatus.created, trip);
  }

  /// Поездки за день `YYYY-MM-DD` (по времени начала), отсортированные.
  List<Trip> forDay(String date) =>
      _byId.values.where((t) => localDate(t.start, offset) == date).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  /// Дни, в которые есть поездки, с их количеством — по возрастанию.
  Map<String, int> days() {
    final counts = <String, int>{};
    for (final t in _byId.values) {
      final d = localDate(t.start, offset);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    return Map.fromEntries(
        counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// Записи в файл идут строго по очереди; пишем во временный файл и
  /// переименовываем, чтобы при падении не остался обрезанный JSON.
  Future<void> _save() {
    final f = file;
    if (f == null) return Future.value();
    final snapshot = _byId.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final json = const JsonEncoder.withIndent('  ')
        .convert([for (final t in snapshot) t.toJson(offset)]);
    return _pendingWrite = _pendingWrite.then((_) async {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(f.path);
    });
  }
}
