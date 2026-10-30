import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/sms.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

// ================================================================ پیامک خودکار

/// «زمانبندی ارسال پیامک» and automatic reminders (overdue installments,
/// unpaid invoices).
Future<void> showSmsAutomation(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Auto());

class _Auto extends StatefulWidget {
  const _Auto();

  @override
  State<_Auto> createState() => _AutoState();
}

class _AutoState extends State<_Auto> {
  late final AppStore _s = StoreScope.read(context);
  late final _inst = TextEditingController(text: _s.smsAuto.installmentTemplate);
  late final _unpaid = TextEditingController(text: _s.smsAuto.unpaidTemplate);
  late final _days = TextEditingController(text: '${_s.smsAuto.unpaidDays}');
  String? _msg;
  bool _busy = false;

  @override
  void dispose() {
    _inst.dispose();
    _unpaid.dispose();
    _days.dispose();
    super.dispose();
  }

  void _save() {
    _s.smsAuto
      ..installmentTemplate = _inst.text
      ..unpaidTemplate = _unpaid.text
      ..unpaidDays = int.tryParse(normalizeDigits(_days.text)) ?? 30;
    _s.updateSettings((_) {});
  }

  Future<void> _edit([SmsSchedule? sc]) async {
    final x = sc ?? SmsSchedule(id: newId(), at: DateTime.now().add(const Duration(hours: 1)));
    final title = TextEditingController(text: x.title);
    final text = TextEditingController(text: x.text);
    var at = x.at;
    var target = x.target;
    var repeat = x.repeat;
    final chosen = {...x.personIds};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'زمانبندی ارسال پیامک',
          width: 620,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان')),
            const SizedBox(height: 8),
            TextField(controller: text, maxLines: 4, decoration: const InputDecoration(labelText: 'متن پیامک — فیلدها: {نام} {مانده} {واحد} {فروشگاه} {امروز}')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DateField(label: 'تاریخ ارسال', value: at, onChanged: (d) => set(() => at = d == null ? at : DateTime(d.year, d.month, d.day, at.hour, at.minute)))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(at));
                  if (t != null) set(() => at = DateTime(at.year, at.month, at.day, t.hour, t.minute));
                },
                child: Text('ساعت ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'),
              ),
              const SizedBox(width: 8),
              DropdownButton<Repeat>(
                value: repeat,
                items: [for (final r in Repeat.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => set(() => repeat = v ?? repeat),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 4, children: [
              for (final t in SmsTarget.values) ChoiceChip(label: Text(t.label), selected: target == t, onSelected: (_) => set(() => target = t)),
            ]),
            if (target == SmsTarget.chosen)
              SizedBox(
                height: 200,
                child: ListView(children: [
                  for (final p in _s.peopleSorted.where((p) => normalizeMobile(p.phone).isNotEmpty))
                    CheckboxListTile(
                      dense: true,
                      value: chosen.contains(p.id),
                      title: Text('${p.name} — ${p.phone}'),
                      onChanged: (v) => set(() {
                        if (v == true) {
                          chosen.add(p.id);
                        } else {
                          chosen.remove(p.id);
                        }
                      }),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
    if (ok == true && text.text.trim().isNotEmpty) {
      x
        ..title = title.text.trim()
        ..text = text.text.trim()
        ..at = at
        ..target = target
        ..repeat = repeat
        ..personIds = chosen.toList()
        ..enabled = true;
      if (sc == null) _s.smsSchedules.add(x);
      _s.updateSettings((_) {});
      setState(() {});
    }
    title.dispose();
    text.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _s.smsAuto;
    final pending = dueAutoSms(_s);
    return FormDialog(
      title: 'پیامک خودکار و زمانبندی',
      width: 820,
      leading: TextButton.icon(
        onPressed: _busy || pending.isEmpty
            ? null
            : () async {
                _save();
                setState(() => _busy = true);
                final n = await runAutoSms(_s);
                if (mounted) {
                  setState(() {
                    _busy = false;
                    _msg = _s.settings.sms.configured ? '$n پیامک ارسال شد' : 'پنل پیامک تنظیم نشده است';
                  });
                }
              },
        icon: const Icon(Icons.send_rounded),
        label: Text('ارسال موارد سررسید شده (${pending.length})'),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            _save();
            Navigator.pop(context);
          },
          child: const Text('تایید'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_s.settings.sms.configured) const Text('ابتدا پنل پیامک را در «ارسال پیام» ← تنظیمات وارد کنید.', style: TextStyle(color: Colors.red)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: a.overdueInstallments,
          onChanged: (v) => setState(() => a.overdueInstallments = v),
          title: const Text('ارسال پیامک اقساط معوقه (از دفترچه اقساط مطالبات)'),
        ),
        TextField(controller: _inst, maxLines: 2, decoration: const InputDecoration(labelText: 'متن — {نام} {مبلغ قسط} {سررسید} {بابت} {فروشگاه}', isDense: true)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: a.unpaidInvoices,
          onChanged: (v) => setState(() => a.unpaidInvoices = v),
          title: const Text('ارسال پیامک فاکتورهای تسویه نشده (ماهی یک بار به بدهکاران)'),
        ),
        Row(children: [
          SizedBox(width: 200, child: TextField(controller: _days, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'فاکتورهای قدیمی‌تر از (روز)', isDense: true))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _unpaid, maxLines: 2, decoration: const InputDecoration(labelText: 'متن — {نام} {مانده} {واحد} {فروشگاه}', isDense: true))),
        ]),
        const Divider(height: 24),
        Row(children: [
          const Text('زمانبندی ارسال پیامک', style: TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('زمانبندی جدید')),
        ]),
        for (final sc in _s.smsSchedules)
          ListTile(
            dense: true,
            leading: Icon(sc.enabled ? Icons.schedule_send_rounded : Icons.check_circle_outline_rounded),
            title: Text(sc.title.isEmpty ? sc.text : sc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${sc.target.label} — ${sc.repeat.label} — ${sc.enabled ? 'ارسال بعدی ${jFormat(sc.at)} ساعت ${sc.at.hour}:${sc.at.minute.toString().padLeft(2, '0')}' : 'ارسال شده'}'),
            onTap: () => _edit(sc),
            trailing: IconButton(
              onPressed: () => setState(() {
                _s.smsSchedules.remove(sc);
                _s.updateSettings((_) {});
              }),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        const SizedBox(height: 6),
        const Text('پیامک‌های زمانبندی شده و یادآورها هنگام باز بودن برنامه هر چند دقیقه یک بار بررسی و ارسال می‌شوند؛ هر مورد فقط یک بار ارسال می‌شود.', style: TextStyle(fontSize: 12)),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

// ================================================================ تقویم

/// Things on a day of the calendar: reminders, due cheques, installments and
/// pro-forma deliveries («رویت تقویم تحویل»).
List<(IconData, String, Reminder?)> calendarItems(AppStore s, DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  bool same(DateTime x) => x.year == d.year && x.month == d.month && x.day == d.day;
  return [
    for (final r in s.reminders.where((r) => r.on(d))) (r.done ? Icons.check_circle_outline : Icons.alarm_rounded, r.title, r),
    for (final c in s.cheques.where((c) => same(c.dueDate) && (c.status == ChequeStatus.pending || c.status == ChequeStatus.deposited)))
      (c.direction == ChequeDirection.received ? Icons.call_received_rounded : Icons.call_made_rounded,
          'چک ${c.direction == ChequeDirection.received ? 'دریافتی' : 'پرداختی'} ${s.person(c.personId)?.name ?? ''} ${groupDigits(c.amount)}', null),
    for (final p in s.installmentPlans)
      for (final i in p.items.where((i) => !i.settled && same(i.due))) (Icons.event_repeat_rounded, 'قسط ${s.person(p.personId)?.name ?? ''} ${groupDigits(i.remaining)}', null),
    for (final o in s.invoices.where((i) => i.proforma && i.dueDate != null && same(i.dueDate!)))
      (Icons.local_shipping_outlined, 'تحویل سفارش ${o.number} ${s.person(o.personId)?.name ?? ''}', null),
  ];
}

Future<void> showCalendar(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Calendar());

class _Calendar extends StatefulWidget {
  const _Calendar();

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late Jalali _month = () {
    final j = Jalali.fromDateTime(DateTime.now());
    return Jalali(j.year, j.month, 1);
  }();
  DateTime _day = dateOnly(DateTime.now());

  Future<void> _edit(AppStore s, [Reminder? r]) async {
    final title = TextEditingController(text: r?.title ?? '');
    final note = TextEditingController(text: r?.note ?? '');
    var at = r?.at ?? _day;
    var repeat = r?.repeat ?? Repeat.none;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: r == null ? 'یادداشت جدید' : 'ویرایش یادداشت',
          width: 440,
          leading: r == null
              ? null
              : TextButton(
                  onPressed: () {
                    s.reminders.remove(r);
                    s.updateSettings((_) {});
                    Navigator.pop(ctx, false);
                  },
                  child: const Text('حذف'),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان')),
            const SizedBox(height: 8),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DateField(label: 'تاریخ', value: at, onChanged: (d) => set(() => at = d ?? at))),
              const SizedBox(width: 8),
              DropdownButton<Repeat>(
                value: repeat,
                items: [for (final x in Repeat.values) DropdownMenuItem(value: x, child: Text(x.label))],
                onChanged: (v) => set(() => repeat = v ?? repeat),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final x = r ?? Reminder(id: newId(), at: at, title: '');
      x
        ..title = title.text.trim()
        ..note = note.text.trim()
        ..at = at
        ..repeat = repeat;
      if (r == null) s.reminders.add(x);
      s.updateSettings((_) {});
    }
    title.dispose();
    note.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final first = _month.toDateTime();
    final len = Jalali.monthLength(_month.year, _month.month);
    final lead = _month.weekDayIndex; // 0 = شنبه
    final today = dateOnly(DateTime.now());
    final items = calendarItems(s, _day);
    return SakanWindow(
      title: 'یادسپار تقویم',
      width: 1150,
      height: 700,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                IconButton(
                  onPressed: () => setState(() => _month = _month.month == 1 ? Jalali(_month.year - 1, 12, 1) : Jalali(_month.year, _month.month - 1, 1)),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                Text('${jalaliMonthNames[_month.month - 1]} ${_month.year}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                IconButton(
                  onPressed: () => setState(() => _month = _month.month == 12 ? Jalali(_month.year + 1, 1, 1) : Jalali(_month.year, _month.month + 1, 1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const Spacer(),
                sakanBtn('امروز', () {
                  final j = Jalali.fromDateTime(DateTime.now());
                  setState(() {
                    _month = Jalali(j.year, j.month, 1);
                    _day = today;
                  });
                }, icon: Icons.today_rounded),
              ]),
              Row(children: [
                for (final w in const ['شنبه', 'یکشنبه', 'دوشنبه', 'سه شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'])
                  Expanded(child: Center(child: Text(w, style: const TextStyle(fontWeight: FontWeight.w700)))),
              ]),
              const SizedBox(height: 4),
              Expanded(
                child: LayoutBuilder(builder: (ctx, c) {
                  final rows = ((lead + len) / 7).ceil();
                  final h = c.maxHeight / rows;
                  return Column(children: [
                    for (var r = 0; r < rows; r++)
                      SizedBox(
                        height: h,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: () {
                                final n = r * 7 + col - lead + 1;
                                if (n < 1 || n > len) return const SizedBox();
                                final d = DateTime(first.year, first.month, first.day + n - 1);
                                final its = calendarItems(s, d);
                                final sel = d == _day;
                                return InkWell(
                                  onTap: () => setState(() => _day = d),
                                  onDoubleTap: () => _edit(s),
                                  child: Container(
                                    margin: const EdgeInsets.all(2),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: sel ? const Color(0xFFDDEBFF) : (col == 6 ? const Color(0xFFFFF1F1) : Colors.white),
                                      border: Border.all(color: d == today ? sakanSel : Colors.black12, width: d == today ? 2 : 1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: col == 6 ? Colors.red : null)),
                                      for (final it in its.take(3))
                                        Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
                                      if (its.length > 3) Text('+${its.length - 3}', style: const TextStyle(fontSize: 10.5)),
                                    ]),
                                  ),
                                );
                              }(),
                            ),
                        ]),
                      ),
                  ]);
                }),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 320,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(jFormatLong(_day), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              sakanBtn('یادداشت جدید', () => _edit(s), icon: Icons.add_alarm_rounded),
              const SizedBox(height: 6),
              Expanded(
                child: Card(
                  child: ListView(children: [
                    for (final it in items)
                      ListTile(
                        dense: true,
                        leading: Icon(it.$1),
                        title: Text(it.$2),
                        subtitle: it.$3 == null || it.$3!.note.isEmpty ? null : Text(it.$3!.note),
                        onTap: it.$3 == null ? null : () => _edit(s, it.$3),
                        trailing: it.$3 == null
                            ? null
                            : Checkbox(
                                value: it.$3!.done,
                                onChanged: (v) => setState(() {
                                  it.$3!.done = v ?? false;
                                  s.updateSettings((_) {});
                                }),
                              ),
                      ),
                    if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('موردی برای این روز نیست')),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
