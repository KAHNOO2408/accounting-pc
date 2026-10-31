/// «ترازو»: weighted EAN-13 barcodes («ساخت بارکد وزنی») and the PLU file
/// sent to label scales («حافظه ترازو» / «مدیریت ساخت فایل ترازو»).
library;

import '../core/jalali.dart';
import 'models.dart';
import 'store.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v, int d) => v is num ? v.toInt() : int.tryParse('$v') ?? d;

class ScaleConfig {
  List<String> prefixes; // e.g. 20..29
  int codeDigits; // PLU digits after the prefix
  int valueDigits; // weight (grams) or price digits
  bool valueIsPrice;

  /// «تعیین کلیدهای ترازو»: key number → product id; [keyCount] 40 or 63.
  Map<String, String> keys = {};
  int keyCount = 40;
  int memory = 6000; // «تعداد حافظه دستگاه»

  ScaleConfig({List<String>? prefixes, this.codeDigits = 5, this.valueDigits = 5, this.valueIsPrice = false}) : prefixes = prefixes ?? ['20', '21', '22', '23', '24', '25', '26', '27', '28', '29'];
  Map<String, dynamic> toJson() => {'prefixes': prefixes, 'codeDigits': codeDigits, 'valueDigits': valueDigits, 'valueIsPrice': valueIsPrice, 'keys': keys, 'keyCount': keyCount, 'memory': memory};
  factory ScaleConfig.fromJson(Map<String, dynamic> j) => ScaleConfig(
        prefixes: j['prefixes'] is List ? [for (final x in j['prefixes'] as List) '$x'] : null,
        codeDigits: _i(j['codeDigits'], 5),
        valueDigits: _i(j['valueDigits'], 5),
        valueIsPrice: j['valueIsPrice'] == true,
      )
        ..keys = j['keys'] is Map ? {for (final e in (j['keys'] as Map).entries) '${e.key}': '${e.value}'} : {}
        ..keyCount = _i(j['keyCount'], 40)
        ..memory = _i(j['memory'], 6000);
}

/// A row of «لیست فاکتورهای ثبت شده در ترازو».
class ScaleSaleRow {
  final String scaleNo; // شماره ترازو
  final String invoiceNo; // شماره فاکتور ترازو
  final DateTime date;
  final String code; // PLU / بارکد / کد کالا
  final double qty; // تعداد / وزن (کیلوگرم)
  final int unitPrice;
  final int total;
  const ScaleSaleRow({required this.scaleNo, required this.invoiceNo, required this.date, required this.code, required this.qty, required this.unitPrice, required this.total});
  String get ref => '$scaleNo:$invoiceNo';
}

/// Reads the scale's sales export: scale no, invoice no, date [time], code,
/// quantity/weight, unit price, total (header row optional; comma/tab/semicolon).
List<ScaleSaleRow> parseScaleSales(List<List<String>> rows) {
  final out = <ScaleSaleRow>[];
  for (final r in rows) {
    final c = r.map((x) => normalizeDigits(x.trim())).toList();
    if (c.length < 6 || int.tryParse(c[0]) == null) continue;
    final dm = RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?').firstMatch(c[2]);
    if (dm == null) continue;
    final y = int.parse(dm[1]!), mo = int.parse(dm[2]!), d = int.parse(dm[3]!);
    var date = y < 1700 ? Jalali(y, mo, d).toDateTime() : DateTime(y, mo, d);
    if (dm[4] != null) date = DateTime(date.year, date.month, date.day, int.parse(dm[4]!), int.parse(dm[5]!));
    final qty = double.tryParse(c[4]) ?? 0;
    final unit = (double.tryParse(c[5]) ?? 0).round();
    final total = c.length > 6 ? (double.tryParse(c[6]) ?? 0).round() : (qty * unit).round();
    out.add(ScaleSaleRow(scaleNo: c[0], invoiceNo: c[1], date: date, code: c[3], qty: qty, unitPrice: unit, total: total));
  }
  return out;
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

  /// Products sent to the scale («حافظه ترازو»), by memory number.
  List<Product> scaleProducts() => products.where((p) => !p.archived && p.info['scale'] == '1').toList()
    ..sort((a, b) => (int.tryParse(pluOf(a)) ?? 0).compareTo(int.tryParse(pluOf(b)) ?? 0));

  /// «ساخت فایل LSG» (and «ذخیره برای مدل Vista Plus» with [vista]): one
  /// tab-separated line per memory: PLU, code, name, unit price, type
  /// (0 وزنی / 1 تعدادی), shelf days, print expiry, barcode.
  String lsgFile({bool vista = false}) {
    final sep = vista ? ';' : '\t';
    final b = StringBuffer();
    for (final p in scaleProducts()) {
      final type = p.info['scaleType'] == 'n' ? 1 : 0;
      b.write([pluOf(p), p.code, p.name.replaceAll(RegExp('[\t;\r\n]'), ' '), p.sellPrice, type, p.info['shelfDays'] ?? '0', p.info['printExpiry'] == '1' ? 1 : 0, p.info['barcode'] ?? ''].join(sep));
      b.write('\r\n');
    }
    return b.toString();
  }

  /// «تعیین کلیدهای ترازو» file: key number, PLU.
  String keysFile() {
    final b = StringBuffer();
    final ks = scale.keys.keys.map(int.tryParse).whereType<int>().toList()..sort();
    for (final k in ks) {
      final p = product(scale.keys['$k']);
      if (p != null) b.write('$k\t${pluOf(p)}\r\n');
    }
    return b.toString();
  }

  /// Turns the scale's invoices into sale invoices (once per scale invoice).
  /// Returns (invoices made, unknown codes).
  (int, Set<String>) importScaleSales(List<ScaleSaleRow> rows, {String? accountId}) {
    final done = {for (final i in invoices) if ((i.info['scaleRef'] ?? '').isNotEmpty) i.info['scaleRef']!};
    final groups = <String, List<ScaleSaleRow>>{};
    for (final r in rows) {
      if (!done.contains(r.ref)) (groups[r.ref] ??= []).add(r);
    }
    final unknown = <String>{};
    var n = 0;
    for (final g in groups.values) {
      final lines = <InvoiceLine>[];
      for (final r in g) {
        final p = products.where((p) => pluOf(p) == r.code || int.tryParse(pluOf(p)) == int.tryParse(r.code) || p.code == r.code || (p.info['barcode'] ?? '') == r.code).firstOrNull ??
            matchScan(r.code)?.$1;
        if (p == null) {
          unknown.add(r.code);
          continue;
        }
        lines.add(InvoiceLine(productId: p.id, qty: r.qty, unitPrice: r.unitPrice == 0 ? p.sellPrice : r.unitPrice));
      }
      if (lines.isEmpty) continue;
      final inv = Invoice(
        id: newId(),
        kind: InvoiceKind.sale,
        number: nextInvoiceNumber(InvoiceKind.sale),
        date: g.first.date,
        lines: lines,
        accountId: accountId,
        note: 'فاکتور ترازو ${g.first.scaleNo} شماره ${g.first.invoiceNo}',
        info: {'scaleRef': g.first.ref},
      );
      inv.paid = accountId == null ? 0 : inv.total;
      saveInvoice(inv);
      n++;
    }
    return (n, unknown);
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
