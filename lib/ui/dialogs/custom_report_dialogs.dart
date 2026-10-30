import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/custom_reports.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';

DateTime _yearStart() {
  final j = Jalali.fromDateTime(DateTime.now());
  return Jalali(j.year, 1, 1).toDateTime();
}

Widget _range(DateTime from, DateTime to, void Function(DateTime, DateTime) set) => Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 160, child: DateField(label: 'از تاریخ', value: from, onChanged: (d) => set(d ?? from, to))),
      const SizedBox(width: 6),
      SizedBox(width: 160, child: DateField(label: 'تا تاریخ', value: to, onChanged: (d) => set(from, d ?? to))),
    ]);

// ================================================================ ترازنامه / سود و زیان سفارشی

Future<void> showCustomStatements(BuildContext context, {required bool balanceSheet}) =>
    showDialog<void>(context: context, builder: (_) => _Statements(balanceSheet: balanceSheet));

class _Statements extends StatefulWidget {
  final bool balanceSheet;
  const _Statements({required this.balanceSheet});

  @override
  State<_Statements> createState() => _StatementsState();
}

class _StatementsState extends State<_Statements> {
  String? _sel;
  DateTime _from = _yearStart(), _to = dateOnly(DateTime.now());
  bool _edit = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.customStatements.where((x) => x.balanceSheet == widget.balanceSheet).toList();
    if (list.isEmpty) {
      final st = widget.balanceSheet ? CustomStatement.sampleBalanceSheet() : CustomStatement.sampleProfit();
      s.customStatements.add(st);
      list.add(st);
    }
    final st = list.where((x) => x.id == _sel).firstOrNull ?? list.first;
    final vals = evaluateStatement(s, st, from: _from, to: _to);
    final title = widget.balanceSheet ? 'ترازنامه سفارشی' : 'صورتحساب سود/زیان سفارشی';
    return SakanWindow(
      title: title,
      width: 1000,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<String>(
              value: st.id,
              items: [for (final x in list) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setState(() => _sel = v),
            ),
            sakanBtn('الگوی جدید', () {
              final n = widget.balanceSheet ? CustomStatement.sampleBalanceSheet() : CustomStatement.sampleProfit();
              n.name = '${n.name} ${list.length + 1}';
              s.customStatements.add(n);
              s.updateSettings((_) {});
              setState(() {
                _sel = n.id;
                _edit = true;
              });
            }, icon: Icons.add_rounded),
            sakanBtn(_edit ? 'پایان ویرایش' : 'ساخت الگو / ویرایش', () {
              s.updateSettings((_) {});
              setState(() => _edit = !_edit);
            }, icon: Icons.edit_note_rounded),
            if (!widget.balanceSheet) _range(_from, _to, (a, b) => setState(() {
                _from = a;
                _to = b;
              })),
            if (widget.balanceSheet) SizedBox(width: 170, child: DateField(label: 'تا تاریخ', value: _to, onChanged: (d) => setState(() => _to = d ?? _to))),
            sakanBtn('چاپ', () => printTable(
                  store: s,
                  title: st.name,
                  subtitle: widget.balanceSheet ? 'تا تاریخ ${jFormat(_to)}' : 'از ${jFormat(_from)} تا ${jFormat(_to)}',
                  headers: const ['شرح', 'مبلغ'],
                  rows: [for (var i = 0; i < st.rows.length; i++) [st.rows[i].title, vals[i] == null ? '' : groupDigits(vals[i]!)]],
                  numeric: const {1},
                  fileName: 'gozaresh-sefareshi',
                ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          if (_edit)
            TextField(
              controller: TextEditingController(text: st.name),
              decoration: const InputDecoration(labelText: 'نام الگو', isDense: true),
              onChanged: (v) => st.name = v.trim(),
            ),
          if (_edit) const Text('کدها: کد کل (۲ رقمی) یا معین (۴ رقمی)، با «-» کم می‌شود. «جمع» ردیف‌های قبل از خود را جمع می‌زند.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Expanded(
            child: Card(
              child: ListView(children: [
                for (var i = 0; i < st.rows.length; i++)
                  _edit
                      ? Padding(
                          key: ObjectKey(st.rows[i]),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          child: Row(children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(initialValue: st.rows[i].title, decoration: const InputDecoration(labelText: 'شرح', isDense: true), onChanged: (v) => st.rows[i].title = v),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: st.rows[i].codes.join(' '),
                                enabled: !st.rows[i].header && !st.rows[i].total,
                                textDirection: TextDirection.ltr,
                                decoration: const InputDecoration(labelText: 'کدها', isDense: true),
                                onChanged: (v) => st.rows[i].codes = normalizeDigits(v).split(RegExp(r'[\s,،]+')).where((x) => x.isNotEmpty).toList(),
                              ),
                            ),
                            FilterChip(label: const Text('عنوان'), selected: st.rows[i].header, onSelected: (v) => setState(() => st.rows[i].header = v)),
                            FilterChip(label: const Text('جمع'), selected: st.rows[i].total, onSelected: (v) => setState(() => st.rows[i].total = v)),
                            FilterChip(label: const Text('بستانکار مثبت'), selected: st.rows[i].creditPositive, onSelected: (v) => setState(() => st.rows[i].creditPositive = v)),
                            IconButton(onPressed: () => setState(() => st.rows.insert(i + 1, StatementRow(title: ''))), icon: const Icon(Icons.add_rounded, size: 18)),
                            IconButton(onPressed: () => setState(() => st.rows.removeAt(i)), icon: const Icon(Icons.close_rounded, size: 18)),
                          ]),
                        )
                      : ListTile(
                          dense: true,
                          title: Text(st.rows[i].title,
                              style: TextStyle(fontWeight: st.rows[i].header || st.rows[i].total ? FontWeight.w900 : null, fontSize: st.rows[i].header ? 15 : null)),
                          trailing: vals[i] == null ? null : Money(vals[i]!, style: TextStyle(fontWeight: st.rows[i].total ? FontWeight.w900 : FontWeight.w600)),
                        ),
                if (_edit)
                  TextButton.icon(onPressed: () => setState(() => st.rows.add(StatementRow(title: ''))), icon: const Icon(Icons.add_rounded), label: const Text('ردیف')),
              ]),
            ),
          ),
          if (_edit && list.length > 1)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() {
                  s.customStatements.remove(st);
                  s.updateSettings((_) {});
                  _sel = null;
                  _edit = false;
                }),
                child: const Text('حذف این الگو'),
              ),
            ),
        ]),
      ),
    );
  }
}

