import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printSlip, printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show pickPersonId;

/// «گزارش مطالبات» (receivable = true) / «گزارش تعهدات» (false) — plans and their remaining.
Future<void> showInstallmentPlans(BuildContext context, {required bool receivable}) =>
    showDialog<void>(context: context, builder: (_) => _Plans(receivable: receivable));

class _Plans extends StatefulWidget {
  final bool receivable;
  const _Plans({required this.receivable});

  @override
  State<_Plans> createState() => _PlansState();
}

class _PlansState extends State<_Plans> {
  String? _sel;
  bool _openOnly = true;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final now = DateTime.now();
    final list = s.installmentPlans.where((p) => p.receivable == widget.receivable && (!_openOnly || p.remaining > 0)).toList()
      ..sort((a, b) => a.firstDue.compareTo(b.firstDue));
    final sel = list.where((p) => p.id == _sel).firstOrNull;
    final title = widget.receivable ? 'گزارش مطالبات (دفترچه اقساط)' : 'گزارش تعهدات (دفترچه اقساط)';
    return SakanWindow(
      title: title,
      width: 1150,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('دفترچه اقساط جدید', () => showInstallmentEditor(context, receivable: widget.receivable), key: 'Ins', icon: Icons.add_rounded),
            sakanBtn('ویرایش / پرداخت اقساط', sel == null ? null : () => showInstallmentEditor(context, edit: sel), icon: Icons.edit_calendar_outlined),
            sakanBtn('چاپ دفترچه', sel == null ? null : () => printInstallmentBook(s, sel), icon: Icons.print_outlined),
            sakanBtn('ریز اقساط', () => _detail(s, list), icon: Icons.list_alt_rounded),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف دفترچه', 'دفترچه اقساط ${s.person(sel.personId)?.name ?? ''} حذف شود؟')) {
                      s.removeInstallmentPlan(sel.id);
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            FilterChip(label: const Text('فقط دارای مانده'), selected: _openOnly, onSelected: (v) => setState(() => _openOnly = v)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('کد حساب', 80),
                sakanHead('عنوان حساب', 0),
                sakanHead('بابت', 170),
                sakanHead('کل مبلغ', 120),
                sakanHead('تعداد اقساط', 80),
                sakanHead('تاریخ شروع پرداخت', 110),
                sakanHead('قسط بعدی', 100),
                sakanHead('معوق', 110),
                sakanHead('مانده پرداختنی', 120),
              ],
              count: list.length,
              empty: 'دفترچه اقساطی ثبت نشده',
              row: (ctx, i) {
                final p = list[i];
                final on = p.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                final next = p.items.where((x) => !x.settled).firstOrNull;
                final overdue = p.items.where((x) => !x.settled && x.due.isBefore(dateOnly(now))).fold<int>(0, (a, x) => a + x.remaining);
                final person = s.person(p.personId);
                return InkWell(
                  onTap: () => setState(() => _sel = p.id),
                  onDoubleTap: () => showInstallmentEditor(context, edit: p),
                  child: Container(
                    color: on ? sakanSel : (overdue > 0 ? const Color(0xFFFBE3E3) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text('${person?.code ?? ''}', style: st), 80),
                      sakanCell(Text(person?.name ?? '', style: st), 0, align: Alignment.centerRight),
                      sakanCell(Text(p.babat, style: st, overflow: TextOverflow.ellipsis), 170),
                      sakanCell(Text(groupDigits(p.total), style: st), 120),
                      sakanCell(Text('${p.items.length}', style: st), 80),
                      sakanCell(Text(jFormat(p.firstDue), style: st), 110),
                      sakanCell(Text(next == null ? 'تسویه' : jFormat(next.due), style: st), 100),
                      sakanCell(Text(groupDigits(overdue), style: st), 110),
                      sakanCell(Text(groupDigits(p.remaining), style: st.copyWith(fontWeight: FontWeight.w700)), 120),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text('جمع کل ${groupDigits(list.fold<int>(0, (a, p) => a + p.total))} — مانده ${groupDigits(list.fold<int>(0, (a, p) => a + p.remaining))}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  /// «ریز تعهدات / مطالبات»: every unpaid installment by due date.
  void _detail(AppStore s, List<InstallmentPlan> plans) {
    final rows = [
      for (final p in plans)
        for (final i in p.items.where((x) => !x.settled)) (p, i),
    ]..sort((a, b) => a.$2.due.compareTo(b.$2.due));
    printTable(
      store: s,
      title: widget.receivable ? 'ریز مطالبات' : 'ریز تعهدات',
      headers: const ['کد حساب', 'عنوان حساب', 'بابت', 'تاریخ سررسید', 'مبلغ قسط', 'مانده قسط'],
      rows: [
        for (final (p, i) in rows) ['${s.person(p.personId)?.code ?? ''}', s.person(p.personId)?.name ?? '', p.babat, jFormat(i.due), groupDigits(i.amount), groupDigits(i.remaining)],
      ],
      numeric: const {4, 5},
      footer: ['', '', '', 'جمع', groupDigits(rows.fold<int>(0, (a, r) => a + r.$2.amount)), groupDigits(rows.fold<int>(0, (a, r) => a + r.$2.remaining))],
      fileName: widget.receivable ? 'riz-motalebat' : 'riz-tahodat',
    );
  }
}

/// «دفترچه اقساط» print: one coupon per installment.
void printInstallmentBook(AppStore s, InstallmentPlan p) {
  final person = s.person(p.personId);
  printSlip(
    store: s,
    title: 'دفترچه اقساط',
    narrow: false,
    fields: [
      ('نام طرف حساب', person?.name ?? ''),
      ('کد طرف حساب', '${person?.code ?? ''}'),
      ('بابت', p.babat),
      ('کل مبلغ اقساط', groupDigits(p.total)),
      ('سود متعلقه', groupDigits(p.interest)),
      ('تعداد اقساط', '${p.items.length}'),
      ('تاریخ شروع محاسبه سود', jFormat(p.interestFrom)),
      ('تاریخ شروع پرداخت اقساط', jFormat(p.firstDue)),
      if (p.interestPct != 0) ('درصد سود', '${p.interestPct}'),
      if (p.penaltyPct != 0) ('درصد جریمه', '${p.penaltyPct}'),
      if (p.guarantorName.isNotEmpty) ('ضامن', '${p.guarantorName} ${p.guarantorPhone}'.trim()),
    ],
    itemHeaders: const ['ردیف', 'تاریخ سررسید قسط', 'مبلغ قسط', 'تاریخ پرداخت', 'مهر و امضا'],
    items: [
      for (var k = 0; k < p.items.length; k++)
        ['${k + 1}', jFormat(p.items[k].due), groupDigits(p.items[k].amount), p.items[k].paidOn == null ? '' : jFormat(p.items[k].paidOn!), ''],
    ],
    fileName: 'daftarche-aghsat',
  );
}

Future<void> showInstallmentEditor(BuildContext context, {InstallmentPlan? edit, bool receivable = true}) =>
    showDialog<void>(context: context, builder: (_) => _Editor(edit: edit, receivable: edit?.receivable ?? receivable));

class _Editor extends StatefulWidget {
  final InstallmentPlan? edit;
  final bool receivable;
  const _Editor({this.edit, required this.receivable});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final InstallmentPlan _p = widget.edit == null
      ? InstallmentPlan(id: newId(), receivable: widget.receivable, interestFrom: DateTime.now(), firstDue: DateTime(DateTime.now().year, DateTime.now().month + 1, DateTime.now().day))
      : InstallmentPlan.fromJson(widget.edit!.toJson());
  late final _principal = TextEditingController(text: _p.principal == 0 ? '' : groupDigits(_p.principal));
  late final _count = TextEditingController(text: '${_p.count}');
  late final _every = TextEditingController(text: '${_p.everyMonths}');
  late final _interest = TextEditingController(text: _p.interestPct == 0 ? '' : '${_p.interestPct}');
  late final _penalty = TextEditingController(text: _p.penaltyPct == 0 ? '' : '${_p.penaltyPct}');
  late final _babat = TextEditingController(text: _p.babat);
  late final _gName = TextEditingController(text: _p.guarantorName);
  late final _gPhone = TextEditingController(text: _p.guarantorPhone);
  late final _gId = TextEditingController(text: _p.guarantorId);
  String? _err;

  @override
  void dispose() {
    for (final c in [_principal, _count, _every, _interest, _penalty, _babat, _gName, _gPhone, _gId]) {
      c.dispose();
    }
    super.dispose();
  }

  void _read() {
    _p
      ..principal = parseMoney(_principal.text)
      ..count = int.tryParse(normalizeDigits(_count.text)) ?? 1
      ..everyMonths = (int.tryParse(normalizeDigits(_every.text)) ?? 1).clamp(1, 120)
      ..interestPct = double.tryParse(normalizeDigits(_interest.text)) ?? 0
      ..penaltyPct = double.tryParse(normalizeDigits(_penalty.text)) ?? 0
      ..babat = _babat.text.trim()
      ..guarantorName = _gName.text.trim()
      ..guarantorPhone = _gPhone.text.trim()
      ..guarantorId = normalizeDigits(_gId.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final now = DateTime.now();
    final title = widget.receivable ? 'دفترچه اقساط (مطالبات)' : 'دفترچه اقساط (تعهدات)';
    Widget f(TextEditingController c, String label, {bool money = false}) => Expanded(
          child: TextField(
            controller: c,
            textDirection: TextDirection.ltr,
            inputFormatters: money ? [MoneyInputFormatter()] : null,
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );
    return FormDialog(
      title: title,
      width: 860,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            _read();
            if (_p.personId == null) return setState(() => _err = 'طرف حساب را انتخاب کنید');
            if (_p.items.isEmpty) return setState(() => _err = '«محاسبه اقساط» را بزنید');
            s.saveInstallmentPlan(_p);
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final id = await pickPersonId(context, title: 'طرف حساب');
                if (id != null) setState(() => _p.personId = id);
              },
              icon: const Icon(Icons.person_search_rounded),
              label: Text(s.person(_p.personId)?.name ?? 'طرف حساب'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: TextField(controller: _babat, decoration: const InputDecoration(labelText: 'بابت', isDense: true))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('اطلاعات ضامن: '),
          Expanded(child: TextField(controller: _gName, decoration: const InputDecoration(labelText: 'نام ضامن', isDense: true))),
          const SizedBox(width: 6),
          Expanded(child: TextField(controller: _gPhone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تلفن ضامن', isDense: true))),
          const SizedBox(width: 6),
          Expanded(child: TextField(controller: _gId, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'کد ملی ضامن', isDense: true))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          f(_principal, 'کل مبلغ', money: true),
          const SizedBox(width: 6),
          f(_count, 'تعداد اقساط'),
          const SizedBox(width: 6),
          f(_every, 'فاصله اقساط (ماه)'),
          const SizedBox(width: 6),
          f(_interest, 'درصد سود سالانه'),
          const SizedBox(width: 6),
          f(_penalty, 'درصد جریمه ماهانه'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: DateField(label: 'تاریخ شروع محاسبه سود', value: _p.interestFrom, onChanged: (d) => setState(() => _p.interestFrom = d ?? _p.interestFrom))),
          const SizedBox(width: 8),
          Expanded(child: DateField(label: 'تاریخ شروع پرداخت اقساط', value: _p.firstDue, onChanged: (d) => setState(() => _p.firstDue = d ?? _p.firstDue))),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () async {
              if (_p.items.any((i) => i.paid > 0) && !await confirm(context, 'محاسبه مجدد', 'پرداخت‌های ثبت شده پاک می‌شوند. ادامه می‌دهید؟', ok: 'ادامه')) return;
              setState(() {
                _read();
                _p.generate();
                _err = null;
              });
            },
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('محاسبه اقساط'),
          ),
        ]),
        const SizedBox(height: 10),
        if (_p.items.isNotEmpty)
          Text('جمع اقساط ${groupDigits(_p.total)} — سود متعلقه ${groupDigits(_p.interest)} — پرداخت شده ${groupDigits(_p.paid)} — مانده ${groupDigits(_p.remaining)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        for (var k = 0; k < _p.items.length; k++)
          () {
            final it = _p.items[k];
            final pen = _p.penaltyOf(it, now);
            return ListTile(
              dense: true,
              leading: CircleAvatar(radius: 14, child: Text('${k + 1}', style: const TextStyle(fontSize: 11))),
              title: Text('سررسید ${jFormat(it.due)} — ${groupDigits(it.amount)}'),
              subtitle: Text([
                if (it.paid > 0) 'پرداخت ${groupDigits(it.paid)}${it.paidOn == null ? '' : ' در ${jFormat(it.paidOn!)}'}',
                if (pen > 0) 'جریمه تاخیر ${groupDigits(pen)}',
              ].join(' — ')),
              trailing: it.settled
                  ? TextButton(onPressed: () => setState(() => it
                    ..paid = 0
                    ..paidOn = null), child: const Text('لغو پرداخت'))
                  : TextButton(onPressed: () => setState(() => it
                    ..paid = it.amount
                    ..paidOn = DateTime.now()), child: const Text('ثبت پرداخت')),
            );
          }(),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
