/// «ساخت فایل اطلاعات مالیاتی» — the seasonal purchases/sales list (گزارش
/// معاملات فصلی، ماده ۱۶۹) per counterparty, for the tax portal's Excel import.
library;

import '../core/jalali.dart';
import 'models.dart';
import 'store.dart';

class SeasonRow {
  final Person? person;
  int amount = 0;
  int discount = 0;
  int vat = 0;
  int count = 0;
  SeasonRow(this.person);
}

/// (start, end) of a Jalali season (1..4).
(DateTime, DateTime) seasonRange(int year, int season) {
  final m1 = (season - 1) * 3 + 1, m3 = m1 + 2;
  return (Jalali(year, m1, 1).toDateTime(), Jalali(year, m3, Jalali.monthLength(year, m3)).toDateTime());
}

/// Purchases (sales = false) or sales of a season, one row per person.
List<SeasonRow> seasonRows(AppStore s, int year, int season, {required bool sales}) {
  final (from, to) = seasonRange(year, season);
  final rows = <String, SeasonRow>{};
  for (final inv in s.realInvoices) {
    if (inv.date.isBefore(from) || inv.date.isAfter(to)) continue;
    final sign = switch (inv.kind) {
      InvoiceKind.sale => sales ? 1 : 0,
      InvoiceKind.saleReturn => sales ? -1 : 0,
      InvoiceKind.purchase => sales ? 0 : 1,
      InvoiceKind.purchaseReturn => sales ? 0 : -1,
      _ => 0,
    };
    if (sign == 0) continue;
    final r = rows.putIfAbsent(inv.personId ?? '', () => SeasonRow(s.person(inv.personId)));
    r.amount += sign * inv.subtotal;
    r.discount += sign * inv.discount;
    r.vat += sign * inv.vatTotal;
    r.count++;
  }
  return rows.values.where((r) => r.amount != 0).toList()..sort((a, b) => b.amount.compareTo(a.amount));
}

const seasonHeaders = ['ردیف', 'نوع شخص', 'شماره/شناسه ملی', 'کد اقتصادی', 'نام', 'کد پستی', 'نشانی', 'تلفن', 'تعداد فاکتور', 'مبلغ کل', 'تخفیف', 'مالیات و عوارض'];

List<List<String>> seasonTable(List<SeasonRow> rows) => [
      for (var i = 0; i < rows.length; i++)
        () {
          final p = rows[i].person;
          final info = p?.info ?? const {};
          return [
            '${i + 1}',
            info['kind'] == 'legal' ? 'حقوقی' : 'حقیقی',
            info['nationalId'] ?? '',
            info['economicCode'] ?? '',
            p?.name ?? 'متفرقه',
            info['postalCode'] ?? '',
            info['address'] ?? '',
            p?.phone ?? '',
            '${rows[i].count}',
            '${rows[i].amount}',
            '${rows[i].discount}',
            '${rows[i].vat}',
          ];
        }(),
    ];

/// People in the rows who lack the national id the portal needs.
List<Person> missingTaxInfo(List<SeasonRow> rows) => [for (final r in rows) if (r.person != null && (r.person!.info['nationalId'] ?? '').isEmpty) r.person!];

// ===================================================================== TTMS

/// «ایجاد فایل مالیاتی ویژه نرم افزار TTMS» options (step 2 of Sakan's form).
class TtmsOptions {
  int year;
  int season;
  int month; // 0 = whole season
  int threshold; // «مبلغ تشخیص معاملات کمتر از حد نصاب در قانون 169»
  bool skipIncomplete; // عملیاتی که ناقص هستند ارسال نگردد
  bool skipNoDuty; // ... سر فصل عوارض ندارند ارسال نگردد
  bool skipZeroDuty; // ... مبلغ عوارض آنها صفر است ارسال نگردد
  TtmsOptions({required this.year, required this.season, this.month = 0, this.threshold = 0, this.skipIncomplete = true, this.skipNoDuty = false, this.skipZeroDuty = false});
}

/// «اطلاعات مورد نیاز حساب برای ساخت فایل TTMS» — missing fields of a person.
List<String> ttmsMissing(Person p) {
  final i = p.info;
  return [
    if ((i['nationalId'] ?? '').isEmpty) i['kind'] == 'legal' ? 'شناسه ملی' : 'کد ملی',
    if ((i['postalCode'] ?? '').isEmpty) 'کد پستی',
    if ((i['province'] ?? '').isEmpty) 'استان',
    if ((i['city'] ?? '').isEmpty) 'شهر',
    if ((i['address'] ?? '').isEmpty) 'آدرس',
  ];
}

/// An invoice is used in the tax file unless «عدم استفاده از سند در فایل مالیاتی».
bool usedInTaxFile(Invoice i) => i.info['taxFile'] != '0';

/// One operation of the season with its state for «مشاهده لیست عملیات».
class TtmsOp {
  final Invoice inv;
  final bool incomplete;
  final bool excluded;
  final String reason;
  const TtmsOp(this.inv, {this.incomplete = false, this.excluded = false, this.reason = ''});
}

