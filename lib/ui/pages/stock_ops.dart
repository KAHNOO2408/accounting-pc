import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/invoice_editor.dart' show fmtQty, parseQty;
import '../theme.dart';
import '../widgets/common.dart';

// ======================================================= waste / consumption

Future<void> showWasteDialog(BuildContext context, {AdjustReason reason = AdjustReason.waste}) =>
    showDialog<void>(context: context, builder: (_) => _WasteDialog(reason: reason));

class _WasteDialog extends StatefulWidget {
  final AdjustReason reason;
  const _WasteDialog({required this.reason});

  @override
  State<_WasteDialog> createState() => _WasteDialogState();
}

class _WasteDialogState extends State<_WasteDialog> {
  late AdjustReason _reason = widget.reason;
  String? _product;
  String? _wh;
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  DateTime _date = dateOnly(DateTime.now());
  String? _err;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final q = parseQty(_qty.text);
    if (_product == null) {
      setState(() => _err = 'کالا را انتخاب کنید');
      return;
    }
    if (q <= 0) {
      setState(() => _err = 'مقدار معتبر نیست');
      return;
    }
    StoreScope.read(context).addAdjusts([
      StockAdjust(id: newId(), date: _date, productId: _product!, qty: -q, reason: _reason, note: _note.text.trim(), warehouseId: _wh),
    ]);
    Navigator.pop(context);
    toast(context, '${_reason.label} ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final p = store.product(_product);
    return FormDialog(
      title: 'ضایعات یا مصرف کالا',
      width: 520,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ثبت')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AdjustReason>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: AdjustReason.waste, label: Text('ضایعات / خرابی')),
              ButtonSegment(value: AdjustReason.consume, label: Text('مصرف داخلی')),
            ],
            selected: {_reason},
            onSelectionChanged: (s) => setState(() => _reason = s.first),
          ),
          if (store.warehouses.length > 1) ...[
            const SizedBox(height: 16),
            FieldDropdown<String>(
              label: 'انبار',
              value: store.whId(_wh),
              items: [for (final w in store.warehouses) DropdownMenuItem(value: w.id, child: Text(w.name))],
              onChanged: (v) => setState(() => _wh = v),
            ),
          ],
          const SizedBox(height: 16),
          FieldDropdown<String?>(
            label: 'کالا',
            value: _product,
            items: [
              for (final x in store.productsSorted.where((x) => !x.archived))
                DropdownMenuItem<String?>(
                  value: x.id,
                  child: Row(children: [
                    Expanded(child: Text(x.name, overflow: TextOverflow.ellipsis)),
                    Text('موجودی ${fmtQty(store.stock(x.id, warehouseId: store.warehouses.length > 1 ? store.whId(_wh) : null))}',
                        style: th.textTheme.labelSmall),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _product = v),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'مقدار', suffixText: p?.unit),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
            ],
          ),
          const SizedBox(height: 14),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'شرح (مثلاً: شکستگی هنگام حمل)')),
          if (p != null) ...[
            const SizedBox(height: 10),
            Text('ارزش تقریبی: ${groupDigits((parseQty(_qty.text) * store.avgCost(p.id)).round())} — در سود و زیان به‌عنوان هزینه منظور می‌شود',
                style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
          ],
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

// ================================================================== convert

Future<void> showConvertDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ConvertDialog());

class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog();

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  String? _from;
  String? _to;
  final _qOut = TextEditingController(text: '1');
  final _qIn = TextEditingController(text: '1');
  final _note = TextEditingController();
  DateTime _date = dateOnly(DateTime.now());
  String? _err;

  @override
  void dispose() {
    _qOut.dispose();
    _qIn.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final a = parseQty(_qOut.text);
    final b = parseQty(_qIn.text);
    if (_from == null || _to == null || _from == _to) {
      setState(() => _err = 'کالای مبدا و مقصد را درست انتخاب کنید');
      return;
    }
    if (a <= 0 || b <= 0) {
      setState(() => _err = 'مقادیر معتبر نیستند');
      return;
    }
    final g = newId();
    StoreScope.read(context).addAdjusts([
      StockAdjust(id: newId(), date: _date, productId: _from!, qty: -a, reason: AdjustReason.convertOut, groupId: g, note: _note.text.trim()),
      StockAdjust(id: newId(), date: _date, productId: _to!, qty: b, reason: AdjustReason.convertIn, groupId: g, note: _note.text.trim()),
    ]);
    Navigator.pop(context);
    toast(context, 'تبدیل کالا ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final items = [
      for (final x in store.productsSorted.where((x) => !x.archived))
        DropdownMenuItem<String?>(value: x.id, child: Text('${x.name}  (${fmtQty(store.stock(x.id))} ${x.unit})')),
    ];
    return FormDialog(
      title: 'تبدیل کالا',
      width: 560,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ثبت تبدیل')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('مثلاً یک کارتن ۲۰تایی را به ۲۰ عدد تکی تبدیل کنید.', style: th.textTheme.bodySmall),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(flex: 3, child: FieldDropdown<String?>(label: 'از کالا', value: _from, items: items, onChanged: (v) => setState(() => _from = v))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _qOut, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مقدار خروج'))),
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Icon(Icons.arrow_downward_rounded),
          ),
          Row(children: [
            Expanded(flex: 3, child: FieldDropdown<String?>(label: 'به کالا', value: _to, items: items, onChanged: (v) => setState(() => _to = v))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _qIn, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مقدار ورود'))),
          ]),
          const SizedBox(height: 14),
          DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
          const SizedBox(height: 14),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'شرح')),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

