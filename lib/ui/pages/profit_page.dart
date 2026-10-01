import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../dialogs/invoice_editor.dart' show fmtQty;
import '../theme.dart';
import '../widgets/common.dart';
import 'transactions_page.dart' show RangePreset, RangePresetX;

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  RangePreset _preset = RangePreset.thisMonth;
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    DateTime from, to;
    if (_preset == RangePreset.custom) {
      from = _from ?? DateTime(2000);
      to = _to ?? DateTime(2100);
    } else {
      final r = _preset.range();
      from = r.$1 ?? DateTime(2000);
      to = r.$2 ?? DateTime(2100);
    }
    final p = store.profit(from, to);
    final products = p.byProduct.values.toList()..sort((a, b) => b.profit.compareTo(a.profit));
    final margin = p.netSales == 0 ? null : (p.grossProfit * 100 / p.netSales).round();

    Widget line(String label, int v, {Color? color, bool bold = false, bool minus = false, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(minus ? '−' : (bold ? '=' : '+'),
                    style: TextStyle(color: th.hintColor, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: bold
                            ? th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
                            : th.textTheme.bodyMedium),
                    if (hint != null) Text(hint, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                  ],
                ),
              ),
              Money(v,
                  showUnit: bold,
                  style: (bold ? th.textTheme.titleLarge : th.textTheme.bodyLarge)
                      ?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'سود و زیان',
          subtitle: 'سود فروش کالا بر اساس میانگین قیمت خرید، به‌علاوه سایر درآمدها و هزینه‌ها',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in RangePreset.values)
                ChoiceChip(label: Text(r.label), selected: _preset == r, onSelected: (_) => setState(() => _preset = r)),
              if (_preset == RangePreset.custom) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 230,
                  child: DateField(label: 'از', value: _from, clearable: true, onChanged: (d) => setState(() => _from = d)),
                ),
                SizedBox(
                  width: 230,
                  child: DateField(label: 'تا', value: _to, clearable: true, onChanged: (d) => setState(() => _to = d)),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 470,
                  child: Card(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text('صورت سود و زیان', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        line('فروش', p.sales, hint: 'پس از کسر تخفیف فاکتورها'),
                        line('برگشت از فروش', p.saleReturns, minus: true),
                        line('بهای تمام‌شده کالای فروش‌رفته', p.cogs, minus: true, hint: 'میانگین قیمت خرید × تعداد'),
                        const Divider(),
                        line('سود ناخالص', p.grossProfit,
                            bold: true, color: p.grossProfit >= 0 ? AppColors.income : AppColors.expense),
                        if (margin != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Text('حاشیه سود: $margin٪', style: th.textTheme.labelMedium?.copyWith(color: th.hintColor)),
                          ),
                        const Divider(),
                        line('هزینه‌های جانبی دریافتی از مشتری', p.saleExtra),
                        line('تخفیف‌های دریافتی از فروشنده', p.discountsReceived + p.purchaseInvoiceDiscounts),
                        line('سایر درآمدها', p.otherIncome),
                        line('تخفیف‌های داده‌شده به مشتری', p.discountsGiven, minus: true),
                        line('هزینه‌های جانبی خرید', p.purchaseExtra, minus: true),
                        line('هزینه‌ها', p.expenses, minus: true),
                        const Divider(thickness: 2),
                        line('سود (زیان) خالص', p.netProfit,
                            bold: true, color: p.netProfit >= 0 ? AppColors.income : AppColors.expense),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text('جمع خرید کالا در این بازه: ',
                                style: th.textTheme.labelMedium?.copyWith(color: th.hintColor)),
                            Money(p.purchases, style: th.textTheme.labelMedium?.copyWith(color: th.hintColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text('سود به تفکیک کالا',
                              style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          color: th.colorScheme.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          child: DefaultTextStyle(
                            style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
                            child: const Row(
                              children: [
                                Expanded(child: Text('کالا')),
                                SizedBox(width: 80, child: Text('تعداد', textAlign: TextAlign.center)),
                                SizedBox(width: 130, child: Text('فروش', textAlign: TextAlign.left)),
                                SizedBox(width: 130, child: Text('بهای تمام‌شده', textAlign: TextAlign.left)),
                                SizedBox(width: 130, child: Text('سود', textAlign: TextAlign.left)),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: products.isEmpty
                              ? const EmptyState(icon: Icons.trending_up_rounded, text: 'در این بازه فروشی ثبت نشده')
                              : ListView.separated(
                                  itemCount: products.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (context, i) {
                                    final r = products[i];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                                          SizedBox(width: 80, child: Text(fmtQty(r.qty), textAlign: TextAlign.center)),
                                          SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: Money(r.revenue))),
                                          SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: Money(r.cost))),
                                          SizedBox(
                                            width: 130,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Money(r.profit, colorBySign: true, style: const TextStyle(fontWeight: FontWeight.w700)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
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
}
