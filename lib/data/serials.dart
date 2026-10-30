/// «سریال های کالا» and «کالا با مشخصه» — serial tracking and attribute
/// variants (رنگ، سایز…) of products, computed from invoice rows.
library;

import 'models.dart';
import 'store.dart';

/// Product attributes stored as `info['attrs']` = «رنگ=قرمز,آبی;سایز=S,M».
List<(String, List<String>)> productAttrs(Product p) {
  final raw = p.info['attrs'] ?? '';
  final out = <(String, List<String>)>[];
  for (final part in raw.split(';')) {
    final kv = part.split('=');
    if (kv.length != 2 || kv[0].trim().isEmpty) continue;
    final vals = kv[1].split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    if (vals.isNotEmpty) out.add((kv[0].trim(), vals));
  }
  return out;
}

String encodeAttrs(List<(String, List<String>)> a) => a.map((x) => '${x.$1}=${x.$2.join(',')}').join(';');

/// Every combination of the attribute values, e.g. «قرمز / S».
List<String> productVariants(Product p) {
  var combos = <String>[''];
  for (final (_, vals) in productAttrs(p)) {
    combos = [for (final c in combos) for (final v in vals) c.isEmpty ? v : '$c / $v'];
  }
  return combos.where((c) => c.isNotEmpty).toList();
}

bool tracksSerial(Product? p) => p?.info['serial'] == '1';

/// Serials of the opening stock (`info['openSerials']`, comma separated).
List<String> openingSerials(Product p) => (p.info['openSerials'] ?? '').split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

class SerialMove {
  final String serial;
  final Invoice invoice;
  final InvoiceLine line;
  SerialMove(this.serial, this.invoice, this.line);
  bool get inbound => invoice.kind.stockSign > 0;
}

extension SerialStore on AppStore {
  /// Stock of one «مشخصه» of a product.
  double variantStock(String productId, String variant, {String? excludeInvoiceId}) {
    final p = product(productId);
    var q = double.tryParse(p?.info['vopen:$variant'] ?? '') ?? 0;
    for (final inv in realInvoices) {
      if (inv.id == excludeInvoiceId) continue;
      for (final l in inv.lines) {
        if (l.productId == productId && l.variant == variant) q += inv.kind.stockSign * l.qty;
      }
    }
    return q;
  }

  /// All movements of serials (oldest first), optionally for one product.
  List<SerialMove> serialMoves({String? productId, String? serial}) {
    final out = <SerialMove>[];
    final list = [...realInvoices]..sort((a, b) => a.date.compareTo(b.date) != 0 ? a.date.compareTo(b.date) : a.createdAt.compareTo(b.createdAt));
    for (final inv in list) {
      for (final l in inv.lines) {
        if (productId != null && l.productId != productId) continue;
        for (final sn in l.serials) {
          if (serial == null || sn == serial) out.add(SerialMove(sn, inv, l));
        }
      }
    }
    return out;
  }

  /// Serials currently in stock (value: the inbound move, null = opening stock).
  Map<String, SerialMove?> serialsInStock({String? productId, String? excludeInvoiceId}) {
    final last = <String, SerialMove>{};
    for (final m in serialMoves(productId: productId)) {
      if (m.invoice.id == excludeInvoiceId) continue;
      last['${m.line.productId}|${m.serial}'] = m;
    }
    final out = <String, SerialMove?>{};
    for (final p in products.where((p) => productId == null || p.id == productId)) {
      for (final sn in openingSerials(p)) {
        if (!last.containsKey('${p.id}|$sn')) out[sn] = null;
      }
    }
    for (final e in last.entries) {
      if (e.value.inbound) out[e.key.split('|').last] = e.value;
    }
    return out;
  }

  /// «انتقال بین سریال»: the serial [from] in invoice [invoiceId] becomes [to].
  bool swapSerial(String invoiceId, String from, String to) {
    final inv = invoices.where((i) => i.id == invoiceId).firstOrNull;
    if (inv == null) return false;
    for (final l in inv.lines) {
      final i = l.serials.indexOf(from);
      if (i >= 0) {
        l.serials[i] = to;
        saveInvoice(inv);
        return true;
      }
    }
    return false;
  }

  /// Checks the serials of an invoice before saving; returns an error or null.
  String? checkSerials(Invoice inv) {
    final seen = <String>{};
    for (final l in inv.lines) {
      final p = product(l.productId);
      if (!tracksSerial(p)) continue;
      if (l.serials.length != l.qty.round()) return 'تعداد سریال های ${p!.name} (${l.serials.length}) با تعداد ردیف (${l.qty.round()}) برابر نیست';
      final inStock = serialsInStock(productId: p!.id, excludeInvoiceId: inv.id);
      for (final sn in l.serials) {
        if (!seen.add('${p.id}|$sn')) return 'سریال $sn تکراری است';
        final there = inStock.containsKey(sn);
        if (inv.kind.stockSign < 0 && !there) return 'سریال $sn از ${p.name} در انبار نیست';
        if (inv.kind.stockSign > 0 && there) return 'سریال $sn از ${p.name} از قبل در انبار است';
      }
    }
    return null;
  }
}
