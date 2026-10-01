import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/invoice_editor.dart';
import '../dialogs/product_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _q = '';
  bool _lowOnly = false;
  bool _showArchived = false;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final all = store.productsSorted.where((p) => _showArchived || !p.archived).toList();
    final stocks = {for (final p in all) p.id: store.stock(p.id)};
    final costs = {for (final p in all) p.id: store.avgCost(p.id)};
    final list = all.where((p) {
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !p.code.toLowerCase().contains(q)) return false;
      if (_lowOnly && (stocks[p.id] ?? 0) > p.minQty) return false;
      return true;
    }).toList();
    final lowCount = all.where((p) => (stocks[p.id] ?? 0) <= p.minQty).length;
    if (_selected != null && store.product(_selected) == null) _selected = null;
    final sel = store.product(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'انبار محصولات',
          subtitle: 'موجودی هر کالا از روی فاکتورهای خرید و فروش به‌روز می‌شود',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final id = await showProductDialog(context);
                if (id != null) setState(() => _selected = id);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('کالای جدید'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'ارزش موجودی انبار (به قیمت تمام‌شده)',
                  value: store.stockValue(),
                  icon: Icons.inventory_2_outlined,
                  color: th.colorScheme.primary,
                  hint: '${all.length} کالا',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _lowOnly = !_lowOnly),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: lowCount > 0 ? AppColors.expense : th.hintColor, size: 30),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('کالاهای رو به اتمام', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                                Text('$lowCount کالا',
                                    style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          if (_lowOnly) const Pill('فیلتر فعال', color: AppColors.expense),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    hintText: 'جستجوی نام یا کد کالا',
                                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                                  ),
                                  onChanged: (v) => setState(() => _q = v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: const Text('فقط کم‌موجود'),
                                selected: _lowOnly,
                                onSelected: (v) => setState(() => _lowOnly = v),
                              ),
                              const SizedBox(width: 6),
                              FilterChip(
                                label: const Text('بایگانی‌شده‌ها'),
                                selected: _showArchived,
                                onSelected: (v) => setState(() => _showArchived = v),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          color: th.colorScheme.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: DefaultTextStyle(
                            style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
                            child: const Row(
                              children: [
                                Expanded(child: Text('کالا')),
                                SizedBox(width: 110, child: Text('موجودی', textAlign: TextAlign.center)),
                                SizedBox(width: 130, child: Text('میانگین خرید', textAlign: TextAlign.left)),
                                SizedBox(width: 130, child: Text('قیمت فروش', textAlign: TextAlign.left)),
                                SizedBox(width: 140, child: Text('ارزش موجودی', textAlign: TextAlign.left)),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: list.isEmpty
                              ? const EmptyState(icon: Icons.inventory_2_outlined, text: 'کالایی پیدا نشد')
                              : ListView.separated(
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (context, i) {
                                    final p = list[i];
                                    final st = stocks[p.id] ?? 0;
                                    final low = st <= p.minQty;
                                    final selected = p.id == _selected;
                                    return InkWell(
                                      onTap: () => setState(() => _selected = p.id),
                                      onDoubleTap: () => showProductDialog(context, edit: p),
                                      child: Container(
                                        color: selected ? th.colorScheme.primary.withValues(alpha: 0.07) : null,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(p.name,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: p.archived ? th.hintColor : null,
                                                      )),
                                                  if (p.code.isNotEmpty)
                                                    Text(p.code,
                                                        style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                                                ],
                                              ),
                                            ),
                                            SizedBox(
                                              width: 110,
                                              child: Center(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Pill('${fmtQty(st)} ${p.unit}',
                                                      color: st <= 0
                                                          ? th.colorScheme.error
                                                          : (low ? AppColors.expense : AppColors.income)),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 130,
                                              child: Align(alignment: Alignment.centerLeft, child: Money(costs[p.id] ?? 0)),
                                            ),
                                            SizedBox(
                                              width: 130,
                                              child: Align(alignment: Alignment.centerLeft, child: Money(p.sellPrice)),
                                            ),
                                            SizedBox(
                                              width: 140,
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Money(st > 0 ? (st * (costs[p.id] ?? 0)).round() : 0,
                                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 400,
                  child: sel == null
                      ? const Card(
                          child: EmptyState(icon: Icons.touch_app_outlined, text: 'برای دیدن گردش کالا، یک کالا را انتخاب کنید'))
                      : _detail(context, store, sel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, AppStore store, Product p) {
    final th = Theme.of(context);
    // movement history (kardex): oldest -> newest with running stock
    final moves = <_Move>[];
    for (final inv in store.realInvoices) {
      var q = 0.0;
      for (final l in inv.lines) {
        if (l.productId == p.id) q += l.qty;
      }
      if (q != 0) {
        moves.add(_Move(inv.date, '${inv.kind.label} ${inv.number}', inv.kind.stockSign * q, invoice: inv,
            order: inv.createdAt));
      }
    }
    for (final a in store.adjusts) {
      if (a.productId == p.id) {
        moves.add(_Move(a.date, a.reason.label + (a.note.isEmpty ? '' : ' — ${a.note}'), a.qty, adjust: a, order: a.createdAt));
      }
    }
    moves.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.order.compareTo(b.order);
    });
    var run = p.openingQty;
    for (final m in moves) {
      run += m.qty;
      m.balance = run;
    }
    final shown = moves.reversed.toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('موجودی فعلی: ${fmtQty(store.stock(p.id))} ${p.unit}',
                          style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'ویرایش کالا',
                  onPressed: () => showProductDialog(context, edit: p),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'حذف / بایگانی',
                  onPressed: () async {
                    final used = store.productInUse(p.id);
                    final ok = await confirm(context, 'حذف کالا',
                        used ? 'این کالا در فاکتورها استفاده شده و بایگانی می‌شود. ادامه؟' : '«${p.name}» حذف شود؟');
                    if (ok) {
                      store.removeProduct(p.id);
                      setState(() => _selected = null);
                    }
                  },
                  icon: Icon(Icons.delete_outline, color: th.colorScheme.error),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showInvoiceEditor(context, kind: InvoiceKind.sale),
                    icon: const Icon(Icons.sell_outlined, size: 18),
                    label: const Text('فروش'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showInvoiceEditor(context, kind: InvoiceKind.purchase),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('خرید'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text('گردش کالا', style: th.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: shown.isEmpty
                ? const EmptyState(icon: Icons.swap_vert_rounded, text: 'هنوز گردشی ثبت نشده')
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final r = shown[i];
                      final inc = r.qty > 0;
                      return ListTile(
                        dense: true,
                        onTap: () async {
                          if (r.invoice != null) {
                            showInvoiceEditor(context, edit: r.invoice);
                          } else if (r.adjust != null) {
                            final ok = await confirm(context, 'حذف سند انبار', 'این ${r.adjust!.reason.label} حذف شود؟');
                            if (ok) store.removeAdjust(r.adjust!);
                          }
                        },
                        leading: Icon(inc ? Icons.add_circle_outline : Icons.remove_circle_outline,
                            color: inc ? AppColors.income : AppColors.expense),
                        title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(jFormat(r.date)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${inc ? '+' : '−'}${fmtQty(r.qty.abs())}',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, color: inc ? AppColors.income : AppColors.expense)),
                            Text('مانده ${fmtQty(r.balance)}', style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Move {
  final DateTime date;
  final String title;
  final double qty;
  final Invoice? invoice;
  final StockAdjust? adjust;
  final int order;
  double balance = 0;
  _Move(this.date, this.title, this.qty, {this.invoice, this.adjust, this.order = 0});
}
