/// «ترازو»: weighted EAN-13 barcodes («ساخت بارکد وزنی») and the PLU file
/// sent to label scales («حافظه ترازو» / «مدیریت ساخت فایل ترازو»).
library;

import '../core/jalali.dart' show normalizeDigits;
import 'models.dart';
import 'store.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v, int d) => v is num ? v.toInt() : int.tryParse('$v') ?? d;

class ScaleConfig {
  List<String> prefixes; // e.g. 20..29
  int codeDigits; // PLU digits after the prefix
  int valueDigits; // weight (grams) or price digits
  bool valueIsPrice;
  ScaleConfig({List<String>? prefixes, this.codeDigits = 5, this.valueDigits = 5, this.valueIsPrice = false}) : prefixes = prefixes ?? ['20', '21', '22', '23', '24', '25', '26', '27', '28', '29'];
  Map<String, dynamic> toJson() => {'prefixes': prefixes, 'codeDigits': codeDigits, 'valueDigits': valueDigits, 'valueIsPrice': valueIsPrice};
  factory ScaleConfig.fromJson(Map<String, dynamic> j) => ScaleConfig(
        prefixes: j['prefixes'] is List ? [for (final x in j['prefixes'] as List) '$x'] : null,
        codeDigits: _i(j['codeDigits'], 5),
        valueDigits: _i(j['valueDigits'], 5),
        valueIsPrice: j['valueIsPrice'] == true,
      );
}

int ean13Check(String twelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = twelve.codeUnitAt(i) - 48;
    sum += i.isOdd ? d * 3 : d;
  }
  return (10 - sum % 10) % 10;
}

/// (PLU, value) of a weighted barcode, or null.
(String, int)? parseWeighted(String code, ScaleConfig c) {
  final t = normalizeDigits(code.trim());
  if (t.length != 13 || !RegExp(r'^\d{13}$').hasMatch(t)) return null;
  final pre = c.prefixes.where((p) => t.startsWith(p)).firstOrNull;
  if (pre == null) return null;
  if (ean13Check(t.substring(0, 12)) != int.parse(t[12])) return null;
  final plu = t.substring(pre.length, pre.length + c.codeDigits);
  final v = t.substring(pre.length + c.codeDigits, (pre.length + c.codeDigits + c.valueDigits).clamp(0, 12));
  return (plu, int.parse(v));
}

/// Builds a weighted barcode (for tests and printed labels).
String makeWeighted(String prefix, String plu, int value, ScaleConfig c) {
  final body = '$prefix${plu.padLeft(c.codeDigits, '0')}${value.toString().padLeft(c.valueDigits, '0')}';
  final twelve = body.padRight(12, '0').substring(0, 12);
  return '$twelve${ean13Check(twelve)}';
}

String pluOf(Product p) => (p.info['plu'] ?? '').isNotEmpty ? p.info['plu']! : p.code;

extension ScaleStore on AppStore {
  /// A scanned code: exact code / barcode, or a weighted barcode → (product, qty in unit 1).
  (Product, double?)? matchScan(String text) {
    final t = normalizeDigits(text.trim());
    if (t.isEmpty) return null;
    for (final p in products.where((p) => !p.archived)) {
      final codes = [p.code, p.info['barcode'] ?? '', ...(p.info['barcodes'] ?? '').split(',')].map((e) => normalizeDigits(e.trim()));
      if (codes.contains(t)) return (p, null);
    }
    final w = parseWeighted(t, scale);
    if (w == null) return null;
    final p = products.where((p) => !p.archived && (pluOf(p) == w.$1 || int.tryParse(pluOf(p)) == int.tryParse(w.$1))).firstOrNull;
    if (p == null) return null;
    if (scale.valueIsPrice) return (p, p.sellPrice <= 0 ? 1 : w.$2 / p.sellPrice);
    return (p, w.$2 / 1000); // grams → kg
  }

  /// «تعیین کالاهایی که به حافظه ترازو انتقال پیدا می کند»: products flagged
  /// `info['scale'] == '1'`, as CSV (PLU, name, price per unit, unit).
  String scaleFile() {
    final b = StringBuffer('PLU,Name,Price,Unit,Code\r\n');
    for (final p in products.where((p) => !p.archived && p.info['scale'] == '1')) {
      final name = p.name.replaceAll(',', ' ');
      b.write('${pluOf(p)},$name,${p.sellPrice},${p.unit},${p.code}\r\n');
    }
    return b.toString();
  }
}

String scaleSummary(ScaleConfig c) => 'پیشوند ${c.prefixes.join('،')} — ${c.codeDigits} رقم کد — ${c.valueDigits} رقم ${c.valueIsPrice ? 'مبلغ' : 'وزن (گرم)'}';

// keep _s used for future fields
String scaleText(Object? v) => _s(v);
