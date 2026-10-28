import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/marketing.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty, pickPersonId;

// ================================================================ بازاریابان

/// «بازاریابان» — marketers (person accounts) with their default percent,
/// the commission settings and the commission reports.
Future<void> showMarketersWindow(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Marketers());

class _Marketers extends StatefulWidget {
  const _Marketers();

  @override
  State<_Marketers> createState() => _MarketersState();
}

class _MarketersState extends State<_Marketers> {
  String? _sel;

  Future<void> _setPct(AppStore s, Person p) async {
    final c = TextEditingController(text: p.marketerPct == 0 ? '' : fmtQty(p.marketerPct));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'بازاریاب — ${p.name}',
        width: 400,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: c,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'درصد بازاریابی پیش فرض', suffixText: '٪'),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
          Text('خالی یا صفر: سهم از «درصد بازاریابی» هر کالا حساب می‌شود.', style: Theme.of(ctx).textTheme.bodySmall),
        ]),
      ),
    );
    if (ok == true) {
      p
        ..marketer = true
        ..marketerPct = parseQty(c.text);
      s.upsertPerson(p);
    }
    c.dispose();
  }

  Future<void> _add(AppStore s) async {
    final id = await pickPersonId(context, title: 'انتخاب حساب بازاریاب');
    final p = s.person(id);
    if (p == null || !mounted) return;
    await _setPct(s, p);
    setState(() => _sel = p.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final st = s.settings;
    final list = s.marketers;
    final sel = list.where((p) => p.id == _sel).firstOrNull;
    final expenseLedgers = chart.where((k) => k.side == Side.expense).expand((k) => k.ledgers).toList();
    return SakanWindow(
      title: 'بازاریابان',
      width: 820,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            sakanBtn('بازاریاب جدید', () => _add(s), icon: Icons.person_add_alt_1_outlined),
            sakanBtn('درصد پیش فرض', sel == null ? null : () => _setPct(s, sel), icon: Icons.percent_rounded),
            sakanBtn('حذف از بازاریابان', sel == null ? null : () => s.upsertPerson(sel..marketer = false), icon: Icons.person_remove_outlined),
            sakanBtn('گزارش پورسانت', () => showCommissionReport(context, marketerId: _sel), icon: Icons.receipt_long_outlined),
            sakanBtn('فروش بازاریاب روزانه', () => showMarketerSales(context, monthly: false), icon: Icons.today_outlined),
            sakanBtn('فروش بازاریاب ماهانه', () => showMarketerSales(context, monthly: true), icon: Icons.calendar_month_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('ردیف', 50), sakanHead('نام بازاریاب', 0), sakanHead('تلفن', 150), sakanHead('درصد پیش فرض', 120), sakanHead('مانده حساب', 150)],
              count: list.length,
              empty: 'بازاریابی تعریف نشده',
              row: (ctx, i) {
                final p = list[i];
                final on = p.id == _sel;
                final ts = TextStyle(color: on ? Colors.white : null);
                return InkWell(
                  onTap: () => setState(() => _sel = p.id),
                  onDoubleTap: () => _setPct(s, p),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text('${i + 1}', style: ts), 50),
                      sakanCell(Text(p.name, style: ts.copyWith(fontWeight: FontWeight.w700)), 0, align: Alignment.centerRight),
                      sakanCell(Text(p.phone, style: ts, textDirection: TextDirection.ltr), 150),
                      sakanCell(Text(p.marketerPct == 0 ? 'درصد کالا' : '${fmtQty(p.marketerPct)}٪', style: ts), 120),
                      sakanCell(Text(groupDigits(s.personBalance(p.id)), style: ts, textDirection: TextDirection.ltr), 150),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: st.commissionExpense, onChanged: (v) => s.updateSettings((x) => x.commissionExpense = v ?? true)),
              const Text('پورسانت بعنوان هزینه بر عهده فروشنده محسوب گردد'),
            ]),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                value: expenseLedgers.any((m) => m.code == st.commissionAccount) ? st.commissionAccount : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'حساب هزینه بازاریابان', isDense: true),
                items: [for (final m in expenseLedgers) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}', overflow: TextOverflow.ellipsis))],
                onChanged: st.commissionExpense ? (v) => s.updateSettings((x) => x.commissionAccount = v ?? '5010') : null,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ================================================================ تیم بازاریابی فاکتور

class MarketingTeam {
  final List<MarketerShare> marketers;
  final String? distributorId;
  const MarketingTeam(this.marketers, this.distributorId);
}

/// «انتخاب تیم بازاریابی» of an invoice: marketers with percent or amount, and «مسئول پخش».
Future<MarketingTeam?> showMarketingTeamDialog(BuildContext context, {required List<MarketerShare> current, String? distributorId, required int invoiceNet}) =>
    showDialog<MarketingTeam>(
      context: context,
      builder: (_) => _TeamDialog(current: current, distributorId: distributorId, net: invoiceNet),
    );

