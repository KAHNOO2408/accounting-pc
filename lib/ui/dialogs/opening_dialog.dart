import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;
import 'misc_dialogs.dart';

/// Entry point used by the ribbon: offers a backup first, like Sakan.
Future<void> openOpeningVoucher(BuildContext context) async {
  final backup = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: AppColors.loan, size: 36),
      title: const Text('اخطار'),
      content: const Text(
        'اکیداً قبل از انجام تغییرات در سند افتتاحیه از سیستم پشتیبان تهیه نمایید.\nآیا مایل به انجام پشتیبان‌گیری هستید؟',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله')),
      ],
    ),
  );
  if (backup == null || !context.mounted) return;
  if (backup) quickBackup(context);
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const OpeningDialog());
}

class _Grp {
  final String title;
  final List<String> moeens;
  const _Grp(this.title, this.moeens);
}

List<_Grp> _groupsOf(Side side) => [
      for (final k in chart.where((k) => k.side == side)) _Grp(k.name, [for (final m in k.ledgers) m.code]),
    ];

class OpeningDialog extends StatefulWidget {
  const OpeningDialog({super.key});

  @override
  State<OpeningDialog> createState() => OpeningState();
}

class OpeningState extends State<OpeningDialog> {
  final Map<String, int> acc = {};
  final Map<String, int> per = {};
  final Map<String, double> qty = {};
  final Map<String, int> cost = {};
  final Map<String, int> other = {};
  late DateTime date;
  bool updateBuy = false;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    for (final a in s.accounts) {
      acc[a.id] = a.opening;
    }
    for (final p in s.people) {
      per[p.id] = p.opening;
    }
    for (final p in s.products) {
      qty[p.id] = p.openingQty;
      cost[p.id] = s.openingCost(p);
    }
    other.addAll(s.settings.openingOther);
    date = s.settings.openingDate ?? Jalali(Jalali.now().year, 1, 1).toDateTime();
  }

  AppStore get store => StoreScope.read(context);

  bool isCashAccount(Account a) => a.type == AccountType.cash;

  /// Value of a ledger (on its natural side).
  int moeenValue(String code) {
    switch (code) {
      case mCash:
        return store.accounts.where(isCashAccount).fold(0, (s, a) => s + (acc[a.id] ?? 0));
      case mBank:
        return store.accounts.where((a) => !isCashAccount(a)).fold(0, (s, a) => s + (acc[a.id] ?? 0));
      case mStock:
        return store.products.fold(0, (s, p) => s + ((qty[p.id] ?? 0) * (cost[p.id] ?? 0)).round());
      case mDebtorsTrade:
        return per.values.where((v) => v > 0).fold(0, (s, v) => s + v);
      case mCreditorsTrade:
        return per.values.where((v) => v < 0).fold(0, (s, v) => s - v);
      default:
        return other[code] ?? 0;
    }
  }

  int groupValue(_Grp g) => g.moeens.fold(0, (s, c) => s + moeenValue(c));

  int get totalAssets => _groupsOf(Side.asset).fold(0, (s, g) => s + groupValue(g));
  int get totalLiabilities => _groupsOf(Side.liability).fold(0, (s, g) => s + groupValue(g));

  /// Capital balances the voucher.
  int get capital => totalAssets - totalLiabilities;

  Map<String, Object> snapshot() => {
        'acc': Map.of(acc),
        'per': Map.of(per),
        'qty': Map.of(qty),
        'cost': Map.of(cost),
        'other': Map.of(other),
      };

  void restore(Map<String, Object> s) {
    setState(() {
      acc
        ..clear()
        ..addAll(s['acc'] as Map<String, int>);
      per
        ..clear()
        ..addAll(s['per'] as Map<String, int>);
      qty
        ..clear()
        ..addAll(s['qty'] as Map<String, double>);
      cost
        ..clear()
        ..addAll(s['cost'] as Map<String, int>);
      other
        ..clear()
        ..addAll(s['other'] as Map<String, int>);
    });
  }

  void refresh() => setState(() {});

  void _confirm() {
    store.applyOpening(
      date: date,
      accountOpenings: acc,
      personOpenings: per,
      productQty: qty,
      productCost: cost,
      other: other,
      updateBuyPrice: updateBuy,
    );
    Navigator.pop(context);
    toast(context, 'سند افتتاحیه ثبت شد');
  }

  Future<void> _openGroup(_Grp g, Side side) async {
    if (side == Side.equity) {
      toast(context, 'سرمایه به‌صورت خودکار برابر «جمع دارایی‌ها − جمع بدهی‌ها» محاسبه می‌شود');
      return;
    }
    final snap = snapshot();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupDialog(owner: this, group: g, side: side),
    );
    if (ok != true) restore(snap);
    refresh();
  }

  List<(String, String, int, int)> previewLines() {
    final s = store;
    final out = <(String, String, int, int)>[];
    void add(String code, String detail, int v, bool debitSide) {
      if (v == 0) return;
      final m = findMoeen(code)!;
      final onDebit = debitSide == (v > 0);
      final abs = v.abs();
      out.add(('${m.kol.name} / ${m.name}', detail, onDebit ? abs : 0, onDebit ? 0 : abs));
    }

    for (final a in s.accounts) {
      add(isCashAccount(a) ? mCash : mBank, a.name, acc[a.id] ?? 0, true);
    }
    for (final p in s.products) {
      add(mStock, '${p.name} (${fmtQty(qty[p.id] ?? 0)})', ((qty[p.id] ?? 0) * (cost[p.id] ?? 0)).round(), true);
    }
    for (final p in s.people) {
      final v = per[p.id] ?? 0;
      if (v > 0) add(mDebtorsTrade, p.name, v, true);
      if (v < 0) add(mCreditorsTrade, p.name, -v, false);
    }
    other.forEach((code, v) {
      final m = findMoeen(code);
      if (m == null) return;
      add(code, '', v, m.debitNature);
    });
    add(mCapital, '', capital, false);
    return out;
  }

  Future<void> _preview() => showDialog<void>(
        context: context,
        builder: (ctx) {
          final th = Theme.of(ctx);
          final lines = previewLines();
          final dr = lines.fold<int>(0, (s, l) => s + l.$3);
          final cr = lines.fold<int>(0, (s, l) => s + l.$4);
          return FormDialog(
            title: 'مشاهده سند افتتاحیه — ${Jalali.fromDateTime(date).format()}',
            width: 860,
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: th.colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.all(10),
                  child: const Row(children: [
                    SizedBox(width: 40, child: Text('ردیف')),
                    Expanded(flex: 3, child: Text('کل / معین')),
                    Expanded(flex: 2, child: Text('تفصیلی')),
                    SizedBox(width: 140, child: Text('بدهکار', textAlign: TextAlign.left)),
                    SizedBox(width: 140, child: Text('بستانکار', textAlign: TextAlign.left)),
                  ]),
                ),
                for (var i = 0; i < lines.length; i++)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant))),
                    child: Row(children: [
                      SizedBox(width: 40, child: Text('${i + 1}')),
                      Expanded(flex: 3, child: Text(lines[i].$1)),
                      Expanded(flex: 2, child: Text(lines[i].$2)),
                      SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: lines[i].$3 == 0 ? const SizedBox() : Money(lines[i].$3))),
                      SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: lines[i].$4 == 0 ? const SizedBox() : Money(lines[i].$4))),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Expanded(child: Text('جمع', style: TextStyle(fontWeight: FontWeight.w800))),
                    SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: Money(dr, style: const TextStyle(fontWeight: FontWeight.w800)))),
                    SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: Money(cr, style: const TextStyle(fontWeight: FontWeight.w800)))),
                  ]),
                ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    StoreScope.of(context);
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _confirm,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f1): _preview,
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: size.width > 1100 ? 1060 : size.width - 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(children: [
                  Text('سند افتتاحیه', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _side(
                          'دارایی ها',
                          AppColors.income,
                          [for (final g in _groupsOf(Side.asset)) (g, Side.asset)],
                          'جمع دارایی ها',
                          totalAssets,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _side(
                          'بدهی ها + سرمایه',
                          AppColors.expense,
                          [
                            for (final g in _groupsOf(Side.liability)) (g, Side.liability),
                            (const _Grp('حقوق صاحبان سهام', [mCapital]), Side.equity),
                          ],
                          'جمع بدهی ها',
                          totalLiabilities + capital,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: Row(children: [
                  SizedBox(
                    width: 250,
                    child: DateField(label: 'تاریخ سند افتتاحیه', value: date, onChanged: (d) => setState(() => date = d ?? date)),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _preview,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('مشاهده سند (F1)'),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: updateBuy,
                      onChanged: (v) => setState(() => updateBuy = v ?? false),
                      title: const Text('بروزرسانی آخرین فی خرید انجام شود؟'),
                    ),
                  ),
                  FilledButton(onPressed: _confirm, child: const Text('تایید (F9)')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _side(String title, Color color, List<(_Grp, Side)> groups, String totalLabel, int total) {
    final th = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: th.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 12),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OpeningRow(
                label: g.$1.title,
                value: g.$2 == Side.equity ? capital : groupValue(g.$1),
                color: color,
                drill: g.$2 != Side.equity,
                onTap: () => _openGroup(g.$1, g.$2),
              ),
            ),
          const Divider(height: 18),
          _OpeningRow(label: totalLabel, value: total, color: color, strong: true),
        ],
      ),
    );
  }
}

class _OpeningRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool drill;
  final bool strong;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _OpeningRow({
    required this.label,
    required this.value,
    required this.color,
    this.drill = false,
    this.strong = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Row(children: [
      Expanded(
        flex: 5,
        child: Material(
          color: strong ? color.withValues(alpha: 0.12) : th.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Expanded(
                  child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
                ),
                if (drill) Icon(Icons.keyboard_arrow_left_rounded, size: 18, color: th.hintColor),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 4,
        child: trailing ??
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: strong ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Money(value, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w700)),
              ),
            ),
      ),
    ]);
  }
}

