import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../print.dart' show openFile;
import '../../data/store.dart';
import '../dialogs/txn_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/txn_table.dart';

enum RangePreset { all, thisMonth, lastMonth, last3, thisYear, custom }

extension RangePresetX on RangePreset {
  String get label => switch (this) {
        RangePreset.all => 'همه',
        RangePreset.thisMonth => 'این ماه',
        RangePreset.lastMonth => 'ماه قبل',
        RangePreset.last3 => '۳ ماه اخیر',
        RangePreset.thisYear => 'امسال',
        RangePreset.custom => 'دلخواه',
      };

  /// Returns [from, to] or nulls.
  (DateTime?, DateTime?) range() {
    final now = Jalali.now();
    switch (this) {
      case RangePreset.all:
      case RangePreset.custom:
        return (null, null);
      case RangePreset.thisMonth:
        return (now.firstOfMonth.toDateTime(), now.lastOfMonth.toDateTime());
      case RangePreset.lastMonth:
        final m = now.addMonths(-1);
        return (m.firstOfMonth.toDateTime(), m.lastOfMonth.toDateTime());
      case RangePreset.last3:
        return (now.addMonths(-2).firstOfMonth.toDateTime(), now.lastOfMonth.toDateTime());
      case RangePreset.thisYear:
        return (Jalali(now.year, 1, 1).toDateTime(), Jalali(now.year, 12, Jalali.monthLength(now.year, 12)).toDateTime());
    }
  }
}

class TransactionsPage extends StatefulWidget {
  final FocusNode searchFocus;
  const TransactionsPage({super.key, required this.searchFocus});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _f = TxnFilter();
  RangePreset _preset = RangePreset.all;
  final _search = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _setPreset(RangePreset p) {
    setState(() {
      _preset = p;
      if (p != RangePreset.custom) {
        final r = p.range();
        _f.from = r.$1;
        _f.to = r.$2;
      }
    });
  }

  void _reset() {
    setState(() {
      _preset = RangePreset.all;
      _f
        ..from = null
        ..to = null
        ..types = {}
        ..accountId = null
        ..categoryId = null
        ..personId = null
        ..query = ''
        ..minAmount = null
        ..maxAmount = null;
      _search.clear();
      _min.clear();
      _max.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final list = store.filter(_f);
    var inc = 0, exp = 0;
    for (final t in list) {
      if (t.type == TxnType.income) inc += t.amount;
      if (t.type == TxnType.expense) exp += t.amount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'تراکنش‌ها',
          subtitle: 'همه ورود و خروج‌ها، قابل جستجو و فیلتر',
          actions: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                focusNode: widget.searchFocus,
                decoration: InputDecoration(
                  hintText: 'جستجو در شرح، مبلغ، شخص… (Ctrl+F)',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() {
                            _search.clear();
                            _f.query = '';
                          }),
                        ),
                ),
                onChanged: (v) => setState(() => _f.query = v),
              ),
            ),
            OutlinedButton.icon(
              onPressed: list.isEmpty
                  ? null
                  : () {
                      try {
                        final path = store.exportTxnsXlsx(list);
                        toast(context, 'فایل اکسل ذخیره شد: $path');
                        openFile(path);
                      } catch (e) {
                        toast(context, 'خطا: $e', error: true);
                      }
                    },
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('خروجی اکسل'),
            ),
            FilledButton.icon(
              onPressed: () => showTxnDialog(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('تراکنش جدید'),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 290, child: _filters(context, store)),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: TxnTable(txns: list)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: th.colorScheme.surfaceContainerLow,
                            border: Border(top: BorderSide(color: th.colorScheme.outlineVariant)),
                          ),
                          child: Wrap(
                            spacing: 28,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('${list.length} ردیف', style: th.textTheme.bodySmall),
                              _sum(context, 'جمع درآمد', inc, AppColors.income),
                              _sum(context, 'جمع هزینه', exp, AppColors.expense),
                              _sum(context, 'خالص', inc - exp, inc - exp >= 0 ? AppColors.income : AppColors.expense),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sum(BuildContext context, String label, int v, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
          Money(v, showUnit: true, style: TextStyle(fontWeight: FontWeight.w700, color: c)),
        ],
      );

  Widget _filters(BuildContext context, AppStore store) {
    final th = Theme.of(context);
    final cats = [...store.categoriesOf(CategoryKind.expense), ...store.categoriesOf(CategoryKind.income)];
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('فیلترها', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!_f.isEmpty) TextButton(onPressed: _reset, child: const Text('پاک کردن همه')),
            ],
          ),
          const SizedBox(height: 10),
          Text('بازه زمانی', style: th.textTheme.labelMedium?.copyWith(color: th.hintColor)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in RangePreset.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _preset == p,
                  onSelected: (_) => _setPreset(p),
                ),
            ],
          ),
          if (_preset == RangePreset.custom) ...[
            const SizedBox(height: 10),
            DateField(
              label: 'از تاریخ',
              value: _f.from,
              clearable: true,
              onChanged: (d) => setState(() => _f.from = d),
            ),
            const SizedBox(height: 8),
            DateField(
              label: 'تا تاریخ',
              value: _f.to,
              clearable: true,
              onChanged: (d) => setState(() => _f.to = d),
            ),
          ] else if (_f.from != null) ...[
            const SizedBox(height: 8),
            Text('${jFormat(_f.from!)}  تا  ${jFormat(_f.to!)}', style: th.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Text('نوع تراکنش', style: th.textTheme.labelMedium?.copyWith(color: th.hintColor)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in TxnType.values)
                FilterChip(
                  label: Text(t.label),
                  selected: _f.types.contains(t),
                  onSelected: (s) => setState(() {
                    if (s) {
                      _f.types.add(t);
                    } else {
                      _f.types.remove(t);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FieldDropdown<String?>(
            label: 'حساب',
            value: _f.accountId,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('همه حساب‌ها')),
              for (final a in store.accounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _f.accountId = v),
          ),
          const SizedBox(height: 12),
          FieldDropdown<String?>(
            label: 'دسته‌بندی',
            value: _f.categoryId,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('همه دسته‌ها')),
              for (final c in cats)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Row(children: [
                    ColorDot(c.color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    Text(c.kind == CategoryKind.income ? 'درآمد' : 'هزینه',
                        style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _f.categoryId = v),
          ),
          const SizedBox(height: 12),
          FieldDropdown<String?>(
            label: 'طرف حساب',
            value: _f.personId,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('همه اشخاص')),
              for (final p in store.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _f.personId = v),
          ),
          const SizedBox(height: 16),
          Text('محدوده مبلغ', style: th.textTheme.labelMedium?.copyWith(color: th.hintColor)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'از'),
                  onChanged: (v) => setState(() => _f.minAmount = v.isEmpty ? null : parseMoney(v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _max,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(labelText: 'تا'),
                  onChanged: (v) => setState(() => _f.maxAmount = v.isEmpty ? null : parseMoney(v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
