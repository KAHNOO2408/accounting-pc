import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../core/qr.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/report_layout.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../dialogs/invoice_editor.dart' show fmtQty;
import '../print.dart' show openFile;
import '../widgets/common.dart' show toast;

/// Values that fill a layout: page fields and one map per data row.
class ReportData {
  final Map<String, String> fields;
  final List<Map<String, String>> rows;
  final String title;
  const ReportData({required this.fields, required this.rows, this.title = ''});
}

/// Replaces `{field}` placeholders.
String fillText(String text, Map<String, String> values) =>
    text.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) => values[m.group(1)!.trim()] ?? '');

String _money(int v) => groupDigits(v);

/// Builds the data of an invoice printout (فاکتور / حواله انبار).
ReportData invoiceReportData(AppStore s, Invoice inv, {PrintDocType type = PrintDocType.invoice}) {
  final st = s.settings;
  final p = s.person(inv.personId);
  final title = inv.proforma ? 'پیش فاکتور فروش' : inv.kind.label;

  // settlement of this invoice («نحوه تسویه»)
  var settled = 0;
  for (final v in s.settlementsOf(inv.id)) {
    for (final l in v.lines) {
      if (p != null && l.tafsiliId == p.id) settled += l.debit - l.credit;
    }
  }
  final summary = s.settlementSummary(inv);
  var cash = 0, bank = 0, cheque = 0, discount = 0, advance = 0, other = 0;
  summary.forEach((k, v) {
    if (k.contains('چک')) {
      cheque += v;
    } else if (k.contains('تخفیف')) {
      discount += v;
    } else if (k.contains('بانک')) {
      bank += v;
    } else if (k.contains('پیش')) {
      advance += v;
    } else if (k.contains('نقد') || k.contains('صندوق') || k.contains('تنخواه')) {
      cash += v;
    } else {
      other += v;
    }
  });
  if (inv.paid > 0 && summary.isEmpty) cash += inv.paid;
  String dot(int v) => v == 0 ? '.' : _money(v);
  final sign = inv.kind.txnType.personSign;
  final before = p == null ? 0 : s.personBalance(p.id, excludeInvoiceId: inv.id) - settled;
  final debt = before + sign * inv.total;
  final received = p == null ? (cash + bank + cheque + discount + advance + other) : -settled + inv.paid;
  final after = p == null ? 0 : s.personBalance(p.id);
  final lineDisc = inv.lines.fold<int>(0, (a, l) => a + l.discount);

  final fields = <String, String>{
    'شماره حواله': inv.warehouseNo == 0 ? '${inv.number}' : '${inv.warehouseNo}',
    'شماره فاکتور': '${inv.number}',
    'شماره سند': '${s.docNumberOf('inv:${inv.id}') ?? ''}',
    'تاریخ': jFormat(inv.date),
    'عنوان فاکتور': title,
    'نام فروشگاه': st.businessName.isEmpty ? st.ownerName : st.businessName,
    'تلفن فروشنده': st.businessPhone,
    'آدرس فروشگاه': st.businessAddress,
    'نام خریدار': p?.name ?? (inv.info['buyerName']?.isNotEmpty == true ? inv.info['buyerName']! : 'متفرقه'),
    'تلفن خریدار': p?.phone ?? '',
    'آدرس خریدار': inv.info['address'] ?? '',
    'تحویل گیرنده': inv.info['receiver'] ?? '',
    'بابت': inv.info['babat'] ?? '',
    'جمع اقلام': fmtQty(inv.lines.fold<double>(0, (a, l) => a + l.qty)),
    'جمع تخفیف': _money(inv.discount + lineDisc),
    'جمع اقلام با احتساب تخفیف': _money(inv.subtotal - inv.discount),
    'جمع فاکتور بدون تخفیف': _money(inv.lines.fold<int>(0, (a, l) => a + (l.qty * l.unitPrice).round())),
    'شماره درخواست': inv.info['requestNo'] ?? '',
    'هزینه حمل': _money(inv.extra),
    'جمع کل فاکتور': _money(inv.total),
    'مبلغ به حروف': '${amountInWords(inv.total)} ${st.currency}',
    'مانده حساب از قبل': _money(before),
    'مانده بدهکاری': _money(debt),
    'جمع دریافتی': _money(received),
    'کل مانده حساب': _money(after),
    'مبلغ دریافت چک': dot(cheque),
    'مبلغ دریافت نقدی': dot(cash),
    'مبلغ تخفیف از فروش': dot(discount),
    'مبلغ حواله بانکی': dot(bank),
    'مبلغ کسر از پیش دریافت': dot(advance),
    'نحوه تسویه': summary.isEmpty ? (inv.remaining > 0 ? 'نسیه' : '') : [for (final e in summary.entries) '${e.key}: ${_money(e.value)}'].join('  ،  '),
    'هزینه حمل بعهده خریدار': _money(inv.extra),
    'هزینه حمل بعهده فروشنده': dot(inv.shipBySeller),
    'توضیحات': inv.note,
  };
  final rows = <Map<String, String>>[];
  var i = 0;
  for (final l in inv.lines) {
    i++;
    final pr = s.product(l.productId);
    rows.add({
      'ردیف': '$i',
      'کد کالا': pr?.code ?? '',
      'نام کالا': pr?.name ?? l.title,
      'تعداد': fmtQty(l.qty),
      'واحد': pr?.unit ?? '',
      'فی': _money(l.unitPrice),
      'تخفیف': _money(l.discount),
      'جمع': _money(l.total),
      'جمع بدون تخفیف': _money((l.qty * l.unitPrice).round()),
      'نام انبار': s.warehouse(l.warehouseId)?.name ?? '',
    });
  }
  return ReportData(fields: fields, rows: rows, title: '$title ${inv.number}');
}

