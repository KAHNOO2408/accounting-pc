import '../core/jalali.dart';
import 'chart.dart';
import 'models.dart';
import 'store.dart';

/// One double-entry posting derived from the app data.
class Posting {
  final DateTime date;
  final String moeen;
  final String? tafsiliId;
  final String docLabel;
  final int? docNo; // manual voucher number, invoice number…
  final bool isVoucher;
  final bool isOpening;
  final String desc;
  final int debit;
  final int credit;
  final int order;

  const Posting({
    required this.date,
    required this.moeen,
    this.tafsiliId,
    required this.docLabel,
    this.docNo,
    this.isVoucher = false,
    this.isOpening = false,
    this.desc = '',
    this.debit = 0,
    this.credit = 0,
    this.order = 0,
  });

  String get kol => moeen.substring(0, 3);
}

/// Builds the full journal (دفتر روزنامه) from every document in the store.
/// Each document produces balanced postings.
List<Posting> buildJournal(AppStore s) {
  final out = <Posting>[];
  final openDate = s.settings.openingDate ?? DateTime(2000);

  void pair(
    DateTime d,
    String label,
    String desc,
    int amount, {
    required String drM,
    String? drT,
    required String crM,
    String? crT,
    int? no,
    int order = 0,
  }) {
    if (amount == 0) return;
    if (amount < 0) {
      pair(d, label, desc, -amount, drM: crM, drT: crT, crM: drM, crT: drT, no: no, order: order);
      return;
    }
    out.add(Posting(date: d, moeen: drM, tafsiliId: drT, docLabel: label, docNo: no, desc: desc, debit: amount, order: order));
    out.add(Posting(date: d, moeen: crM, tafsiliId: crT, docLabel: label, docNo: no, desc: desc, credit: amount, order: order));
  }

  String accM(String? id) {
    final a = s.account(id);
    if (a == null) return mOtherLiab;
    return a.type == AccountType.cash ? mCash : mBank;
  }

  // ------------------------------------------------------------- opening
  void op(String moeen, String? t, int v, String desc) {
    if (v == 0) return;
    final m = findMoeen(moeen)!;
    final dr = m.debitNature == (v > 0);
    out.add(Posting(
      date: openDate,
      moeen: moeen,
      tafsiliId: t,
      docLabel: 'سند افتتاحیه',
      isOpening: true,
      desc: desc,
      debit: dr ? v.abs() : 0,
      credit: dr ? 0 : v.abs(),
      order: -1,
    ));
  }

  var assets = 0;
  var liabs = 0;
  for (final a in s.accounts) {
    op(accM(a.id), a.id, a.opening, 'موجودی اول دوره');
    assets += a.opening;
  }
  for (final p in s.people) {
    op(mDebtorsTrade, p.id, p.opening, 'مانده اول دوره');
    assets += p.opening;
  }
  for (final p in s.products) {
    final v = (p.openingQty * s.openingCost(p)).round();
    op(mStock, p.id, v, 'موجودی اول دوره');
    assets += v;
  }
  s.settings.openingOther.forEach((code, v) {
    final m = findMoeen(code);
    if (m == null) return;
    op(code, null, v, 'مانده اول دوره');
    if (m.debitNature) {
      assets += v;
    } else {
      liabs += v;
    }
  });
  op(mCapital, null, assets - liabs, 'سرمایه اول دوره');

  // --------------------------------------------------------- transactions
  for (final t in s.txns) {
    if (t.invoiceId != null && t.type.isInvoice) continue; // handled per invoice below
    final cat = t.categoryId;
    final person = t.personId;
    final pM = person == null ? mDebtorsOther : mDebtorsTrade;
    final label = t.type.label;
    final desc = t.note;
    final acc = t.accountId;
    final a = acc == null ? mOtherLiab : accM(acc);
    final o = t.createdAt;
    switch (t.type) {
      case TxnType.income:
        pair(t.date, label, desc, t.amount, drM: a, drT: acc, crM: mIncome, crT: cat, order: o);
      case TxnType.expense:
        pair(t.date, label, desc, t.amount, drM: mExpense, drT: cat, crM: a, crT: acc, order: o);
      case TxnType.transfer:
        pair(t.date, label, desc, t.amount, drM: accM(t.toAccountId), drT: t.toAccountId, crM: a, crT: acc, order: o);
      case TxnType.lend:
      case TxnType.repay:
        pair(t.date, label, desc, t.amount, drM: pM, drT: person, crM: a, crT: acc, order: o);
      case TxnType.borrow:
      case TxnType.collect:
        pair(t.date, label, desc, t.amount, drM: a, drT: acc, crM: pM, crT: person, order: o);
      case TxnType.purchaseDiscount:
        pair(t.date, label, desc, t.amount, drM: pM, drT: person, crM: mPurchaseDiscount, order: o);
      case TxnType.saleDiscount:
        pair(t.date, label, desc, t.amount, drM: mSaleDiscount, crM: pM, crT: person, order: o);
      case TxnType.loanIn:
        pair(t.date, label, desc, t.amount, drM: a, drT: acc, crM: mLoans, order: o);
      case TxnType.loanPay:
        pair(t.date, label, desc, t.amount, drM: mLoans, crM: a, crT: acc, order: o);
      default:
        break;
    }
  }

  // ------------------------------------------------------------- invoices
  for (final inv in s.realInvoices) {
    final label = '${inv.kind.label} ${inv.number}';
    final p = inv.personId;
    final pM = p == null ? mDebtorsOther : mDebtorsTrade;
    final o = inv.createdAt;
    final sub = inv.subtotal;
    int share(InvoiceLine l) => sub == 0 ? 0 : (inv.discount * l.total / sub).round();
    switch (inv.kind) {
      case InvoiceKind.purchase:
      case InvoiceKind.purchaseReturn:
        final buy = inv.kind == InvoiceKind.purchase;
        var lineSum = 0;
        for (final l in inv.lines) {
          final v = l.total - share(l);
          lineSum += v;
          // free-text lines (services) go to expenses, goods to stock
          final m = l.productId == null ? mExpense : mStock;
          if (buy) {
            pair(inv.date, label, inv.note, v, drM: m, drT: l.productId, crM: pM, crT: p, no: inv.number, order: o);
          } else {
            pair(inv.date, label, inv.note, v, drM: pM, drT: p, crM: m, crT: l.productId, no: inv.number, order: o);
          }
        }
        final rest = inv.total - lineSum;
        if (buy) {
          pair(inv.date, label, 'هزینه‌های جانبی', rest, drM: '50102', crM: pM, crT: p, no: inv.number, order: o);
        } else {
          pair(inv.date, label, 'هزینه‌های جانبی', rest, drM: pM, drT: p, crM: '50102', no: inv.number, order: o);
        }
      case InvoiceKind.sale:
      case InvoiceKind.saleReturn:
        final sale = inv.kind == InvoiceKind.sale;
        var lineSum = 0;
        for (final l in inv.lines) {
          final rev = l.total - share(l);
          lineSum += rev;
          if (sale) {
            pair(inv.date, label, inv.note, rev, drM: pM, drT: p, crM: mSales, crT: l.productId, no: inv.number, order: o);
          } else {
            pair(inv.date, label, inv.note, rev, drM: mSalesReturn, drT: l.productId, crM: pM, crT: p, no: inv.number, order: o);
          }
          if (l.productId != null) {
            final cost = (l.qty * s.avgCost(l.productId!)).round();
            if (sale) {
              pair(inv.date, label, 'بهای تمام شده', cost, drM: mCogs, drT: l.productId, crM: mStock, crT: l.productId, no: inv.number, order: o);
            } else {
              pair(inv.date, label, 'بهای تمام شده', cost, drM: mStock, drT: l.productId, crM: mCogs, crT: l.productId, no: inv.number, order: o);
            }
          }
        }
        final rest = inv.total - lineSum; // extra charges and rounding
        if (sale) {
          pair(inv.date, label, 'هزینه‌های جانبی', rest, drM: pM, drT: p, crM: '40102', no: inv.number, order: o);
        } else {
          pair(inv.date, label, 'هزینه‌های جانبی', rest, drM: '40102', crM: pM, crT: p, no: inv.number, order: o);
        }
    }
  }

  // ------------------------------------------------------- stock adjustments
  for (final a in s.adjusts) {
    final v = (a.qty * s.avgCost(a.productId)).round();
    pair(a.date, a.reason.label, a.note, v, drM: mStock, drT: a.productId, crM: mStockLoss, crT: a.productId, order: a.createdAt);
  }

  // ---------------------------------------------------------- manual vouchers
  for (final v in s.vouchers) {
    for (final l in v.lines) {
      out.add(Posting(
        date: v.date,
        moeen: l.moeen,
        tafsiliId: l.tafsiliId,
        docLabel: 'سند ${v.number}',
        docNo: v.number,
        isVoucher: true,
        desc: l.desc.isEmpty ? v.desc : l.desc,
        debit: l.debit,
        credit: l.credit,
        order: v.createdAt,
      ));
    }
  }

  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return out;
}

