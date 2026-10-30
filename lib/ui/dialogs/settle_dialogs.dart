import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'extras_dialogs.dart' show showInvoiceOffset;
import 'invoice_editor.dart' show pickPersonId, showInvoiceEditor;

/// «تسویه فاکتور به فاکتور» (Sakan): the person's payments are allocated to
/// their invoices in a «سند تسویه»; each invoice shows what is paid and what
/// is left, with the days to its due date and «راس فاکتور».
Future<void> showInvoiceSettle(BuildContext context, {String? personId, SettleDoc? edit}) =>
    showDialog<void>(context: context, builder: (_) => _Settle(personId: personId ?? edit?.personId, edit: edit));

class _Row {
  final Invoice inv;
  bool selected = false;
  final pay = TextEditingController();
  final cash = TextEditingController();
  final cheque = TextEditingController();
  final note = TextEditingController();
  _Row(this.inv);
  int get amount => parseMoney(pay.text);
  void dispose() {
    for (final c in [pay, cash, cheque, note]) {
      c.dispose();
    }
  }
}

class _Settle extends StatefulWidget {
  final String? personId;
  final SettleDoc? edit;
  const _Settle({this.personId, this.edit});

  @override
  State<_Settle> createState() => _SettleState();
}

class _SettleState extends State<_Settle> {
  late String? _person = widget.personId;
  bool _sales = true;
  int _settled = 1; // 0 همه، 1 تسویه نشده ها، 2 تسویه شده ها
  int _due = 0; // 0 همه، 1 سررسید شده ها، 2 سررسید نشده ها
  String? _marketer;
  DateTime _date = DateTime.now();
  final _docNote = TextEditingController();
  List<_Row> _rows = [];
  String? _msg;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _date = e.date;
      _docNote.text = e.note;
      _settled = 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _docNote.dispose();
    super.dispose();
  }

  DateTime _dueOf(Invoice i) => i.dueDate ?? i.date;
  int _days(Invoice i) => dateOnly(_dueOf(i)).difference(dateOnly(DateTime.now())).inDays;

  /// «فراخوانی اطلاعات».
  void _load() {
    if (!mounted) return;
    final s = StoreScope.read(context);
    for (final r in _rows) {
      r.dispose();
    }
    final kinds = _sales ? {InvoiceKind.sale} : {InvoiceKind.purchase};
    final ex = widget.edit?.id;
    final list = s.realInvoices.where((i) {
      if (!kinds.contains(i.kind) || (_person != null && i.personId != _person)) return false;
      if (_person == null && i.personId == null) return false;
      if (_marketer != null && !i.marketers.any((m) => m.personId == _marketer)) return false;
      final open = s.invoiceUnsettled(i, excludeDoc: ex);
      final inDoc = widget.edit?.rows.any((r) => r.invoiceId == i.id) ?? false;
      if (!inDoc && _settled == 1 && open <= 0) return false;
      if (!inDoc && _settled == 2 && open > 0) return false;
      if (_due == 1 && _days(i) > 0) return false;
      if (_due == 2 && _days(i) <= 0) return false;
      return true;
    }).toList()
      ..sort((a, b) => _dueOf(a).compareTo(_dueOf(b)));
    _rows = [
      for (final i in list)
        () {
          final r = _Row(i);
          final old = widget.edit?.rows.where((x) => x.invoiceId == i.id).firstOrNull;
          if (old != null) {
            r.selected = true;
            r.pay.text = groupDigits(old.amount);
            if (old.cash != 0) r.cash.text = groupDigits(old.cash);
            if (old.cheque != 0) r.cheque.text = groupDigits(old.cheque);
            r.note.text = old.note;
          }
          return r;
        }(),
    ];
    setState(() => _msg = null);
  }

  /// Allocates the person's unallocated payments to the oldest invoices.
  void _auto(AppStore s) {
    if (_person == null) return;
    var free = s.unallocatedPayments(_person!, sales: _sales);
    for (final r in _rows) {
      final open = s.invoiceUnsettled(r.inv, excludeDoc: widget.edit?.id);
      if (free <= 0 || open <= 0) continue;
      final a = open < free ? open : free;
      r
        ..selected = true
        ..pay.text = groupDigits(a);
      free -= a;
    }
    setState(() => _msg = free > 0 ? 'مبلغ ${groupDigits(free)} پس از تسویه همه فاکتورها باقی ماند' : null);
  }

  /// «راس فاکتور»: amount-weighted due date of the selected invoices.
  (DateTime, int)? _ras(AppStore s) {
    final sel = _rows.where((r) => r.selected).toList();
    if (sel.isEmpty) return null;
    var w = 0.0, sum = 0;
    for (final r in sel) {
      final open = s.invoiceUnsettled(r.inv, excludeDoc: widget.edit?.id);
      w += open * _days(r.inv);
      sum += open;
    }
    if (sum <= 0) return null;
    final days = (w / sum).round();
    return (dateOnly(DateTime.now()).add(Duration(days: days)), days);
  }

  void _save(AppStore s) {
    final rows = [
      for (final r in _rows)
        if (r.selected && r.amount != 0)
          SettleRow(invoiceId: r.inv.id, amount: r.amount, cash: parseMoney(r.cash.text), cheque: parseMoney(r.cheque.text), note: r.note.text.trim()),
    ];
    for (final r in rows) {
      final inv = _rows.firstWhere((x) => x.inv.id == r.invoiceId).inv;
      if (r.amount > s.invoiceUnsettled(inv, excludeDoc: widget.edit?.id)) {
        setState(() => _msg = 'مبلغ پرداختی فاکتور ${inv.number} از مانده تسویه نشده آن بیشتر است');
        return;
      }
    }
    if (rows.isEmpty) {
      if (widget.edit != null) s.removeSettleDoc(widget.edit!.id);
      Navigator.pop(context);
      return;
    }
    final d = SettleDoc(
      id: widget.edit?.id ?? newId(),
      number: widget.edit?.number ?? s.nextSettleNumber(),
      date: _date,
      personId: _person,
      note: _docNote.text.trim(),
      rows: rows,
    );
    s.saveSettleDoc(d);
    Navigator.pop(context);
    toast(context, 'سند تسویه ${d.number} ثبت شد');
  }

  Future<void> _history(AppStore s, Invoice inv) => showDialog<void>(
        context: context,
        builder: (ctx) {
          final h = s.settleHistory(inv);
          return FormDialog(
            title: 'لیست سندهای تسویه',
            width: 820,
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت'))],
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'شماره فاکتور: ${inv.number}    تاریخ فاکتور: ${jFormat(inv.date)}    مبلغ: ${groupDigits(inv.total)}    '
                'مبلغ تسویه نشده: ${groupDigits(s.invoiceUnsettled(inv))}    تعداد روز تا تسویه: ${_days(inv)}'
                '${inv.marketers.isEmpty ? '' : '    نام بازاریاب: ${s.person(inv.marketers.first.personId)?.name ?? ''}'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (s.invoiceDirectPaid(inv) != 0) Text('پرداخت هنگام صدور / تسویه فاکتور: ${groupDigits(s.invoiceDirectPaid(inv))}'),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: Colors.black12),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFEFF5FC)),
                    children: [
                      for (final t in const ['شماره مبنا', 'تاریخ', 'شرح', 'توضیحات پرداخت', 'مانده قبلی', 'مبلغ پرداختی در این سند', 'مانده نهایی'])
                        Padding(padding: const EdgeInsets.all(5), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                    ],
                  ),
                  for (final (d, r, before, after) in h)
                    TableRow(children: [
                      for (final t in ['${d.number}', jFormat(d.date), d.note, r.note, groupDigits(before), groupDigits(r.amount), groupDigits(after)])
                        Padding(padding: const EdgeInsets.all(5), child: Text(t, style: const TextStyle(fontSize: 12))),
                    ]),
                ],
              ),
              if (h.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('سند تسویه‌ای برای این فاکتور ثبت نشده')),
            ]),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final ex = widget.edit?.id;
    final selected = _rows.where((r) => r.selected).toList();
    final selSum = selected.fold<int>(0, (a, r) => a + s.invoiceUnsettled(r.inv, excludeDoc: ex));
    final paySum = selected.fold<int>(0, (a, r) => a + r.amount);
    final ras = _ras(s);
    final marketers = s.people.where((p) => p.marketer).toList();
    Widget seg(List<String> labels, int v, ValueChanged<int> on) => SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (var i = 0; i < labels.length; i++) ButtonSegment(value: i, label: Text(labels[i], style: const TextStyle(fontSize: 12)))],
          selected: {v},
          onSelectionChanged: (x) {
            on(x.first);
            _load();
          },
        );
    return SakanWindow(
      title: widget.edit == null ? 'تسویه فاکتور به فاکتور' : 'ویرایش سند تسویه ${widget.edit!.number}',
      width: 1300,
      height: 740,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ---------------------------------------------------- عنوان حساب
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: widget.edit != null
                      ? null
                      : () async {
                          final id = await pickPersonId(context, title: 'عنوان حساب');
                          if (id != null) {
                            _person = id;
                            _load();
                          }
                        },
                  icon: const Icon(Icons.person_search_rounded),
                  label: Text(s.person(_person)?.name ?? 'همه طرف حساب‌ها'),
                ),
                if (_person != null) ...[
                  Text('معین طرف حساب: ${_sales ? 'بدهکاران تجاری' : 'بستانکاران تجاری'}'),
                  Text('مانده دفتر: ${groupDigits(s.personBalance(_person!))}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
                seg(const ['فاکتورهای فروش', 'فاکتورهای خرید'], _sales ? 0 : 1, (v) => _sales = v == 0),
                if (marketers.isNotEmpty)
                  DropdownButton<String?>(
                    value: _marketer,
                    hint: const Text('بازاریاب'),
                    items: [const DropdownMenuItem<String?>(value: null, child: Text('همه بازاریاب‌ها')), for (final m in marketers) DropdownMenuItem<String?>(value: m.id, child: Text(m.name))],
                    onChanged: (v) {
                      _marketer = v;
                      _load();
                    },
                  ),
              ]),
            ),
          ),
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('نحوه نمایش:'),
            seg(const ['همه', 'تسویه نشده ها', 'تسویه شده ها'], _settled, (v) => _settled = v),
            seg(const ['همه', 'سررسید شده ها', 'سررسید نشده ها'], _due, (v) => _due = v),
            sakanBtn('فراخوانی اطلاعات', _load, icon: Icons.refresh_rounded),
            sakanBtn('تسویه خودکار از پرداخت‌های طرف حساب', _person == null ? null : () => _auto(s), icon: Icons.auto_fix_high_rounded),
            sakanBtn('تسویه با فاکتور خرید', () => showInvoiceOffset(context), icon: Icons.compare_arrows_rounded),
            sakanBtn('لیست سندهای تسویه', () => showSettleDocs(context, personId: _person), icon: Icons.list_alt_rounded),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('', 34),
                sakanHead('شماره ثابت فاکتور', 80),
                sakanHead('تاریخ فاکتور', 88),
                sakanHead(_sales ? 'نام خریدار' : 'نام فروشنده', 0),
                sakanHead('نام بازاریاب', 100),
                sakanHead('مبلغ فاکتور', 105),
                sakanHead('مبلغ پرداخت شده فاکتور', 110),
                sakanHead('مانده تسویه نشده فاکتور', 110),
                sakanHead('مبلغ پرداختی', 110),
                sakanHead('نقد', 90),
                sakanHead('چک', 90),
                sakanHead('توضیحات بابت مبلغ پرداختی در این سند', 150),
                sakanHead('تعداد روز باقیمانده', 70),
                sakanHead('', 40),
              ],
              count: _rows.length,
              empty: _person == null ? 'طرف حساب را انتخاب کنید یا «فراخوانی اطلاعات» را بزنید' : 'فاکتوری با این شرایط نیست',
              row: (ctx, i) {
                final r = _rows[i];
                final paid = s.invoicePaidTotal(r.inv, excludeDoc: ex);
                final open = r.inv.total - paid;
                final days = _days(r.inv);
                Widget money(TextEditingController c, {bool main = false}) => TextField(
                      controller: c,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [MoneyInputFormatter()],
                      style: TextStyle(fontSize: 12.5, fontWeight: main ? FontWeight.w800 : null),
                      decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                      onChanged: (_) => setState(() => r.selected = r.amount != 0 || r.selected),
                    );
                return Container(
                  color: r.selected ? const Color(0xFFFFF4C2) : (open <= 0 ? const Color(0xFFE6F6E6) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                  child: Row(children: [
                    sakanCell(
                      Checkbox(
                        value: r.selected,
                        onChanged: (v) => setState(() {
                          r.selected = v ?? false;
                          if (r.selected && r.pay.text.isEmpty && open > 0) r.pay.text = groupDigits(open);
                          if (!r.selected) r.pay.clear();
                        }),
                      ),
                      34,
                    ),
                    sakanCell(Text('${r.inv.number}'), 80),
                    sakanCell(Text(jFormat(r.inv.date)), 88),
                    sakanCell(Text(s.person(r.inv.personId)?.name ?? '', overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                    sakanCell(Text(r.inv.marketers.isEmpty ? '' : s.person(r.inv.marketers.first.personId)?.name ?? '', overflow: TextOverflow.ellipsis), 100),
                    sakanCell(Text(groupDigits(r.inv.total)), 105),
                    sakanCell(Text(groupDigits(paid)), 110),
                    sakanCell(Text(groupDigits(open), style: const TextStyle(fontWeight: FontWeight.w700)), 110),
                    sakanCell(money(r.pay, main: true), 110),
                    sakanCell(money(r.cash), 90),
                    sakanCell(money(r.cheque), 90),
                    sakanCell(
                      TextField(controller: r.note, style: const TextStyle(fontSize: 12), decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8))),
                      150,
                    ),
                    sakanCell(Text('$days', style: TextStyle(color: days < 0 ? Colors.red : null, fontWeight: FontWeight.w700)), 70),
                    sakanCell(
                      PopupMenuButton<int>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 0, child: Text('مشاهده ریز سندهای تسویه')),
                          PopupMenuItem(value: 1, child: Text('نمایش فاکتور')),
                        ],
                        onSelected: (v) => v == 0 ? _history(s, r.inv) : showInvoiceEditor(context, edit: r.inv),
                      ),
                      40,
                    ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('جمع فاکتورهای انتخابی: ${groupDigits(selSum)}    جمع مبلغ: ${groupDigits(paySum)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 16),
            if (ras != null) Text('راس فاکتور: ${jFormat(ras.$1)} (${ras.$2} روز)', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1F3BB3))),
            const Spacer(),
            SizedBox(width: 150, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
            const SizedBox(width: 8),
            SizedBox(width: 220, child: TextField(controller: _docNote, decoration: const InputDecoration(labelText: 'شرح', isDense: true))),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: () => _save(s), icon: const Icon(Icons.save_rounded), label: const Text('ذخیره اطلاعات و خروج')),
          ]),
          if (_msg != null) Text(_msg!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// «لیست سندهای تسویه».
Future<void> showSettleDocs(BuildContext context, {String? personId}) {
  final s = StoreScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final docs = s.settleDocs.where((d) => personId == null || d.personId == personId).toList()..sort((a, b) => b.number.compareTo(a.number));
      String invs(SettleDoc d) => d.rows.map((r) => s.invoices.where((i) => i.id == r.invoiceId).firstOrNull?.number ?? '').join('، ');
      return FormDialog(
        title: 'لیست سندهای تسویه',
        width: 860,
        leading: TextButton.icon(
          onPressed: () => printTable(
            store: s,
            title: 'لیست سندهای تسویه',
            headers: const ['شماره ثابت سند تسویه', 'تاریخ', 'طرف حساب', 'فاکتورها', 'شرح', 'مبلغ'],
            rows: [for (final d in docs) ['${d.number}', jFormat(d.date), s.person(d.personId)?.name ?? '', invs(d), d.note, groupDigits(d.total)]],
            numeric: const {5},
            fileName: 'sanad-tasvie',
          ),
          icon: const Icon(Icons.print_outlined),
          label: const Text('چاپ'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت'))],
        child: Column(children: [
          for (final d in docs)
            ListTile(
              dense: true,
              title: Text('سند تسویه ${d.number} — ${s.person(d.personId)?.name ?? ''} — ${groupDigits(d.total)}'),
              subtitle: Text('${jFormat(d.date)} — فاکتورها: ${invs(d)}${d.note.isEmpty ? '' : ' — ${d.note}'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'ویرایش',
                  onPressed: () async {
                    await showInvoiceSettle(ctx, edit: d);
                    set(() {});
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () async {
                    if (await confirm(ctx, 'حذف سند تسویه', 'سند تسویه ${d.number} حذف شود؟')) {
                      s.removeSettleDoc(d.id);
                      set(() {});
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]),
            ),
          if (docs.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('سند تسویه‌ای ثبت نشده')),
        ]),
      );
    }),
  );
}
