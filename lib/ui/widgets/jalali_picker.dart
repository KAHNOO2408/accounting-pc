import 'package:flutter/material.dart';

import '../../core/jalali.dart';

Future<DateTime?> showJalaliDatePicker(BuildContext context, {required DateTime initial}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _JalaliPickerDialog(initial: Jalali.fromDateTime(initial)),
  );
}

class _JalaliPickerDialog extends StatefulWidget {
  final Jalali initial;
  const _JalaliPickerDialog({required this.initial});

  @override
  State<_JalaliPickerDialog> createState() => _JalaliPickerDialogState();
}

class _JalaliPickerDialogState extends State<_JalaliPickerDialog> {
  late Jalali _view; // first day of shown month
  late Jalali _selected;
  late final TextEditingController _typed;
  String? _typedError;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _view = widget.initial.firstOfMonth;
    _typed = TextEditingController(text: widget.initial.format());
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _pick(Jalali j) {
    setState(() {
      _selected = j;
      _typed.text = j.format();
      _typedError = null;
    });
  }

  void _applyTyped() {
    final j = Jalali.tryParse(_typed.text);
    if (j == null) {
      setState(() => _typedError = 'قالب: ۱۴۰۵/۰۷/۰۹');
      return;
    }
    Navigator.pop(context, j.toDateTime());
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final today = Jalali.now();
    final len = _view.monthLen;
    final offset = _view.weekDayIndex;
    final cells = offset + len;
    final rows = (cells / 7).ceil();
    final years = [for (var y = today.year - 15; y <= today.year + 10; y++) y];
    if (!years.contains(_view.year)) years.add(_view.year);
    years.sort();

    return Dialog(
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'ماه قبل',
                    onPressed: () => setState(() => _view = _view.addMonths(-1)),
                    icon: const Icon(Icons.chevron_right_rounded, textDirection: TextDirection.ltr),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _view.month,
                            items: [
                              for (var m = 1; m <= 12; m++)
                                DropdownMenuItem(value: m, child: Text(jalaliMonthNames[m - 1])),
                            ],
                            onChanged: (m) {
                              if (m != null) setState(() => _view = Jalali(_view.year, m, 1));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _view.year,
                            items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                            onChanged: (y) {
                              if (y != null) setState(() => _view = Jalali(y, _view.month, 1));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'ماه بعد',
                    onPressed: () => setState(() => _view = _view.addMonths(1)),
                    icon: const Icon(Icons.chevron_left_rounded, textDirection: TextDirection.ltr),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final d in jalaliWeekDaysShort)
                    Expanded(
                      child: Center(
                        child: Text(d,
                            style: th.textTheme.labelMedium?.copyWith(
                                color: d == 'ج' ? th.colorScheme.error : th.hintColor)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var c = 0; c < 7; c++) Expanded(child: _cell(context, r * 7 + c - offset + 1, len, today, c == 6)),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _typed,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: 'تایپ تاریخ',
                        errorText: _typedError,
                      ),
                      onSubmitted: (_) => _applyTyped(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _pick(today),
                    child: const Text('امروز'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(_selected.formatWithWeekday(), style: th.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () {
                      final j = Jalali.tryParse(_typed.text);
                      Navigator.pop(context, (j ?? _selected).toDateTime());
                    },
                    child: const Text('تایید'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int day, int len, Jalali today, bool friday) {
    if (day < 1 || day > len) return const SizedBox(height: 40);
    final th = Theme.of(context);
    final j = Jalali(_view.year, _view.month, day);
    final sel = j == _selected;
    final isToday = j == today;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pick(j),
        onDoubleTap: () => Navigator.pop(context, j.toDateTime()),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? th.colorScheme.primary : null,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !sel ? Border.all(color: th.colorScheme.primary) : null,
          ),
          child: Text(
            '$day',
            style: TextStyle(
              color: sel ? th.colorScheme.onPrimary : (friday ? th.colorScheme.error : null),
              fontWeight: sel || isToday ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
