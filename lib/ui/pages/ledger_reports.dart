import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart';
import '../../data/store.dart';
import '../dialogs/voucher_dialog.dart' show tafsiliOptions;
import '../print.dart';
import '../theme.dart';
import '../widgets/common.dart';

// ================================================================ shared bits

/// A Sakan-style "محدودیت" box: checkbox header that reveals its inputs.
class _LimitBox extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? child;
  final bool enabled;

  const _LimitBox({required this.title, required this.value, required this.onChanged, this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: value ? th.colorScheme.primary.withValues(alpha: 0.05) : th.colorScheme.surfaceContainerLow,
        border: Border.all(color: value ? th.colorScheme.primary.withValues(alpha: 0.4) : th.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: value,
            onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? null : th.hintColor)),
          ),
          if (value && child != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 12), child: child),
        ],
      ),
    );
  }
}

class _Range extends StatelessWidget {
  final Widget a;
  final Widget b;
  const _Range(this.a, this.b);

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: a),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('تا')),
        Expanded(child: b),
      ]);
}

/// Picks kol → moeen → tafsili.
class _AccountPicker extends StatelessWidget {
  final String? kol;
  final String? moeen;
  final String? tafsili;
  final bool allowTafsili;
  final void Function(String? kol, String? moeen, String? tafsili) onChanged;

  const _AccountPicker({this.kol, this.moeen, this.tafsili, this.allowTafsili = true, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final k = kol == null ? null : chart.firstWhere((x) => x.code == kol);
    final m = findMoeen(moeen);
    final opts = m == null ? const <(String, String)>[] : tafsiliOptions(store, m);
    return Row(children: [
      Expanded(
        child: FieldDropdown<String?>(
          label: 'کل',
          value: kol,
          items: [for (final x in chart) DropdownMenuItem<String?>(value: x.code, child: Text('${x.code}  ${x.name}'))],
          onChanged: (v) => onChanged(v, null, null),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FieldDropdown<String?>(
          label: 'معین',
          value: moeen,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('— همه —')),
            if (k != null) for (final x in k.ledgers) DropdownMenuItem<String?>(value: x.code, child: Text('${x.code}  ${x.name}')),
          ],
          onChanged: (v) => onChanged(kol, v, null),
        ),
      ),
      if (allowTafsili) ...[
        const SizedBox(width: 8),
        Expanded(
          child: FieldDropdown<String?>(
            label: 'تفصیلی',
            value: tafsili,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— همه —')),
              for (final o in opts) DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
            ],
            onChanged: (v) => onChanged(kol, moeen, v),
          ),
        ),
      ],
    ]);
  }
}

/// Every detail entity, for "دفتر ربط".
List<(String, String)> _allTafsili(AppStore s) => [
      for (final a in s.accounts) (a.id, 'حساب: ${a.name}'),
      for (final p in s.peopleSorted) (p.id, 'شخص: ${p.name}'),
      for (final p in s.productsSorted) (p.id, 'کالا: ${p.name}'),
    ];

String _rangeText(ReportFilter f) {
  final parts = <String>[];
  if (f.from != null || f.to != null) {
    parts.add('از ${f.from == null ? 'ابتدا' : jFormat(f.from!)} تا ${f.to == null ? 'امروز' : jFormat(f.to!)}');
  }
  if (f.noFrom != null || f.noTo != null) parts.add('سند ${f.noFrom ?? '…'} تا ${f.noTo ?? '…'}');
  return parts.isEmpty ? 'کل دوره' : parts.join('  ·  ');
}

Widget _dialogFrame(BuildContext context, {required String title, required Widget child, required List<Widget> actions, double width = 620}) {
  return FormDialog(title: title, width: width, actions: actions, child: child);
}

// =============================================================== trial balance

Future<void> showTrialBalanceFilter(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _TrialFilterDialog());

class _TrialFilterDialog extends StatefulWidget {
  const _TrialFilterDialog();

  @override
  State<_TrialFilterDialog> createState() => _TrialFilterDialogState();
}

