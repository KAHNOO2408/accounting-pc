import 'models.dart';
import 'store.dart';

/// کنترل سود فروش — like Sakan's «هشدار در هنگام فروش کالا زیر قیمت خرید»
/// and its report of goods «که با ضرر یا سود کم در حال فروش هستند».
enum MarginLevel { unknown, ok, low, loss }

class MarginCheck {
  /// Net unit sale price (after the row discount).
  final int unitNet;

  /// Unit cost used for the comparison (0 = unknown).
  final int unitCost;
  final MarginLevel level;
  const MarginCheck(this.unitNet, this.unitCost, this.level);

  int get unitProfit => unitNet - unitCost;

  /// Profit as a percent of the sale price (null when it can't be computed).
  double? get pct => unitCost <= 0 ? null : (unitNet <= 0 ? -100 : unitProfit * 100 / unitNet);

  bool get bad => level == MarginLevel.loss || level == MarginLevel.low;
}

/// Classifies one sale row. [minPct] is the lowest acceptable profit as a
/// percent of the sale price; 0 means only selling below cost is flagged.
MarginCheck checkMargin({required double qty, required int unitPrice, int discount = 0, required int unitCost, double minPct = 0}) {
  if (qty <= 0 || unitPrice <= 0) return MarginCheck(0, unitCost, MarginLevel.unknown);
  final unitNet = ((qty * unitPrice - discount) / qty).round();
  if (unitCost <= 0) return MarginCheck(unitNet, 0, MarginLevel.unknown);
  if (unitNet < unitCost) return MarginCheck(unitNet, unitCost, MarginLevel.loss);
  if (minPct > 0 && (unitNet - unitCost) * 100 < minPct * unitNet) {
    return MarginCheck(unitNet, unitCost, MarginLevel.low);
  }
  return MarginCheck(unitNet, unitCost, MarginLevel.ok);
}

/// One sale row found by [AppStore.lowMarginSales].
class LowMarginRow {
  final Invoice invoice;
  final InvoiceLine line;
  final MarginCheck check;
  const LowMarginRow(this.invoice, this.line, this.check);

  /// Total profit (negative = loss) of the row.
  int get profit => (check.unitProfit * line.shownQty).round();
}

extension MarginStore on AppStore {
  /// Unit cost for the margin check: weighted average purchase cost, falling
  /// back to the product's buy price when it was never purchased.
  int marginCost(String? productId) {
    if (productId == null) return 0;
    final avg = avgCost(productId);
    if (avg > 0) return avg;
    return product(productId)?.buyPrice ?? 0;
  }

  MarginCheck checkLine(InvoiceLine l) => checkMargin(
        qty: l.shownQty,
        unitPrice: l.shownFi,
        discount: l.discount,
        unitCost: (marginCost(l.productId) * (l.inOtherUnit ? l.qty / l.unitQty : 1)).round(),
        minPct: settings.minMarginPct,
      );

  /// Sale rows in [from]..[to] sold at a loss or below the minimum margin,
  /// worst first.
  List<LowMarginRow> lowMarginSales(DateTime from, DateTime to) {
    final out = <LowMarginRow>[];
    final cache = <String, int>{};
    for (final inv in realInvoices) {
      if (inv.kind != InvoiceKind.sale) continue;
      if (inv.date.isBefore(from) || inv.date.isAfter(to)) continue;
      for (final l in inv.lines) {
        final id = l.productId;
        if (id == null) continue;
        final c = checkMargin(
          qty: l.shownQty,
          unitPrice: l.shownFi,
          discount: l.discount,
          unitCost: (cache.putIfAbsent(id, () => marginCost(id)) * (l.inOtherUnit ? l.qty / l.unitQty : 1)).round(),
          minPct: settings.minMarginPct,
        );
        if (c.bad) out.add(LowMarginRow(inv, l, c));
      }
    }
    out.sort((a, b) => (a.check.pct ?? 0).compareTo(b.check.pct ?? 0));
    return out;
  }
}
