import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'voucher_dialog.dart' show tafsiliOptions;

// ================================================================ account picker

List<Moeen> get _allMoeens => [for (final k in chart) ...k.moeens];

/// Moeen + optional tafsili chooser (عنوان حساب).
class AccountPicker extends StatelessWidget {
  final String label;
  final String? moeen;
  final String? tafsili;
  final List<Moeen>? moeens;
  final void Function(String? moeen, String? tafsili) onChanged;
  const AccountPicker({super.key, required this.label, required this.moeen, required this.tafsili, required this.onChanged, this.moeens});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = moeens ?? _allMoeens;
    final m = findMoeen(moeen);
    final opts = m == null ? const <(String, String)>[] : tafsiliOptions(s, m);
    return Row(children: [
      Expanded(
        flex: 3,
        child: FieldDropdown<String?>(
          label: label,
          value: moeen,
          items: [for (final x in list) DropdownMenuItem<String?>(value: x.code, child: Text('${x.code} — ${x.name}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => onChanged(v, null),
        ),
      ),
      if (m != null && m.hasEntity) ...[
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FieldDropdown<String?>(
            label: 'تفصیلی',
            value: tafsili,
            items: [for (final o in opts) DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => onChanged(moeen, v),
          ),
        ),
      ],
    ]);
  }
}

// ================================================================ تقسیم سود و زیان

class _SplitRow {
  String? moeen;
  String? tafsili;
  final pct = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  _SplitRow({this.moeen});

  void dispose() {
    for (final c in [pct, amount, note]) {
      c.dispose();
    }
  }
}

/// [shareholders] = «تقسیم سود و زیان صاحبان سهام», otherwise «سال مالی».
Future<void> showProfitSplitDialog(BuildContext context, {bool shareholders = false}) =>
    showDialog<void>(context: context, builder: (_) => _SplitDialog(shareholders: shareholders));

class _SplitDialog extends StatefulWidget {
  final bool shareholders;
  const _SplitDialog({required this.shareholders});

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  late final TextEditingController _number;
  final _total = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _date;
  String? _src = mRetained;
  String? _srcTaf;
  String _partnersMoeen = mPartners;
  bool _byPercent = true;
  final List<_SplitRow> _rows = [];
  String? _err;

  bool get sh => widget.shareholders;

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    _number = TextEditingController(text: '${s.nextVoucherNumber()}');
    final n = DateTime.now();
    _date = DateTime(n.year, n.month, n.day);
    final def = sh ? s.ledgerBalance(mRetained) : s.profit(Jalali(Jalali.now().year, 1, 1).toDateTime(), n).netProfit;
    if (def > 0) _total.text = groupDigits(def);
    _total.addListener(_refresh);
    _addRow();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_number, _total, _desc]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final r = _SplitRow(moeen: sh ? null : mRetained);
    r.pct.addListener(_refresh);
    r.amount.addListener(_refresh);
    setState(() => _rows.add(r));
  }

  int get _totalV => parseMoney(_total.text);

  double _pctOf(_SplitRow r) => double.tryParse(normalizeDigits(r.pct.text.trim()).replaceAll('٫', '.')) ?? 0;

  int _amountOf(_SplitRow r) => _byPercent ? (_totalV * _pctOf(r) / 100).round() : parseMoney(r.amount.text);