// =========================================================== group popup

class _GroupDialog extends StatefulWidget {
  final OpeningState owner;
  final _Grp group;
  final Side side;
  const _GroupDialog({required this.owner, required this.group, required this.side});

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final Map<String, TextEditingController> _free = {};

  OpeningState get o => widget.owner;

  bool _isEntity(String code) => code == mCash || code == mBank || code == mStock || code == mDebtorsTrade || code == mCreditorsTrade;

  @override
  void initState() {
    super.initState();
    for (final c in widget.group.moeens) {
      if (!_isEntity(c)) {
        final v = o.other[c] ?? 0;
        _free[c] = TextEditingController(text: v == 0 ? '' : groupDigits(v))
          ..addListener(() {
            o.other[c] = parseMoney(_free[c]!.text);
            setState(() {});
          });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _free.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openEntity(String code) async {
    final snap = o.snapshot();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EntityDialog(owner: o, moeen: code),
    );
    if (ok != true) o.restore(snap);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final color = widget.side == Side.asset ? AppColors.income : AppColors.expense;
    final total = widget.group.moeens.fold<int>(0, (s, c) => s + o.moeenValue(c));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => Navigator.pop(context, true),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context, false),
      },
      child: FormDialog(
        title: 'لیست دفاتر موجود در گروه ${widget.group.title}',
        width: 600,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تایید (F9)')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in widget.group.moeens)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OpeningRow(
                  label: findMoeen(c)!.name,
                  value: o.moeenValue(c),
                  color: color,
                  drill: _isEntity(c),
                  onTap: _isEntity(c) ? () => _openEntity(c) : null,
                  trailing: _isEntity(c)
                      ? null
                      : TextField(
                          controller: _free[c],
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          inputFormatters: [MoneyInputFormatter()],
                          decoration: InputDecoration(
                            hintText: '0',
                            filled: true,
                            fillColor: color.withValues(alpha: 0.08),
                          ),
                        ),
                ),
              ),
            const Divider(height: 18),
            _OpeningRow(label: 'جمع ${widget.group.title}', value: total, color: color, strong: true),
            const SizedBox(height: 8),
            Text(
              'دفاتری که فلش دارند با کلیک باز می‌شوند (صندوق‌ها، بانک‌ها، کالاها، اشخاص). بقیه را مستقیم وارد کنید.',
              style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ entity grid

class _EntityDialog extends StatefulWidget {
  final OpeningState owner;
  final String moeen;
  const _EntityDialog({required this.owner, required this.moeen});

  @override
  State<_EntityDialog> createState() => _EntityDialogState();
}

class _EntityDialogState extends State<_EntityDialog> {
  final Map<String, TextEditingController> _amount = {};
  final Map<String, TextEditingController> _qty = {};
  String _q = '';

  OpeningState get o => widget.owner;
  bool get _isStock => widget.moeen == mStock;

  @override
  void dispose() {
    for (final c in [..._amount.values, ..._qty.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<(String, String, String)> _rows(AppStore s) => switch (widget.moeen) {
        mCash => [for (final a in s.accounts.where((a) => a.type == AccountType.cash)) (a.id, a.name, a.type.label)],
        mBank => [for (final a in s.accounts.where((a) => a.type != AccountType.cash)) (a.id, a.name, a.bank.isEmpty ? a.type.label : a.bank)],
        mStock => [for (final p in s.productsSorted) (p.id, p.name, p.code)],
        _ => [for (final p in s.peopleSorted) (p.id, p.name, p.phone)],
      };

  int _get(String id) => switch (widget.moeen) {
        mCash || mBank => o.acc[id] ?? 0,
        mStock => o.cost[id] ?? 0,
        mDebtorsTrade => (o.per[id] ?? 0) > 0 ? o.per[id]! : 0,
        _ => (o.per[id] ?? 0) < 0 ? -o.per[id]! : 0,
      };

  void _set(String id, int v) {
    switch (widget.moeen) {
      case mCash || mBank:
        o.acc[id] = v;
      case mStock:
        o.cost[id] = v;
      case mDebtorsTrade:
        if (v > 0 || (o.per[id] ?? 0) > 0) o.per[id] = v;
      default:
        if (v > 0 || (o.per[id] ?? 0) < 0) o.per[id] = -v;
    }
  }

  TextEditingController _ctl(String id) => _amount.putIfAbsent(id, () {
        final v = _get(id);
        return TextEditingController(text: v == 0 ? '' : groupDigits(v))
          ..addListener(() {
            _set(id, parseMoney(_amount[id]!.text));
            setState(() {});
          });
      });

  TextEditingController _qctl(String id) => _qty.putIfAbsent(id, () {
        final v = o.qty[id] ?? 0;
        return TextEditingController(text: v == 0 ? '' : fmtQty(v))
          ..addListener(() {
            o.qty[id] = parseQty(_qty[id]!.text);
            setState(() {});
          });
      });

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final m = findMoeen(widget.moeen)!;
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final rows = _rows(s).where((r) => q.isEmpty || r.$2.toLowerCase().contains(q) || r.$3.toLowerCase().contains(q)).toList();
    final total = o.moeenValue(widget.moeen);
    const dense = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => Navigator.pop(context, true),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context, false),
      },
      child: FormDialog(
        title: m.name,
        width: _isStock ? 860 : 680,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تایید (F9)')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: const InputDecoration(hintText: 'جستجو…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 10),
            Container(
              color: th.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: DefaultTextStyle(
                style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w700),
                child: Row(children: [
                  const SizedBox(width: 40, child: Text('ردیف')),
                  const Expanded(child: Text('اسم دفتر')),
                  if (_isStock) ...[
                    const SizedBox(width: 110, child: Text('تعداد', textAlign: TextAlign.center)),
                    const SizedBox(width: 150, child: Text('فی خرید', textAlign: TextAlign.center)),
                    const SizedBox(width: 150, child: Text('ریال موجودی', textAlign: TextAlign.left)),
                  ] else
                    const SizedBox(width: 200, child: Text('ریال موجودی', textAlign: TextAlign.center)),
                ]),
              ),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _isStock
                      ? 'کالایی تعریف نشده'
                      : (widget.moeen == mCash || widget.moeen == mBank ? 'حسابی از این نوع تعریف نشده' : 'شخصی تعریف نشده'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: th.hintColor),
                ),
              ),
            for (var i = 0; i < rows.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant))),
                child: Row(children: [
                  SizedBox(width: 40, child: Text('${i + 1}')),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(rows[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (rows[i].$3.isNotEmpty) Text(rows[i].$3, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                    ]),
                  ),
                  if (_isStock) ...[
                    SizedBox(
                      width: 110,
                      child: TextField(controller: _qctl(rows[i].$1), textAlign: TextAlign.center, textDirection: TextDirection.ltr, decoration: dense),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 144,
                      child: TextField(
                        controller: _ctl(rows[i].$1),
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [MoneyInputFormatter()],
                        decoration: dense,
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Money(((o.qty[rows[i].$1] ?? 0) * (o.cost[rows[i].$1] ?? 0)).round(),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _ctl(rows[i].$1),
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [MoneyInputFormatter()],
                        decoration: dense,
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Text('جمع ${m.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Money(total, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            if (widget.moeen == mDebtorsTrade || widget.moeen == mCreditorsTrade)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'هر شخص فقط یکی از «بدهکاران تجاری» یا «بستانکاران تجاری» را دارد؛ وارد کردن مبلغ در یکی، دیگری را صفر می‌کند.',
                  style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
