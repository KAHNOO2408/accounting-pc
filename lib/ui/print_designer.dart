import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/jalali.dart';
import '../core/qr.dart';
import '../data/models.dart';
import '../data/mrt_import.dart';
import '../data/storage.dart';
import '../data/store.dart';
import 'dialogs/invoice_editor.dart' show fmtQty;
import 'print.dart' show openFile;
import 'report/report_designer.dart';
import 'report/report_render.dart';
import '../data/report_layout.dart';
import 'theme.dart';
import 'widgets/common.dart';

// =================================================================== model

class PrintLabel {
  final String name;
  final String code;
  final int price;
  const PrintLabel(this.name, this.code, this.price);
}

/// Everything a printout shows, independent of how it is drawn.
class PrintDoc {
  String title = '';
  List<String> business = [];
  List<(String, String)> meta = [];
  List<String> headers = [];
  List<List<String>> rows = [];
  Set<int> numeric = {};
  List<(String, String, bool)> totals = [];
  String words = '';
  String note = '';
  String footer = '';
  List<String> signatures = [];
  List<PrintLabel> labels = [];
}

String defaultPrintTitle(Invoice inv, PrintDocType t) => switch (t) {
      PrintDocType.warehouse => inv.kind.stockSign > 0 ? 'رسید انبار' : 'حواله انبار',
      PrintDocType.barcode => 'برچسب بارکد',
      PrintDocType.ledger => 'گزارش حساب',
      PrintDocType.invoice => inv.proforma ? 'پیش‌فاکتور فروش' : inv.kind.label,
    };

PrintDoc buildPrintDoc(AppStore s, Invoice inv, PrintTemplate t) {
  final d = PrintDoc();
  final st = s.settings;
  final person = s.person(inv.personId);
  d.title = t.title.trim().isEmpty ? defaultPrintTitle(inv, t.type) : t.title.trim();

  if (t.type == PrintDocType.barcode) {
    for (final l in inv.lines) {
      final p = s.product(l.productId);
      if (p == null) continue;
      final n = l.qty.ceil().clamp(1, 300);
      for (var i = 0; i < n; i++) {
        d.labels.add(PrintLabel(p.name, barcodeValue(s, p), p.sellPrice > 0 ? p.sellPrice : l.unitPrice));
      }
    }
    return d;
  }

  if (t.showHeader) {
    d.business = [
      st.businessName.isEmpty ? (st.ownerName.isEmpty ? 'فروشگاه' : st.ownerName) : st.businessName,
      if (st.businessPhone.isNotEmpty) 'تلفن: ${st.businessPhone}',
      if (st.businessAddress.isNotEmpty) st.businessAddress,
    ];
  }
  d.meta = [
    ('شماره', '${inv.number}'),
    ('تاریخ', jFormat(inv.date)),
    if (t.showBuyer) (inv.kind.buySide ? 'فروشنده' : 'خریدار', person?.name ?? (inv.kind.buySide ? 'متفرقه' : 'مشتری نقدی')),
    if (t.showBuyer && person != null && person.phone.isNotEmpty) ('تلفن', person.phone),
  ];

  final money = t.type != PrintDocType.warehouse;
  final cols = t.columns.where((c) => printColumns.containsKey(c) && (money || !{'price', 'disc', 'total'}.contains(c))).toList();
  if (!cols.contains('name')) cols.insert(cols.isEmpty ? 0 : 1, 'name');
  d.headers = [for (final c in cols) printColumns[c]!];
  d.numeric = {for (var i = 0; i < cols.length; i++) if ({'price', 'disc', 'total'}.contains(cols[i])) i};
  var n = 0;
  for (final l in inv.lines) {
    n++;
    final p = s.product(l.productId);
    d.rows.add([
      for (final c in cols)
        switch (c) {
          'idx' => '$n',
          'code' => p?.code ?? '',
          'name' => p?.name ?? l.title,
          'qty' => fmtQty(l.qty),
          'unit' => p?.unit ?? '',
          'price' => groupDigits(l.unitPrice),
          'disc' => l.discount == 0 ? '-' : groupDigits(l.discount),
          _ => groupDigits(l.total),
        },
    ]);
  }

  final cur = st.currency;
  if (money) {
    d.totals = [
      ('جمع ردیف‌ها', '${groupDigits(inv.subtotal)} $cur', false),
      if (inv.discount != 0) ('تخفیف', '${groupDigits(inv.discount)} $cur', false),
      if (inv.extra != 0) ('هزینه‌های جانبی', '${groupDigits(inv.extra)} $cur', false),
      ('مبلغ قابل پرداخت', '${groupDigits(inv.total)} $cur', true),
    ];
    if (t.showBalance && person != null && !inv.proforma) {
      var settled = 0;
      for (final v in s.settlementsOf(inv.id)) {
        for (final l in v.lines) {
          if (l.tafsiliId == person.id) settled += l.debit - l.credit;
        }
      }
      final prev = s.personBalance(person.id, excludeInvoiceId: inv.id) - settled;
      final now = s.personBalance(person.id);
      d.totals.addAll([
        (prev >= 0 ? 'مانده حساب قبلی (بدهکار)' : 'مانده حساب قبلی (بستانکار)', '${groupDigits(prev.abs())} $cur', false),
        if (settled != 0) (inv.kind.moneyIn ? 'دریافتی این فاکتور' : 'پرداختی این فاکتور', '${groupDigits(settled.abs())} $cur', false),
        (now >= 0 ? 'کل مانده حساب (بدهکار)' : 'کل مانده حساب (بستانکار)', '${groupDigits(now.abs())} $cur', true),
      ]);
    }
    if (t.showWords) d.words = '${amountInWords(inv.total)} $cur';
  }
  if (t.showNote) d.note = inv.note;
  d.footer = t.footer;
  if (t.showSignatures) {
    d.signatures = t.type == PrintDocType.warehouse ? ['امضاء تحویل دهنده', 'امضاء تحویل گیرنده'] : ['مهر و امضاء فروشنده', 'امضاء خریدار'];
  }
  return d;
}

