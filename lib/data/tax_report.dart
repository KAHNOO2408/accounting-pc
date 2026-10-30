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