// =============================================================== stock count

class StockCountPage extends StatefulWidget {
  const StockCountPage({super.key});

  @override
  State<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends State<StockCountPage> {
  final Map<String, TextEditingController> _ctrl = {};
  DateTime _date = dateOnly(DateTime.now());
  String _q = '';

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String id, double sys) =>
      _ctrl.putIfAbsent(id, () => TextEditingController(text: fmtQty(sys))..addListener(() => setState(() {})));

  Future<void> _apply(AppStore store) async {
    final counted = <String, double>{};
    _ctrl.forEach((id, c) {
      if (c.text.trim().isEmpty) return;
      counted[id] = parseQty(c.text);
    });
    final changes = counted.entries.where((e) => (e.value - store.stock(e.key)).abs() > 1e-9).length;
    if (changes == 0) {
      toast(context, 'مغایرتی برای ثبت وجود ندارد');
      return;
    }
    final ok = await confirm(context, 'ثبت انبارگردانی', 'برای $changes کالا سند اصلاح موجودی ثبت شود؟', ok: 'ثبت', danger: false);
    if (!ok || !mounted) return;
    final n = store.applyCount(counted, _date);
    for (final c in _ctrl.values) {
      c.dispose();
    }
    setState(_ctrl.clear);
    if (mounted) toast(context, 'انبارگردانی ثبت شد ($n کالا اصلاح شد)');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final list = store.productsSorted
        .where((p) => !p.archived && (q.isEmpty || p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q)))
        .toList();
    var diffs = 0;
    var diffValue = 0;
    for (final p in store.products) {
      final c = _ctrl[p.id];
      if (c == null) continue;
      final d = parseQty(c.text) - store.stock(p.id);
      if (d.abs() > 1e-9) {
        diffs++;
        diffValue += (d * store.avgCost(p.id)).round();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'انبارگردانی',
          subtitle: 'موجودی شمارش‌شده را وارد کنید؛ اختلاف‌ها به‌صورت سند اصلاح موجودی ثبت می‌شوند',
          actions: [
            SizedBox(width: 230, child: DateField(label: 'تاریخ انبارگردانی', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
            FilledButton.icon(
              onPressed: () => _apply(store),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('ثبت مغایرت‌ها'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Row(
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  decoration: const InputDecoration(hintText: 'جستجوی کالا', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const Spacer(),
              Text('$diffs مغایرت · ارزش خالص: ', style: th.textTheme.bodySmall),
              Money(diffValue, showUnit: true, colorBySign: true, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: th.colorScheme.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: DefaultTextStyle(
                      style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
                      child: const Row(children: [
                        Expanded(child: Text('کالا')),
                        SizedBox(width: 120, child: Text('موجودی سیستم', textAlign: TextAlign.center)),
                        SizedBox(width: 140, child: Text('شمارش‌شده', textAlign: TextAlign.center)),
                        SizedBox(width: 120, child: Text('اختلاف', textAlign: TextAlign.center)),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(icon: Icons.inventory_2_outlined, text: 'کالایی وجود ندارد')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final p = list[i];
                              final sys = store.stock(p.id);
                              final c = _c(p.id, sys);
                              final d = parseQty(c.text) - sys;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                                child: Row(children: [
                                  Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                                  SizedBox(width: 120, child: Text('${fmtQty(sys)} ${p.unit}', textAlign: TextAlign.center)),
                                  SizedBox(
                                    width: 140,
                                    child: TextField(
                                      controller: c,
                                      textAlign: TextAlign.center,
                                      textDirection: TextDirection.ltr,
                                      decoration: const InputDecoration(
                                          isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      d.abs() < 1e-9 ? '—' : '${d > 0 ? '+' : '−'}${fmtQty(d.abs())}',
                                      textAlign: TextAlign.center,
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: d.abs() < 1e-9 ? th.hintColor : (d > 0 ? AppColors.income : AppColors.expense),
                                      ),
                                    ),
                                  ),
                                ]),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