class _TeamRow {
  final String personId;
  final pct = TextEditingController();
  final amount = TextEditingController();
  _TeamRow(this.personId);
}

class _TeamDialog extends StatefulWidget {
  final List<MarketerShare> current;
  final String? distributorId;
  final int net;
  const _TeamDialog({required this.current, this.distributorId, required this.net});

  @override
  State<_TeamDialog> createState() => _TeamDialogState();
}

class _TeamDialogState extends State<_TeamDialog> {
  final List<_TeamRow> _rows = [];
  String? _dist;

  @override
  void initState() {
    super.initState();
    _dist = widget.distributorId;
    for (final m in widget.current) {
      final r = _TeamRow(m.personId);
      if (m.pct != 0) r.pct.text = fmtQty(m.pct);
      if (m.amount != 0) r.amount.text = groupDigits(m.amount);
      _rows.add(r);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.pct.dispose();
      r.amount.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final free = s.marketers.where((p) => !_rows.any((r) => r.personId == p.id)).toList();
    return FormDialog(
      title: 'انتخاب تیم بازاریابی',
      width: 640,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MarketingTeam([
              for (final r in _rows) MarketerShare(personId: r.personId, pct: parseQty(r.pct.text), amount: parseMoney(r.amount.text)),
            ], _dist),
          ),
          child: const Text('تایید'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'افزودن بازاریاب', isDense: true),
              items: [for (final p in free) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (id) {
                if (id == null) return;
                final p = s.person(id)!;
                setState(() {
                  final r = _TeamRow(id);
                  if (p.marketerPct != 0) r.pct.text = fmtQty(p.marketerPct);
                  _rows.add(r);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: () => showMarketersWindow(context).then((_) => setState(() {})), child: const Text('تعریف بازاریاب')),
        ]),
        const SizedBox(height: 10),
        for (final r in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(s.person(r.personId)?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: r.pct,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'درصد', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: r.amount,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'یا مبلغ', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  parseMoney(r.amount.text) != 0
                      ? groupDigits(parseMoney(r.amount.text))
                      : (parseQty(r.pct.text) != 0 ? groupDigits((widget.net * parseQty(r.pct.text) / 100).round()) : 'درصد کالا'),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _rows.remove(r)),
                icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935)),
              ),
            ]),
          ),
        if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('بازاریابی انتخاب نشده', style: th.textTheme.bodySmall)),
        const Divider(height: 24),
        DropdownButtonFormField<String?>(
          value: _dist,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'مسئول پخش', isDense: true),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final p in s.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _dist = v),
        ),
      ]),
    );
  }
}

// ================================================================ گزارش‌ها

(DateTime, DateTime) _monthRange() {
  final now = DateTime.now();
  return (DateTime(now.year, now.month - 1, now.day), now);
}

/// «گزارش پورسانت» — marketer shares per invoice.
Future<void> showCommissionReport(BuildContext context, {String? marketerId}) =>
    showDialog<void>(context: context, builder: (_) => _CommissionReport(marketerId: marketerId));

class _CommissionReport extends StatefulWidget {
  final String? marketerId;
  const _CommissionReport({this.marketerId});

  @override
  State<_CommissionReport> createState() => _CommissionReportState();
}