String postingDate(Posting p) => Jalali.fromDateTime(p.date).format();

// =================================================================== reports

enum TbLevel { kol, moeen, tafsili }

/// Shared filters of the trial balance and ledger reports (محدودیت‌ها).
class ReportFilter {
  TbLevel level = TbLevel.kol;
  String? pathKol;
  String? pathMoeen;
  String? linkTafsili;
  DateTime? from;
  DateTime? to;
  int? noFrom;
  int? noTo;
  Set<int>? docs; // "سند های"

  bool _inDocs(Posting p) {
    if (noFrom != null || noTo != null || docs != null) {
      if (!p.isVoucher || p.docNo == null) return false;
      if (noFrom != null && p.docNo! < noFrom!) return false;
      if (noTo != null && p.docNo! > noTo!) return false;
      if (docs != null && docs!.isNotEmpty && !docs!.contains(p.docNo)) return false;
    }
    return true;
  }

  bool _inPath(Posting p) {
    if (pathMoeen != null && p.moeen != pathMoeen) return false;
    if (pathKol != null && p.kol != pathKol) return false;
    if (linkTafsili != null && p.tafsiliId != linkTafsili) return false;
    return true;
  }

  /// Included in balances (everything up to the end date).
  bool forBalance(Posting p) => (to == null || !p.date.isAfter(to!)) && _inDocs(p) && _inPath(p);

