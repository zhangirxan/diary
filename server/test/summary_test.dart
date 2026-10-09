import 'package:driver_diary_server/driver_diary_server.dart';
import 'package:test/test.dart';

const almaty = Duration(hours: 5);

Trip trip(String id, String start, String end, int amount, Payment payment,
        int commission) =>
    Trip(
      id: id,
      start: DateTime.parse(start),
      end: DateTime.parse(end),
      amount: amount,
      payment: payment,
      commission: commission,
    );

void main() {
  group('DaySummary', () {
    test('пример из задания: 2 поездки, карта + наличные', () {
      final s = DaySummary.of([
        trip('t1', '2026-10-01T08:10:00+05:00', '2026-10-01T08:32:00+05:00',
            2400, Payment.card, 360),
        trip('t2', '2026-10-01T09:05:00+05:00', '2026-10-01T09:20:00+05:00',
            1500, Payment.cash, 225),
      ]);

      expect(s.tripCount, 2);
      expect(s.revenue, 3900);
      expect(s.commission, 585);
      expect(s.net, 3315);
      expect(s.cash.count, 1);
      expect(s.cash.amount, 1500);
      expect(s.card.count, 1);
      expect(s.card.amount, 2400);
      expect(s.driveTime, const Duration(minutes: 37));
    });

    test('пустой день — нули, а не ошибка', () {
      final s = DaySummary.of(const []);
      expect(s.toJson(), {
        'tripCount': 0,
        'revenue': 0,
        'commission': 0,
        'net': 0,
        'cash': {'count': 0, 'amount': 0},
        'card': {'count': 0, 'amount': 0},
        'driveMinutes': 0,
      });
    });

    test('наличные + карта всегда дают выручку', () {
      final s = DaySummary.of([
        for (var i = 0; i < 10; i++)
          trip(
              't$i',
              '2026-10-01T${(8 + i).toString().padLeft(2, '0')}:00:00+05:00',
              '2026-10-01T${(8 + i).toString().padLeft(2, '0')}:30:00+05:00',
              1000 + i * 137,
              i.isEven ? Payment.cash : Payment.card,
              150 + i),
      ]);
      expect(s.cash.amount + s.card.amount, s.revenue);
      expect(s.cash.count + s.card.count, s.tripCount);
    });
  });

  group('Границы дня', () {
    test('поездка в 00:20 по Алматы относится к своему дню, а не к UTC',
        () async {
      final store = TripStore(offset: almaty);
      // 2026-10-01T19:20Z == 2026-10-02T00:20+05:00
      final night = trip('n', '2026-10-01T19:20:00Z', '2026-10-01T19:44:00Z',
          2300, Payment.card, 345);
      await store.add(night);
      expect(store.forDay('2026-10-01'), isEmpty);
      expect(store.forDay('2026-10-02').single.id, 'n');
    });

    test('поездка через полночь считается в день начала', () async {
      final store = TripStore(offset: almaty);
      await store.add(trip('m', '2026-10-01T23:50:00+05:00',
          '2026-10-02T00:15:00+05:00', 2000, Payment.cash, 300));
      expect(store.forDay('2026-10-01'), hasLength(1));
      expect(store.forDay('2026-10-02'), isEmpty);
    });
  });
}
