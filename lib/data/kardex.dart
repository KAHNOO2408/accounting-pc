import 'chart.dart';
import 'journal.dart';
import 'models.dart';
import 'store.dart';

/// One row of a product's کاردکس (moving-average method).
class KardexRow {
  final String docKey; // 'inv:id' / 'adj:id' / 'tr:id' / 'open'
  final int? number; // شماره سند
  final DateTime date;
  final String desc;
  final double qty; // signed
  final int fi; // unit cost
  final int total; // signed value of the movement
  final String warehouse;
  final Invoice? invoice;
  final int order;
  double balance = 0; // running quantity
  int value = 0; // running value
  int avg = 0; // running average cost after this row

  KardexRow({
    required this.docKey,
    this.number,
    required this.date,
    required this.desc,
    required this.qty,
    this.fi = 0,
    this.total = 0,
    this.warehouse = '',
    this.invoice,
    this.order = 0,
  });
}

String invoiceDesc(AppStore s, Invoice inv) {
  final who = s.person(inv.personId)?.name ?? (inv.info['buyerName']?.isNotEmpty == true ? inv.info['buyerName']! : 'متفرقه');
  final word = switch (inv.kind) {
    InvoiceKind.sale => 'فروش به',
    InvoiceKind.purchase => 'خرید از',
    InvoiceKind.saleReturn => 'برگشت از فروش',
    InvoiceKind.purchaseReturn => 'برگشت از خرید به',
  };
  return 'فاکتور ${inv.number}  $word  $who';
}

/// Builds the کاردکس of [productId] (all warehouses, or one with [warehouseId]).
List<KardexRow> buildKardex(AppStore s, String productId, {String? warehouseId}) {
  final p = s.product(productId);
  if (p == null) return [];
  final w = warehouseId;
  bool inW(String? id) => w == null || s.whId(id) == w;
  final raw = <KardexRow>[];
  for (final inv in s.realInvoices) {
    final sub = inv.subtotal;
    for (final l in inv.lines) {
      if (l.productId != productId || !inW(l.warehouseId)) continue;
      final share = sub == 0 ? 0 : (inv.discount * l.total / sub).round();
      final net = l.total - share;
      raw.add(KardexRow(
        docKey: 'inv:${inv.id}',
        number: s.docNumberOf('inv:${inv.id}') ?? inv.number,
        date: inv.date,
        desc: invoiceDesc(s, inv),
        qty: inv.kind.stockSign * l.qty,
        // purchases enter at their net price; the others are valued in the second pass
        fi: inv.kind == InvoiceKind.purchase && l.qty != 0 ? (net / l.qty).round() : -1,
        total: inv.kind == InvoiceKind.purchase ? net : 0,
        warehouse: s.warehouse(l.warehouseId)?.name ?? '',
        invoice: inv,
        order: inv.createdAt,
      ));
    }
  }
  for (final a in s.adjusts) {
    if (a.productId != productId || !inW(a.warehouseId)) continue;
    raw.add(KardexRow(
      docKey: 'adj:${a.id}',
      date: a.date,
      desc: a.reason.label + (a.note.isEmpty ? '' : ' — ${a.note}'),
      qty: a.qty,
      fi: -1,
      warehouse: s.warehouse(a.warehouseId)?.name ?? '',
      order: a.createdAt,
    ));
  }
  if (w != null) {
    for (final t in s.transfers) {
      for (final l in t.lines) {
        if (l.productId != productId) continue;
        if (s.whId(t.fromId) == w) {
          raw.add(KardexRow(
              docKey: 'tr:${t.id}', number: t.number, date: t.date, desc: 'انتقال به ${s.warehouse(l.toId)?.name ?? ''}', qty: -l.qty, fi: -1,
              warehouse: s.warehouse(t.fromId)?.name ?? '', order: t.createdAt));
        }
        if (s.whId(l.toId) == w) {
          raw.add(KardexRow(
              docKey: 'tr:${t.id}', number: t.number, date: t.date, desc: 'انتقال از ${s.warehouse(t.fromId)?.name ?? ''}', qty: l.qty, fi: -1,
              warehouse: s.warehouse(l.toId)?.name ?? '', order: t.createdAt));
        }
      }
    }
  }
  raw.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.order.compareTo(b.order);
  });

  final out = <KardexRow>[];
  var qty = 0.0;
  var value = 0;
  final openQty = inW(null) ? p.openingQty : 0.0;
  if (openQty != 0) {
    final c = s.openingCost(p) > 0 ? s.openingCost(p) : p.buyPrice;
    final r = KardexRow(
      docKey: 'open',
      date: DateTime(1900),
      desc: 'موجودی اول دوره',
      qty: openQty,
      fi: c,
      total: (openQty * c).round(),
      warehouse: s.warehouse(null)?.name ?? '',
    );
    qty = openQty;
    value = r.total;
    r
      ..balance = qty
      ..value = value
      ..avg = c;
    out.add(r);
  }
  for (final r in raw) {
    final avg = qty > 0 ? (value / qty).round() : p.buyPrice;
    final fi = r.fi >= 0 ? r.fi : avg;
    final total = r.fi >= 0 ? r.total : (r.qty * fi).round();
    final row = KardexRow(
      docKey: r.docKey,
      number: r.number,
      date: r.date,
      desc: r.desc,
      qty: r.qty,
      fi: fi,
      total: total,
      warehouse: r.warehouse,
      invoice: r.invoice,
      order: r.order,
    );
    qty += r.qty;
    value += total;
    if (qty.abs() < 1e-9) value = 0;
    row
      ..balance = qty
      ..value = value
      ..avg = qty > 0 ? (value / qty).round() : fi;
    out.add(row);
  }
  return out;
}