/// Text encoded in a product's barcode (Code 128 supports ASCII only).
String barcodeValue(AppStore s, Product p) {
  final ascii = normalizeDigits(p.code).runes.where((r) => r >= 32 && r < 127).map(String.fromCharCode).join().trim();
  if (ascii.isNotEmpty) return ascii;
  final i = s.products.indexOf(p);
  return '${10000 + (i < 0 ? 0 : i)}';
}

// =================================================================== code 128

const _c128 = [
  '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213', //
  '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
  '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
  '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
  '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
  '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
  '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
  '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
  '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
  '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
  '114131', '311141', '411131', '211412', '211214', '211232',
];

/// Code 128-B modules (true = black bar) for [text], without quiet zones.
List<bool> code128(String text) {
  final codes = <int>[104];
  for (final r in text.runes) {
    codes.add((r >= 32 && r < 127 ? r : 63) - 32);
  }
  var sum = 104;
  for (var i = 1; i < codes.length; i++) {
    sum += codes[i] * i;
  }
  codes.add(sum % 103);
  final out = <bool>[];
  void emit(String pattern) {
    for (var i = 0; i < pattern.length; i++) {
      final w = int.parse(pattern[i]);
      for (var k = 0; k < w; k++) {
        out.add(i.isEven);
      }
    }
  }

  for (final c in codes) {
    emit(_c128[c]);
  }
  emit('2331112'); // stop
  return out;
}

String _barcodeSvg(String text, {double height = 34}) {
  final m = code128(text);
  final b = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${m.length + 20} $height" '
      'preserveAspectRatio="none" width="100%" height="${height}px"><rect width="100%" height="100%" fill="#fff"/>');
  var i = 0;
  while (i < m.length) {
    if (!m[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j < m.length && m[j]) {
      j++;
    }
    b.write('<rect x="${i + 10}" y="0" width="${j - i}" height="$height" fill="#000"/>');
    i = j;
  }
  b.write('</svg>');
  return b.toString();
}

