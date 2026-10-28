import 'package:flutter_test/flutter_test.dart';
import 'package:taraz/data/margin.dart';

void main() {
  test('below cost is a loss', () {
    final c = checkMargin(qty: 2, unitPrice: 900, unitCost: 1000);
    expect(c.level, MarginLevel.loss);
    expect(c.unitProfit, -100);
  });

  test('row discount lowers the net unit price', () {
    // 2 × 1100 − 400 = 1800 → 900 per unit, below a 1000 cost
    final c = checkMargin(qty: 2, unitPrice: 1100, discount: 400, unitCost: 1000);
    expect(c.unitNet, 900);
    expect(c.level, MarginLevel.loss);
  });

  test('minimum margin flags thin profits only when set', () {
    expect(checkMargin(qty: 1, unitPrice: 1030, unitCost: 1000).level, MarginLevel.ok);
    expect(checkMargin(qty: 1, unitPrice: 1030, unitCost: 1000, minPct: 5).level, MarginLevel.low);
    expect(checkMargin(qty: 1, unitPrice: 1100, unitCost: 1000, minPct: 5).level, MarginLevel.ok);
  });

  test('unknown cost or empty row is not judged', () {
    expect(checkMargin(qty: 1, unitPrice: 500, unitCost: 0).level, MarginLevel.unknown);
    expect(checkMargin(qty: 0, unitPrice: 500, unitCost: 100).level, MarginLevel.unknown);
  });
}