  void _save() {
    final s = StoreScope.read(context);
    final rows = _rows.where((r) => _amountOf(r) != 0).toList();
    final sum = rows.fold<int>(0, (a, r) => a + _amountOf(r));
    String? err;
    if (_src == null) {
      err = 'عنوان حساب ${sh ? 'سود قابل تقسیم' : 'مبدا'} را انتخاب کنید';
    } else if (findMoeen(_src)!.hasEntity && _srcTaf == null) {
      err = 'تفصیلی حساب مبدا را انتخاب کنید';
    } else if (_totalV <= 0) {
      err = 'مبلغ قابل تقسیم را وارد کنید';
    } else if (rows.isEmpty) {
      err = 'حداقل یک ردیف با مبلغ وارد کنید';
    } else if (rows.any((r) => sh ? r.tafsili == null : (r.moeen == null || (findMoeen(r.moeen)!.hasEntity && r.tafsili == null)))) {
      err = sh ? 'صاحب سهم هر ردیف را انتخاب کنید' : 'عنوان حساب هر ردیف را کامل انتخاب کنید';
    } else if (sum > _totalV) {
      err = 'جمع ردیف‌ها (${groupDigits(sum)}) از مبلغ قابل تقسیم بیشتر است';
    } else if (rows.any((r) => !sh && r.moeen == _src && (r.tafsili ?? '') == (_srcTaf ?? ''))) {
      err = 'حساب مقصد نباید با حساب مبدا یکی باشد';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    final title = sh ? 'تقسیم سود و زیان صاحبان سهام' : 'تقسیم سود و زیان سال مالی';
    final desc = _desc.text.trim().isEmpty ? title : _desc.text.trim();
    final lines = <VoucherLine>[
      VoucherLine(moeen: _src!, tafsiliId: _srcTaf, desc: desc, debit: sum),
      for (final r in rows)
        VoucherLine(
          moeen: sh ? _partnersMoeen : r.moeen!,
          tafsiliId: r.tafsili,
          desc: r.note.text.trim().isEmpty ? '$desc${_byPercent ? ' (${fmtPct(_pctOf(r))}٪)' : ''}' : r.note.text.trim(),
          credit: _amountOf(r),
        ),
    ];
    final v = Voucher(
      id: newId(),
      number: int.tryParse(normalizeDigits(_number.text.trim())) ?? s.nextVoucherNumber(),
      fixedNumber: s.nextFixedNumber(),
      date: _date,
      desc: desc,
      lines: lines,
      kind: sh ? 'shareSplit' : 'profitSplit',
    );
    s.saveVoucher(v);
    Navigator.pop(context);
    toast(context, '$title — سند ${v.number} ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final sumPct = _rows.fold<double>(0, (a, r) => a + (_byPercent ? _pctOf(r) : (_totalV == 0 ? 0 : _amountOf(r) * 100 / _totalV)));
    final sumAmt = _rows.fold<int>(0, (a, r) => a + _amountOf(r));
    final size = MediaQuery.of(context).size;
    final partnerMoeens = chart.firstWhere((k) => k.code == '301').moeens.where((m) => m.kind == TafsiliKind.person).toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.insert): _addRow,
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1000,
          height: (size.height * 0.9).clamp(440.0, 780.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HeaderBand(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              child: Row(children: [
                Icon(sh ? Icons.groups_2_outlined : Icons.pie_chart_outline_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(sh ? 'تقسیم سود و زیان صاحبان سهام' : 'تقسیم سود و زیان سال مالی',
                      style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  SizedBox(
                    width: 130,
                    child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند')),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 170, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح سند'))),
                ]),
                const SizedBox(height: 8),
                AccountPicker(
                  label: sh ? 'عنوان حساب سود قابل تقسیم' : 'عنوان حساب (خلاصه حساب سود و زیان)',
                  moeen: _src,
                  tafsili: _srcTaf,
                  onChanged: (m, t) => setState(() {
                    _src = m;
                    _srcTaf = t;
                  }),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: MoneyField(controller: _total, label: 'مبلغ')),
                  const SizedBox(width: 16),
                  Radio<bool>(value: true, groupValue: _byPercent, onChanged: (v) => setState(() => _byPercent = v ?? true)),
                  const Text('تعیین درصدی'),
                  const SizedBox(width: 10),
                  Radio<bool>(value: false, groupValue: _byPercent, onChanged: (v) => setState(() => _byPercent = v ?? true)),
                  const Text('تعیین مبلغی'),
                ]),
                if (sh) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Expanded(
                      child: InputDecorator(decoration: InputDecoration(labelText: 'عنوان کل صاحبان سهام'), child: Text('301 — حقوق صاحبان سهام')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FieldDropdown<String>(
                        label: 'عنوان معین صاحبان سهام',
                        value: _partnersMoeen,
                        items: [for (final m in partnerMoeens) DropdownMenuItem(value: m.code, child: Text('${m.code} — ${m.name}'))],
                        onChanged: (v) => setState(() => _partnersMoeen = v ?? _partnersMoeen),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      color: Brand.of(context).accent.withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: DefaultTextStyle(
                        style: th.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w800, color: th.colorScheme.onSurface),
                        child: Row(children: [
                          const SizedBox(width: 44, child: Text('ردیف')),
                          Expanded(flex: 4, child: Text(sh ? 'صاحب سهم' : 'عنوان حساب')),
                          const SizedBox(width: 90, child: Text('درصد', textAlign: TextAlign.center)),
                          const SizedBox(width: 150, child: Text('مبلغ', textAlign: TextAlign.center)),
                          const Expanded(flex: 2, child: Text('توضیحات')),
                          const SizedBox(width: 40),
                        ]),
                      ),
                    ),
                    Expanded(
                      child: ListView(children: [
                        for (var i = 0; i < _rows.length; i++) _row(s, th, i),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add_rounded), label: const Text('افزودن (Insert)')),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Row(children: [
                Text('جمع درصد: ${fmtPct(sumPct)}٪', style: TextStyle(fontWeight: FontWeight.w800, color: sumPct > 100.001 ? th.colorScheme.error : null)),
                const SizedBox(width: 18),
                const Text('جمع مبلغ: '),
                Money(sumAmt, style: TextStyle(fontWeight: FontWeight.w800, color: sumAmt > _totalV ? th.colorScheme.error : AppColors.income)),
                const SizedBox(width: 12),
                if (_err != null) Expanded(child: Text(_err!, style: TextStyle(color: th.colorScheme.error))) else const Spacer(),
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(AppStore s, ThemeData th, int i) {
    final r = _rows[i];
    final m = findMoeen(r.moeen);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(children: [
        SizedBox(width: 44, child: Text('${i + 1}')),
        Expanded(
          flex: 4,
          child: sh
              ? DropdownButtonFormField<String>(
                  value: r.tafsili,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, hintText: 'انتخاب شخص'),
                  items: [for (final p in s.peopleSorted) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => r.tafsili = v),
                )
              : Row(children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: r.moeen,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        for (final x in _allMoeens) DropdownMenuItem(value: x.code, child: Text('${x.code} — ${x.name}', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() {
                        r.moeen = v;
                        r.tafsili = null;
                      }),
                    ),
                  ),
                  if (m != null && m.hasEntity) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: r.tafsili,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true, hintText: 'تفصیلی'),
                        items: [
                          for (final o in tafsiliOptions(s, m)) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => r.tafsili = v),
                      ),
                    ),
                  ],
                ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 82,
          child: _byPercent
              ? TextField(
                  controller: r.pct,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(isDense: true, suffixText: '٪'),
                )
              : Center(child: Text(_totalV == 0 ? '—' : '${fmtPct(_amountOf(r) * 100 / _totalV)}٪')),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          child: _byPercent
              ? Center(child: Money(_amountOf(r), style: const TextStyle(fontWeight: FontWeight.w700)))
              : TextField(
                  controller: r.amount,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(isDense: true),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: TextField(controller: r.note, decoration: const InputDecoration(isDense: true))),
        SizedBox(
          width: 40,
          child: IconButton(
            tooltip: 'حذف ردیف',
            onPressed: _rows.length == 1 ? null : () => setState(() => _rows.removeAt(i).dispose()),
            icon: Icon(Icons.remove_circle_outline, size: 20, color: th.colorScheme.error),
          ),
        ),
      ]),
    );
  }
}

String fmtPct(double v) {
  final r = (v * 100).round() / 100;
  return r == r.roundToDouble() ? '${r.toInt()}' : r.toStringAsFixed(2);
}

// ================================================================ مرکز اسناد

Future<void> showDocCentersDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Centers());