/// Splits rows into pages. The footers go on the last page.
List<List<Map<String, String>>> paginate(ReportLayout l, ReportData d) {
  final avail = l.pageH - 2 * l.margin;
  final head = l.heightOf(BandKind.header) + l.heightOf(BandKind.columns);
  final foot = l.heightOf(BandKind.footer1) + l.heightOf(BandKind.footer2);
  final rowH = l.heightOf(BandKind.data);
  final perPage = ((avail - head) / rowH).floor().clamp(1, 1000);
  final perLast = ((avail - head - foot) / rowH).floor().clamp(0, 1000);
  final pages = <List<Map<String, String>>>[];
  var rest = [...d.rows];
  while (rest.length > perLast) {
    final n = rest.length < perPage ? rest.length : perPage;
    pages.add(rest.take(n).toList());
    rest = rest.skip(n).toList();
  }
  pages.add(rest);
  return pages;
}

const _ptToMm = 0.3528;

// =================================================================== Flutter

class ReportItemView extends StatelessWidget {
  final RItem item;
  final String text;
  final double scale; // px per mm
  final bool selected;
  const ReportItemView({super.key, required this.item, required this.text, required this.scale, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final b = item.border;
    final bw = (item.borderWidth * scale).cl(0.6, 6.0);
    BorderSide side(int bit) => b & bit != 0 ? BorderSide(color: Colors.black, width: bw) : BorderSide.none;
    if (item.isQr) {
      return Container(
        width: item.w * scale,
        height: item.h * scale,
        decoration: BoxDecoration(
          border: Border(top: side(Sides.top), right: side(Sides.right), bottom: side(Sides.bottom), left: side(Sides.left)),
        ),
        foregroundDecoration: selected ? BoxDecoration(border: Border.all(color: Colors.blue, width: 1.5)) : null,
        child: text.trim().isEmpty
            ? const Center(child: Icon(Icons.qr_code_2_rounded, color: Colors.black26))
            : CustomPaint(painter: QrPainter(text)),
      );
    }
    Widget child = Text(
      text,
      maxLines: item.vertical ? 1 : null,
      softWrap: !item.vertical,
      overflow: TextOverflow.clip,
      textAlign: switch (item.align) {
        'center' => TextAlign.center,
        'left' => TextAlign.left,
        _ => TextAlign.right,
      },
      style: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: item.fontSize * _ptToMm * scale,
        height: 1.15,
        fontWeight: item.bold ? FontWeight.w800 : FontWeight.w400,
        color: Colors.black,
      ),
    );
    if (item.vertical) child = RotatedBox(quarterTurns: 3, child: child);
    return Container(
      width: item.w * scale,
      height: item.h * scale,
      padding: EdgeInsets.symmetric(horizontal: 0.6 * scale),
      decoration: BoxDecoration(
        color: item.fill == 0 ? null : Color(item.fill),
        border: Border(top: side(Sides.top), right: side(Sides.right), bottom: side(Sides.bottom), left: side(Sides.left)),
      ),
      foregroundDecoration: selected ? BoxDecoration(border: Border.all(color: Colors.blue, width: 1.5)) : null,
      alignment: switch (item.align) {
        'center' => Alignment.center,
        'left' => Alignment.centerLeft,
        _ => Alignment.centerRight,
      },
      child: text.isEmpty ? null : FittedBox(fit: BoxFit.scaleDown, alignment: _al(item.align), child: child),
    );
  }

  Alignment _al(String a) => switch (a) {
        'center' => Alignment.center,
        'left' => Alignment.centerLeft,
        _ => Alignment.centerRight,
      };
}