class BarcodePainter extends CustomPainter {
  final List<bool> modules;
  BarcodePainter(String text) : modules = code128(text);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / (modules.length + 20);
    final paint = Paint()..color = Colors.black;
    for (var i = 0; i < modules.length; i++) {
      if (modules[i]) canvas.drawRect(Rect.fromLTWH((i + 10) * w, 0, w + 0.2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant BarcodePainter old) => old.modules.length != modules.length;
}

// =================================================================== html

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String printDocHtml(PrintDoc d, PrintTemplate t, {bool autoPrint = true}) {
  final page = switch (t.paper) {
    '80mm' => '80mm auto',
    'A4' => 'A4',
    _ => 'A5',
  };
  final b = StringBuffer();
  if (t.type == PrintDocType.barcode) {
    b.writeln('<div class="labels" style="grid-template-columns: repeat(${t.labelCols.clamp(1, 8)}, 1fr)">');
    for (final l in d.labels) {
      final mark = t.labelQr ? '<div class="lq">${qrSvg(l.code)}</div>' : _barcodeSvg(l.code);
      b.writeln('<div class="label"><div class="ln">${_esc(l.name)}</div>$mark'
          '<div class="lc">${_esc(l.code)}</div>${t.showPrice && l.price > 0 ? '<div class="lp">${groupDigits(l.price)}</div>' : ''}</div>');
    }
    b.writeln('</div>');
  } else {
    b.writeln('<div class="head"><div class="biz">');
    for (var i = 0; i < d.business.length; i++) {
      b.writeln(i == 0 ? '<h1>${_esc(d.business[i])}</h1>' : '<div>${_esc(d.business[i])}</div>');
    }
    b.writeln('</div><div class="doc"><h2>${_esc(d.title)}</h2></div></div>');
    b.writeln('<div class="meta">${d.meta.map((m) => '<div>${_esc(m.$1)}: <b>${_esc(m.$2)}</b></div>').join()}</div>');
    b.writeln('<table class="items"><thead><tr>${[
      for (var i = 0; i < d.headers.length; i++) '<th>${_esc(d.headers[i])}</th>'
    ].join()}</tr></thead><tbody>');
    for (final r in d.rows) {
      b.writeln('<tr>${[
        for (var i = 0; i < r.length; i++) '<td class="${d.numeric.contains(i) ? 'num' : (i == r.length - 1 || d.headers[i] == printColumns['name'] ? 'name' : '')}">${_esc(r[i])}</td>'
      ].join()}</tr>');
    }
    b.writeln('</tbody></table>');
    if (d.totals.isNotEmpty || d.words.isNotEmpty) {
      b.writeln('<div class="bottom"><div class="words">${d.words.isEmpty ? '' : 'مبلغ به حروف: <b>${_esc(d.words)}</b>'}</div><table class="sums">');
      for (final x in d.totals) {
        b.writeln('<tr class="${x.$3 ? 'strong' : ''}"><th>${_esc(x.$1)}</th><td class="num">${_esc(x.$2)}</td></tr>');
      }
      b.writeln('</table></div>');
    }
    if (d.note.isNotEmpty) b.writeln('<div class="note">توضیحات: ${_esc(d.note)}</div>');
    if (d.signatures.isNotEmpty) b.writeln('<div class="sign">${d.signatures.map((x) => '<div>${_esc(x)}</div>').join()}</div>');
    if (d.footer.isNotEmpty) b.writeln('<div class="footer">${_esc(d.footer)}</div>');
  }
  final narrow = t.paper == '80mm';
  return '''<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>${_esc(d.title)}</title>
<style>
  @page { size: $page; margin: ${narrow ? '3mm' : '10mm'}; }
  * { box-sizing: border-box; }
  body { font-family: Vazirmatn, Tahoma, sans-serif; font-size: ${t.fontSize}px; color: #111; margin: 0; }
  .head { display: flex; justify-content: space-between; align-items: flex-start; ${narrow ? 'flex-direction: column; align-items: center; text-align: center;' : ''} border-bottom: 2px solid #333; padding-bottom: 6px; margin-bottom: 8px; }
  .biz h1 { margin: 0; font-size: 1.5em; } .doc h2 { margin: 0; font-size: 1.3em; }
  .meta { display: flex; flex-wrap: wrap; gap: 6px 22px; margin: 6px 0 10px; }
  table { width: 100%; border-collapse: collapse; }
  .items th, .items td { border: 1px solid #999; padding: 4px 5px; text-align: center; }
  .items th { background: #eee; } .items td.name { text-align: right; }
  .num { direction: ltr; text-align: left !important; white-space: nowrap; }
  .bottom { display: flex; gap: 14px; margin-top: 10px; align-items: flex-start; ${narrow ? 'flex-direction: column;' : ''} }
  .words { flex: 1; } .sums { width: ${narrow ? '100%' : '50%'}; }
  .sums th { text-align: right; font-weight: normal; padding: 3px 6px; border-bottom: 1px solid #ddd; }
  .sums td { padding: 3px 6px; border-bottom: 1px solid #ddd; }
  .sums .strong th, .sums .strong td { font-weight: bold; }
  .note { margin-top: 8px; } .footer { margin-top: 14px; padding-top: 6px; border-top: 1px solid #999; text-align: center; color: #333; }
  .sign { display: flex; justify-content: space-around; margin-top: 30px; color: #444; }
  .labels { display: grid; gap: 4mm; }
  .label { border: 1px dashed #bbb; padding: 2mm; text-align: center; page-break-inside: avoid; }
  .ln { font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .lc { direction: ltr; font-family: monospace; letter-spacing: 1px; } .lp { font-weight: bold; }
  .lq { width: 18mm; height: 18mm; margin: 1mm auto; }
  .noprint { margin: 10px; text-align: center; } @media print { .noprint { display: none; } }
</style></head><body>
<div class="noprint"><button onclick="window.print()">چاپ</button></div>
$b
${autoPrint ? '<script>window.onload=function(){setTimeout(function(){window.print();},300);};</script>' : ''}
</body></html>''';
}

/// Writes the printout for [inv] with [t] and opens it in the browser.
String printWithTemplate(AppStore s, Invoice inv, PrintTemplate t, {bool autoPrint = true}) {
  final html = printDocHtml(buildPrintDoc(s, inv, t), t, autoPrint: autoPrint);
  final dir = Directory('${Storage.userFolder.path}${Storage.sep}prints');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}${Storage.sep}${t.type.name}-${inv.number}.html');
  f.writeAsStringSync(html, flush: true);
  openFile(f.path);
  return f.path;
}

// =================================================================== preview widget

class PrintPreview extends StatelessWidget {
  final PrintDoc doc;
  final PrintTemplate template;
  const PrintPreview({super.key, required this.doc, required this.template});

