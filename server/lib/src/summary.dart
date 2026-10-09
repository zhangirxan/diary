import 'trip.dart';

class PaymentBreakdown {
  const PaymentBreakdown({required this.count, required this.amount});

  final int count;
  final int amount;

  Map<String, Object?> toJson() => {'count': count, 'amount': amount};
}

/// Сводка за день.
class DaySummary {
  const DaySummary({
    required this.tripCount,
    required this.revenue,
    required this.commission,
    required this.cash,
    required this.card,
    required this.driveTime,
  });

  final int tripCount;

  /// Выручка — сумма всех поездок.
  final int revenue;
  final int commission;
  final PaymentBreakdown cash;
  final PaymentBreakdown card;

  /// Суммарное время в поездках.
  final Duration driveTime;

  /// «На руки» — выручка за вычетом комиссии.
  int get net => revenue - commission;

  factory DaySummary.of(Iterable<Trip> trips) {
    var count = 0, revenue = 0, commission = 0;
    var cashCount = 0, cashAmount = 0, cardCount = 0, cardAmount = 0;
    var drive = Duration.zero;
    for (final t in trips) {
      count++;
      revenue += t.amount;
      commission += t.commission;
      drive += t.duration;
      switch (t.payment) {
        case Payment.cash:
          cashCount++;
          cashAmount += t.amount;
        case Payment.card:
          cardCount++;
          cardAmount += t.amount;
      }
    }
    return DaySummary(
      tripCount: count,
      revenue: revenue,
      commission: commission,
      cash: PaymentBreakdown(count: cashCount, amount: cashAmount),
      card: PaymentBreakdown(count: cardCount, amount: cardAmount),
      driveTime: drive,
    );
  }

  Map<String, Object?> toJson() => {
        'tripCount': tripCount,
        'revenue': revenue,
        'commission': commission,
        'net': net,
        'cash': cash.toJson(),
        'card': card.toJson(),
        'driveMinutes': driveTime.inMinutes,
      };
}