Widget _band(ReportLayout l, BandKind b, Map<String, String> values, double scale) => SizedBox(
      width: l.contentW * scale,
      height: l.heightOf(b) * scale,
      child: Stack(clipBehavior: Clip.none, children: [
        for (final it in l.itemsOf(b))
          Positioned(
            left: it.x * scale,
            top: it.y * scale,
            child: ReportItemView(item: it, text: fillText(it.text, values), scale: scale),
          ),
      ]),
    );

/// The printed pages as widgets.
List<Widget> reportPages(ReportLayout l, ReportData d, double scale) {
  final pages = paginate(l, d);
  return [
    for (var p = 0; p < pages.length; p++)
      Container(
        width: l.pageW * scale,
        height: l.pageH * scale,
        margin: const EdgeInsets.only(bottom: 18),
        padding: EdgeInsets.all(l.margin * scale),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))]),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _band(l, BandKind.header, {...d.fields, 'صفحه': '${p + 1} of ${pages.length}'}, scale),
            _band(l, BandKind.columns, d.fields, scale),
            for (final r in pages[p]) _band(l, BandKind.data, {...d.fields, ...r}, scale),
            if (p == pages.length - 1) ...[
              _band(l, BandKind.footer1, d.fields, scale),
              _band(l, BandKind.footer2, d.fields, scale),
            ],
          ]),
        ),
      ),
  ];
}

// =================================================================== HTML

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _itemHtml(RItem it, String text) {
  String bd(int bit, String side) => it.border & bit != 0 ? 'border-$side:${it.borderWidth}mm solid #000;' : '';
  if (it.isQr) {
    return '<div class="it qr" style="left:${it.x}mm;top:${it.y}mm;width:${it.w}mm;height:${it.h}mm;'
        '${bd(Sides.top, 'top')}${bd(Sides.right, 'right')}${bd(Sides.bottom, 'bottom')}${bd(Sides.left, 'left')}">'
        '${qrSvg(text)}</div>';
  }
  final align = switch (it.align) {
    'center' => 'center',
    'left' => 'left',
    _ => 'right',
  };
  final justify = switch (it.align) {
    'center' => 'center',
    'left' => 'flex-end',
    _ => 'flex-start',
  };
  final rot = it.vertical ? 'writing-mode:vertical-rl;transform:rotate(180deg);' : '';
  return '<div class="it" style="left:${it.x}mm;top:${it.y}mm;width:${it.w}mm;height:${it.h}mm;'
      '${bd(Sides.top, 'top')}${bd(Sides.right, 'right')}${bd(Sides.bottom, 'bottom')}${bd(Sides.left, 'left')}'
      '${it.fill == 0 ? '' : 'background:#${(it.fill & 0xFFFFFF).toRadixString(16).padLeft(6, '0')};'}'
      'font-size:${it.fontSize}pt;font-weight:${it.bold ? 800 : 400};justify-content:$justify;text-align:$align;">'
      '<span style="$rot">${_esc(text)}</span></div>';
}

String _bandHtml(ReportLayout l, BandKind b, Map<String, String> values) {
  final sb = StringBuffer('<div class="band" style="height:${l.heightOf(b)}mm">');
  for (final it in l.itemsOf(b)) {
    sb.write(_itemHtml(it, fillText(it.text, values)));
  }
  sb.write('</div>');
  return sb.toString();
}

String reportHtml(ReportLayout l, ReportData d, {bool autoPrint = true}) {
  final pages = paginate(l, d);
  final body = StringBuffer();
  for (var p = 0; p < pages.length; p++) {
    body.write('<div class="page">');
    body.write(_bandHtml(l, BandKind.header, {...d.fields, 'صفحه': '${p + 1} of ${pages.length}'}));
    body.write(_bandHtml(l, BandKind.columns, d.fields));
    for (final r in pages[p]) {
      body.write(_bandHtml(l, BandKind.data, {...d.fields, ...r}));
    }
    if (p == pages.length - 1) {
      body.write(_bandHtml(l, BandKind.footer1, d.fields));
      body.write(_bandHtml(l, BandKind.footer2, d.fields));
    }
    body.write('</div>');
  }
  return '''<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>${_esc(d.title)}</title>
<style>
  @page { size: ${l.pageW}mm ${l.pageH}mm; margin: 0; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: Vazirmatn, Tahoma, sans-serif; color: #000; }
  .page { width: ${l.pageW}mm; height: ${l.pageH}mm; padding: ${l.margin}mm; position: relative; overflow: hidden; page-break-after: always; }
  .page:last-child { page-break-after: auto; }
  .band { position: relative; width: ${l.contentW}mm; direction: ltr; }
  .it { position: absolute; display: flex; align-items: center; overflow: hidden; direction: rtl; padding: 0 0.6mm; white-space: nowrap; line-height: 1.15; }
  .it.qr { padding: 0; justify-content: center; }
  .noprint { text-align: center; margin: 8px; } @media print { .noprint { display: none; } }
</style></head><body>
<div class="noprint"><button onclick="window.print()">چاپ</button></div>
$body
${autoPrint ? '<script>window.onload=function(){setTimeout(function(){window.print();},300);};</script>' : ''}
</body></html>''';
}