class _Centers extends StatefulWidget {
  const _Centers();

  @override
  State<_Centers> createState() => _CentersState();
}

class _CentersState extends State<_Centers> {
  String? _sel;

  Future<void> _edit({String? old}) async {
    final c = TextEditingController(text: old ?? '');
    final s = StoreScope.read(context);
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: old == null ? 'افزودن مرکز اسناد' : 'ویرایش مرکز اسناد',
          width: 440,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                final e = s.saveCenter(c.text, old: old);
                if (e != null) return set(() => err = e);
                Navigator.pop(ctx);
                setState(() => _sel = c.text.trim());
              },
              child: const Text('تایید'),
            ),
          ],
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(labelText: 'نام مرکز اسناد', errorText: err),
          ),
        ),
      ),
    );
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context)},
      child: FormDialog(
        title: 'مراکز اسناد',
        width: 520,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.tonalIcon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('افزودن')),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: () {
              if (_sel == null) return toast(context, 'مرکز اسناد را انتخاب کنید', error: true);
              final e = s.removeCenter(_sel!);
              if (e != null) return toast(context, e, error: true);
              setState(() => _sel = null);
            },
            child: const Text('حذف'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: () {
              if (_sel == null) return toast(context, 'مرکز اسناد را انتخاب کنید', error: true);
              _edit(old: _sel);
            },
            child: const Text('ویرایش'),
          ),
        ]),
        actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: Brand.of(context).accent.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text('نام مرکز اسناد', style: th.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          for (final c in s.docCenters)
            Material(
              color: c == _sel ? th.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _sel = c),
                onDoubleTap: () => _edit(old: c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    Expanded(child: Text(c, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${s.vouchers.where((v) => v.center == c).length} سند', style: th.textTheme.labelSmall),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
