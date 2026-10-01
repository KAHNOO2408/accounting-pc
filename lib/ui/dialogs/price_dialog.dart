import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty;

// Rounding choice is remembered during the session.
int _roundStep = 0;
bool _roundUp = false;

/// Rounds [v] to a multiple of [step] (up or down).
int roundPrice(int v, int step, {bool up = false}) {
  if (step <= 1) return v;
  final r = v % step;
  if (r == 0) return v;
  return up ? v - r + step : v - r;
}

/// Last purchase unit price of a product (falls back to the product's buy price).
int lastBuyPrice(AppStore s, Product p) {
  Invoice? last;
  int price = p.buyPrice;
  for (final inv in s.realInvoices) {
    if (inv.kind != InvoiceKind.purchase) continue;
    for (final l in inv.lines) {
      if (l.productId != p.id) continue;
      if (last == null || !inv.date.isBefore(last.date)) {
        last = inv;
        price = l.unitPrice;
      }
    }
  }
  return price;
}

/// «تعیین فی» — choose the unit price of an invoice row.
Future<int?> showUnitPriceDialog(BuildContext context, {required Product product, String? personId, int current = 0}) =>
    showDialog<int>(context: context, builder: (_) => _PriceDialog(product: product, personId: personId, current: current));

class _PriceDialog extends StatefulWidget {
  final Product product;
  final String? personId;
  final int current;
  const _PriceDialog({required this.product, this.personId, this.current = 0});

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final List<TextEditingController> _prices;
  final _step = TextEditingController(text: _roundStep == 0 ? '' : groupDigits(_roundStep));
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _prices = [p.sellPrice, p.sellPrice2, p.sellPrice3]
        .map((v) => TextEditingController(text: v == 0 ? '' : groupDigits(v)))
        .toList();
    for (final c in [..._prices, _step]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    if (widget.current > 0) {
      final i = [p.sellPrice, p.sellPrice2, p.sellPrice3].indexOf(widget.current);
      if (i >= 0) {
        _sel = i;
      } else {
        _prices[0].text = groupDigits(widget.current);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [..._prices, _step]) {
      c.dispose();
    }
    super.dispose();
  }

  void _savePrices() {
    final s = StoreScope.read(context);
    final p = widget.product
      ..sellPrice = parseMoney(_prices[0].text)
      ..sellPrice2 = parseMoney(_prices[1].text)
      ..sellPrice3 = parseMoney(_prices[2].text);
    s.upsertProduct(p);
    toast(context, 'بهای فروش کالا ذخیره شد');
  }

  void _ok() {
    _roundStep = parseMoney(_step.text);
    final v = roundPrice(parseMoney(_prices[_sel].text), _roundStep, up: _roundUp);
    Navigator.pop(context, v);
  }

  void _history(int mode) {
    final s = StoreScope.read(context);
    final kind = mode == 2 ? InvoiceKind.purchase : InvoiceKind.sale;
    final title = switch (mode) {
      0 => 'کل فروش ها',
      1 => 'کل فروش های طرف حساب',
      _ => 'کل خرید ها',
    };
    if (mode == 1 && widget.personId == null) {
      toast(context, 'طرف حساب انتخاب نشده است', error: true);
      return;
    }
    final rows = <(Invoice, InvoiceLine)>[];
    for (final inv in s.realInvoices) {
      if (inv.kind != kind) continue;
      if (mode == 1 && inv.personId != widget.personId) continue;
      for (final l in inv.lines) {
        if (l.productId == widget.product.id) rows.add((inv, l));
      }
    }
    rows.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final th = Theme.of(ctx);
        return FormDialog(
          title: '$title — ${widget.product.name}',
          width: 720,
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
          child: rows.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('سابقه‌ای ثبت نشده')))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DefaultTextStyle(
                    style: th.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w800, color: th.hintColor),
                    child: const Row(children: [
                      SizedBox(width: 100, child: Text('تاریخ')),
                      SizedBox(width: 80, child: Text('شماره')),
                      Expanded(child: Text('طرف حساب')),
                      SizedBox(width: 70, child: Text('تعداد')),
                      SizedBox(width: 130, child: Text('فی', textAlign: TextAlign.left)),
                    ]),
                  ),
                  const Divider(),
                  for (final (inv, l) in rows)
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _prices[_sel].text = groupDigits(l.unitPrice));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          SizedBox(width: 100, child: Text(jFormat(inv.date))),
                          SizedBox(width: 80, child: Text('${inv.number}')),
                          Expanded(child: Text(s.person(inv.personId)?.name ?? '—', overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 70, child: Text(fmtQty(l.qty))),
                          SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: Money(l.unitPrice))),
                        ]),
                      ),
                    ),
                ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final p = widget.product;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _history(0),
        const SingleActivator(LogicalKeyboardKey.f3): () => _history(1),
        const SingleActivator(LogicalKeyboardKey.f4): () => _history(2),
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'تعیین فی — ${p.name}',
        width: 680,
        leading: Wrap(spacing: 6, children: [
          OutlinedButton(onPressed: () => _history(0), child: const Text('کل فروش ها F2')),
          OutlinedButton(onPressed: () => _history(1), child: const Text('کل فروش های طرف حساب F3')),
          OutlinedButton(onPressed: () => _history(2), child: const Text('کل خرید ها F4')),
        ]),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
          FilledButton(onPressed: _ok, child: const Text('تایید F9')),
        ],
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InputDecorator(decoration: const InputDecoration(labelText: 'واحد'), child: Text(p.unit)),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'آخرین فی خرید'),
                child: Align(alignment: Alignment.centerLeft, child: Money(lastBuyPrice(s, p))),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Radio<int>(value: i, groupValue: _sel, onChanged: (v) => setState(() => _sel = v ?? 0)),
                    Expanded(
                      child: TextField(
                        controller: _prices[i],
                        autofocus: i == _sel,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        inputFormatters: [MoneyInputFormatter()],
                        onTap: () => setState(() => _sel = i),
                        onSubmitted: (_) => _ok(),
                        decoration: InputDecoration(labelText: 'بهای فروش ${i + 1}', isDense: true),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _step,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    inputFormatters: [MoneyInputFormatter()],
                    decoration: const InputDecoration(labelText: 'حد رند شدن مبلغ', hintText: 'مثلاً ۱۰۰۰'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(tooltip: 'ذخیره بهای فروش در کالا', onPressed: _savePrices, icon: const Icon(Icons.save_outlined)),
              ]),
              const SizedBox(height: 10),
              Text('نحوه رند کردن مبلغ', style: th.textTheme.labelMedium),
              Row(children: [
                Radio<bool>(value: true, groupValue: _roundUp, onChanged: (v) => setState(() => _roundUp = v ?? false)),
                const Text('به بالا'),
                const SizedBox(width: 12),
                Radio<bool>(value: false, groupValue: _roundUp, onChanged: (v) => setState(() => _roundUp = v ?? false)),
                const Text('به پایین'),
              ]),
              const SizedBox(height: 8),
              Text('نتیجه: ${groupDigits(roundPrice(parseMoney(_prices[_sel].text), parseMoney(_step.text), up: _roundUp))}',
                  style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('توجه: رند کردن مبلغ بر روی فی انتخاب شده اعمال می‌شود.',
                  style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.error)),
            ]),
          ),
        ]),
      ),
    );
  }
}