String printReport(ReportLayout l, ReportData d, {String fileName = 'report', bool autoPrint = true}) {
  final dir = Directory('${Storage.userFolder.path}${Storage.sep}prints');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}${Storage.sep}$fileName.html');
  f.writeAsStringSync(reportHtml(l, d, autoPrint: autoPrint), flush: true);
  openFile(f.path);
  return f.path;
}

// =================================================================== Report Preview window

/// «خروجی به اکسل» of a report: one Excel column per text box of the data band
/// (right to left), headed by the column-band box above it.
String exportReportXlsx(AppStore s, ReportLayout l, ReportData d, {String fileName = 'report'}) {
  final data = l.itemsOf(BandKind.data).where((i) => !i.isQr && i.text.trim().isNotEmpty).toList()
    ..sort((a, b) => b.x.compareTo(a.x));
  final heads = l.itemsOf(BandKind.columns).where((i) => !i.isQr && i.text.trim().isNotEmpty).toList();
  String header(RItem it) {
    RItem? best;
    var bestOverlap = 0.0;
    for (final h in heads) {
      final o = (it.x + it.w < h.x + h.w ? it.x + it.w : h.x + h.w) - (it.x > h.x ? it.x : h.x);
      if (o > bestOverlap) {
        bestOverlap = o;
        best = h;
      }
    }
    final t = best == null ? it.text : fillText(best.text, d.fields);
    return t.replaceAll(RegExp(r'[{}]'), '').trim();
  }

  final headers = [for (final it in data) header(it)];
  final rows = [
    for (final r in d.rows) [for (final it in data) fillText(it.text, {...d.fields, ...r}).trim()]
  ];
  final title = d.title.isNotEmpty ? d.title : l.name;
  return s.exportTableXlsx(headers, rows, name: fileName, sheet: title, titleLines: [
    title,
    if (s.settings.businessName.isNotEmpty) s.settings.businessName,
  ]);
}

Future<void> showReportPreview(BuildContext context, ReportLayout l, ReportData d, {String fileName = 'report'}) =>
    showDialog<void>(context: context, builder: (_) => _Preview(layout: l, data: d, fileName: fileName));

class _Preview extends StatefulWidget {
  final ReportLayout layout;
  final ReportData data;
  final String fileName;
  const _Preview({required this.layout, required this.data, required this.fileName});

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  double _zoom = 1.4;

  void _print() {
    try {
      printReport(widget.layout, widget.data, fileName: widget.fileName);
    } catch (_) {}
  }

  void _excel() {
    try {
      final path = exportReportXlsx(StoreScope.read(context), widget.layout, widget.data, fileName: widget.fileName);
      openFile(path);
      toast(context, 'فایل اکسل ساخته شد');
    } catch (e) {
      toast(context, 'خروجی اکسل ناموفق: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const mm = 3.78; // px per mm at 100%
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _print,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _excel,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: size.width - 24,
            height: size.height - 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: const Color(0xFFECEFF4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(children: [
                    const Text('Report-Preview', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 16),
                    IconButton(tooltip: 'Print (Ctrl+P)', onPressed: _print, icon: const Icon(Icons.print_outlined)),
                    IconButton(
                      tooltip: 'Export to Excel (Ctrl+E)',
                      onPressed: _excel,
                      icon: const Icon(Icons.grid_on_rounded, color: Color(0xFF15803D)),
                    ),
                    IconButton(
                      tooltip: 'Zoom out',
                      onPressed: () => setState(() => _zoom = (_zoom - 0.1).cl(0.5, 3)),
                      icon: const Icon(Icons.zoom_out),
                    ),
                    Text('${(_zoom * 100).round()}%'),
                    IconButton(
                      tooltip: 'Zoom in',
                      onPressed: () => setState(() => _zoom = (_zoom + 0.1).cl(0.5, 3)),
                      icon: const Icon(Icons.zoom_in),
                    ),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ]),
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFF9EA7B3),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(children: reportPages(widget.layout, widget.data, mm * _zoom)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

extension _Cl on double {
  double cl(num lo, num hi) => this < lo ? lo.toDouble() : (this > hi ? hi.toDouble() : this);
}
