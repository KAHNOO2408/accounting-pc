/// «ترازنامه سفارشی»، «صورتحساب سود/زیان سفارشی»، «صورت خلاصه درآمد و
/// هزینه»، «گزارشات پویا نمودار» و «گزارش تلفیقی صورت حساب سود و زیان».
library;

import '../core/jalali.dart';
import 'books.dart';
import 'chart.dart';
import 'journal.dart';
import 'models.dart';
import 'store.dart';

String _s(Object? v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// A row of a custom statement. [codes] are کل (2 digits) or معین (4 digits)
/// codes; a leading «-» subtracts the code.
class StatementRow {
  String title;
  List<String> codes;
  bool header; // عنوان بخش
  bool total; // جمع ردیف‌های بالا (از جمع قبلی)
  bool creditPositive; // مانده بستانکار مثبت نمایش داده شود
  StatementRow({required this.title, List<String>? codes, this.header = false, this.total = false, this.creditPositive = false}) : codes = codes ?? [];
  Map<String, dynamic> toJson() => {'title': title, 'codes': codes, 'header': header, 'total': total, 'creditPositive': creditPositive};
  factory StatementRow.fromJson(Map<String, dynamic> j) => StatementRow(
        title: _s(j['title']),
        codes: j['codes'] is List ? [for (final x in j['codes'] as List) '$x'] : null,
        header: j['header'] == true,
        total: j['total'] == true,
        creditPositive: j['creditPositive'] == true,
      );
}

class CustomStatement {
  String id;
  String name;
  bool balanceSheet; // ترازنامه (مانده تا تاریخ) / سود و زیان (گردش دوره)
  List<StatementRow> rows;
  CustomStatement({required this.id, required this.name, this.balanceSheet = true, List<StatementRow>? rows}) : rows = rows ?? [];
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'balanceSheet': balanceSheet, 'rows': rows.map((r) => r.toJson()).toList()};
  factory CustomStatement.fromJson(Map<String, dynamic> j) =>
      CustomStatement(id: _s(j['id']), name: _s(j['name']), balanceSheet: j['balanceSheet'] != false, rows: _list(j['rows']).map(StatementRow.fromJson).toList());

  static CustomStatement sampleBalanceSheet() => CustomStatement(id: newId(), name: 'ترازنامه سفارشی', rows: [
        StatementRow(title: 'دارایی ها', header: true),
        StatementRow(title: 'دارایی های جاری', codes: ['10', '11']),
        StatementRow(title: 'دارایی های غیر جاری', codes: ['12']),
        StatementRow(title: 'جمع دارایی ها', total: true),
        StatementRow(title: 'بدهی ها و حقوق صاحبان سهام', header: true),
        StatementRow(title: 'بدهی های جاری', codes: ['20'], creditPositive: true),
        StatementRow(title: 'بدهی های غیر جاری', codes: ['21'], creditPositive: true),
        StatementRow(title: 'حقوق صاحبان سهام', codes: ['30'], creditPositive: true),
        StatementRow(title: 'سود و زیان دوره', codes: ['40', '50'], creditPositive: true),
        StatementRow(title: 'جمع بدهی ها و حقوق صاحبان سهام', total: true, creditPositive: true),
      ]);

  static CustomStatement sampleProfit() => CustomStatement(id: newId(), name: 'صورتحساب سود/زیان سفارشی', balanceSheet: false, rows: [
        StatementRow(title: 'فروش خالص', codes: ['4060', '4050', '5055', '5050'], creditPositive: true),
        StatementRow(title: 'بهای تمام شده کالای فروش رفته', codes: ['5040'], creditPositive: true),
        StatementRow(title: 'سود ناخالص', total: true, creditPositive: true),
        StatementRow(title: 'هزینه های عمومی و اداری', codes: ['5005', '5012', '5013', '5007'], creditPositive: true),
        StatementRow(title: 'سایر درآمدها', codes: ['4025', '4020', '4010'], creditPositive: true),
        StatementRow(title: 'سود خالص', total: true, creditPositive: true),
      ]);
}

/// Values of a statement's rows (null for headers).
List<int?> evaluateStatement(AppStore s, CustomStatement st, {DateTime? from, DateTime? to, List<Posting>? journal}) {
  final j = journal ?? buildJournal(s);
  final bal = <String, int>{};
  for (final p in j) {
    if (to != null && p.date.isAfter(to)) continue;
    if (!st.balanceSheet && from != null && p.date.isBefore(from)) continue;
    if (!st.balanceSheet && p.isOpening) continue;
    bal[p.moeen] = (bal[p.moeen] ?? 0) + p.debit - p.credit;
  }
  int code(String c) {
    if (c.length <= 2) return bal.entries.where((e) => kolOf(e.key).code == c).fold(0, (a, e) => a + e.value);
    return bal[c] ?? 0;
  }

  final out = <int?>[];
  var since = 0;
  for (final r in st.rows) {
    if (r.header) {
      out.add(null);
      continue;
    }
    if (r.total) {
      var t = 0;
      for (var k = since; k < out.length; k++) {
        if (!st.rows[k].header && !st.rows[k].total) t += out[k] ?? 0;
      }
      out.add(t);
      // sheets: each total covers its own section; profit: totals are running
      if (st.balanceSheet) since = out.length;
      continue;
    }
    var v = 0;
    for (final c in r.codes) {
      final t = c.trim();
      if (t.isEmpty) continue;
      v += t.startsWith('-') ? -code(t.substring(1)) : code(t);
    }
    out.add(r.creditPositive ? -v : v);
  }
  return out;
}

