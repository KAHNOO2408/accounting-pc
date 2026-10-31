import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

// ================================================================ سالن های تولید

Future<void> showHalls(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Halls());

class _Halls extends StatefulWidget {
  const _Halls();

  @override
  State<_Halls> createState() => _HallsState();
}

class _HallsState extends State<_Halls> {
  Future<void> _edit(AppStore s, [ProductionHall? h]) async {
    final name = TextEditingController(text: h?.name ?? '');
    final note = TextEditingController(text: h?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: h == null ? 'تعریف سالن تولید' : 'ویرایش سالن تولید',
        width: 400,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت F10')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
        ],
        child: Column(children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام سالن')),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      s.saveHall((h ?? ProductionHall(id: newId(), name: ''))
        ..name = name.text.trim()
        ..note = note.text.trim());
    }
    name.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return FormDialog(
      title: 'سالن های تولید',
      width: 520,
      leading: TextButton.icon(onPressed: () => _edit(s), icon: const Icon(Icons.add_rounded), label: const Text('تعریف')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت F10'))],
      child: Column(children: [
        for (final h in s.halls)
          ListTile(
            dense: true,
            title: Text(h.name),
            subtitle: h.note.isEmpty ? null : Text(h.note),
            onTap: () => _edit(s, h),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: s.formulas.any((f) => f.hallId == h.id) || s.productions.any((p) => p.hallId == h.id)
                  ? null
                  : () {
                      s.halls.removeWhere((x) => x.id == h.id);
                      s.updateSettings((_) {});
                    },
            ),
          ),
        if (s.halls.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('سالنی تعریف نشده')),
      ]),
    );
  }
}

// ================================================================ مواد اولیه (shared row editor)

class _MatRow {
  String? productId;
  final qty = TextEditingController();
  _MatRow([this.productId, double q = 0]) {
    if (q != 0) qty.text = fmtQty(q);
  }
}

Widget _materials(BuildContext context, AppStore s, List<_MatRow> rows, VoidCallback changed, {double factor = 1}) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [
      const Text('مواد اولیه و قطعات', style: TextStyle(fontWeight: FontWeight.w800)),
      const Spacer(),
      TextButton.icon(
        onPressed: () {
          rows.add(_MatRow());
          changed();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('افزودن ردیف'),
      ),
    ]),
    for (final r in rows)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: r.productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'کالا', isDense: true),
              items: [for (final p in s.productsSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name))],
              onChanged: (v) {
                r.productId = v;
                changed();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: r.qty,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: 'مقدار', isDense: true, suffixText: s.product(r.productId)?.unit),
              onChanged: (_) => changed(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Text(
              r.productId == null ? '' : groupDigits((parseQty(r.qty.text) * factor * s.avgCost(r.productId!)).round()),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: () {
              rows.remove(r);
              changed();
            },
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      ),
  ]);
}

// ================================================================ فرمول های تولید

Future<void> showFormulas(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Formulas());

class _Formulas extends StatefulWidget {
  const _Formulas();

  @override
  State<_Formulas> createState() => _FormulasState();
}