// ================================================================ صورت خلاصه درآمد و هزینه

Future<void> showIncomeExpenseSummary(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _IncExp());

class _IncExp extends StatefulWidget {
  const _IncExp();

  @override
  State<_IncExp> createState() => _IncExpState();
}

class _IncExpState extends State<_IncExp> {
  DateTime _from = _yearStart(), _to = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = incomeExpenseSummary(s, _from, _to);
    final inc = rows.fold<int>(0, (a, r) => a + r.$2), exp = rows.fold<int>(0, (a, r) => a + r.$3);
    return FormDialog(
      title: 'صورت خلاصه درآمد و هزینه',
      width: 700,
      leading: _range(_from, _to, (a, b) => setState(() {
                _from = a;
                _to = b;
              })),
      actions: [
        TextButton(
          onPressed: () => printTable(
            store: s,
            title: 'صورت خلاصه درآمد و هزینه',
            subtitle: 'از ${jFormat(_from)} تا ${jFormat(_to)}',
            headers: const ['شرح', 'درآمد', 'هزینه'],
            rows: [for (final r in rows) [r.$1, groupDigits(r.$2), groupDigits(r.$3)]],
            numeric: const {1, 2},
            footer: ['جمع — خالص ${groupDigits(inc - exp)}', groupDigits(inc), groupDigits(exp)],
            fileName: 'kholase-daramad-hazine',
          ),
          child: const Text('چاپ'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rows)
          ListTile(
            dense: true,
            title: Text(r.$1),
            trailing: Text(r.$2 != 0 ? '+${groupDigits(r.$2)}' : '-${groupDigits(r.$3)}',
                textDirection: TextDirection.ltr, style: TextStyle(color: r.$2 != 0 ? Colors.green.shade800 : Colors.red.shade700, fontWeight: FontWeight.w700)),
          ),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('درآمد یا هزینه‌ای در این بازه ثبت نشده')),
        const Divider(),
        Text('جمع درآمد ${groupDigits(inc)} — جمع هزینه ${groupDigits(exp)} — خالص ${groupDigits(inc - exp)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ================================================================ گزارشات پویا نمودار

Future<void> showDynamicReport(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Dyn());

class _Dyn extends StatefulWidget {
  const _Dyn();

  @override
  State<_Dyn> createState() => _DynState();
}

class _DynState extends State<_Dyn> {
  DynMetric _m = DynMetric.sales;
  DynGroup _g = DynGroup.month;
  DateTime _from = _yearStart(), _to = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final data = dynamicSeries(s, _m, _g, _from, _to);
    final maxAbs = data.fold<int>(1, (a, d) => d.$2.abs() > a ? d.$2.abs() : a);
    return SakanWindow(
      title: 'گزارشات پویا نمودار',
      width: 1000,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<DynMetric>(value: _m, items: [for (final m in DynMetric.values) DropdownMenuItem(value: m, child: Text(m.label))], onChanged: (v) => setState(() => _m = v ?? _m)),
            DropdownButton<DynGroup>(
              value: _g,
              items: [
                for (final g in DynGroup.values)
                  if (_m != DynMetric.profit || g == DynGroup.day || g == DynGroup.month) DropdownMenuItem(value: g, child: Text(g.label)),
              ],
              onChanged: (v) => setState(() => _g = v ?? _g),
            ),
            _range(_from, _to, (a, b) => setState(() {
                _from = a;
                _to = b;
              })),
            sakanBtn('چاپ', () => printTable(
                  store: s,
                  title: '${_m.label} ${_g.label}',
                  subtitle: 'از ${jFormat(_from)} تا ${jFormat(_to)}',
                  headers: const ['عنوان', 'مبلغ'],
                  rows: [for (final d in data) [d.$1, groupDigits(d.$2)]],
                  numeric: const {1},
                  footer: ['جمع', groupDigits(data.fold(0, (a, d) => a + d.$2))],
                  fileName: 'gozaresh-pooya',
                ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              child: data.isEmpty
                  ? const Center(child: Text('داده‌ای در این بازه نیست'))
                  : ListView(padding: const EdgeInsets.all(10), children: [
                      for (final (label, v) in data)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            SizedBox(width: 160, child: Text(label, overflow: TextOverflow.ellipsis)),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (ctx, c) => Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Container(
                                    height: 20,
                                    width: (c.maxWidth * v.abs() / maxAbs).clamp(2, c.maxWidth).toDouble(),
                                    decoration: BoxDecoration(color: v < 0 ? Colors.red.shade400 : const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(4)),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 130, child: Text(groupDigits(v), textAlign: TextAlign.left, textDirection: TextDirection.ltr)),
                          ]),
                        ),
                    ]),
            ),
          ),
          Text('جمع: ${groupDigits(data.fold(0, (a, d) => a + d.$2))}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

// ================================================================ گزارش تلفیقی

Future<void> showConsolidatedProfit(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Cons());

class _Cons extends StatefulWidget {
  const _Cons();

  @override
  State<_Cons> createState() => _ConsState();
}

class _ConsState extends State<_Cons> {
  DateTime _from = DateTime(2000), _to = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final data = consolidatedProfit(s, _from, _to);
    const heads = ['دفتر', 'فروش خالص', 'بهای تمام شده', 'سود ناخالص', 'سایر درآمدها', 'هزینه ها', 'سود خالص'];
    List<String> row(String name, ProfitReport r) => [
          name,
          groupDigits(r.netSales),
          groupDigits(r.cogs),
          groupDigits(r.grossProfit),
          groupDigits(r.otherIncome),
          groupDigits(r.expenses),
          groupDigits(r.netProfit),
        ];
    int sum(int Function(ProfitReport) f) => data.fold(0, (a, d) => a + f(d.$2));
    final total = ['جمع تلفیقی', groupDigits(sum((r) => r.netSales)), groupDigits(sum((r) => r.cogs)), groupDigits(sum((r) => r.grossProfit)), groupDigits(sum((r) => r.otherIncome)), groupDigits(sum((r) => r.expenses)), groupDigits(sum((r) => r.netProfit))];
    return FormDialog(
      title: 'گزارش تلفیقی صورت حساب سود و زیان',
      width: 960,
      leading: _range(_from, _to, (a, b) => setState(() {
                _from = a;
                _to = b;
              })),
      actions: [
        TextButton(
          onPressed: () => printTable(
            store: s,
            title: 'گزارش تلفیقی صورت حساب سود و زیان',
            headers: heads,
            rows: [for (final (n, r) in data) row(n, r)],
            numeric: const {1, 2, 3, 4, 5, 6},
            footer: total,
            fileName: 'sod-zian-talfighi',
          ),
          child: const Text('چاپ'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
      child: Table(
        border: TableBorder.all(color: Colors.black12),
        children: [
          TableRow(decoration: const BoxDecoration(color: Color(0xFFEFF5FC)), children: [for (final h in heads) Padding(padding: const EdgeInsets.all(6), child: Text(h, style: const TextStyle(fontWeight: FontWeight.w800)))]),
          for (final (n, r) in data) TableRow(children: [for (final c in row(n, r)) Padding(padding: const EdgeInsets.all(6), child: Text(c))]),
          TableRow(decoration: const BoxDecoration(color: Color(0xFFF5F5F5)), children: [for (final c in total) Padding(padding: const EdgeInsets.all(6), child: Text(c, style: const TextStyle(fontWeight: FontWeight.w800)))]),
        ],
      ),
    );
  }
}
