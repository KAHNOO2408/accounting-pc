import 'dart:io';

import '../core/format.dart';
import '../core/jalali.dart';
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
