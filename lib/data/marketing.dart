import '../core/jalali.dart';
import 'models.dart';
import 'store.dart';

/// «بازاریابان و پورسانت» — Sakan's marketers and commission.
///
/// A sale's «تیم بازاریابی» lists marketers (person accounts). Each gets a
/// fixed amount, or a percent of the invoice («درصد بازاریابی»), or — with
/// neither — the products' own «درصد بازاریابی» shared equally. The total is
/// «هزینه پورسانت», posted as the seller's expense to the marketers' accounts.

/// «درصد بازاریابی» set on a product.
double productMarketingPct(Product? p) => double.tryParse(p?.info['marketingPct'] ?? '') ?? 0;

class CommissionRow {
  final Invoice invoice;
  final String marketerId;
  final double pct;
  final int amount;
  const CommissionRow(this.invoice, this.marketerId, this.pct, this.amount);

  /// Sales count positive, returns negative.
  int get signed => invoice.kind == InvoiceKind.saleReturn ? -amount : amount;
}

class MarketerSales {
  final String marketerId;
  final String period; // day or month (Jalali)
  int invoices = 0;
  int sales = 0;
  int returns = 0;
  int commission = 0;
  MarketerSales(this.marketerId, this.period);
  int get net => sales - returns;
}

extension MarketingStore on AppStore {
  List<Person> get marketers => peopleSorted.where((p) => p.marketer).toList();

  /// «سهم بازاریابی» of one row from the product's percent.
  int rowCommission(InvoiceLine l) => (l.total * productMarketingPct(product(l.productId)) / 100).round();

  /// Commission of each marketer of [inv] (percent, amount).
  List<(MarketerShare, double, int)> commissions(Invoice inv) {
    if (inv.kind != InvoiceKind.sale && inv.kind != InvoiceKind.saleReturn) return const [];
    final base = inv.subtotal - inv.discount;
    final byProduct = inv.lines.fold<int>(0, (a, l) => a + rowCommission(l));
    final auto = inv.marketers.where((m) => m.amount == 0 && m.pct == 0).length;
    return [
      for (final m in inv.marketers)
        if (m.amount != 0)
          (m, base == 0 ? 0.0 : m.amount * 100 / base, m.amount)
        else if (m.pct != 0)
          (m, m.pct, (base * m.pct / 100).round())
        else
          (m, base == 0 ? 0.0 : byProduct / auto * 100 / base, (byProduct / auto).round()),
    ];
  }

  /// «هزینه پورسانت» of an invoice.
  int commissionTotal(Invoice inv) => commissions(inv).fold(0, (a, c) => a + c.$3);

  /// «گزارش پورسانت»: every marketer share in [from]..[to].
  List<CommissionRow> commissionReport(DateTime from, DateTime to, {String? marketerId}) {
    final out = <CommissionRow>[];
    for (final inv in realInvoices) {
      if (inv.date.isBefore(from) || inv.date.isAfter(to)) continue;
      for (final (m, pct, amount) in commissions(inv)) {
        if (marketerId != null && m.personId != marketerId) continue;
        out.add(CommissionRow(inv, m.personId, pct, amount));
      }
    }
    out.sort((a, b) => a.invoice.date.compareTo(b.invoice.date));
    return out;
  }

  /// «فروش بازاریاب» per day or month.
  List<MarketerSales> salesByMarketer(DateTime from, DateTime to, {bool monthly = false}) {
    final map = <String, MarketerSales>{};
    for (final r in commissionReport(from, to)) {
      final j = Jalali.fromDateTime(r.invoice.date);
      final period = monthly ? '${j.year}/${j.month.toString().padLeft(2, '0')}' : j.format();
      final row = map.putIfAbsent('${r.marketerId}|$period', () => MarketerSales(r.marketerId, period));
      final net = r.invoice.subtotal - r.invoice.discount;
      if (r.invoice.kind == InvoiceKind.saleReturn) {
        row.returns += net;
      } else {
        row.sales += net;
        row.invoices++;
      }
      row.commission += r.signed;
    }
    final out = map.values.toList()
      ..sort((a, b) {
        final c = a.period.compareTo(b.period);
        return c != 0 ? c : (person(a.marketerId)?.name ?? '').compareTo(person(b.marketerId)?.name ?? '');
      });
    return out;
  }
}