List<TtmsOp> ttmsOps(AppStore s, TtmsOptions o) {
  var (from, to) = seasonRange(o.year, o.season);
  if (o.month > 0) {
    from = Jalali(o.year, o.month, 1).toDateTime();
    to = Jalali(o.year, o.month, Jalali.monthLength(o.year, o.month)).toDateTime();
  }
  final out = <TtmsOp>[];
  for (final inv in s.realInvoices) {
    if (inv.date.isBefore(from) || inv.date.isAfter(to)) continue;
    if (!{InvoiceKind.sale, InvoiceKind.saleReturn, InvoiceKind.purchase, InvoiceKind.purchaseReturn}.contains(inv.kind)) continue;
    final p = s.person(inv.personId);
    final incomplete = p != null && p.info['finalConsumer'] != '1' && p.info['refused'] != '1' && ttmsMissing(p).isNotEmpty;
    var reason = '';
    if (!usedInTaxFile(inv)) {
      reason = 'عدم استفاده از سند';
    } else if (incomplete && o.skipIncomplete) {
      reason = 'اطلاعات طرف حساب ناقص';
    } else if (o.skipNoDuty && inv.lines.every((l) => l.dutyPct == 0)) {
      reason = 'بدون سرفصل عوارض';
    } else if (o.skipZeroDuty && inv.dutyTotal == 0) {
      reason = 'عوارض صفر';
    }
    out.add(TtmsOp(inv, incomplete: incomplete, excluded: reason.isNotEmpty, reason: reason));
  }
  out.sort((a, b) => a.inv.date.compareTo(b.inv.date));
  return out;
}

const ttmsHeaders = [
  'ردیف', 'نوع شخص', 'کد ملی / شناسه ملی', 'شماره اقتصادی', 'نام', 'نام شرکت / نام خانوادگی', 'کد پستی', 'استان', 'شهر', 'پیش کد شهر', 'تلفن', 'آدرس', //
  'نوع کالا و خدمات', 'تعداد فاکتور', 'مبلغ کل', 'تخفیف', 'مالیات', 'عوارض',
];

/// Sheets of the TTMS file: (sheet name, rows).
List<(String, List<List<String>>)> ttmsSheets(AppStore s, TtmsOptions o) {
  final ops = ttmsOps(s, o).where((x) => !x.excluded);
  final groups = <String, Map<String, List<Invoice>>>{'خرید': {}, 'فروش': {}, 'امتناع': {}, 'عرضه به مصرف کننده نهایی': {}};
  for (final x in ops) {
    final p = s.person(x.inv.personId);
    final buy = x.inv.kind.buySide;
    final sheet = p == null || p.info['finalConsumer'] == '1'
        ? (buy ? 'خرید' : 'عرضه به مصرف کننده نهایی')
        : (p.info['refused'] == '1' ? 'امتناع' : (buy ? 'خرید' : 'فروش'));
    final key = '${p?.id ?? ''}|${x.inv.info['taxGoodsType'] ?? 'goods'}|${buy ? 'b' : 's'}';
    (groups[sheet]![key] ??= []).add(x.inv);
  }
  List<String> row(int i, Person? p, String type, List<Invoice> invs, {String? name}) {
    int sum(int Function(Invoice) f) => invs.fold(0, (a, inv) => a + (inv.kind == InvoiceKind.saleReturn || inv.kind == InvoiceKind.purchaseReturn ? -1 : 1) * f(inv));
    final info = p?.info ?? const {};
    final legal = info['kind'] == 'legal';
    final parts = (p?.name ?? '').split(' ');
    return [
      '$i',
      p == null ? '' : (legal ? 'حقوقی' : 'حقیقی'),
      info['nationalId'] ?? '',
      info['economicCode'] ?? '',
      legal || p == null ? '' : (info['firstName'] ?? (parts.length > 1 ? parts.first : '')),
      name ?? (legal ? (p?.name ?? '') : (info['lastName'] ?? (parts.length > 1 ? parts.skip(1).join(' ') : p?.name ?? ''))),
      info['postalCode'] ?? '',
      info['province'] ?? '',
      info['city'] ?? '',
      info['cityCode'] ?? '',
      p?.phone ?? '',
      info['address'] ?? '',
      type == 'services' ? 'خدمات' : 'کالا',
      '${invs.length}',
      '${sum((x) => x.subtotal)}',
      '${sum((x) => x.discount)}',
      '${sum((x) => x.taxTotal)}',
      '${sum((x) => x.dutyTotal)}',
    ];
  }

  final out = <(String, List<List<String>>)>[];
  for (final e in groups.entries) {
    final rows = <List<String>>[];
    final small = <Invoice>[];
    var i = 0;
    for (final g in e.value.entries) {
      final p = s.person(g.key.split('|').first);
      final total = g.value.fold<int>(0, (a, x) => a + x.total);
      // «معاملات کمتر از حد نصاب» are reported in one row
      if (o.threshold > 0 && total < o.threshold && e.key != 'امتناع') {
        small.addAll(g.value);
        continue;
      }
      if (p == null) {
        small.addAll(g.value);
        continue;
      }
      rows.add(row(++i, p, g.key.split('|')[1], g.value));
    }
    if (small.isNotEmpty) rows.add(row(++i, null, 'goods', small, name: e.key == 'عرضه به مصرف کننده نهایی' ? 'مصرف کننده نهایی' : 'معاملات کمتر از حد نصاب'));
    out.add((e.key, rows));
  }
  return out;
}