  @override
  Widget build(BuildContext context) {
    final t = template;
    final pageW = switch (t.paper) {
      '80mm' => 300.0,
      'A4' => 794.0,
      _ => 560.0,
    };
    final pageH = switch (t.paper) {
      '80mm' => null,
      'A4' => 1123.0,
      _ => 794.0,
    };
    final fs = t.fontSize.toDouble();
    final base = TextStyle(fontFamily: 'Vazirmatn', fontSize: fs, color: const Color(0xFF111111));
    final bold = base.copyWith(fontWeight: FontWeight.w800);
    Widget cell(String s, {bool head = false, bool isNum = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Text(s,
              textAlign: isNum ? TextAlign.left : TextAlign.center,
              textDirection: isNum ? TextDirection.ltr : null,
              style: head ? bold : base),
        );

    final body = <Widget>[];
    if (t.type == PrintDocType.barcode) {
      final cols = t.labelCols.clamp(1, 8);
      body.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in doc.labels.take(60))
            Container(
              width: (pageW - 40 - (cols - 1) * 8) / cols,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(l.name, style: bold, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (t.labelQr)
                  SizedBox(height: 60, width: 60, child: CustomPaint(painter: QrPainter(l.code)))
                else
                  SizedBox(height: 30, width: double.infinity, child: CustomPaint(painter: BarcodePainter(l.code))),
                Text(l.code, style: base.copyWith(fontFamily: 'monospace'), textDirection: TextDirection.ltr),
                if (t.showPrice && l.price > 0) Text(groupDigits(l.price), style: bold),
              ]),
            ),
        ],
      ));
      if (doc.labels.isEmpty) body.add(Text('کالایی برای برچسب وجود ندارد', style: base));
    } else {
      body.add(Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(width: 2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < doc.business.length; i++)
                Text(doc.business[i], style: i == 0 ? bold.copyWith(fontSize: fs * 1.5) : base),
            ]),
          ),
          Text(doc.title, style: bold.copyWith(fontSize: fs * 1.3)),
        ]),
      ));
      body.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(spacing: 20, runSpacing: 4, children: [
          for (final m in doc.meta) Text.rich(TextSpan(style: base, children: [TextSpan(text: '${m.$1}: '), TextSpan(text: m.$2, style: bold)])),
        ]),
      ));
      body.add(Table(
        border: TableBorder.all(color: Colors.black45),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          for (var i = 0; i < doc.headers.length; i++)
            i: doc.headers[i] == printColumns['name'] ? const FlexColumnWidth(3) : const FlexColumnWidth(1),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFEEEEEE)),
            children: [for (final h in doc.headers) cell(h, head: true)],
          ),
          for (final r in doc.rows)
            TableRow(children: [for (var i = 0; i < r.length; i++) cell(r[i], isNum: doc.numeric.contains(i))]),
        ],
      ));
      if (doc.totals.isNotEmpty || doc.words.isNotEmpty) {
        body.add(const SizedBox(height: 8));
        body.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: doc.words.isEmpty ? const SizedBox() : Text('مبلغ به حروف: ${doc.words}', style: base)),
          const SizedBox(width: 10),
          SizedBox(
            width: t.paper == '80mm' ? pageW * 0.6 : pageW * 0.45,
            child: Column(children: [
              for (final x in doc.totals)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
                  child: Row(children: [
                    Expanded(child: Text(x.$1, style: x.$3 ? bold : base)),
                    Text(x.$2, style: x.$3 ? bold : base, textDirection: TextDirection.ltr),
                  ]),
                ),
            ]),
          ),
        ]));
      }
      if (doc.note.isNotEmpty) body.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text('توضیحات: ${doc.note}', style: base)));
      if (doc.signatures.isNotEmpty) {
        body.add(Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [for (final x in doc.signatures) Text(x, style: base)]),
        ));
      }
      if (doc.footer.isNotEmpty) {
        body.add(Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black38))),
          child: Text(doc.footer, style: base, textAlign: TextAlign.center),
        ));
      }
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: Container(
        width: pageW,
        constraints: BoxConstraints(minHeight: pageH ?? 200),
        padding: EdgeInsets.all(t.paper == '80mm' ? 10 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))],
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body),
      ),
    );
  }
}

// =================================================================== تعیین نوع چاپ menu

/// Shows the «تعیین نوع چاپ» menu under [anchor] and opens the report builder.
Future<void> showPrintTypeMenu(BuildContext anchor, Future<Invoice?> Function() ensureSaved) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  RelativeRect pos = const RelativeRect.fromLTRB(200, 200, 200, 200);
  if (box != null && overlay != null) {
    final o = box.localToGlobal(Offset.zero, ancestor: overlay);
    pos = RelativeRect.fromLTRB(o.dx, o.dy + box.size.height, overlay.size.width - o.dx - box.size.width, 0);
  }
  final t = await showMenu<PrintDocType>(
    context: anchor,
    position: pos,
    items: [
      for (final x in PrintDocType.values.where((x) => x != PrintDocType.ledger))
        PopupMenuItem(
          value: x,
          child: Row(children: [
            Icon(
              switch (x) {
                PrintDocType.invoice => Icons.receipt_long_outlined,
                PrintDocType.warehouse => Icons.inventory_2_outlined,
                PrintDocType.barcode => Icons.qr_code_2_rounded,
                PrintDocType.ledger => Icons.receipt_long_outlined,
              },
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(x.label),
          ]),
        ),
    ],
  );
  if (t == null || !anchor.mounted) return;
  final inv = await ensureSaved();
  if (inv == null || !anchor.mounted) return;
  await showReportBuilder(anchor, inv, t);
}

