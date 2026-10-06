import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../print.dart' show openFile;
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late int _year;
  int _month = 0; // 0 = whole year

  @override
  void initState() {
    super.initState();
    _year = Jalali.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final now = Jalali.now();

    final years = <int>{now.year};
    for (final t in store.txns) {
      years.add(Jalali.fromDateTime(t.date).year);
    }
    final yearList = years.toList()..sort((a, b) => b.compareTo(a));

    final months = <MonthBar>[];
    final rows = <(String, MonthTotals)>[];
    for (var m = 1; m <= 12; m++) {
      final t = store.monthTotals(Jalali(_year, m, 1));
      months.add(MonthBar(jalaliMonthNames[m - 1], t.income, t.expense));
      rows.add((jalaliMonthNames[m - 1], t));
    }
    final yearTotal = MonthTotals();
    for (final r in rows) {
      yearTotal.income += r.$2.income;
      yearTotal.expense += r.$2.expense;
    }

    final DateTime from;
    final DateTime to;
    if (_month == 0) {
      from = Jalali(_year, 1, 1).toDateTime();
      to = Jalali(_year, 12, Jalali.monthLength(_year, 12)).toDateTime();
    } else {
      from = Jalali(_year, _month, 1).toDateTime();
      to = Jalali(_year, _month, Jalali.monthLength(_year, _month)).toDateTime();
    }

    List<(String, int, Color)> shares(TxnType type) => [
          for (final e in store.categoryTotals(from, to, type))
            (
              store.category(e.key)?.name ?? 'بدون دسته',
              e.value,
              Color(store.category(e.key)?.color ?? 0xFF94A3B8),
            ),
        ];

    final expShares = shares(TxnType.expense);
    final incShares = shares(TxnType.income);
    final periodLabel = _month == 0 ? 'سال $_year' : '${jalaliMonthNames[_month - 1]} $_year';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'گزارش‌ها',
          subtitle: 'تحلیل درآمد و هزینه بر اساس ماه و دسته',
          actions: [
            SizedBox(
              width: 140,
              child: FieldDropdown<int>(
                label: 'سال',
                value: _year,
                items: [for (final y in yearList) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: (v) => setState(() => _year = v ?? _year),
              ),
            ),
            SizedBox(
              width: 170,
              child: FieldDropdown<int>(
                label: 'بازه دسته‌بندی',
                value: _month,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('کل سال')),
                  for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(jalaliMonthNames[m - 1])),
                ],
                onChanged: (v) => setState(() => _month = v ?? 0),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                try {
                  final list = store.txns.where((t) => !t.date.isBefore(from) && !t.date.isAfter(to)).toList();
                  final path = store.exportTxnsXlsx(list,
                      name: 'report', titleLines: ['گزارش تراکنش‌ها', 'از ${jFormat(from)} تا ${jFormat(to)}']);
                  toast(context, 'فایل اکسل ذخیره شد: $path');
                  openFile(path);
                } catch (e) {
                  toast(context, 'خطا: $e', error: true);
                }
              },
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text('خروجی $periodLabel'),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(label: 'درآمد سال $_year', value: yearTotal.income, icon: Icons.south_west_rounded, color: AppColors.income),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StatTile(label: 'هزینه سال $_year', value: yearTotal.expense, icon: Icons.north_east_rounded, color: AppColors.expense),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StatTile(
                        label: 'پس‌انداز (خالص)',
                        value: yearTotal.net,
                        icon: Icons.savings_outlined,
                        color: th.colorScheme.primary,
                        hint: yearTotal.income == 0
                            ? null
                            : 'نرخ پس‌انداز ${(yearTotal.net * 100 / yearTotal.income).round()}٪',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Panel(title: 'روند ماهانه $_year', child: IncomeExpenseChart(data: months, height: 260)),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Panel(
                        title: 'هزینه‌ها بر اساس دسته — $periodLabel',
                        child: expShares.isEmpty
                            ? const EmptyState(icon: Icons.pie_chart_outline, text: 'هزینه‌ای در این بازه نیست')
                            : ShareBars(items: expShares, maxItems: 12),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Panel(
                        title: 'درآمدها بر اساس دسته — $periodLabel',
                        child: incShares.isEmpty
                            ? const EmptyState(icon: Icons.pie_chart_outline, text: 'درآمدی در این بازه نیست')
                            : ShareBars(items: incShares, maxItems: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Panel(
                  title: 'جدول ماهانه',
                  flush: true,
                  child: Column(
                    children: [
                      _tableRow(context, 'ماه', null, null, null, header: true),
                      for (var i = 0; i < rows.length; i++)
                        InkWell(
                          onTap: () => setState(() => _month = i + 1),
                          child: _tableRow(context, rows[i].$1, rows[i].$2.income, rows[i].$2.expense, rows[i].$2.net,
                              highlight: _month == i + 1),
                        ),
                      _tableRow(context, 'جمع سال', yearTotal.income, yearTotal.expense, yearTotal.net, header: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableRow(BuildContext context, String label, int? inc, int? exp, int? net,
      {bool header = false, bool highlight = false}) {
    final th = Theme.of(context);
    final st = header
        ? th.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)
        : th.textTheme.bodyMedium;
    Widget cell(int? v, String h, Color? c) => Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: v == null
                ? Text(h, style: st?.copyWith(color: th.hintColor))
                : Money(v, style: st?.copyWith(color: c, fontWeight: FontWeight.w600)),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? th.colorScheme.primary.withValues(alpha: 0.07)
            : (header ? th.colorScheme.surfaceContainerLow : null),
        border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: st)),
          cell(inc, 'درآمد', AppColors.income),
          cell(exp, 'هزینه', AppColors.expense),
          cell(net, 'خالص', net == null ? null : (net >= 0 ? AppColors.income : AppColors.expense)),
        ],
      ),
    );
  }
}