/// کنترل کاردکس — the first row where each product's stock goes negative.
List<(Product, KardexRow)> negativeKardexes(AppStore s) {
  final out = <(Product, KardexRow)>[];
  for (final p in s.productsSorted) {
    if (p.info['noNegCheck'] == '1') continue;
    final ws = s.warehouses.length > 1 ? [null, ...s.warehouses.map((w) => w.id)] : [null];
    for (final w in ws) {
      final r = buildKardex(s, p.id, warehouseId: w).where((r) => r.balance < -1e-9).firstOrNull;
      if (r != null) {
        out.add((p, r));
        break;
      }
    }
  }
  return out;
}

/// One mismatch between the accounting voucher of a document and the کاردکس.
class KardexCheckRow {
  final Product product;
  final Invoice invoice;
  final int docNo;
  final int docAmount;
  final int kardexNo;
  final int kardexAmount;
  KardexCheckRow(this.product, this.invoice, this.docNo, this.docAmount, this.kardexNo, this.kardexAmount);
}

/// چک کاردکس — compares stock postings of every invoice with its کاردکس value.
List<KardexCheckRow> checkKardex(AppStore s, {bool all = false}) {
  final journal = buildJournal(s);
  final byDoc = <String, int>{};
  for (final p in journal) {
    if (p.moeen != mStock || p.tafsiliId == null) continue;
    final k = '${p.docLabel}|${p.tafsiliId}';
    byDoc[k] = (byDoc[k] ?? 0) + (p.debit - p.credit);
  }
  final out = <KardexCheckRow>[];
  for (final prod in s.productsSorted) {
    final rows = buildKardex(s, prod.id);
    final seen = <String>{};
    for (final r in rows) {
      final inv = r.invoice;
      if (inv == null || !seen.add(inv.id)) continue;
      final kv = rows.where((x) => x.invoice?.id == inv.id).fold<int>(0, (a, x) => a + x.total);
      final dv = byDoc['${inv.kind.label} ${inv.number}|${prod.id}'] ?? 0;
      if (all || kv.abs() != dv.abs()) {
        out.add(KardexCheckRow(prod, inv, inv.number, dv.abs(), r.number ?? inv.number, kv.abs()));
      }
    }
  }
  return out;
}

/// One account whose balance contradicts its nature (گزارش خلاف ماهیت).
class NatureRow {
  final Moeen moeen;
  final String? tafsiliId;
  final String tafsiliName;
  final String tafsiliCode;
  final int balance; // signed on natural side (negative = contra)
  final String breakingDoc;
  NatureRow(this.moeen, this.tafsiliId, this.tafsiliName, this.tafsiliCode, this.balance, this.breakingDoc);
}

List<NatureRow> contraNature(AppStore s, {bool includeStock = true}) {
  final journal = [...buildJournal(s)]..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.order.compareTo(b.order);
    });
  final bal = <String, int>{};
  final breaker = <String, String>{};
  for (final p in journal) {
    final m = findMoeen(p.moeen);
    if (m == null) continue;
    // people may legitimately sit on either side
    if (m.kind == TafsiliKind.person) continue;
    if (m.code == mStock && !includeStock) continue;
    if (m.side == Side.income || m.side == Side.expense) continue;
    final k = '${p.moeen}|${p.tafsiliId ?? ''}';
    final before = bal[k] ?? 0;
    final now = before + (m.debitNature ? p.debit - p.credit : p.credit - p.debit);
    bal[k] = now;
    if (now < 0 && before >= 0) {
      breaker[k] = p.isOpening ? 'افتتاحیه' : (p.docNo != null ? '${p.docNo}' : p.docLabel);
    }
  }
  final out = <NatureRow>[];
  bal.forEach((k, v) {
    if (v >= 0) return;
    final parts = k.split('|');
    final m = findMoeen(parts[0])!;
    final t = parts[1].isEmpty ? null : parts[1];
    final name = t == null ? '' : s.tafsiliName(VoucherLine(moeen: m.code, tafsiliId: t));
    final code = t == null ? '' : (m.kind == TafsiliKind.product ? (s.product(t)?.code ?? '') : (s.account(t)?.number ?? ''));
    out.add(NatureRow(m, t, name, code, v, breaker[k] ?? ''));
  });
  out.sort((a, b) => a.moeen.code.compareTo(b.moeen.code));
  return out;
}