// =================================================================== گزارش سازی

/// Which layouts an invoice uses: each document has its own (فاکتور فروش، فاکتور خرید، پیش فاکتور…).
String invoiceVariant(Invoice inv) => inv.proforma ? 'proforma' : inv.kind.name;

Future<void> showReportBuilder(BuildContext context, Invoice inv, PrintDocType type) => type == PrintDocType.barcode
    ? showDialog<void>(context: context, builder: (_) => _ReportBuilder(inv: inv, type: type))
    : showLayoutPicker(
        context,
        type: type,
        variant: invoiceVariant(inv),
        data: (s) => invoiceReportData(s, inv, type: type),
        fileName: '${type.name}-${inv.number}',
      );

/// «گزارش سازی» of any band layout: pick, build, edit, preview and print.
Future<void> showLayoutPicker(BuildContext context,
        {required PrintDocType type, String variant = '', required ReportData Function(AppStore s) data, String fileName = 'report'}) =>
    showDialog<void>(context: context, builder: (_) => _LayoutPicker(type: type, variant: variant, data: data, fileName: fileName));

/// Opens the in-app «Report Preview» of an invoice with the default layout.
Future<void> previewInvoice(BuildContext context, Invoice inv, PrintDocType type) {
  final s = StoreScope.read(context);
  return showReportPreview(context, s.defaultLayout(type, variant: invoiceVariant(inv)), invoiceReportData(s, inv, type: type),
      fileName: '${type.name}-${inv.number}');
}

/// «گزارش سازی» for band layouts (فاکتور / حواله انبار / پرینت حساب).
class _LayoutPicker extends StatefulWidget {
  final PrintDocType type;
  final String variant;
  final ReportData Function(AppStore s) data;
  final String fileName;
  const _LayoutPicker({required this.type, this.variant = '', required this.data, this.fileName = 'report'});

  @override
  State<_LayoutPicker> createState() => _LayoutPickerState();
}

class _LayoutPickerState extends State<_LayoutPicker> {
  String? _id;

  String get _v => hasVariants(widget.type) ? widget.variant : '';

  List<ReportLayout> _list(AppStore s) => s.layoutsOf(widget.type, variant: _v);

  ReportLayout _current(AppStore s) => _list(s).where((x) => x.id == _id).firstOrNull ?? s.defaultLayout(widget.type, variant: _v);

  ReportData _data(AppStore s) => widget.data(s);

  Future<void> _design({required bool create}) async {
    final s = StoreScope.read(context);
    final cur = _current(s);
    final base = create
        ? (cur.copy()
          ..id = newId()
          ..variant = _v
          ..name = 'طرح ${_list(s).length + 1}')
        : cur;
    final r = await showReportDesigner(context, base, _data(s));
    if (r != null && mounted) {
      s.saveLayout(r);
      setState(() => _id = r.id);
    }
  }

  /// «وارد کردن از سکان»: one layout per chosen .mrt file.
  Future<void> _importMrt() async {
    final s = StoreScope.read(context);
    final files = await fs.openFiles(acceptedTypeGroups: const [
      fs.XTypeGroup(label: 'گزارش سکان / استیمول', extensions: ['mrt', 'MRT']),
    ]);
    if (files.isEmpty || !mounted) return;
    String? lastId;
    final unknown = <String>{};
    var ok = 0;
    final errors = <String>[];
    for (final f in files) {
      try {
        final text = await f.readAsString();
        var name = f.name.replaceAll(RegExp(r'\.mrt$', caseSensitive: false), '').trim();
        if (name.isEmpty) name = 'طرح سکان';
        final r = importMrt(text, type: widget.type, variant: _v, name: name);
        s.saveLayout(r.layout);
        lastId = r.layout.id;
        unknown.addAll(r.unknownFields);
        ok++;
      } catch (e) {
        errors.add('${f.name}: $e');
      }
    }
    if (!mounted) return;
    if (lastId != null) setState(() => _id = lastId);
    if (errors.isNotEmpty) {
      toast(context, 'وارد نشد — ${errors.join('  ،  ')}', error: true);
    } else {
      toast(
        context,
        unknown.isEmpty
            ? '$ok طرح از سکان وارد شد'
            : '$ok طرح وارد شد؛ ${unknown.length} فیلد سکان معادل ندارد و خالی چاپ می‌شود (با «ویرایش» قابل اصلاح است)',
      );
    }
  }

