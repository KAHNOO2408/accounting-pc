import 'dart:io';

import '../core/format.dart';
import '../core/jalali.dart';
import '../data/chart.dart';
import '../data/journal.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../data/store.dart';
import 'dialogs/invoice_editor.dart' show fmtQty;

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Builds a printable HTML page for the invoice and opens it in the browser
/// (the print dialog opens automatically). Returns the file path.
String printInvoice(AppStore store, Invoice inv) {
  final s = store.settings;
  final cur = s.currency;
  final person = store.person(inv.personId);
  final title = inv.proforma ? 'پیش‌فاکتور فروش' : inv.kind.label;
  final rows = StringBuffer();
  var i = 0;
  for (final l in inv.lines) {
    i++;
    final p = store.product(l.productId);
    rows.writeln('<tr>'
        '<td>$i</td>'
        '<td class="name">${_esc(p?.name ?? l.title)}${p != null && p.code.isNotEmpty ? '<small> (${_esc(p.code)})</small>' : ''}</td>'
        '<td>${fmtQty(l.qty)} ${_esc(p?.unit ?? '')}</td>'
        '<td class="num">${groupDigits(l.unitPrice)}</td>'
        '<td class="num">${l.discount == 0 ? '-' : groupDigits(l.discount)}</td>'
        '<td class="num">${groupDigits(l.total)}</td>'
        '</tr>');
  }

  String sumRow(String k, int v, {bool strong = false}) =>
      '<tr class="${strong ? 'strong' : ''}"><th>$k</th><td class="num">${groupDigits(v)} $cur</td></tr>';

  final html = '''<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<title>${_esc(title)} ${inv.number}</title>
<style>
  @page { size: A5; margin: 10mm; }
  * { box-sizing: border-box; }
  body { font-family: Vazirmatn, Tahoma, "Segoe UI", sans-serif; color: #111; margin: 0; font-size: 12px; }
  .head { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #333; padding-bottom: 8px; margin-bottom: 10px; }
  .biz h1 { margin: 0; font-size: 18px; }
  .biz div { color: #444; margin-top: 2px; }
  .doc { text-align: left; }
  .doc h2 { margin: 0; font-size: 16px; }
  .meta { display: flex; gap: 24px; margin: 8px 0 12px; flex-wrap: wrap; }
  .meta b { color: #000; }
  table { width: 100%; border-collapse: collapse; }
  .items th, .items td { border: 1px solid #999; padding: 5px 6px; text-align: center; }
  .items th { background: #eee; }
  .items td.name { text-align: right; }
  .num { direction: ltr; text-align: left !important; white-space: nowrap; }
  .bottom { display: flex; gap: 16px; margin-top: 12px; align-items: flex-start; }
  .words { flex: 1; border: 1px dashed #999; padding: 8px; }
  .sums { width: 48%; }
  .sums th { text-align: right; font-weight: normal; padding: 4px 6px; border-bottom: 1px solid #ddd; }
  .sums td { padding: 4px 6px; border-bottom: 1px solid #ddd; }
  .sums .strong th, .sums .strong td { font-weight: bold; font-size: 14px; border-top: 2px solid #333; }
  .sign { display: flex; justify-content: space-around; margin-top: 36px; color: #444; }
  .note { margin-top: 10px; color: #333; }
  @media print { .noprint { display: none; } }
  .noprint { margin: 12px 0; text-align: center; }
  .noprint button { font: inherit; padding: 6px 18px; }
</style>
</head>
<body>
<div class="noprint"><button onclick="window.print()">چاپ</button></div>
<div class="head">
  <div class="biz">
    <h1>${_esc(s.businessName.isEmpty ? (s.ownerName.isEmpty ? 'فروشگاه' : s.ownerName) : s.businessName)}</h1>
    ${s.businessPhone.isEmpty ? '' : '<div>تلفن: ${_esc(s.businessPhone)}</div>'}
    ${s.businessAddress.isEmpty ? '' : '<div>${_esc(s.businessAddress)}</div>'}
  </div>
  <div class="doc">
    <h2>${_esc(title)}</h2>
    <div>شماره: <b>${inv.number}</b></div>
    <div>تاریخ: <b>${jFormat(inv.date)}</b></div>
  </div>
</div>
<div class="meta">
  <div>${inv.kind.buySide ? 'فروشنده' : 'خریدار'}: <b>${_esc(person?.name ?? (inv.kind.buySide ? 'متفرقه' : 'مشتری نقدی'))}</b></div>
  ${person != null && person.phone.isNotEmpty ? '<div>تلفن: <b>${_esc(person.phone)}</b></div>' : ''}
</div>
<table class="items">
  <thead><tr><th>#</th><th>شرح کالا / خدمت</th><th>تعداد</th><th>فی ($cur)</th><th>تخفیف</th><th>مبلغ ($cur)</th></tr></thead>
  <tbody>
$rows
  </tbody>
</table>
<div class="bottom">
  <div class="words">مبلغ به حروف: <b>${amountInWords(inv.total)} $cur</b></div>
  <table class="sums">
    ${sumRow('جمع ردیف‌ها', inv.subtotal)}
    ${inv.discount == 0 ? '' : sumRow('تخفیف', inv.discount)}
    ${inv.extra == 0 ? '' : sumRow('هزینه‌های جانبی', inv.extra)}
    ${sumRow('مبلغ قابل پرداخت', inv.total, strong: true)}
    ${inv.proforma ? '' : sumRow(inv.kind.moneyIn ? 'دریافت شده' : 'پرداخت شده', inv.paid)}
    ${inv.proforma || inv.remaining == 0 ? '' : sumRow('مانده', inv.remaining)}
  </table>
</div>
${inv.note.isEmpty ? '' : '<div class="note">توضیحات: ${_esc(inv.note)}</div>'}
<div class="sign"><div>مهر و امضای فروشنده</div><div>امضای خریدار</div></div>
<script>window.onload = function(){ setTimeout(function(){ window.print(); }, 300); };</script>
</body>
</html>''';

  final dir = Directory('${Storage.userFolder.path}${Storage.sep}prints');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final kind = inv.proforma ? 'proforma' : inv.kind.name;
  final f = File('${dir.path}${Storage.sep}$kind-${inv.number}.html');
  f.writeAsStringSync(html, flush: true);
  openFile(f.path);
  return f.path;
}