class _FormulasState extends State<_Formulas> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final sel = s.formulas.where((f) => f.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'فرمول های تولید',
      width: 1000,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            sakanBtn('تعریف فرمول', () => showFormulaEditor(context), key: 'Ins', icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => showFormulaEditor(context, sel), icon: Icons.edit_outlined),
            sakanBtn('تولید با این فرمول', sel == null ? null : () => showProductionEditor(context, formula: sel), icon: Icons.precision_manufacturing_outlined),
            sakanBtn('برآورد قیمت تمام شده', sel == null ? null : () => showCostEstimate(context, sel), icon: Icons.calculate_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف فرمول', 'فرمول «${sel.name}» حذف شود؟')) {
                      s.formulas.removeWhere((f) => f.id == sel.id);
                      s.updateSettings((_) {});
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('سالن های تولید', () => showHalls(context), icon: Icons.factory_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('نام فرمول', 0), sakanHead('کالای تولیدی', 200), sakanHead('مقدار تولید', 100), sakanHead('تعداد مواد', 90), sakanHead('سربار', 120), sakanHead('سالن', 140), sakanHead('قیمت تمام شده هر واحد', 150)],
              count: s.formulas.length,
              empty: 'فرمولی تعریف نشده',
              row: (ctx, i) {
                final f = s.formulas[i];
                final on = f.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                final (m, o) = s.estimateProduction(f, f.yieldQty);
                return InkWell(
                  onTap: () => setState(() => _sel = f.id),
                  onDoubleTap: () => showFormulaEditor(context, f),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text(f.name, style: st), 0, align: Alignment.centerRight),
                      sakanCell(Text(s.product(f.productId)?.name ?? '', style: st, overflow: TextOverflow.ellipsis), 200),
                      sakanCell(Text(fmtQty(f.yieldQty), style: st), 100),
                      sakanCell(Text('${f.lines.length}', style: st), 90),
                      sakanCell(Text(groupDigits(f.overhead), style: st), 120),
                      sakanCell(Text(s.halls.where((h) => h.id == f.hallId).firstOrNull?.name ?? '', style: st), 140),
                      sakanCell(Text(f.yieldQty <= 0 ? '' : groupDigits(((m + o) / f.yieldQty).round()), style: st.copyWith(fontWeight: FontWeight.w700)), 150),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

Future<void> showFormulaEditor(BuildContext context, [ProductionFormula? f]) => showDialog<void>(context: context, builder: (_) => _FormulaEditor(edit: f));

class _FormulaEditor extends StatefulWidget {
  final ProductionFormula? edit;
  const _FormulaEditor({this.edit});

  @override
  State<_FormulaEditor> createState() => _FormulaEditorState();
}

class _FormulaEditorState extends State<_FormulaEditor> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _yield = TextEditingController(text: fmtQty(widget.edit?.yieldQty ?? 1));
  late final _overhead = TextEditingController(text: widget.edit == null || widget.edit!.overhead == 0 ? '' : groupDigits(widget.edit!.overhead));
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late String? _product = widget.edit?.productId;
  late String? _hall = widget.edit?.hallId;
  late final List<_MatRow> _rows = [for (final l in widget.edit?.lines ?? <ProductionLine>[]) _MatRow(l.productId, l.qty)];
  String? _err;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    if (_rows.isEmpty) _rows.add(_MatRow());
    return FormDialog(
      title: widget.edit == null ? 'تعریف فرمول تولید' : 'ویرایش فرمول تولید',
      width: 760,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final lines = [for (final r in _rows) if (r.productId != null && parseQty(r.qty.text) > 0) ProductionLine(productId: r.productId!, qty: parseQty(r.qty.text))];
            if (_name.text.trim().isEmpty) return setState(() => _err = 'نام فرمول را وارد کنید');
            if (_product == null) return setState(() => _err = 'کالای تولیدی را انتخاب کنید');
            if (lines.isEmpty) return setState(() => _err = 'حداقل یک ماده اولیه وارد کنید');
            if (lines.any((l) => l.productId == _product)) return setState(() => _err = 'کالای تولیدی نمی‌تواند ماده اولیه خودش باشد');
            s.saveFormula((widget.edit ?? ProductionFormula(id: newId(), name: '', productId: ''))
              ..name = _name.text.trim()
              ..productId = _product!
              ..yieldQty = parseQty(_yield.text) <= 0 ? 1 : parseQty(_yield.text)
              ..overhead = parseMoney(_overhead.text)
              ..hallId = _hall
              ..note = _note.text.trim()
              ..lines = lines);
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'نام فرمول'))),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _hall,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'سالن تولید'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('—')), for (final h in s.halls) DropdownMenuItem<String?>(value: h.id, child: Text(h.name))],
              onChanged: (v) => setState(() => _hall = v),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              value: _product,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'کالای تولیدی'),
              items: [for (final p in s.productsSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => _product = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _yield, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مقدار تولید با این مواد'))),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _overhead,
              textDirection: TextDirection.ltr,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(labelText: 'سربار (دستمزد، انرژی…)'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _materials(context, s, _rows, () => setState(() {})),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'توضیحات')),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}

// ================================================================ برآورد قیمت تمام شده

Future<void> showCostEstimate(BuildContext context, ProductionFormula f) {
  final s = StoreScope.read(context);
  final q = TextEditingController(text: fmtQty(f.yieldQty));
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final qty = parseQty(q.text);
      final lines = f.scaled(qty);
      final (m, o) = s.estimateProduction(f, qty);
      final short = [for (final l in lines) if (s.stock(l.productId) < l.qty) l];
      return FormDialog(
        title: 'برآورد قیمت تمام شده کالای تولیدی — ${s.product(f.productId)?.name ?? ''}',
        width: 680,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 200, child: TextField(controller: q, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مقدار تولید'), onChanged: (_) => set(() {}))),
          const SizedBox(height: 8),
          for (final l in lines)
            ListTile(
              dense: true,
              title: Text(s.product(l.productId)?.name ?? ''),
              subtitle: Text('موجودی ${fmtQty(s.stock(l.productId))}', style: TextStyle(color: s.stock(l.productId) < l.qty ? Colors.red : null)),
              trailing: Text('${fmtQty(l.qty)} × ${groupDigits(s.avgCost(l.productId))} = ${groupDigits((l.qty * s.avgCost(l.productId)).round())}'),
            ),
          const Divider(),
          Text('بهای مواد: ${groupDigits(m)}    سربار: ${groupDigits(o)}'),
          Text('قیمت تمام شده کل: ${groupDigits(m + o)}    هر واحد: ${qty <= 0 ? '—' : groupDigits(((m + o) / qty).round())}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (short.isNotEmpty) Text('موجودی ${short.length} قلم ماده اولیه برای این مقدار کافی نیست', style: const TextStyle(color: Colors.red)),
        ]),
      );
    }),
  ).whenComplete(q.dispose);
}