/// «صورت خلاصه درآمد و هزینه»: (category name, income, expense) for the range.
List<(String, int, int)> incomeExpenseSummary(AppStore s, DateTime from, DateTime to) {
  final m = <String, (int, int)>{};
  for (final t in s.txns) {
    if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
    if (t.type != TxnType.income && t.type != TxnType.expense) continue;
    final name = s.category(t.categoryId)?.name ?? (t.type == TxnType.income ? 'سایر درآمدها' : 'سایر هزینه ها');
    final o = m[name] ?? (0, 0);
    m[name] = t.type == TxnType.income ? (o.$1 + t.amount, o.$2) : (o.$1, o.$2 + t.amount);
  }
  final rows = [for (final e in m.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => (b.$2 + b.$3).compareTo(a.$2 + a.$3));
  return rows;
}

enum DynMetric { sales, purchases, expenses, income, profit }

extension DynMetricX on DynMetric {
  String get label => switch (this) {
        DynMetric.sales => 'فروش خالص',
        DynMetric.purchases => 'خرید',
        DynMetric.expenses => 'هزینه ها',
        DynMetric.income => 'درآمدها',
        DynMetric.profit => 'سود خالص',
      };
}

enum DynGroup { day, month, product, person }

extension DynGroupX on DynGroup {
  String get label => switch (this) {
        DynGroup.day => 'روزانه',
        DynGroup.month => 'ماهانه',
        DynGroup.product => 'به تفکیک کالا',
        DynGroup.person => 'به تفکیک طرف حساب',
      };
}

/// «گزارشات پویا نمودار»: (label, value) series.
List<(String, int)> dynamicSeries(AppStore s, DynMetric m, DynGroup g, DateTime from, DateTime to) {
  final out = <String, int>{};
  final order = <String, DateTime>{};
  String key(DateTime d) {
    final j = Jalali.fromDateTime(d);
    final k = g == DynGroup.day ? j.format() : '${j.year}/${j.month.toString().padLeft(2, '0')}';
    order.putIfAbsent(k, () => d);
    return k;
  }

  bool inR(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
  if (m == DynMetric.profit) {
    var d = DateTime(from.year, from.month, from.day);
    while (!d.isAfter(to)) {
      final j = Jalali.fromDateTime(d);
      final start = g == DynGroup.day ? d : Jalali(j.year, j.month, 1).toDateTime();
      final end = g == DynGroup.day ? d : Jalali(j.year, j.month, Jalali.monthLength(j.year, j.month)).toDateTime();
      final k = key(start);
      out[k] = s.profit(start.isBefore(from) ? from : start, end.isAfter(to) ? to : end).netProfit;
      d = DateTime(end.year, end.month, end.day + 1);
    }
  } else if (m == DynMetric.expenses || m == DynMetric.income) {
    for (final t in s.txns.where((t) => inR(t.date) && t.type == (m == DynMetric.income ? TxnType.income : TxnType.expense))) {
      final k = switch (g) {
        DynGroup.person => s.person(t.personId)?.name ?? 'بدون طرف حساب',
        DynGroup.product => s.category(t.categoryId)?.name ?? 'بدون دسته',
        _ => key(t.date),
      };
      out[k] = (out[k] ?? 0) + t.amount;
    }
  } else {
    final kinds = m == DynMetric.sales ? {InvoiceKind.sale: 1, InvoiceKind.saleReturn: -1} : {InvoiceKind.purchase: 1, InvoiceKind.purchaseReturn: -1};
    for (final inv in s.realInvoices.where((i) => inR(i.date) && kinds.containsKey(i.kind))) {
      final sign = kinds[inv.kind]!;
      if (g == DynGroup.product) {
        for (final l in inv.lines) {
          final k = s.product(l.productId)?.name ?? (l.title.isEmpty ? 'خدمات' : l.title);
          out[k] = (out[k] ?? 0) + sign * l.total;
        }
        continue;
      }
      final k = g == DynGroup.person ? (s.person(inv.personId)?.name ?? 'متفرقه') : key(inv.date);
      out[k] = (out[k] ?? 0) + sign * (inv.subtotal - inv.discount);
    }
  }
  final list = [for (final e in out.entries) (e.key, e.value)];
  if (g == DynGroup.day || g == DynGroup.month) {
    list.sort((a, b) => (order[a.$1] ?? DateTime(0)).compareTo(order[b.$1] ?? DateTime(0)));
  } else {
    list.sort((a, b) => b.$2.compareTo(a.$2));
  }
  return list;
}

/// «گزارش تلفیقی صورت حساب سود و زیان»: the profit report of every book.
List<(String, ProfitReport)> consolidatedProfit(AppStore current, DateTime from, DateTime to) {
  final reg = BookRegistry.of(current);
  final curId = BookRegistry.idOf(current.storage.dir);
  final out = <(String, ProfitReport)>[];
  final books = reg.books.where((b) => !b.deleted).toList();
  if (books.isEmpty) return [('دفتر جاری', current.profit(from, to))];
  for (final b in books) {
    try {
      final st = b.id == curId ? current : reg.open(b.id);
      out.add((b.title, st.profit(from, to)));
    } catch (_) {}
  }
  return out;
}