  void _print() {
    final s = StoreScope.read(context);
    final l = _current(s);
    s.setDefaultLayout(l);
    try {
      printReport(l, _data(s), fileName: widget.fileName);
    } catch (e) {
      toast(context, 'چاپ ناموفق: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final list = _list(s);
    final l = _current(s);
    final size = MediaQuery.of(context).size;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f12): _print,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 980,
            height: (size.height * 0.9).clamp(420.0, 900.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                child: Row(children: [
                  const Icon(Icons.print_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('گزارش سازی — ${widget.type.label}${_v.isEmpty ? '' : ' (${layoutVariants[_v] ?? _v})'}',
                        style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                  Text('فیلتر گزارش', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 260,
                    child: FieldDropdown<String>(
                      label: 'گزارش',
                      value: l.id,
                      items: [
                        for (final x in list)
                          DropdownMenuItem(
                            value: x.id,
                            child: Text('${x.name}${s.defaultLayout(widget.type, variant: _v).id == x.id ? '  (پیش‌فرض)' : ''}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _id = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: () => _design(create: true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('ساخت گزارش'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.loan.withValues(alpha: 0.18), foregroundColor: AppColors.loan),
                    onPressed: () => _design(create: false),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('ویرایش'),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'فایل گزارش سکان (‎.mrt‎) را به طرح این برنامه تبدیل می‌کند',
                    child: OutlinedButton.icon(
                      onPressed: _importMrt,
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text('وارد کردن از سکان'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (s.reportLayouts.any((x) => x.id == l.id))
                    TextButton.icon(
                      onPressed: () async {
                        final builtin = l.id.startsWith('builtin-');
                        final ok = await confirm(context, builtin ? 'بازگشت به طرح اصلی' : 'حذف طرح',
                            builtin ? 'تغییرات طرح ۱ پاک شود و طرح اصلی برگردد؟' : 'طرح «${l.name}» حذف شود؟',
                            ok: builtin ? 'بازگشت' : 'حذف');
                        if (!ok) return;
                        s.removeLayout(l.id);
                        setState(() => _id = null);
                      },
                      icon: Icon(l.id.startsWith('builtin-') ? Icons.restore_rounded : Icons.delete_outline_rounded, color: th.colorScheme.error),
                      label: Text(l.id.startsWith('builtin-') ? 'بازگشت به طرح اصلی' : 'حذف طرح', style: TextStyle(color: th.colorScheme.error)),
                    ),
                ]),
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFB8BFC9),
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Center(child: Column(children: reportPages(l, _data(s), 3.0))),
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                child: Row(children: [
                  Text('کاغذ ${l.pageW.round()}×${l.pageH.round()} میلی‌متر', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                  const Spacer(),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => showReportPreview(context, l, _data(s), fileName: widget.fileName),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('مشاهده پویا'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('چاپ F12')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ReportBuilder extends StatefulWidget {
  final Invoice inv;
  final PrintDocType type;
  const _ReportBuilder({required this.inv, required this.type});

  @override
  State<_ReportBuilder> createState() => _ReportBuilderState();
}

class _ReportBuilderState extends State<_ReportBuilder> {
  String? _id;

  PrintTemplate _current(AppStore s) {
    final list = s.templatesOf(widget.type);
    return list.where((t) => t.id == _id).firstOrNull ?? s.defaultTemplate(widget.type);
  }

  Future<void> _design({PrintTemplate? edit}) async {
    final s = StoreScope.read(context);
    final base = edit?.copy() ??
        (_current(s).copy()
          ..id = newId()
          ..name = 'طرح ${s.templatesOf(widget.type).length + 1}');
    final r = await showDialog<PrintTemplate>(context: context, builder: (_) => _Designer(inv: widget.inv, template: base));
    if (r != null) {
      s.saveTemplate(r);
      setState(() => _id = r.id);
    }
  }

  void _print({bool auto = true}) {
    final s = StoreScope.read(context);
    final t = _current(s);
    s.setDefaultTemplate(t);
    try {
      printWithTemplate(s, widget.inv, t, autoPrint: auto);
    } catch (e) {
      toast(context, 'چاپ ناموفق: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final list = s.templatesOf(widget.type);
    final t = _current(s);
    final size = MediaQuery.of(context).size;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f12): _print,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 980,
            height: (size.height * 0.9).clamp(420.0, 900.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                child: Row(children: [
                  const Icon(Icons.print_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('گزارش سازی — ${widget.type.label}',
                        style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Row(children: [
                  Text('فیلتر گزارش', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 260,
                    child: FieldDropdown<String>(
                      label: 'گزارش',
                      value: t.id,
                      items: [
                        for (final x in list)
                          DropdownMenuItem(
                            value: x.id,
                            child: Text('${x.name}${s.defaultTemplate(widget.type).id == x.id ? '  (پیش‌فرض)' : ''}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _id = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: () => _design(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('ساخت گزارش'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.loan.withValues(alpha: 0.18), foregroundColor: AppColors.loan),
                    onPressed: () => _design(edit: t),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('ویرایش'),
                  ),
                  const SizedBox(width: 8),
                  if (!t.id.startsWith('builtin-') && list.length > 1)
                    IconButton(
                      tooltip: 'حذف طرح',
                      onPressed: () async {
                        final ok = await confirm(context, 'حذف طرح', 'طرح «${t.name}» حذف شود؟');
                        if (!ok) return;
                        s.removeTemplate(t.id);
                        setState(() => _id = null);
                      },
                      icon: Icon(Icons.delete_outline_rounded, color: th.colorScheme.error),
                    ),
                ]),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFDDE3EA),
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(child: PrintPreview(doc: buildPrintDoc(s, widget.inv, t), template: t)),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                child: Row(children: [
                  Text('کاغذ ${t.paper} — قلم ${t.fontSize}', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                  const Spacer(),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _print(auto: false),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('مشاهده پویا'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('چاپ (F12)')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// =================================================================== designer

class _Designer extends StatefulWidget {
  final Invoice inv;
  final PrintTemplate template;
  const _Designer({required this.inv, required this.template});

  @override
  State<_Designer> createState() => _DesignerState();
}

class _DesignerState extends State<_Designer> {
  late final PrintTemplate t = widget.template;
  late final _name = TextEditingController(text: t.name);
  late final _title = TextEditingController(text: t.title);
  late final _footer = TextEditingController(text: t.footer);

  @override
  void dispose() {
    for (final c in [_name, _title, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    t
      ..name = _name.text.trim().isEmpty ? 'طرح' : _name.text.trim()
      ..title = _title.text.trim()
      ..footer = _footer.text.trim();
    Navigator.pop(context, t);
  }

  Widget _check(String label, bool v, ValueChanged<bool> on) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: v,
        onChanged: (x) => setState(() => on(x ?? false)),
        title: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final barcode = t.type == PrintDocType.barcode;
    final money = t.type != PrintDocType.warehouse;
    // live values while typing
    final live = t.copy()
      ..title = _title.text.trim()
      ..footer = _footer.text.trim();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1180,
          height: (size.height * 0.92).clamp(440.0, 940.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HeaderBand(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              child: Row(children: [
                const Icon(Icons.design_services_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('طراحی گزارش — ${t.type.label}',
                      style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 360,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام طرح')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: 'عنوان چاپ', hintText: defaultPrintTitle(widget.inv, t.type)),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FieldDropdown<String>(
                          label: 'اندازه کاغذ',
                          value: t.paper,
                          items: const [
                            DropdownMenuItem(value: 'A4', child: Text('A4')),
                            DropdownMenuItem(value: 'A5', child: Text('A5')),
                            DropdownMenuItem(value: '80mm', child: Text('فیش ۸۰ میلی‌متری')),
                          ],
                          onChanged: (v) => setState(() => t.paper = v ?? t.paper),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FieldDropdown<int>(
                          label: 'اندازه قلم',
                          value: t.fontSize,
                          items: [for (final f in [9, 10, 11, 12, 13, 14, 16]) DropdownMenuItem(value: f, child: Text('$f'))],
                          onChanged: (v) => setState(() => t.fontSize = v ?? t.fontSize),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    if (barcode) ...[
                      FieldDropdown<int>(
                        label: 'تعداد برچسب در هر سطر',
                        value: t.labelCols,
                        items: [for (var i = 1; i <= 6; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                        onChanged: (v) => setState(() => t.labelCols = v ?? t.labelCols),
                      ),
                      _check('نمایش قیمت روی برچسب', t.showPrice, (v) => t.showPrice = v),
                      _check('QR کد به‌جای بارکد خطی', t.labelQr, (v) => t.labelQr = v),
                    ] else ...[
                      Text('بخش‌ها', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      _check('سربرگ (نام و مشخصات فروشگاه)', t.showHeader, (v) => t.showHeader = v),
                      _check('مشخصات طرف حساب', t.showBuyer, (v) => t.showBuyer = v),
                      if (money) _check('مبلغ به حروف', t.showWords, (v) => t.showWords = v),
                      if (money) _check('مانده حساب قبلی و کل مانده حساب', t.showBalance, (v) => t.showBalance = v),
                      _check('توضیحات فاکتور', t.showNote, (v) => t.showNote = v),
                      _check('محل امضاء', t.showSignatures, (v) => t.showSignatures = v),
                      const SizedBox(height: 8),
                      Text('ستون‌های جدول', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      for (final e in printColumns.entries)
                        if (money || !{'price', 'disc', 'total'}.contains(e.key))
                          _check(e.value, t.columns.contains(e.key), (v) {
                            if (v) {
                              final order = printColumns.keys.toList();
                              t.columns = [...t.columns, e.key]..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
                            } else {
                              t.columns = t.columns.where((c) => c != e.key).toList();
                            }
                          }),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _footer,
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'متن پایین برگه (آدرس، شرایط، شماره کارت…)'),
                      ),
                    ],
                  ]),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Container(
                    color: const Color(0xFFDDE3EA),
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(child: PrintPreview(doc: buildPrintDoc(s, widget.inv, live), template: live)),
                  ),
                ),
              ]),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Row(children: [
                const Spacer(),
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('ذخیره طرح (F9)')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// =================================================================== طراحی فرم های چاپ

/// One place to design the printout of each document separately.
Future<void> showPrintForms(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _PrintForms());

/// A sample invoice of [variant]: the latest real one, or a made-up one.
Invoice sampleInvoice(AppStore s, String variant) {
  final kind = variant == 'proforma' ? InvoiceKind.sale : InvoiceKind.values.firstWhere((k) => k.name == variant, orElse: () => InvoiceKind.sale);
  final real = s.invoices.where((i) => invoiceVariant(i) == variant).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (real.isNotEmpty) return real.first;
  final prods = s.productsSorted.take(3).toList();
  return Invoice(
    id: 'sample',
    kind: kind,
    proforma: variant == 'proforma',
    number: 1,
    date: DateTime.now(),
    personId: s.peopleSorted.firstOrNull?.id,
    lines: prods.isEmpty
        ? [InvoiceLine(title: 'کالای نمونه', qty: 2, unitPrice: 150000), InvoiceLine(title: 'کالای نمونه ۲', qty: 1, unitPrice: 320000)]
        : [for (final p in prods) InvoiceLine(productId: p.id, title: p.name, qty: 1, unitPrice: kind == InvoiceKind.purchase ? p.buyPrice : p.sellPrice)],
  );
}

/// Sample data of «پرینت حساب» for the designer.
ReportData sampleLedgerData(AppStore s) {
  final st = s.settings;
  final name = s.peopleSorted.firstOrNull?.name ?? 'طرف حساب نمونه';
  final today = jFormat(DateTime.now());
  Map<String, String> row(String i, String desc, String d, String c, String m, String t) =>
      {'ردیف': i, 'ش س': i, 'تاریخ سند': today, 'شرح سند': desc, 'بدهکار': d, 'بستانکار': c, 'مانده ردیف': m, 'ت': t, 'شماره ثابت': i};
  return ReportData(
    title: 'گزارش حساب $name',
    fields: {
      'نام حساب': name,
      'کد حساب': '7001',
      'عنوان کل': 'اشخاص',
      'عنوان معین': 'اشخاص',
      'نام فروشگاه': st.businessName.isEmpty ? st.ownerName : st.businessName,
      'تاریخ': today,
      'جمع بدهکار': '1,500,000',
      'جمع بستانکار': '500,000',
      'مانده': '1,000,000',
      'تشخیص': 'بد',
    },
    rows: [
      row('', 'منقول از قبل', '0', '0', '0', '-'),
      row('1', 'فاکتور 1  فروش  1 قلم کالا', '1,500,000', '0', '1,500,000', 'بد'),
      row('2', 'دریافت نقدی', '0', '500,000', '1,000,000', 'بد'),
    ],
  );
}

class _PrintForms extends StatelessWidget {
  const _PrintForms();

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final forms = <(String, IconData, Color, PrintDocType, String)>[
      ('فاکتور فروش', Icons.sell_outlined, AppColors.income, PrintDocType.invoice, 'sale'),
      ('فاکتور خرید', Icons.shopping_cart_outlined, AppColors.expense, PrintDocType.invoice, 'purchase'),
      ('پیش فاکتور', Icons.note_add_outlined, AppColors.discount, PrintDocType.invoice, 'proforma'),
      ('برگشت از فروش', Icons.assignment_return_outlined, AppColors.loan, PrintDocType.invoice, 'saleReturn'),
      ('برگشت از خرید', Icons.remove_shopping_cart_outlined, AppColors.loan, PrintDocType.invoice, 'purchaseReturn'),
      ('حواله انبار', Icons.inventory_2_outlined, AppColors.debt, PrintDocType.warehouse, ''),
      ('گزارش حساب', Icons.receipt_long_outlined, th.colorScheme.primary, PrintDocType.ledger, ''),
    ];
    return FormDialog(
      title: 'طراحی فرم های چاپ',
      width: 620,
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('هر سند طرح چاپ جدا دارد؛ روی هر کدام بزنید تا طرح‌هایش را بسازید، ویرایش کنید یا پیش‌فرض کنید.',
            style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
        const SizedBox(height: 10),
        for (final (label, icon, color, type, variant) in forms)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${s.layoutsOf(type, variant: variant).length} طرح — پیش‌فرض: ${s.defaultLayout(type, variant: variant).name}'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => showLayoutPicker(
                context,
                type: type,
                variant: variant,
                data: (st) => type == PrintDocType.ledger
                    ? sampleLedgerData(st)
                    : invoiceReportData(st, sampleInvoice(st, variant.isEmpty ? 'sale' : variant), type: type),
                fileName: '${type.name}-sample',
              ),
            ),
          ),
      ]),
    );
  }
}