// ================================================================ تولید

Future<void> showProductions(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Productions());

class _Productions extends StatefulWidget {
  const _Productions();

  @override
  State<_Productions> createState() => _ProductionsState();
}

class _ProductionsState extends State<_Productions> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = [...s.productions]..sort((a, b) => b.number.compareTo(a.number));
    final sel = list.where((p) => p.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'تولید حرفه ای',
      width: 1080,
      height: 620,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            sakanBtn('تولید جدید', () => showProductionEditor(context), key: 'Ins', icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => showProductionEditor(context, edit: sel), icon: Icons.edit_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف تولید', 'سند تولید ${sel.number} و گردش انبار آن حذف شود؟')) {
                      s.removeProduction(sel.id);
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('فرمول های تولید', () => showFormulas(context), icon: Icons.science_outlined),
            sakanBtn('چاپ', () => printTable(
                  store: s,
                  title: 'گزارش تولید',
                  headers: const ['شماره', 'تاریخ', 'کالا', 'مقدار', 'بهای مواد', 'سربار', 'قیمت تمام شده', 'هر واحد'],
                  rows: [
                    for (final p in list)
                      ['${p.number}', jFormat(p.date), s.product(p.productId)?.name ?? '', fmtQty(p.qty), groupDigits(p.materialCost), groupDigits(p.overhead), groupDigits(p.totalCost), groupDigits(p.unitCost)],
                  ],
                  numeric: const {3, 4, 5, 6, 7},
                  fileName: 'tolid',
                ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('شماره', 70), sakanHead('تاریخ', 95), sakanHead('کالای تولیدی', 0), sakanHead('مقدار', 90), sakanHead('سالن', 120), sakanHead('بهای مواد', 120), sakanHead('سربار', 110), sakanHead('قیمت تمام شده', 130), sakanHead('هر واحد', 110)],
              count: list.length,
              empty: 'سند تولیدی ثبت نشده',
              row: (ctx, i) {
                final p = list[i];
                final on = p.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                return InkWell(
                  onTap: () => setState(() => _sel = p.id),
                  onDoubleTap: () => showProductionEditor(context, edit: p),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text('${p.number}', style: st), 70),
                      sakanCell(Text(jFormat(p.date), style: st), 95),
                      sakanCell(Text(s.product(p.productId)?.name ?? '', style: st), 0, align: Alignment.centerRight),
                      sakanCell(Text(fmtQty(p.qty), style: st), 90),
                      sakanCell(Text(s.halls.where((h) => h.id == p.hallId).firstOrNull?.name ?? '', style: st), 120),
                      sakanCell(Text(groupDigits(p.materialCost), style: st), 120),
                      sakanCell(Text(groupDigits(p.overhead), style: st), 110),
                      sakanCell(Text(groupDigits(p.totalCost), style: st.copyWith(fontWeight: FontWeight.w700)), 130),
                      sakanCell(Text(groupDigits(p.unitCost), style: st), 110),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

Future<void> showProductionEditor(BuildContext context, {Production? edit, ProductionFormula? formula}) =>
    showDialog<void>(context: context, builder: (_) => _ProductionEditor(edit: edit, formula: formula));

class _ProductionEditor extends StatefulWidget {
  final Production? edit;
  final ProductionFormula? formula;
  const _ProductionEditor({this.edit, this.formula});

  @override
  State<_ProductionEditor> createState() => _ProductionEditorState();
}

class _ProductionEditorState extends State<_ProductionEditor> {
  late final AppStore _s = StoreScope.read(context);
  late DateTime _date = widget.edit?.date ?? DateTime.now();
  late String? _formula = widget.edit?.formulaId ?? widget.formula?.id;
  late String? _product = widget.edit?.productId ?? widget.formula?.productId;
  late String? _hall = widget.edit?.hallId ?? widget.formula?.hallId;
  late String? _wh = widget.edit?.warehouseId;
  late String _overAcc = widget.edit?.overheadAcc ?? mAbsorbedOverhead;
  late final _qty = TextEditingController(text: fmtQty(widget.edit?.qty ?? widget.formula?.yieldQty ?? 1));
  late final _overhead = TextEditingController(text: groupDigits(widget.edit?.overhead ?? widget.formula?.overheadFor(widget.formula!.yieldQty) ?? 0));
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late final List<_MatRow> _rows = widget.edit != null
      ? [for (final l in widget.edit!.lines) _MatRow(l.productId, l.qty)]
      : widget.formula != null
          ? [for (final l in widget.formula!.scaled(widget.formula!.yieldQty)) _MatRow(l.productId, l.qty)]
          : [_MatRow()];
  String? _err;

  void _applyFormula() {
    final f = _s.formulas.where((x) => x.id == _formula).firstOrNull;
    if (f == null) return;
    final q = parseQty(_qty.text);
    _product = f.productId;
    _hall = f.hallId;
    _rows
      ..clear()
      ..addAll([for (final l in f.scaled(q)) _MatRow(l.productId, l.qty)]);
    _overhead.text = groupDigits(f.overheadFor(q));
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final mat = _rows.where((r) => r.productId != null).fold<int>(0, (a, r) => a + (parseQty(r.qty.text) * s.avgCost(r.productId!)).round());
    final total = mat + parseMoney(_overhead.text);
    final qty = parseQty(_qty.text);
    return FormDialog(
      title: widget.edit == null ? 'تولید' : 'ویرایش تولید شماره ${widget.edit!.number}',
      width: 820,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final lines = [for (final r in _rows) if (r.productId != null && parseQty(r.qty.text) > 0) ProductionLine(productId: r.productId!, qty: parseQty(r.qty.text))];
            if (_product == null) return setState(() => _err = 'کالای تولیدی را انتخاب کنید');
            if (qty <= 0) return setState(() => _err = 'مقدار تولید را وارد کنید');
            if (lines.isEmpty) return setState(() => _err = 'مواد اولیه را وارد کنید');
            if (lines.any((l) => l.productId == _product)) return setState(() => _err = 'کالای تولیدی نمی‌تواند ماده اولیه خودش باشد');
            if (!s.settings.saleOptions.allowNegative) {
              for (final l in lines) {
                final have = s.stock(l.productId) + (widget.edit?.lines.where((x) => x.productId == l.productId).fold<double>(0, (a, x) => a + x.qty) ?? 0);
                if (have < l.qty - 1e-9) return setState(() => _err = 'موجودی ${s.product(l.productId)?.name} کافی نیست (${fmtQty(have)})');
              }
            }
            s.saveProduction(Production(
              id: widget.edit?.id ?? newId(),
              number: widget.edit?.number ?? s.nextProductionNumber(),
              date: _date,
              productId: _product!,
              qty: qty,
              formulaId: _formula,
              hallId: _hall,
              warehouseId: _wh,
              lines: lines,
              overhead: parseMoney(_overhead.text),
              overheadAcc: _overAcc,
              note: _note.text.trim(),
              createdAt: widget.edit?.createdAt,
            ));
            Navigator.pop(context);
            toast(context, 'تولید ثبت شد — قیمت تمام شده هر واحد ${groupDigits(qty <= 0 ? 0 : (total / qty).round())}');
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 180, child: DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _formula,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'فرمول تولید'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('بدون فرمول')), for (final f in s.formulas) DropdownMenuItem<String?>(value: f.id, child: Text(f.name))],
              onChanged: (v) => setState(() {
                _formula = v;
                _applyFormula();
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _hall,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'سالن تولید'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('—')), for (final h in s.halls) DropdownMenuItem<String?>(value: h.id, child: Text(h.name))],
              onChanged: (v) => setState(() => _hall = v),
            ),
          ),
          if (s.warehouses.length > 1) ...[
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _wh,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'انبار'),
                items: [for (final w in s.warehousesFor(_wh)) DropdownMenuItem<String?>(value: w.id, child: Text(w.name))],
                onChanged: (v) => setState(() => _wh = v),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              value: _product,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'کالای تولیدی'),
              items: [for (final p in s.productsSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => _product = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _qty,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'مقدار تولید'),
              onChanged: (_) => setState(() {
                if (_formula != null && widget.edit == null) _applyFormula();
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _overhead,
              textDirection: TextDirection.ltr,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(labelText: 'سربار'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _overAcc,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'حساب سربار (بستانکار)'),
          items: [for (final m in allMoeens) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _overAcc = v ?? _overAcc),
        ),
        const SizedBox(height: 10),
        _materials(context, s, _rows, () => setState(() {})),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'توضیحات')),
        const SizedBox(height: 8),
        Text('بهای مواد ${groupDigits(mat)} + سربار ${groupDigits(parseMoney(_overhead.text))} = ${groupDigits(total)} — هر واحد ${qty <= 0 ? '—' : groupDigits((total / qty).round())}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