class _CommissionReportState extends State<_CommissionReport> {
  late DateTime _from = _monthRange().$1;
  late DateTime _to = _monthRange().$2;
  late String? _m = widget.marketerId;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = s.commissionReport(_from, DateTime(_to.year, _to.month, _to.day, 23, 59), marketerId: _m);
    final total = rows.fold<int>(0, (a, r) => a + r.signed);
    const w = [100.0, 110.0, 70.0, 0.0, 160.0, 70.0, 130.0];
    return SakanWindow(
      title: 'گزارش پورسانت',
      width: 1000,
      height: 660,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 190, child: DateField(label: 'از تاریخ', value: _from, onChanged: (d) => setState(() => _from = d ?? _from))),
            SizedBox(width: 190, child: DateField(label: 'تا تاریخ', value: _to, onChanged: (d) => setState(() => _to = d ?? _to))),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: _m,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'بازاریاب', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                  for (final p in s.marketers) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _m = v),
              ),
            ),
            sakanBtn('چاپ', () {
              printTable(
                store: s,
                title: 'گزارش پورسانت',
                subtitle: '${jFormat(_from)} تا ${jFormat(_to)}',
                headers: const ['تاریخ', 'نوع', 'شماره', 'خریدار', 'بازاریاب', 'درصد', 'سهم بازاریاب'],
                rows: [
                  for (final r in rows)
                    [
                      jFormat(r.invoice.date),
                      r.invoice.kind.label,
                      '${r.invoice.number}',
                      s.person(r.invoice.personId)?.name ?? 'متفرقه',
                      s.person(r.marketerId)?.name ?? '',
                      r.pct.toStringAsFixed(1),
                      groupDigits(r.signed),
                    ],
                ],
                numeric: const {5, 6},
                footer: ['', '', '', '', '', 'جمع', groupDigits(total)],
                fileName: 'porsant',
              );
            }, icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('تاریخ', w[0]),
                sakanHead('نوع', w[1]),
                sakanHead('شماره', w[2]),
                sakanHead('خریدار', w[3]),
                sakanHead('بازاریاب', w[4]),
                sakanHead('درصد', w[5]),
                sakanHead('سهم بازاریاب', w[6]),
              ],
              count: rows.length,
              empty: 'در این بازه پورسانتی ثبت نشده',
              row: (ctx, i) {
                final r = rows[i];
                return Container(
                  color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                  child: Row(children: [
                    sakanCell(Text(jFormat(r.invoice.date)), w[0]),
                    sakanCell(Text(r.invoice.kind.short), w[1]),
                    sakanCell(Text('${r.invoice.number}'), w[2]),
                    sakanCell(Text(s.person(r.invoice.personId)?.name ?? 'متفرقه', overflow: TextOverflow.ellipsis), w[3], align: Alignment.centerRight),
                    sakanCell(Text(s.person(r.marketerId)?.name ?? '', overflow: TextOverflow.ellipsis), w[4]),
                    sakanCell(Text(r.pct.toStringAsFixed(1)), w[5]),
                    sakanCell(Money(r.signed, colorBySign: true), w[6]),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${rows.length} ردیف'),
            const Spacer(),
            const Text('جمع پورسانت: '),
            Money(total, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}

/// «فروش بازاریاب» روزانه / ماهانه.
Future<void> showMarketerSales(BuildContext context, {required bool monthly}) =>
    showDialog<void>(context: context, builder: (_) => _MarketerSales(monthly: monthly));

class _MarketerSales extends StatefulWidget {
  final bool monthly;
  const _MarketerSales({required this.monthly});

  @override
  State<_MarketerSales> createState() => _MarketerSalesState();
}

class _MarketerSalesState extends State<_MarketerSales> {
  late DateTime _from = _monthRange().$1;
  late DateTime _to = _monthRange().$2;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = s.salesByMarketer(_from, DateTime(_to.year, _to.month, _to.day, 23, 59), monthly: widget.monthly);
    final title = widget.monthly ? 'فروش بازاریاب ماهانه' : 'فروش بازاریاب روزانه';
    const w = [110.0, 0.0, 80.0, 140.0, 140.0, 140.0, 130.0];
    return SakanWindow(
      title: title,
      width: 1000,
      height: 660,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 190, child: DateField(label: 'از تاریخ', value: _from, onChanged: (d) => setState(() => _from = d ?? _from))),
            SizedBox(width: 190, child: DateField(label: 'تا تاریخ', value: _to, onChanged: (d) => setState(() => _to = d ?? _to))),
            sakanBtn('چاپ', () {
              printTable(
                store: s,
                title: title,
                subtitle: '${jFormat(_from)} تا ${jFormat(_to)}',
                headers: [widget.monthly ? 'ماه' : 'روز', 'بازاریاب', 'تعداد فاکتور', 'فروش', 'برگشت', 'خالص', 'پورسانت'],
                rows: [
                  for (final r in rows)
                    [r.period, s.person(r.marketerId)?.name ?? '', '${r.invoices}', groupDigits(r.sales), groupDigits(r.returns), groupDigits(r.net), groupDigits(r.commission)],
                ],
                numeric: const {2, 3, 4, 5, 6},
                fileName: 'bazaryab',
              );
            }, icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead(widget.monthly ? 'ماه' : 'روز', w[0]),
                sakanHead('بازاریاب', w[1]),
                sakanHead('فاکتور', w[2]),
                sakanHead('فروش', w[3]),
                sakanHead('برگشت', w[4]),
                sakanHead('خالص', w[5]),
                sakanHead('پورسانت', w[6]),
              ],
              count: rows.length,
              empty: 'در این بازه فروشی با بازاریاب ثبت نشده',
              row: (ctx, i) {
                final r = rows[i];
                return Container(
                  color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                  child: Row(children: [
                    sakanCell(Text(r.period), w[0]),
                    sakanCell(Text(s.person(r.marketerId)?.name ?? '', overflow: TextOverflow.ellipsis), w[1], align: Alignment.centerRight),
                    sakanCell(Text('${r.invoices}'), w[2]),
                    sakanCell(Money(r.sales), w[3]),
                    sakanCell(Money(r.returns), w[4]),
                    sakanCell(Money(r.net, style: const TextStyle(fontWeight: FontWeight.w700)), w[5]),
                    sakanCell(Money(r.commission), w[6]),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
