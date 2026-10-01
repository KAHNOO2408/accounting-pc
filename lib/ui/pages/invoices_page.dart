import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/invoice_editor.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'transactions_page.dart' show RangePreset, RangePresetX;

class InvoicesPage extends StatefulWidget {
  final bool proforma;
  final InvoiceKind? initialKind;
  const InvoicesPage({super.key, this.proforma = false, this.initialKind});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  late InvoiceKind? _kind = widget.initialKind;
  late RangePreset _preset = widget.proforma ? RangePreset.all : RangePreset.thisMonth;
  String _q = '';

  Color _kindColor(InvoiceKind k) => switch (k) {
        InvoiceKind.sale => AppColors.income,
        InvoiceKind.purchase => AppColors.expense,
        _ => AppColors.loan,
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final r = _preset.range();
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final list = store.invoicesSorted.where((i) {
      if (i.proforma != widget.proforma) return false;
      if (_kind != null && i.kind != _kind) return false;
      if (r.$1 != null && i.date.isBefore(r.$1!)) return false;
      if (r.$2 != null && i.date.isAfter(r.$2!)) return false;
      if (q.isNotEmpty) {
        final hay = [
          '${i.number}',
          store.person(i.personId)?.name ?? '',
          i.note,
          ...i.lines.map((l) => store.product(l.productId)?.name ?? l.title),
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    var sum = 0, paid = 0;
    for (final i in list) {
      final sign = i.kind == InvoiceKind.saleReturn || i.kind == InvoiceKind.purchaseReturn ? -1 : 1;
      sum += sign * i.total;
      paid += sign * i.paid;
    }

    final now = Jalali.now();
    final mFrom = now.firstOfMonth.toDateTime();
    final mTo = now.lastOfMonth.toDateTime();
    final pr = store.profit(mFrom, mTo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: widget.proforma ? 'لیست پیش‌فاکتورها' : 'خرید و فروش',
          subtitle: widget.proforma
              ? 'پیش‌فاکتورها روی انبار و حساب‌ها اثری ندارند؛ هر وقت قطعی شد تبدیل به فاکتور فروش کنید'
              : 'فاکتورهای فروش، خرید و برگشتی — هر فاکتور با هر تعداد قلم',
          actions: widget.proforma
              ? [
                  FilledButton.icon(
                    onPressed: () => showInvoiceEditor(context, proforma: true),
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('پیش‌فاکتور جدید (F7)'),
                  ),
                ]
              : [
            OutlinedButton.icon(
              onPressed: () => showInvoiceEditor(context, kind: InvoiceKind.purchase),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18, color: AppColors.expense),
              label: const Text('فاکتور خرید (F5)'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.income),
              onPressed: () => showInvoiceEditor(context, kind: InvoiceKind.sale),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('فاکتور فروش (F6)'),
            ),
          ],
        ),
        if (!widget.proforma)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'فروش خالص ${now.monthName}',
                  value: pr.netSales,
                  icon: Icons.sell_outlined,
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'خرید ${now.monthName}',
                  value: pr.purchases - pr.purchaseReturns,
                  icon: Icons.shopping_cart_outlined,
                  color: AppColors.expense,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'سود ناخالص ${now.monthName}',
                  value: pr.grossProfit,
                  icon: Icons.trending_up_rounded,
                  color: th.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (!widget.proforma) ...[
                      ChoiceChip(label: const Text('همه'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
                      for (final k in InvoiceKind.values)
                        ChoiceChip(label: Text(k.short), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
                      const SizedBox(width: 12),
                    ],
                    for (final p in RangePreset.values.where((p) => p != RangePreset.custom))
                      ChoiceChip(label: Text(p.label), selected: _preset == p, onSelected: (_) => setState(() => _preset = p)),
                  ],
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'شماره، طرف حساب یا کالا…',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: DefaultTextStyle(
                      style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
                      child: const Row(
                        children: [
                          SizedBox(width: 80, child: Text('شماره')),
                          SizedBox(width: 100, child: Text('تاریخ')),
                          SizedBox(width: 120, child: Text('نوع')),
                          Expanded(flex: 2, child: Text('طرف حساب')),
                          Expanded(flex: 3, child: Text('اقلام')),
                          SizedBox(width: 140, child: Text('مبلغ', textAlign: TextAlign.left)),
                          SizedBox(width: 140, child: Text('مانده', textAlign: TextAlign.left)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: list.isEmpty
                        ? EmptyState(
                            icon: Icons.receipt_outlined,
                            text: widget.proforma ? 'پیش‌فاکتوری ثبت نشده' : 'فاکتوری در این بازه نیست',
                            action: FilledButton.icon(
                              onPressed: () => showInvoiceEditor(context, proforma: widget.proforma),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(widget.proforma ? 'پیش‌فاکتور جدید' : 'اولین فاکتور فروش'),
                            ),
                          )
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final inv = list[i];
                              final c = _kindColor(inv.kind);
                              final items = inv.lines
                                  .map((l) => '${store.product(l.productId)?.name ?? l.title} ×${fmtQty(l.qty)}')
                                  .join('، ');
                              return InkWell(
                                onTap: () => showInvoiceEditor(context, edit: inv),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 80,
                                        child: Text('${inv.number}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                      SizedBox(width: 100, child: Text(jFormat(inv.date), style: th.textTheme.bodySmall)),
                                      SizedBox(
                                        width: 120,
                                        child: Align(
                                          alignment: AlignmentDirectional.centerStart,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Pill(inv.proforma ? 'پیش‌فاکتور' : inv.kind.short,
                                                color: inv.proforma ? AppColors.discount : c, icon: txnIcon(inv.kind.txnType)),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          store.person(inv.personId)?.name ?? (inv.kind.buySide ? 'فروشنده متفرقه' : 'مشتری نقدی'),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(items,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Money(inv.total, style: const TextStyle(fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 140,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: inv.proforma
                                              ? const Text('—')
                                              : inv.remaining == 0
                                              ? const Pill('تسویه', color: AppColors.income)
                                              : Money(inv.remaining,
                                                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.debt)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: th.colorScheme.surfaceContainerLow,
                      border: Border(top: BorderSide(color: th.colorScheme.outlineVariant)),
                    ),
                    child: Wrap(
                      spacing: 28,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${list.length} فاکتور', style: th.textTheme.bodySmall),
                        _kv(th, 'جمع مبلغ', sum),
                        _kv(th, 'پرداخت/دریافت‌شده', paid),
                        _kv(th, 'مانده', sum - paid),
                      ],
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

  Widget _kv(ThemeData th, String k, int v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ', style: th.textTheme.bodySmall),
          Money(v, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );
}