void openFile(String path) {
  try {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else {
      Process.run('xdg-open', [path]);
    }
  } catch (_) {}
}

/// Prints a generic report table (opens in the browser with the print dialog).
String printTable({
  required AppStore store,
  required String title,
  String subtitle = '',
  required List<String> headers,
  required List<List<String>> rows,
  Set<int> numeric = const {},
  List<String>? footer,
  String fileName = 'report',
}) {
  final s = store.settings;
  String cell(String v, int i, {String tag = 'td'}) => '<$tag class="${numeric.contains(i) ? 'num' : ''}">${_esc(v)}</$tag>';
  final body = StringBuffer();
  for (final r in rows) {
    body.writeln('<tr>${[for (var i = 0; i < r.length; i++) cell(r[i], i)].join()}</tr>');
  }
  final html = '''<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>${_esc(title)}</title>
<style>
  @page { size: A4; margin: 10mm; }
  body { font-family: Vazirmatn, Tahoma, sans-serif; font-size: 11px; color: #111; }
  h1 { font-size: 16px; margin: 0 0 2px; } .sub { color: #555; margin-bottom: 10px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { border: 1px solid #999; padding: 4px 6px; text-align: right; }
  th { background: #eee; } tfoot td { font-weight: bold; background: #f5f5f5; }
  .num { direction: ltr; text-align: left; white-space: nowrap; }
  .noprint { text-align: center; margin: 10px; } @media print { .noprint { display: none; } }
</style></head><body>
<div class="noprint"><button onclick="window.print()">چاپ</button></div>
<h1>${_esc(title)}</h1>
<div class="sub">${_esc(s.businessName)}${s.businessName.isEmpty ? '' : ' — '}${_esc(subtitle)} — تاریخ چاپ ${jFormat(DateTime.now())}</div>
<table><thead><tr>${[for (var i = 0; i < headers.length; i++) cell(headers[i], i, tag: 'th')].join()}</tr></thead>
<tbody>
$body</tbody>
${footer == null ? '' : '<tfoot><tr>${[for (var i = 0; i < footer.length; i++) cell(footer[i], i)].join()}</tr></tfoot>'}
</table>
<script>window.onload=function(){setTimeout(function(){window.print();},300);};</script>
</body></html>''';
  final dir = Directory('${Storage.userFolder.path}${Storage.sep}prints');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}${Storage.sep}$fileName.html');
  f.writeAsStringSync(html, flush: true);
  openFile(f.path);
  return f.path;
}

/// Detail (تفصیلی) code shown in «کد دفتر».
String _tafsiliCode(AppStore s, Posting p) {
  final id = p.tafsiliId;
  if (id == null) return '';
  final per = s.person(id);
  if (per != null) return per.code == 0 ? '' : '${per.code}';
  final a = s.account(id);
  if (a != null) return a.info['code'] ?? '';
  final pr = s.product(id);
  if (pr != null) return pr.code;
  return '';
}

