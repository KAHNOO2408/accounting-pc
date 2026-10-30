/// «فرمول های تغییر نرخ»، «ساخت نام و بارکد استاندارد» و «سند ترکیبی عملیات
/// یک روز یا یک ماه».
library;

import 'chart.dart';
import 'journal.dart';
import 'models.dart';
import 'scale.dart' show ean13Check;
import 'store.dart';

enum PriceField { buy, sell1, sell2, sell3 }

extension PriceFieldX on PriceField {
  String get label => switch (this) {
        PriceField.buy => 'بهای خرید',
        PriceField.sell1 => 'بهای فروش ۱',
        PriceField.sell2 => 'بهای فروش ۲',
        PriceField.sell3 => 'بهای فروش ۳',
      };
  int of(Product p) => switch (this) { PriceField.buy => p.buyPrice, PriceField.sell1 => p.sellPrice, PriceField.sell2 => p.sellPrice2, PriceField.sell3 => p.sellPrice3 };
  void set(Product p, int v) {
    switch (this) {
      case PriceField.buy:
        p.buyPrice = v;
      case PriceField.sell1:
        p.sellPrice = v;
      case PriceField.sell2:
        p.sellPrice2 = v;
      case PriceField.sell3:
        p.sellPrice3 = v;
    }
  }
}

enum PriceMode { percent, amount, marginOnBuy, marginOnCost, fixed }

extension PriceModeX on PriceMode {
  String get label => switch (this) {
        PriceMode.percent => 'درصد افزایش/کاهش',
        PriceMode.amount => 'مبلغ افزایش/کاهش',
        PriceMode.marginOnBuy => 'بهای خرید + درصد سود',
        PriceMode.marginOnCost => 'قیمت تمام شده + درصد سود',
        PriceMode.fixed => 'مبلغ ثابت',
      };
}

/// New price of [p] for the formula; [round] rounds up to a multiple (0 = none).
int formulaPrice(AppStore s, Product p, PriceField f, PriceMode m, double value, {int round = 0}) {
  final cur = f.of(p);
  var v = switch (m) {
    PriceMode.percent => cur * (1 + value / 100),
    PriceMode.amount => cur + value,
    PriceMode.marginOnBuy => p.buyPrice * (1 + value / 100),
    PriceMode.marginOnCost => s.avgCost(p.id) * (1 + value / 100),
    PriceMode.fixed => value,
  };
  if (v < 0) v = 0;
  var r = v.round();
  if (round > 0 && r % round != 0) r = (r ~/ round + 1) * round;
  return r;
}

extension ToolsStore on AppStore {
  int applyPriceFormula(List<Product> list, PriceField f, PriceMode m, double value, {int round = 0}) {
    var n = 0;
    for (final p in list) {
      final v = formulaPrice(this, p, f, m, value, round: round);
      if (v == f.of(p)) continue;
      f.set(p, v);
      n++;
    }
    updateSettings((_) {});
    return n;
  }

  /// Gives every product without a barcode an internal EAN-13 (200 + code).
  int makeStandardBarcodes() {
    var n = 0;
    final used = {for (final p in products) p.info['barcode'] ?? ''};
    for (final p in products.where((p) => (p.info['barcode'] ?? '').isEmpty)) {
      final digits = p.code.replaceAll(RegExp(r'\D'), '');
      var body = '200${(digits.isEmpty ? '${p.hashCode % 1000000000}' : digits).padLeft(9, '0')}';
      if (body.length > 12) body = body.substring(body.length - 12);
      var code = '$body${ean13Check(body)}';
      var k = 0;
      while (used.contains(code) && k < 1000) {
        k++;
        final b2 = '201${(int.parse(body.substring(3)) + k).toString().padLeft(9, '0')}';
        code = '$b2${ean13Check(b2)}';
      }
      p.info['barcode'] = code;
      used.add(code);
      n++;
    }
    updateSettings((_) {});
    return n;
  }
}

/// «سند ترکیبی»: postings of a range summed per ledger: (code, name, debit, credit).
List<(String, String, int, int)> combinedVoucher(AppStore s, DateTime from, DateTime to) {
  final m = <String, (int, int)>{};
  for (final p in buildJournal(s)) {
    if (p.isOpening || p.date.isBefore(from) || p.date.isAfter(to)) continue;
    final o = m[p.moeen] ?? (0, 0);
    m[p.moeen] = (o.$1 + p.debit, o.$2 + p.credit);
  }
  final keys = m.keys.toList()..sort();
  return [for (final k in keys) (k, findMoeen(k)?.name ?? k, m[k]!.$1, m[k]!.$2)];
}
