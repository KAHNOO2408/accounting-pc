import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../core/xlsx.dart';
import '../../data/models.dart';
import '../../data/payroll.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// «حضور و غیاب» — clock records, shifts and the monthly result.
Future<void> showAttendance(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Attendance());

class _Attendance extends StatefulWidget {
  const _Attendance();

  @override
  State<_Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<_Attendance> {
  String? _period;
  String? _emp;
  String? _msg;

  Future<void> _import(AppStore s) async {
    final f = await fs.openFile(acceptedTypeGroups: const [
      fs.XTypeGroup(label: 'Excel / CSV / TXT', extensions: ['xlsx', 'csv', 'txt']),
    ]);
    if (f == null) return;
    try {
      final bytes = await File(f.path).readAsBytes();
      final List<List<String>> rows;
      if (f.path.toLowerCase().endsWith('.xlsx')) {
        rows = readXlsx(bytes);
      } else {
        final text = utf8.decode(bytes, allowMalformed: true);
        rows = [for (final l in const LineSplitter().convert(text)) l.split(RegExp(r'[,;\t]'))];
      }
      final (n, unknown) = s.importPunches(parseClockRows(rows));
      setState(() => _msg = '$n روز تردد وارد شد${unknown.isEmpty ? '' : ' — کدهای ناشناخته: ${unknown.take(10).join('، ')}'}');
    } catch (e) {
      setState(() => _msg = 'خطا در خواندن فایل: $e');
    }
  }

  Future<void> _editDay(AppStore s, Employee e, DateTime d) async {
    final old = s.clockOf(e.id, d);
    final inC = TextEditingController(text: hm(old?.inMin));
    final outC = TextEditingController(text: hm(old?.outMin));
    final note = TextEditingController(text: old?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'اصلاح تردد — ${e.fullName} — ${jFormat(d)}',
        width: 380,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: inC, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'ورود (08:00)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: outC, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'خروج (16:30)'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
      ),
    );
    if (ok == true) {
      s.saveClock(ClockRecord(employeeId: e.id, date: d, inMin: parseHm(inC.text), outMin: parseHm(outC.text), note: note.text.trim(), edited: true));
      setState(() {});
    }
    for (final c in [inC, outC, note]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final periods = s.periodsSorted;
    final p = s.payPeriod(_period) ?? periods.firstOrNull;
    final emps = p == null ? <Employee>[] : s.employeesIn(p);
    final e = emps.where((x) => x.id == _emp).firstOrNull;
    final days = <DateTime>[if (p != null) for (var d = p.start; !d.isAfter(p.end); d = DateTime(d.year, d.month, d.day + 1)) d];
    return SakanWindow(
      title: 'حضور و غیاب',
      width: 1200,
      height: 700,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: p?.id,
                decoration: const InputDecoration(labelText: 'دوره حقوقی', isDense: true),
                items: [for (final x in periods) DropdownMenuItem(value: x.id, child: Text(x.name))],
                onChanged: (v) => setState(() => _period = v),
              ),
            ),
            sakanBtn('دریافت اطلاعات تردد از فایل اکسل', () => _import(s), icon: Icons.upload_file_rounded),
            sakanBtn('تعیین شیفت', () => showShifts(context), icon: Icons.schedule_rounded),
            sakanBtn('انتقال به کارکرد', p == null
                ? null
                : () {
                    final n = s.applyAttendance(p);
                    setState(() => _msg = 'کارکرد $n نفر از روی تردد به‌روز شد');
                  }, icon: Icons.move_down_rounded),
            sakanBtn('عملکرد ماهانه پرسنل', p == null
                ? null
                : () => printTable(
                      store: s,
                      title: 'عملکرد ماهانه پرسنل ${p.name}',
                      headers: const ['کد', 'نام', 'شیفت', 'روز حضور', 'غیبت', 'ساعت کار', 'اضافه کار', 'کسر کار', 'تاخیر', 'ناقص'],
                      rows: [
                        for (final x in emps)
                          () {
                            final r = s.attendance(x, p);
                            return [x.personnelCode, x.fullName, s.shiftOf(x).name, '${r.presentDays}', '${r.absentDays}', hm(r.workedMinutes), hm(r.overtimeMinutes), hm(r.shortMinutes), '${r.lateCount}', '${r.incomplete}'];
                          }(),
                      ],
                      fileName: 'amalkard-mahane',
                    ), icon: Icons.print_outlined),
          ]),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: const TextStyle(fontWeight: FontWeight.w700))),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('فایل دستگاه: ستون اول کد پرسنلی یا شماره کارت، ستون دوم تاریخ (شمسی یا میلادی)، بعد ساعت‌ها (ورود، خروج یا هر ردیف یک تردد).', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 520,
                child: SakanGrid(
                  header: [sakanHead('نام', 0), sakanHead('حضور', 60), sakanHead('غیبت', 60), sakanHead('اضافه کار', 80), sakanHead('کسر کار', 80), sakanHead('تاخیر', 60)],
                  count: emps.length,
                  empty: p == null ? 'ابتدا دوره حقوقی بسازید' : 'پرسنلی در این دوره نیست',
                  row: (ctx, i) {
                    final x = emps[i];
                    final r = s.attendance(x, p!);
                    final on = x.id == _emp;
                    final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                    return InkWell(
                      onTap: () => setState(() => _emp = x.id),
                      child: Container(
                        color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                        child: Row(children: [
                          sakanCell(Text(x.fullName, style: st), 0, align: Alignment.centerRight),
                          sakanCell(Text('${r.presentDays}', style: st), 60),
                          sakanCell(Text('${r.absentDays}', style: st), 60),
                          sakanCell(Text(hm(r.overtimeMinutes), style: st), 80),
                          sakanCell(Text(hm(r.shortMinutes), style: st), 80),
                          sakanCell(Text('${r.lateCount}', style: st), 60),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: e == null
                    ? const Center(child: Text('یک نفر را انتخاب کنید تا تردد روزانه نمایش داده شود'))
                    : SakanGrid(
                        header: [sakanHead('تاریخ', 110), sakanHead('روز', 80), sakanHead('ورود', 80), sakanHead('خروج', 80), sakanHead('کارکرد', 80), sakanHead('توضیحات', 0)],
                        count: days.length,
                        row: (ctx, i) {
                          final d = days[i];
                          final c = s.clockOf(e.id, d);
                          final off = d.weekday == DateTime.friday;
                          return InkWell(
                            onDoubleTap: () => _editDay(s, e, d),
                            child: Container(
                              color: off ? const Color(0xFFFFF3E0) : (c == null ? const Color(0xFFFBE9E9) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                              child: Row(children: [
                                sakanCell(Text(jFormat(d)), 110),
                                sakanCell(Text(const ['دوشنبه', 'سه شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'][d.weekday - 1]), 80),
                                sakanCell(Text(hm(c?.inMin)), 80),
                                sakanCell(Text(hm(c?.outMin)), 80),
                                sakanCell(Text(c == null ? '' : hm(c.worked)), 80),
                                sakanCell(Text('${c?.note ?? ''}${c?.edited == true ? ' (اصلاح شده)' : ''}', overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          if (e != null) const Padding(padding: EdgeInsets.only(top: 4), child: Text('برای «اصلاح تردد» روی روز دوبار کلیک کنید.', style: TextStyle(fontSize: 12))),
        ]),
      ),
    );
  }
}

/// «تعیین شیفت»: shift definitions and the shift of each employee.
Future<void> showShifts(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Shifts());

class _Shifts extends StatefulWidget {
  const _Shifts();

  @override
  State<_Shifts> createState() => _ShiftsState();
}

class _ShiftsState extends State<_Shifts> {
  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    Widget time(String label, int v, ValueChanged<int> set) => SizedBox(
          width: 90,
          child: TextFormField(
            initialValue: hm(v),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: label, isDense: true),
            onChanged: (t) {
              final m = parseHm(t);
              if (m != null) set(m);
            },
          ),
        );
    return FormDialog(
      title: 'تعیین شیفت',
      width: 860,
      leading: TextButton.icon(
        onPressed: () => setState(() {
          s.shifts.add(Shift(id: newId(), name: 'شیفت ${s.shifts.length + 1}'));
          s.updateSettings((_) {});
        }),
        icon: const Icon(Icons.add_rounded),
        label: const Text('شیفت جدید'),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            s.updateSettings((_) {});
            Navigator.pop(context);
          },
          child: const Text('تایید'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final sh in s.shifts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 140, child: TextFormField(initialValue: sh.name, decoration: const InputDecoration(labelText: 'نام', isDense: true), onChanged: (v) => sh.name = v.trim())),
              const SizedBox(width: 6),
              time('شروع', sh.start, (v) => sh.start = v),
              const SizedBox(width: 6),
              time('پایان', sh.end, (v) => sh.end = v),
              const SizedBox(width: 6),
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: '${sh.breakMinutes}',
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'استراحت (دقیقه)', isDense: true),
                  onChanged: (v) => sh.breakMinutes = int.tryParse(normalizeDigits(v)) ?? sh.breakMinutes,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: '${sh.graceMinutes}',
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'تاخیر مجاز', isDense: true),
                  onChanged: (v) => sh.graceMinutes = int.tryParse(normalizeDigits(v)) ?? sh.graceMinutes,
                ),
              ),
              FilterChip(label: const Text('پنجشنبه نیمه وقت'), selected: sh.thursdayHalf, onSelected: (v) => setState(() => sh.thursdayHalf = v)),
              IconButton(
                onPressed: () => setState(() {
                  s.shifts.remove(sh);
                  s.employeeShift.removeWhere((_, v) => v == sh.id);
                  s.updateSettings((_) {});
                }),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ]),
          ),
        if (s.shifts.isEmpty) const Text('شیفتی تعریف نشده؛ پیش فرض ۸ تا ۱۶ با ۳۰ دقیقه استراحت.'),
        if (s.shifts.length > 1) ...[
          const Divider(),
          const Text('شیفت هر نفر', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final e in s.activeEmployees)
            Row(children: [
              Expanded(child: Text(e.fullName)),
              SizedBox(
                width: 200,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: s.shiftOf(e).id.isEmpty ? null : s.shiftOf(e).id,
                  items: [for (final sh in s.shifts) DropdownMenuItem(value: sh.id, child: Text(sh.name))],
                  onChanged: (v) => setState(() {
                    if (v != null) s.employeeShift[e.id] = v;
                    s.updateSettings((_) {});
                  }),
                ),
              ),
            ]),
        ],
      ]),
    );
  }
}