  /// Included in the period turnover.
  bool inPeriod(Posting p) => forBalance(p) && (from == null || !p.date.isBefore(from!));

  String keyOf(Posting p) => switch (level) {
        TbLevel.kol => p.kol,
        TbLevel.moeen => p.moeen,
        TbLevel.tafsili => '${p.moeen}|${p.tafsiliId ?? ''}',
      };
}

String accountName(AppStore s, String key) {
  if (key.length == 3) return kolOf('${key}00').name;
  final parts = key.split('|');
  final m = findMoeen(parts[0]);
  if (m == null) return key;
  if (parts.length == 1 || parts[1].isEmpty) return m.name;
  final t = s.tafsiliName(VoucherLine(moeen: m.code, tafsiliId: parts[1]));
  return t.isEmpty ? m.name : '${m.name} / $t';
}

String accountCode(String key) => key.split('|').first;

class TbRow {
  final String key;
  final String code;
  final String name;
  int turnDr = 0;
  int turnCr = 0;
  int bal = 0; // debit positive
  TbRow(this.key, this.code, this.name);
  int get balDr => bal > 0 ? bal : 0;
  int get balCr => bal < 0 ? -bal : 0;
}

class TbOptions {
  int side = 0; // 0 all, 1 debtors only, 2 creditors only
  bool showZero = true;
  bool hideNoTurnover = false;
  bool hideStock = false;
  bool hideMemo = false;
}

List<TbRow> trialBalance(AppStore s, List<Posting> journal, ReportFilter f, TbOptions o) {
  final rows = <String, TbRow>{};
  for (final p in journal) {
    if (!f.forBalance(p)) continue;
    if (o.hideStock) {
      final m = findMoeen(p.moeen);
      if (p.kol == '104' || m?.kind == TafsiliKind.product) continue;
    }
    final k = f.keyOf(p);
    final r = rows.putIfAbsent(k, () => TbRow(k, accountCode(k), accountName(s, k)));
    r.bal += p.debit - p.credit;
    if (f.inPeriod(p)) {
      r.turnDr += p.debit;
      r.turnCr += p.credit;
    }
  }
  final list = rows.values.where((r) {
    if (!o.showZero && r.bal == 0) return false;
    if (o.hideNoTurnover && r.turnDr == 0 && r.turnCr == 0) return false;
    if (o.side == 1 && r.bal <= 0) return false;
    if (o.side == 2 && r.bal >= 0) return false;
    return true;
  }).toList()
    ..sort((a, b) {
      final c = a.code.compareTo(b.code);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return list;
}

class LedgerRow {
  final DateTime date;
  final String doc;
  final String desc;
  final int dr;
  final int cr;
  int balance = 0;
  LedgerRow(this.date, this.doc, this.desc, this.dr, this.cr);
}

class LedgerSection {
  final String key;
  final String name;
  int before = 0;
  final List<LedgerRow> rows = [];
  LedgerSection(this.key, this.name);
  int get dr => rows.fold(0, (s, r) => s + r.dr);
  int get cr => rows.fold(0, (s, r) => s + r.cr);
  int get end => before + dr - cr;
}

List<LedgerSection> generalLedger(AppStore s, List<Posting> journal, ReportFilter f, {bool aggregate = false}) {
  final secs = <String, LedgerSection>{};
  for (final p in journal) {
    if (!f.forBalance(p)) continue;
    final k = f.keyOf(p);
    final sec = secs.putIfAbsent(k, () => LedgerSection(k, '${accountCode(k)}  ${accountName(s, k)}'));
    if (!f.inPeriod(p)) {
      sec.before += p.debit - p.credit;
      continue;
    }
    if (aggregate && sec.rows.isNotEmpty && sec.rows.last.date == p.date) {
      final last = sec.rows.removeLast();
      sec.rows.add(LedgerRow(p.date, 'جمع روز', '', last.dr + p.debit, last.cr + p.credit));
    } else {
      sec.rows.add(LedgerRow(p.date, aggregate ? 'جمع روز' : p.docLabel, aggregate ? '' : p.desc, p.debit, p.credit));
    }
  }
  final list = secs.values.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final sec in list) {
    var b = sec.before;
    for (final r in sec.rows) {
      b += r.dr - r.cr;
      r.balance = b;
    }
  }
  return list;
}
