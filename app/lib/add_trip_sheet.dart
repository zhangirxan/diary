import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'format.dart';

/// Форма новой поездки за день [day].
///
/// id поездки создаётся один раз при открытии формы. Если ответ сервера
/// потерялся и водитель жмёт «Сохранить» ещё раз, уходит тот же id —
/// сервер узнаёт повтор и не создаёт дубль.
class AddTripSheet extends StatefulWidget {
  const AddTripSheet({
    super.key,
    required this.api,
    required this.day,
    required this.utcOffset,
  });

  final DiaryApi api;
  final String day;
  final String utcOffset;

  @override
  State<AddTripSheet> createState() => _AddTripSheetState();
}

class _AddTripSheetState extends State<AddTripSheet> {
  static const commissionRate = 0.15;

  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _commission = TextEditingController();
  late final String _id = _newId();

  TimeOfDay? _start;
  TimeOfDay? _end;
  String _payment = 'card';
  bool _commissionEdited = false;
  bool _saving = false;
  bool _triedSubmit = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  static String _newId() {
    final r = Random.secure();
    final suffix = List.generate(6, (_) => r.nextInt(36).toRadixString(36));
    return 'app-${DateTime.now().millisecondsSinceEpoch}-${suffix.join()}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _commission.dispose();
    super.dispose();
  }

  String _iso(TimeOfDay t) =>
      '${widget.day}T${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00${widget.utcOffset}';

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(bool isStart) async {
    final initial =
        (isStart ? _start : _end) ??
        (isStart ? null : _start) ??
        TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _fieldErrors = {..._fieldErrors}..remove(isStart ? 'start' : 'end');
    });
  }

  void _onAmountChanged(String value) {
    _fieldErrors.remove('amount');
    if (_commissionEdited) return;
    final amount = int.tryParse(value);
    _commission.text = amount == null
        ? ''
        : (amount * commissionRate).round().toString();
  }

  String? get _timeError {
    if (_start == null || _end == null) return 'Укажите начало и окончание';
    if (_toMinutes(_end!) <= _toMinutes(_start!)) {
      return 'Окончание должно быть позже начала';
    }
    return _fieldErrors['start'] ?? _fieldErrors['end'];
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _triedSubmit = true;
      _error = null;
    });
    if (!formOk || _timeError != null) return;

    setState(() => _saving = true);
    try {
      final result = await widget.api.addTrip({
        'id': _id,
        'start': _iso(_start!),
        'end': _iso(_end!),
        'amount': int.parse(_amount.text),
        'payment': _payment,
        'commission': int.parse(_commission.text),
      });
      if (mounted) Navigator.pop(context, result);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
        _fieldErrors = {...e.fields};
      });
      _formKey.currentState!.validate();
    }
  }

  String? _required(String? v, String field, {bool positive = false}) {
    final n = int.tryParse(v ?? '');
    if (n == null) return 'Введите целое число';
    if (positive && n <= 0) return 'Должно быть больше 0';
    if (field == 'commission' && n > (int.tryParse(_amount.text) ?? n)) {
      return 'Больше суммы поездки';
    }
    return _fieldErrors[field];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeError = _triedSubmit || (_start != null && _end != null)
        ? _timeError
        : null;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        // После первой попытки сохранить ошибки обновляются по мере ввода.
        autovalidateMode: _triedSubmit
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Новая поездка', style: theme.textTheme.titleLarge),
            Text(dayTitle(widget.day), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'Начало',
                    value: _start,
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeButton(
                    label: 'Окончание',
                    value: _end,
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            if (timeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  timeError,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Сумма',
                suffixText: 'тг',
                border: OutlineInputBorder(),
              ),
              onChanged: _onAmountChanged,
              validator: (v) => _required(v, 'amount', positive: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('commission'),
              controller: _commission,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Комиссия',
                suffixText: 'тг',
                helperText: _commissionEdited
                    ? null
                    : 'Подставлено ${(commissionRate * 100).round()}% — можно изменить',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                _commissionEdited = true;
                _fieldErrors.remove('commission');
              },
              validator: (v) => _required(v, 'commission'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'card',
                  label: Text('Карта'),
                  icon: Icon(Icons.credit_card),
                ),
                ButtonSegment(
                  value: 'cash',
                  label: Text('Наличные'),
                  icon: Icon(Icons.payments_outlined),
                ),
              ],
              selected: {_payment},
              onSelectionChanged: (s) => setState(() => _payment = s.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '--:--'
        : '${value!.hour.toString().padLeft(2, '0')}:'
              '${value!.minute.toString().padLeft(2, '0')}';
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(text, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
