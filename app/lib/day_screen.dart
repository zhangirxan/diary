import 'package:flutter/material.dart';

import 'add_trip_sheet.dart';
import 'api.dart';
import 'format.dart';

class DayScreen extends StatefulWidget {
  const DayScreen({super.key, required this.api});

  final DiaryApi api;

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  String? _day;
  ActiveDays? _activeDays;
  DayReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Открываемся на последнем дне с поездками, а если их нет — на сегодня.
  Future<void> _init() async {
    try {
      final days = await widget.api.fetchDays();
      _activeDays = days;
      await _open(days.days.isEmpty ? dayKey(DateTime.now()) : days.days.last);
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _open(String day) async {
    setState(() {
      _day = day;
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.api.fetchDay(day);
      // Пока грузилось, могли переключить день — старый ответ не показываем.
      if (!mounted || _day != day) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || _day != day) return;
      setState(() {
        _report = null;
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _reload() async {
    if (_activeDays == null) return _init();
    final days = await widget.api.fetchDays().catchError((_) => _activeDays!);
    _activeDays = days;
    await _open(_day!);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDay(_day!),
      firstDate: DateTime.utc(2020),
      lastDate: DateTime.utc(2100),
      locale: const Locale('ru'),
    );
    if (picked != null) _open(dayKey(picked));
  }

  Future<void> _addTrip() async {
    final result = await showModalBottomSheet<AddTripResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddTripSheet(
        api: widget.api,
        day: _day!,
        utcOffset: _activeDays?.utcOffset ?? '+05:00',
      ),
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.created
              ? 'Поездка добавлена'
              : 'Эта поездка уже была сохранена — дубль не создан',
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дневник смен'),
        actions: [
          IconButton(
            tooltip: 'Выбрать дату',
            icon: const Icon(Icons.calendar_month),
            onPressed: day == null ? null : _pickDate,
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      floatingActionButton: day == null || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addTrip,
              icon: const Icon(Icons.add),
              label: const Text('Поездка'),
            ),
      body: day == null
          ? _buildStatus()
          : Column(
              children: [
                _DaySwitcher(
                  day: day,
                  activeDays: _activeDays?.days ?? const [],
                  onOpen: _open,
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _reload,
                    child: _buildStatus() ?? _buildReport(_report!),
                  ),
                ),
              ],
            ),
    );
  }

  Widget? _buildStatus() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonal(
              onPressed: _reload,
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }
    if (_loading && _report?.date != _day) {
      return const Center(child: CircularProgressIndicator());
    }
    return null;
  }

  Widget _buildReport(DayReport report) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        SummaryCard(summary: report.summary),
        const SizedBox(height: 20),
        Text('Поездки', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (report.trips.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'В этот день поездок не было',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final t in report.trips) TripTile(trip: t),
      ],
    );
  }
}

class _DaySwitcher extends StatelessWidget {
  const _DaySwitcher({
    required this.day,
    required this.activeDays,
    required this.onOpen,
  });

  final String day;
  final List<String> activeDays;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Предыдущий день',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => onOpen(shiftDay(day, -1)),
            ),
            Expanded(
              child: Text(
                dayTitle(day),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Следующий день',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => onOpen(shiftDay(day, 1)),
            ),
          ],
        ),
        if (activeDays.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in activeDays.reversed)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${int.parse(d.substring(8))}.${d.substring(5, 7)}',
                      ),
                      selected: d == day,
                      onSelected: (_) => onOpen(d),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final cashShare = s.revenue == 0 ? 0.0 : s.cash.amount / s.revenue;

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('На руки', style: theme.textTheme.labelLarge),
            Text(
              money(s.net),
              key: const Key('net'),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Metric('Поездок', '${s.tripCount}'),
                _Metric('Выручка', money(s.revenue)),
                _Metric('Комиссия', money(s.commission)),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: s.revenue == 0 ? 0 : cashShare,
                minHeight: 8,
                color: Colors.green.shade600,
                backgroundColor: s.revenue == 0
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.blue.shade400,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Legend(
                  Colors.green.shade600,
                  'Наличные',
                  '${money(s.cash.amount)} · ${s.cash.count}',
                ),
                const Spacer(),
                _Legend(
                  Colors.blue.shade400,
                  'Карта',
                  '${money(s.card.amount)} · ${s.card.count}',
                ),
              ],
            ),
            if (s.driveMinutes > 0) ...[
              const SizedBox(height: 12),
              Text(
                'В поездках: ${minutes(s.driveMinutes)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label, this.value);

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class TripTile extends StatelessWidget {
  const TripTile({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: trip.isCash
            ? Colors.green.shade100
            : Colors.blue.shade100,
        child: Icon(
          trip.isCash ? Icons.payments_outlined : Icons.credit_card,
          color: trip.isCash ? Colors.green.shade800 : Colors.blue.shade800,
        ),
      ),
      title: Text('${trip.startTime} – ${trip.endTime}'),
      subtitle: Text(
        '${minutes(trip.duration.inMinutes)} · ${trip.isCash ? 'наличные' : 'карта'}'
        ' · комиссия ${money(trip.commission)}',
      ),
      trailing: Text(money(trip.amount), style: theme.textTheme.titleMedium),
    );
  }
}