/// «سند حسابداری» — prints the accounting entries of any document in
/// «لیست اسناد» with the Sakan voucher layout: number / base number / date /
/// description on top, rows of book code, description (+ notes), debit and
/// credit, totals and the accountant / manager signatures.
String? printAccountingDoc(AppStore store, String key, {required int number, required int fixed, required DateTime date, String desc = '', bool open = true}) {
  final rows = buildJournal(store).where((p) => p.docKey == key).toList()
    ..sort((a, b) => a.moeen.compareTo(b.moeen));
  if (rows.isEmpty) return null;
  final body = StringBuffer();
  var dr = 0, cr = 0;
  for (final p in rows) {
    dr += p.debit;
    cr += p.credit;
    final m = findMoeen(p.moeen);
    final t = store.tafsiliName(VoucherLine(moeen: p.moeen, tafsiliId: p.tafsiliId));
    final code = [p.moeen, _tafsiliCode(store, p)].where((x) => x.isNotEmpty).join('-');
    final name = [m?.name ?? p.moeen, if (t.isNotEmpty) t].join(' / ');
    body.writeln('<tr><td class="c">${_esc(code)}</td>'
        '<td class="d"><div>${_esc(name)}</div>${p.desc.isEmpty ? '' : '<div class="m">${_esc(p.desc)}</div>'}</td>'
        '<td class="num">${p.debit == 0 ? '' : groupDigits(p.debit)}</td>'
        '<td class="num">${p.credit == 0 ? '' : groupDigits(p.credit)}</td></tr>');
  }
  final s = store.settings;
  final html = '''<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>سند حسابداری $number</title>
<style>
  @page { size: A4; margin: 10mm 5mm; }
  * { box-sizing: border-box; }
  body { font-family: Vazirmatn, Tahoma, sans-serif; font-size: 12px; color: #000; margin: 0; }
  .frame { border: 3px solid #000; padding: 8px 10px 14px; }
  .top { display: flex; justify-content: space-between; align-items: flex-start; }
  .top h1 { font-size: 20px; margin: 0; text-align: center; flex: 1; }
  .kv { min-width: 170px; line-height: 1.9; }
  .kv b { display: inline-block; min-width: 70px; }
  .biz { text-align: center; color: #333; margin-top: -4px; }
  .sharh { margin: 8px 0; padding: 4px 0; border-top: 1px solid #000; }
  table { width: 100%; border-collapse: collapse; }
  th, td { border: 1px solid #000; padding: 4px 6px; }
  th { font-weight: bold; text-align: center; background: #f1f1f1; }
  td.c { text-align: center; width: 13%; white-space: nowrap; }
  td.d { width: 49%; }
  td.d .m { font-size: 10px; color: #333; border-top: 1px dotted #999; margin-top: 2px; }
  .num { direction: ltr; text-align: center; width: 19%; white-space: nowrap; }
  tfoot td { font-weight: bold; }
  .sign { display: flex; justify-content: space-around; margin-top: 26px; font-size: 13px; }
  .noprint { text-align: center; margin: 10px; } @media print { .noprint { display: none; } }
</style></head><body>
<div class="noprint"><button onclick="window.print()">چاپ</button></div>
<div class="frame">
  <div class="top">
    <div class="kv"><div><b>تاریخ سند:</b> ${jFormat(date)}</div></div>
    <h1>سند حسابداری</h1>
    <div class="kv"><div><b>شماره مبنا:</b> $fixed</div><div><b>شماره سند:</b> $number</div></div>
  </div>
  ${s.businessName.isEmpty ? '' : '<div class="biz">${_esc(s.businessName)}</div>'}
  <div class="sharh"><b>شرح سند:</b> ${_esc(desc)}</div>
  <table>
    <thead><tr><th>کد دفتر</th><th>شرح</th><th>بدهکار</th><th>بستانکار</th></tr></thead>
    <tbody>
$body    </tbody>
    <tfoot><tr><td></td><td>جمع</td><td class="num">${groupDigits(dr)}</td><td class="num">${groupDigits(cr)}</td></tr></tfoot>
  </table>
  <div class="sign"><div>مهر /امضاء حسابدار</div><div>مهر/امضاء مدیر عامل</div></div>
</div>
<script>window.onload=function(){setTimeout(function(){window.print();},300);};</script>
</body></html>''';
  final dir = Directory('${Storage.userFolder.path}${Storage.sep}prints');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}${Storage.sep}sanad-$number.html');
  f.writeAsStringSync(html, flush: true);
  if (open) openFile(f.path);
  return f.path;
}