class _TrialFilterDialogState extends State<_TrialFilterDialog> {
  final f = ReportFilter();
  final o = TbOptions();
  bool limPath = false, limLink = false, limCenter = false, limDate = false, limNo = false;
  String? kol, moeen, link;
  DateTime? from, to;
  final noFrom = TextEditingController(), noTo = TextEditingController();

  @override
  void dispose() {
    noFrom.dispose();
    noTo.dispose();
    super.dispose();
  }

  ReportFilter _build() {
    f
      ..pathKol = limPath ? kol : null
      ..pathMoeen = limPath ? moeen : null
      ..linkTafsili = limLink ? link : null
      ..from = limDate ? from : null
      ..to = limDate ? to : null
      ..noFrom = limNo ? int.tryParse(normalizeDigits(noFrom.text.trim())) : null
      ..noTo = limNo ? int.tryParse(normalizeDigits(noTo.text.trim())) : null;
    return f;
  }

  void _show() {
    final filter = _build();
    showDialog<void>(context: context, builder: (_) => TrialBalanceView(filter: filter, options: o));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context)},
      child: _dialogFrame(
        context,
        title: 'تراز آزمایشی',
        width: 640,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton.icon(onPressed: _show, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('مشاهده تراز')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(children: [
                  for (final l in TbLevel.values)
                    RadioListTile<TbLevel>(
                      dense: true,
                      value: l,
                      groupValue: f.level,
                      onChanged: (v) => setState(() => f.level = v!),
                      title: Text(switch (l) {
                        TbLevel.kol => 'تراز حسابهای در سطح کل',
                        TbLevel.moeen => 'تراز حسابهای در سطح معین',
                        TbLevel.tafsili => 'تراز حسابهای در سطح تفصیلی',
                      }),
                    ),
                ]),
              ),
              Expanded(
                child: Tooltip(
                  message: 'حساب ارزی تعریف نشده است',
                  child: CheckboxListTile(
                    dense: true,
                    value: false,
                    onChanged: null,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('مشاهده با ارز', style: TextStyle(color: th.hintColor)),
                  ),
                ),
              ),
            ]),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: th.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                for (final e in const [(1, 'فقط بدهکاران'), (2, 'فقط بستانکاران'), (0, 'همه')])
                  Expanded(
                    child: RadioListTile<int>(
                      dense: true,
                      value: e.$1,
                      groupValue: o.side,
                      onChanged: (v) => setState(() => o.side = v!),
                      title: Text(e.$2),
                    ),
                  ),
              ]),
            ),
            _LimitBox(
              title: 'محدودیت . مسیر دفتر',
              value: limPath,
              onChanged: (v) => setState(() => limPath = v),
              child: _AccountPicker(
                kol: kol,
                moeen: moeen,
                allowTafsili: false,
                onChanged: (k, m, _) => setState(() {
                  kol = k;
                  moeen = m;
                }),
              ),
            ),
            _LimitBox(
              title: 'محدودیت . دفتر ربط',
              value: limLink,
              onChanged: (v) => setState(() => limLink = v),
              child: FieldDropdown<String?>(
                label: 'دفتر تفصیلی',
                value: link,
                items: [for (final e in _allTafsili(store)) DropdownMenuItem<String?>(value: e.$1, child: Text(e.$2))],
                onChanged: (v) => setState(() => link = v),
              ),
            ),
            _LimitBox(
              title: 'محدودیت . مرکز اسناد',
              value: limCenter,
              onChanged: (v) => setState(() => limCenter = v),
              child: FieldDropdown<String>(
                label: 'مرکز اسناد',
                value: 'اصلی',
                items: const [DropdownMenuItem(value: 'اصلی', child: Text('اصلی'))],
                onChanged: (_) {},
              ),
            ),
            _LimitBox(
              title: 'محدودیت . تاریخ سند',
              value: limDate,
              onChanged: (v) => setState(() => limDate = v),
              child: _Range(
                DateField(label: 'از تاریخ', value: from, clearable: true, onChanged: (d) => setState(() => from = d)),
                DateField(label: 'تا تاریخ', value: to, clearable: true, onChanged: (d) => setState(() => to = d)),
              ),
            ),
            _LimitBox(
              title: 'محدودیت . شماره سند',
              value: limNo,
              onChanged: (v) => setState(() => limNo = v),
              child: _Range(
                TextField(controller: noFrom, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'از شماره')),
                TextField(controller: noTo, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تا شماره')),
              ),
            ),
            Text('در فیلتر تاریخ سند و شماره سند می‌بایست یک روز یا یک شماره اختلاف وجود داشته باشد.',
                style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
            const SizedBox(height: 8),
            for (final e in [
              ('عدم نمایش حسابهای انتظامی و طرف حسابهای انتظامی', o.hideMemo, (bool v) => o.hideMemo = v),
              ('حساب هایی که مانده صفر دارند نمایش داده شود', o.showZero, (bool v) => o.showZero = v),
              ('عدم نمایش حسابهای بدون گردش در طی دوره', o.hideNoTurnover, (bool v) => o.hideNoTurnover = v),
              ('عدم نمایش دفاتر موجودی کالا و وابسته های آن', o.hideStock, (bool v) => o.hideStock = v),
            ])
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: e.$2,
                onChanged: (v) => setState(() => e.$3(v ?? false)),
                title: Text(e.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class TrialBalanceView extends StatelessWidget {
  final ReportFilter filter;
  final TbOptions options;
  const TrialBalanceView({super.key, required this.filter, required this.options});

  String get _levelLabel => switch (filter.level) {
        TbLevel.kol => 'سطح کل',
        TbLevel.moeen => 'سطح معین',
        TbLevel.tafsili => 'سطح تفصیلی',
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final journal = buildJournal(store);
    final rows = trialBalance(store, journal, filter, options);
    final tDr = rows.fold<int>(0, (s, r) => s + r.turnDr);
    final tCr = rows.fold<int>(0, (s, r) => s + r.turnCr);
    final bDr = rows.fold<int>(0, (s, r) => s + r.balDr);
    final bCr = rows.fold<int>(0, (s, r) => s + r.balCr);
    final size = MediaQuery.of(context).size;
    const w = 150.0;

    Widget num(int v, {bool bold = false}) => SizedBox(
          width: w,
          child: Align(
            alignment: Alignment.centerLeft,
            child: v == 0 ? const Text('') : Money(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ),
        );

    void doPrint() => printTable(
          store: store,
          title: 'تراز آزمایشی ($_levelLabel)',
          subtitle: _rangeText(filter),
          headers: const ['ردیف', 'کد', 'نام حساب', 'گردش بدهکار', 'گردش بستانکار', 'مانده بدهکار', 'مانده بستانکار'],
          numeric: const {3, 4, 5, 6},
          rows: [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                rows[i].code,
                rows[i].name,
                groupDigits(rows[i].turnDr),
                groupDigits(rows[i].turnCr),
                groupDigits(rows[i].balDr),
                groupDigits(rows[i].balCr),
              ],
          ],
          footer: ['', '', 'جمع', groupDigits(tDr), groupDigits(tCr), groupDigits(bDr), groupDigits(bCr)],
          fileName: 'trial-balance',
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): doPrint,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: size.width - 32,
          height: size.height - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('تراز آزمایشی — $_levelLabel', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(_rangeText(filter), style: th.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ]),
                  const Spacer(),
                  if (bDr != bCr)
                    Pill('عدم تراز: ${groupDigits((bDr - bCr).abs())}', color: Colors.white)
                  else
                    const Pill('تراز است', color: Colors.white, icon: Icons.check_rounded),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(onPressed: doPrint, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('چاپ (Ctrl+P)')),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Container(
                color: th.colorScheme.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: DefaultTextStyle(
                  style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w700),
                  child: const Row(children: [
                    SizedBox(width: 50, child: Text('ردیف')),
                    SizedBox(width: 80, child: Text('کد')),
                    Expanded(child: Text('نام حساب')),
                    SizedBox(width: w, child: Text('گردش بدهکار', textAlign: TextAlign.left)),
                    SizedBox(width: w, child: Text('گردش بستانکار', textAlign: TextAlign.left)),
                    SizedBox(width: w, child: Text('مانده بدهکار', textAlign: TextAlign.left)),
                    SizedBox(width: w, child: Text('مانده بستانکار', textAlign: TextAlign.left)),
                  ]),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const EmptyState(icon: Icons.balance_rounded, text: 'حسابی با این شرایط پیدا نشد')
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          return InkWell(
                            onDoubleTap: () {
                              final lf = ReportFilter()
                                ..level = filter.level
                                ..from = filter.from
                                ..to = filter.to
                                ..noFrom = filter.noFrom
                                ..noTo = filter.noTo;
                              final parts = r.key.split('|');
                              if (filter.level == TbLevel.kol) {
                                lf.pathKol = r.key;
                              } else {
                                lf.pathMoeen = parts[0];
                                if (filter.level == TbLevel.tafsili && parts.length > 1 && parts[1].isNotEmpty) {
                                  lf.linkTafsili = parts[1];
                                }
                              }
                              showDialog<void>(context: context, builder: (_) => GeneralLedgerView(filter: lf));
                            },
                            child: Container(
                              color: i.isOdd ? th.colorScheme.surfaceContainerLow.withValues(alpha: 0.5) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                              child: Row(children: [
                                SizedBox(width: 50, child: Text('${i + 1}', style: TextStyle(color: th.hintColor))),
                                SizedBox(width: 80, child: Text(r.code)),
                                Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                                num(r.turnDr),
                                num(r.turnCr),
                                num(r.balDr),
                                num(r.balCr),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                color: th.colorScheme.primary.withValues(alpha: 0.07),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  const SizedBox(width: 130),
                  Expanded(child: Text('جمع (${rows.length} حساب) — برای دیدن دفتر هر حساب دوبار کلیک کنید',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                  num(tDr, bold: true),
                  num(tCr, bold: true),
                  num(bDr, bold: true),
                  num(bCr, bold: true),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ general ledger

Future<void> showGeneralLedgerFilter(BuildContext context, {String title = 'چاپ دفتر کل', TbLevel level = TbLevel.kol}) =>
    showDialog<void>(context: context, builder: (_) => _LedgerFilterDialog(title: title, level: level));

class _LedgerFilterDialog extends StatefulWidget {
  final String title;
  final TbLevel level;
  const _LedgerFilterDialog({required this.title, required this.level});

  @override
  State<_LedgerFilterDialog> createState() => _LedgerFilterDialogState();
}

class _LedgerFilterDialogState extends State<_LedgerFilterDialog> {
  bool limAcc = false, limBooks = false, limCenter = false, limNo = false, limDate = false, limDocs = false;
  String? kol, moeen, tafsili;
  DateTime? from, to;
  final noFrom = TextEditingController(), noTo = TextEditingController(), docs = TextEditingController();

  @override
  void dispose() {
    noFrom.dispose();
    noTo.dispose();
    docs.dispose();
    super.dispose();
  }

  ReportFilter _build() {
    final f = ReportFilter()..level = widget.level;
    if (limAcc && kol != null) {
      f.pathKol = kol;
      f.level = TbLevel.kol;
      if (moeen != null) {
        f.pathMoeen = moeen;
        f.level = TbLevel.moeen;
        if (tafsili != null) {
          f.linkTafsili = tafsili;
          f.level = TbLevel.tafsili;
        }
      }
      if (widget.level.index > f.level.index) f.level = widget.level;
    }
    if (limDate) {
      f
        ..from = from
        ..to = to;
    }
    if (limNo) {
      f
        ..noFrom = int.tryParse(normalizeDigits(noFrom.text.trim()))
        ..noTo = int.tryParse(normalizeDigits(noTo.text.trim()));
    }
    if (limDocs) {
      f.docs = normalizeDigits(docs.text)
          .split(RegExp(r'[,،\s]+'))
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    }
    return f;
  }

  void _show({bool aggregate = false, bool print = false}) {
    final f = _build();
    if (print) {
      printLedger(StoreScope.read(context), f, aggregate: aggregate, title: widget.title.replaceFirst('چاپ ', ''));
      return;
    }
    showDialog<void>(context: context, builder: (_) => GeneralLedgerView(filter: f, aggregate: aggregate, title: widget.title.replaceFirst('چاپ ', '')));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context)},
      child: _dialogFrame(
        context,
        title: widget.title,
        width: 640,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت (F10)')),
          OutlinedButton.icon(onPressed: () => _show(print: true), icon: const Icon(Icons.print_outlined, size: 18), label: const Text('چاپ')),
          OutlinedButton(onPressed: () => _show(aggregate: true), child: const Text('نمایش به صورت تجمیعی')),
          FilledButton.icon(onPressed: _show, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('نمایش')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LimitBox(
              title: 'محدودیت . دفتر',
              value: limAcc,
              onChanged: (v) => setState(() => limAcc = v),
              child: _AccountPicker(
                kol: kol,
                moeen: moeen,
                tafsili: tafsili,
                onChanged: (k, m, t) => setState(() {
                  kol = k;
                  moeen = m;
                  tafsili = t;
                }),
              ),
            ),
            _LimitBox(
              title: 'محدودیت . مرکز دفاتر',
              value: limBooks,
              onChanged: (v) => setState(() => limBooks = v),
              child: FieldDropdown<String>(
                label: 'مرکز دفاتر',
                value: 'اصلی',
                items: const [DropdownMenuItem(value: 'اصلی', child: Text('اصلی'))],
                onChanged: (_) {},
              ),
            ),
            _LimitBox(
              title: 'محدودیت . مرکز اسناد',
              value: limCenter,
              onChanged: (v) => setState(() => limCenter = v),
              child: FieldDropdown<String>(
                label: 'مرکز اسناد',
                value: 'اصلی',
                items: const [DropdownMenuItem(value: 'اصلی', child: Text('اصلی'))],
                onChanged: (_) {},
              ),
            ),
            _LimitBox(
              title: 'محدودیت . سند تا سند',
              value: limNo,
              onChanged: (v) => setState(() => limNo = v),
              child: _Range(
                TextField(controller: noFrom, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'از سند')),
                TextField(controller: noTo, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تا سند')),
              ),
            ),
            _LimitBox(
              title: 'محدودیت . تاریخ تا تاریخ',
              value: limDate,
              onChanged: (v) => setState(() => limDate = v),
              child: _Range(
                DateField(label: 'از تاریخ', value: from, clearable: true, onChanged: (d) => setState(() => from = d)),
                DateField(label: 'تا تاریخ', value: to, clearable: true, onChanged: (d) => setState(() => to = d)),
              ),
            ),
            Row(children: [
              Checkbox(value: limDocs, onChanged: (v) => setState(() => limDocs = v ?? false)),
              const Text('سند های'),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: docs,
                  enabled: limDocs,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: 'مثلاً 12, 15, 20'),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('محدودیت‌های شماره سند فقط روی اسناد حسابداری دستی اعمال می‌شوند.',
                style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
          ],
        ),
      ),
    );
  }
}

String _levelTitle(TbLevel l) => switch (l) {
      TbLevel.kol => 'دفتر کل',
      TbLevel.moeen => 'دفتر معین',
      TbLevel.tafsili => 'دفتر تفصیلی',
    };

void printLedger(AppStore store, ReportFilter f, {bool aggregate = false, String? title}) {
  final secs = generalLedger(store, buildJournal(store), f, aggregate: aggregate);
  final rows = <List<String>>[];
  for (final s in secs) {
    rows.add(['', s.name, '', '', '', '', '']);
    if (s.before != 0) rows.add(['', '', 'مانده از قبل', '', '', groupDigits(s.before.abs()), s.before >= 0 ? 'بد' : 'بس']);
    for (final r in s.rows) {
      rows.add([jFormat(r.date), r.doc, r.desc, groupDigits(r.dr), groupDigits(r.cr), groupDigits(r.balance.abs()), r.balance >= 0 ? 'بد' : 'بس']);
    }
    rows.add(['', 'جمع ${s.name}', '', groupDigits(s.dr), groupDigits(s.cr), groupDigits(s.end.abs()), s.end >= 0 ? 'بد' : 'بس']);
  }
  printTable(
    store: store,
    title: title ?? _levelTitle(f.level),
    subtitle: _rangeText(f),
    headers: const ['تاریخ', 'سند', 'شرح', 'بدهکار', 'بستانکار', 'مانده', 'تشخیص'],
    numeric: const {3, 4, 5},
    rows: rows,
    fileName: 'ledger',
  );
}

class GeneralLedgerView extends StatelessWidget {
  final ReportFilter filter;
  final bool aggregate;
  final String? title;
  const GeneralLedgerView({super.key, required this.filter, this.aggregate = false, this.title});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final secs = generalLedger(store, buildJournal(store), filter, aggregate: aggregate);
    final size = MediaQuery.of(context).size;
    const w = 140.0;

    Widget num(int v, {bool bold = false}) => SizedBox(
          width: w,
          child: Align(
            alignment: Alignment.centerLeft,
            child: v == 0 ? const Text('') : Money(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ),
        );

    Widget bal(int v, {bool bold = false}) => SizedBox(
          width: w + 40,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Money(v.abs(), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(width: 6),
            SizedBox(
              width: 22,
              child: Text(v == 0 ? '' : (v > 0 ? 'بد' : 'بس'),
                  style: TextStyle(fontSize: 11, color: v > 0 ? AppColors.income : AppColors.expense)),
            ),
          ]),
        );

    final items = <Widget>[];
    for (final s in secs) {
      items.add(Container(
        color: th.colorScheme.primary.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      ));
      if (filter.from != null || s.before != 0) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            const SizedBox(width: 100),
            const SizedBox(width: 160),
            Expanded(child: Text('مانده از قبل', style: TextStyle(color: th.hintColor))),
            num(0),
            num(0),
            bal(s.before),
          ]),
        ));
      }
      for (final r in s.rows) {
        items.add(Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant.withValues(alpha: 0.5)))),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            SizedBox(width: 100, child: Text(jFormat(r.date))),
            SizedBox(width: 160, child: Text(r.doc, overflow: TextOverflow.ellipsis)),
            Expanded(child: Text(r.desc, overflow: TextOverflow.ellipsis, style: TextStyle(color: th.hintColor))),
            num(r.dr),
            num(r.cr),
            bal(r.balance),
          ]),
        ));
      }
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(children: [
          const SizedBox(width: 260),
          Expanded(child: Text('جمع گردش', style: TextStyle(fontWeight: FontWeight.w700, color: th.hintColor))),
          num(s.dr, bold: true),
          num(s.cr, bold: true),
          bal(s.end, bold: true),
        ]),
      ));
    }

    final heading = title ?? _levelTitle(filter.level);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => printLedger(store, filter, aggregate: aggregate, title: heading),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: size.width - 32,
          height: size.height - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$heading${aggregate ? ' (تجمیعی)' : ''}', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                    Text('${_rangeText(filter)}  ·  ${secs.length} حساب', style: th.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ]),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => printLedger(store, filter, aggregate: aggregate, title: heading),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('چاپ (Ctrl+P)'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Container(
                color: th.colorScheme.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: DefaultTextStyle(
                  style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w700),
                  child: const Row(children: [
                    SizedBox(width: 100, child: Text('تاریخ')),
                    SizedBox(width: 160, child: Text('سند')),
                    Expanded(child: Text('شرح')),
                    SizedBox(width: w, child: Text('بدهکار', textAlign: TextAlign.left)),
                    SizedBox(width: w, child: Text('بستانکار', textAlign: TextAlign.left)),
                    SizedBox(width: w + 40, child: Text('مانده', textAlign: TextAlign.left)),
                  ]),
                ),
              ),
              Expanded(
                child: secs.isEmpty
                    ? const EmptyState(icon: Icons.menu_book_rounded, text: 'گردشی با این شرایط پیدا نشد')
                    : ListView(children: items),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's Jalali date (for default report titles).
String todayJalali() => Jalali.now().format();
