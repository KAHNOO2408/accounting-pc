/// «وارد کردن طرح سکان»: converts a Stimulsoft report file (.mrt), as used by
/// Sakan's report designer, into a band layout of this app. Text boxes, frames,
/// lines and rectangles keep their position and size; Sakan's data fields are
/// mapped to the fields of this app (unknown fields print empty).
library;

import 'models.dart' show PrintDocType;
import 'report_layout.dart';

// --------------------------------------------------------------------- tiny XML

class _X {
  final String name;
  final Map<String, String> attrs;
  final List<_X> children = [];
  final StringBuffer _text = StringBuffer();
  _X(this.name, this.attrs);

  String get text => _text.toString();

  _X? child(String n) {
    for (final c in children) {
      if (c.name == n) return c;
    }
    return null;
  }

  String prop(String n) => child(n)?.text.trim() ?? '';
}

String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|lt|gt|amp|quot|apos);'), (m) {
      final e = m[1]!;
      if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
      return switch (e) { 'lt' => '<', 'gt' => '>', 'amp' => '&', 'quot' => '"', _ => "'" };
    });

_X _parse(String xml) {
  final root = _X('#root', const {});
  final stack = <_X>[root];
  var i = 0;
  final n = xml.length;
  final tag = RegExp(r'<(/?)([^\s/>]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|' "'[^']*'" r'))*)\s*(/?)>');
  final attr = RegExp(r'([^\s=]+)\s*=\s*(?:"([^"]*)"|' "'([^']*)')");
  while (i < n) {
    final lt = xml.indexOf('<', i);
    if (lt < 0) {
      stack.last._text.write(_unescape(xml.substring(i)));
      break;
    }
    if (lt > i) stack.last._text.write(_unescape(xml.substring(i, lt)));
    if (xml.startsWith('<?', lt)) {
      final e = xml.indexOf('?>', lt);
      i = e < 0 ? n : e + 2;
      continue;
    }
    if (xml.startsWith('<!--', lt)) {
      final e = xml.indexOf('-->', lt);
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (xml.startsWith('<![CDATA[', lt)) {
      final e = xml.indexOf(']]>', lt);
      stack.last._text.write(xml.substring(lt + 9, e < 0 ? n : e));
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (xml.startsWith('<!', lt)) {
      final e = xml.indexOf('>', lt);
      i = e < 0 ? n : e + 1;
      continue;
    }
    final m = tag.matchAsPrefix(xml, lt);
    if (m == null) {
      stack.last._text.write('<');
      i = lt + 1;
      continue;
    }
    i = m.end;
    if (m[1] == '/') {
      if (stack.length > 1) stack.removeLast();
      continue;
    }
    final attrs = <String, String>{
      for (final a in attr.allMatches(m[3] ?? '')) a[1]!: _unescape(a[2] ?? a[3] ?? ''),
    };
    final el = _X(m[2]!, attrs);
    stack.last.children.add(el);
    if (m[4] != '/') stack.add(el);
  }
  return root;
}

// --------------------------------------------------------------------- fields

/// Sakan column → field of this app (invoices, warehouse slips).
const _invoiceMap = {
  // header (PrintInfoFrosh, InfromationFactorKharid, infoBackFrosh…)
  'Kharidar': 'نام خریدار',
  'FroshandeName': 'نام خریدار',
  'Froshande': 'نام خریدار',
  'KharidarName': 'نام خریدار',
  'Dte_Shamsi': 'تاریخ',
  'FactorDate_Shamsi': 'تاریخ',
  'DteP_Shamsi': 'تاریخ',
  'Dte': 'تاریخ',
  'Fdate_Shamsi': 'تاریخ',
  'ShFactor': 'شماره فاکتور',
  'FCode': 'شماره فاکتور',
  'HavaleNum': 'شماره حواله',
  'DocMabnaNum': 'شماره سند',
  'DocNum': 'شماره سند',
  'Tel1': 'تلفن فروشنده',
  'Tel2': 'تلفن فروشنده',
  'KharidarTel': 'تلفن خریدار',
  'Mobile': 'تلفن خریدار',
  'Address': 'آدرس خریدار',
  'Babat': 'بابت',
  'shdarkhast': 'شماره درخواست',
  'JamFator_system': 'جمع کل فاکتور',
  'JamFator': 'جمع کل فاکتور',
  'MablaghFactorSystem': 'جمع کل فاکتور',
  'MablagKolFactorTSystem': 'جمع اقلام با احتساب تخفیف',
  'MablagKolFactorT': 'جمع اقلام با احتساب تخفیف',
  'MablagKolFactorSystem': 'جمع فاکتور بدون تخفیف',
  'MablagKolFactor': 'جمع فاکتور بدون تخفیف',
  'MablaghFactorBKHTSystem': 'جمع فاکتور بدون تخفیف',
  'JamTakhfif_sys': 'جمع تخفیف',
  'JamTakhfif': 'جمع تخفیف',
  'JamTakhfifAghlam_system': 'جمع تخفیف',
  'HazineKharidar_system': 'هزینه حمل بعهده خریدار',
  'HazineKharidar': 'هزینه حمل بعهده خریدار',
  'jamHazinehaSystem': 'هزینه حمل بعهده فروشنده',
  'BedBesRemainOld_system': 'مانده حساب از قبل',
  'BedBesRemainOld': 'مانده حساب از قبل',
  'BedBesRemainNew_system': 'کل مانده حساب',
  'BedBesRemainNew': 'کل مانده حساب',
  'BedRemainNew_System': 'کل مانده حساب',
  'JamDrayafti_system': 'جمع دریافتی',
  'JamDrayafti': 'جمع دریافتی',
  'JamPardakhati_system': 'جمع دریافتی',
  'JamPardakhati': 'جمع دریافتی',
  'TasvieDateNumber': 'نحوه تسویه',
  'Tozihat': 'توضیحات',
  // PrintMali
  'Money_TakhfifAzForosh': 'مبلغ تخفیف از فروش',
  'Money_TakhfifAzKharid': 'مبلغ تخفیف از فروش',
  'Money_DaryafteCheq': 'مبلغ دریافت چک',
  'Money_PardakhteCheq': 'مبلغ دریافت چک',
  'Money_DaryaftNaghdy': 'مبلغ دریافت نقدی',
  'Money_PardakhtNaghdy': 'مبلغ دریافت نقدی',
  'Money_DaryaftHavaleyeBanki': 'مبلغ حواله بانکی',
  'Money_PardakhtHavaleyeBanki': 'مبلغ حواله بانکی',
  // company (Information)
  'ReportHeader': 'نام فروشگاه',
  'CompanyName': 'نام فروشگاه',
  'DaftarName': 'نام فروشگاه',
  'CAddress': 'آدرس فروشگاه',
  'Tels': 'تلفن فروشنده',
  'DateShamsi': 'تاریخ',
};

/// Columns of the item rows.
const _rowMap = {
  'FrasiName': 'نام کالا',
  'KalaName': 'نام کالا',
  'Name': 'نام کالا',
  'FiVahed1System': 'فی',
  'Fiv1System': 'فی',
  'Fi_system': 'فی',
  'FiVahed1': 'فی',
  'Fi': 'فی',
  'TedadVahed1': 'تعداد',
  'Tedad': 'تعداد',
  'VahedName1': 'واحد',
  'VahedName': 'واحد',
  'JamKalaKaridarSystem': 'جمع',
  'JamKalaKaridar': 'جمع',
  'jamesatr': 'جمع',
  'JamKol': 'جمع',
  'Jam1System': 'جمع بدون تخفیف',
  'TakhfifSystem': 'تخفیف',
  'Takhfif': 'تخفیف',
  'Barcode': 'کد کالا',
  'KalaCode': 'کد کالا',
  'Code': 'کد کالا',
  'AnbarName': 'نام انبار',
};

/// Ledger reports (دفتر کل / معین / تفصیلی).
const _ledgerMap = {
  'Sharh': 'شرح سند',
  'Bed': 'بدهکار',
  'Bes': 'بستانکار',
  'Remian': 'مانده ردیف',
  'Remain': 'مانده ردیف',
  'Date_x0020_Shamsi': 'تاریخ سند',
  'Date_Shamsi': 'تاریخ سند',
  'DocNum': 'ش س',
  'DocMabnaNum': 'شماره ثابت',
  'Type': 'ت',
  'BName': 'نام حساب',
  'BID': 'کد حساب',
  'KolName': 'عنوان کل',
  'MName': 'عنوان معین',
  'ReportHeader': 'نام فروشگاه',
  'CompanyName': 'نام فروشگاه',
  'DateShamsi': 'تاریخ',
};

/// Item-row data sources (one record per printed row).
bool _isRowSource(String src) => RegExp(r'Kala|Aghlam|Khadamat|Servic|Book|Cardex|Havale', caseSensitive: false).hasMatch(src);

/// Maps one `{expression}` of a Sakan text box to a field of this app, or ''.
String mapSakanExpression(String expr, PrintDocType type) {
  var e = expr.trim();
  if (e.isEmpty) return '';
  if (e == 'Line' || e == 'LineABC' || e == 'LineRoman') return '{ردیف}';
  if (e == 'PageNofM' || e == 'PageNumber' || e == 'PageNumberThrough') return '{صفحه}';
  if (e == 'Today' || e == 'Time') return '';
  final ledger = type == PrintDocType.ledger;
  if (e.startsWith('Farsi.BeHorof(') || e.contains('ToWords')) return ledger ? '' : '{مبلغ به حروف}';
  // casts and Sum(...)
  e = e.replaceAll(RegExp(r'^\((double|decimal|int|long|string)\)\s*'), '');
  final sum = RegExp(r'^Sum\(([^()]+)\)$').firstMatch(e);
  if (sum != null) {
    final col = sum[1]!.split('.').last.trim();
    if (ledger) {
      return switch (col) { 'Bed' => '{جمع بدهکار}', 'Bes' => '{جمع بستانکار}', _ => '' };
    }
    return switch (col) {
      'TedadVahed1' || 'Tedad' => '{جمع اقلام}',
      'Jam1System' || 'JamKol' => '{جمع فاکتور بدون تخفیف}',
      'JamKalaKaridarSystem' || 'jamesatr' => '{جمع اقلام با احتساب تخفیف}',
      'TakhfifSystem' => '{جمع تخفیف}',
      _ => '',
    };
  }
  // the summed payment boxes of Sakan's invoices
  if (e.contains('+')) {
    if (e.contains('Money_DaryafteCheq')) return '{مبلغ دریافت چک}';
    if (e.contains('Money_DaryaftNaghdy')) return '{مبلغ دریافت نقدی}';
    if (e.contains('MablagKolFactorTSystem')) return '{جمع اقلام با احتساب تخفیف}';
    return '';
  }
  final m = RegExp(r'^([A-Za-z_][\w]*)\.([\w]+)$').firstMatch(e);
  if (m == null) return '';
  final src = m[1]!;
  final col = m[2]!;
  if (ledger) {
    final f = _ledgerMap[col];
    return f == null ? '' : '{$f}';
  }
  final f = _isRowSource(src) ? (_rowMap[col] ?? _invoiceMap[col]) : (_invoiceMap[col] ?? _rowMap[col]);
  return f == null ? '' : '{$f}';
}

String _mapText(String text, PrintDocType type) =>
    text.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) => mapSakanExpression(m[1]!, type)).replaceAll('\r', '');

// --------------------------------------------------------------------- conversion

class _Rect {
  final double x, y, w, h;
  const _Rect(this.x, this.y, this.w, this.h);
  static _Rect parse(String s) {
    final p = s.split(',').map((v) => double.tryParse(v.trim()) ?? 0).toList();
    while (p.length < 4) {
      p.add(0);
    }
    return _Rect(p[0], p[1], p[2], p[3]);
  }
}

const _bandTypes = {
  'ReportTitleBand',
  'PageHeaderBand',
  'HeaderBand',
  'GroupHeaderBand',
  'DataBand',
  'GroupFooterBand',
  'FooterBand',
  'ReportSummaryBand',
  'PageFooterBand',
  'ColumnHeaderBand',
  'ColumnFooterBand',
  'ChildBand',
};

class _Band {
  final String type;
  final _X el;
  final _Rect r;
  _Band(this.type, this.el, this.r);
}

String _sType(_X e) {
  final t = e.attrs['type'] ?? '';
  final i = t.lastIndexOf('.');
  final s = i < 0 ? t : t.substring(i + 1);
  return s.startsWith('Sti') ? s.substring(3) : s;
}

int _sides(String border) {
  final part = border.split(';').first;
  if (border.contains(';Transparent;')) return 0;
  var b = 0;
  for (final s in part.split(',')) {
    switch (s.trim()) {
      case 'All':
        b = Sides.all;
      case 'Top':
        b |= Sides.top;
      case 'Bottom':
        b |= Sides.bottom;
      case 'Left':
        b |= Sides.left;
      case 'Right':
        b |= Sides.right;
    }
  }
  return b;
}

double _borderWidth(String border) {
  final p = border.split(';');
  final w = p.length > 2 ? double.tryParse(p[2]) ?? 1 : 1;
  return (w * 0.3).clamp(0.2, 1.5).toDouble();
}

const _named = {
  'WhiteSmoke': 0xFFF5F5F5,
  'Gainsboro': 0xFFDCDCDC,
  'MistyRose': 0xFFFFE4E1,
  'LightGray': 0xFFD3D3D3,
  'Silver': 0xFFC0C0C0,
  'Azure': 0xFFF0FFFF,
  'LightSteelBlue': 0xFFB0C4DE,
  'LightBlue': 0xFFADD8E6,
  'PaleGoldenrod': 0xFFEEE8AA,
  'LightSkyBlue': 0xFF87CEFA,
  'PaleGreen': 0xFF98FB98,
  'LightYellow': 0xFFFFFFE0,
  'Lavender': 0xFFE6E6FA,
  'Beige': 0xFFF5F5DC,
  'LightCyan': 0xFFE0FFFF,
  'Honeydew': 0xFFF0FFF0,
  'AliceBlue': 0xFFF0F8FF,
  'Linen': 0xFFFAF0E6,
  'Ivory': 0xFFFFFFF0,
  'Khaki': 0xFFF0E68C,
  'Yellow': 0xFFFFFF00,
  'Black': 0xFF000000,
  'Gray': 0xFF808080,
  'DarkGray': 0xFFA9A9A9,
};

int _fill(String brush) {
  final b = brush.trim();
  if (b.isEmpty || b == 'Transparent' || b == 'White' || b.startsWith('[255:255:255')) return 0;
  final rgb = RegExp(r'^\[(\d+):(\d+):(\d+)(?::(\d+))?\]$').firstMatch(b);
  if (rgb != null) {
    final v = [for (var i = 1; i <= 4; i++) int.tryParse(rgb[i] ?? '') ?? 255];
    // [a:r:g:b] or [r:g:b]
    final (a, r, g, bl) = rgb[4] == null ? (255, v[0], v[1], v[2]) : (v[0], v[1], v[2], v[3]);
    if (a == 0) return 0;
    return 0xFF000000 | (r << 16) | (g << 8) | bl;
  }
  return _named[b] ?? 0;
}

int _seq = 0;
String _newId() => 'm${DateTime.now().microsecondsSinceEpoch}${_seq++}';

/// Name of the report stored in the file (or '').
String mrtReportName(String xml) {
  final m = RegExp(r'<ReportName>([^<]*)</ReportName>').firstMatch(xml);
  final n = m?[1]?.trim() ?? '';
  return n == 'Report' ? '' : n;
}

/// Result of an import, with what could not be brought over.
class MrtImport {
  final ReportLayout layout;
  final int items;
  final int skipped;
  final List<String> unknownFields;
  const MrtImport(this.layout, this.items, this.skipped, this.unknownFields);
}

/// Converts the .mrt [xml] into a layout of [type]. Throws [FormatException]
/// when the file is not a Stimulsoft report.
MrtImport importMrt(String xml, {required PrintDocType type, String variant = '', String name = 'طرح سکان'}) {
  if (!xml.contains('<StiSerializer')) throw const FormatException('این فایل، گزارش استیمول (mrt) نیست');
  final root = _parse(xml.startsWith('﻿') ? xml.substring(1) : xml);
  final ser = root.child('StiSerializer');
  final pages = ser?.child('Pages');
  if (pages == null || pages.children.isEmpty) throw const FormatException('صفحه‌ای در فایل گزارش نیست');
  final page = pages.children.first;

  // Report unit → millimetres.
  final unit = ser!.prop('ReportUnit');
  final k = switch (unit) {
    'Millimeters' => 1.0,
    'Inches' => 25.4,
    'HundredthsOfInch' => 0.254,
    _ => 10.0, // Centimeters
  };

  var pageW = (double.tryParse(page.prop('PageWidth')) ?? 21) * k;
  var pageH = (double.tryParse(page.prop('PageHeight')) ?? 29.7) * k;
  final pm = page.prop('Margins').isEmpty ? '1,1,1,1' : page.prop('Margins');
  final margins = pm.split(',').map((v) => (double.tryParse(v.trim()) ?? 1) * k).toList();
  // one margin for all sides here: the left/right one keeps the band width
  final margin = margins.isEmpty ? 10.0 : (margins.length > 1 ? (margins[0] < margins[1] ? margins[0] : margins[1]) : margins[0]);
  if (pageW <= 0) pageW = 210;
  if (pageH <= 0) pageH = 297;

  final comps = page.child('Components')?.children ?? const <_X>[];
  final bands = <_Band>[];
  final loose = <_X>[];
  for (final c in comps) {
    final t = _sType(c);
    if (_bandTypes.contains(t)) {
      bands.add(_Band(t, c, _Rect.parse(c.prop('ClientRectangle'))));
    } else {
      loose.add(c);
    }
  }
  bands.sort((a, b) => a.r.y.compareTo(b.r.y));

  // Which of our bands each Sakan band goes to.
  final dataIdx = bands.indexWhere((b) => b.type == 'DataBand');
  final assign = <_Band, BandKind>{};
  if (dataIdx >= 0) {
    assign[bands[dataIdx]] = BandKind.data;
    // column titles: the HeaderBand right above the data
    for (var i = dataIdx - 1; i >= 0; i--) {
      final t = bands[i].type;
      if (t == 'HeaderBand' || t == 'ColumnHeaderBand') {
        assign[bands[i]] = BandKind.columns;
        break;
      }
      if (t != 'GroupHeaderBand') break;
    }
    for (var i = 0; i < dataIdx; i++) {
      final b = bands[i];
      if (assign.containsKey(b) || b.type == 'GroupHeaderBand') continue;
      assign[b] = BandKind.header;
    }
    var firstAfter = true;
    for (var i = dataIdx + 1; i < bands.length; i++) {
      final b = bands[i];
      if (b.type == 'GroupFooterBand' || b.type == 'DataBand' || b.type == 'GroupHeaderBand') continue;
      if (b.type == 'PageHeaderBand' || b.type == 'ReportTitleBand') {
        assign[b] = BandKind.header;
        continue;
      }
      assign[b] = firstAfter ? BandKind.footer1 : BandKind.footer2;
      firstAfter = false;
    }
  } else {
    for (final b in bands) {
      assign[b] = BandKind.header;
    }
  }

  // Stack the Sakan bands of each of our bands one under another.
  final offset = <_Band, double>{};
  final heights = {for (final b in BandKind.values) b: 0.0};
  for (final kind in BandKind.values) {
    final group = bands.where((b) => assign[b] == kind).toList();
    var y = 0.0;
    for (final b in group) {
      offset[b] = y;
      y += b.r.h * k;
    }
    heights[kind] = y;
  }

  final items = <RItem>[];
  var skipped = 0;
  final unknown = <String>{};

  void addComp(_X c, BandKind band, double ox, double oy, double maxH) {
    final t = _sType(c);
    final r = _Rect.parse(c.prop('ClientRectangle'));
    var x = ox + r.x * k, y = oy + r.y * k, w = r.w * k, h = r.h * k;
    if (y < 0) {
      h += y;
      y = 0;
    }
    if (maxH > 0 && y + h > maxH) h = maxH - y;
    if (w <= 0 && h <= 0) return;
    switch (t) {
      case 'Text':
      case 'TextInCells':
      case 'RichText':
        final raw = c.prop('Text');
        for (final m in RegExp(r'\{([^{}]*)\}').allMatches(raw)) {
          if (mapSakanExpression(m[1]!, type).isEmpty) unknown.add(m[1]!.trim());
        }
        final font = c.prop('Font').split(',');
        final size = font.length > 1 ? double.tryParse(font[1].trim()) ?? 10 : 10;
        final opts = c.prop('TextOptions');
        final angle = int.tryParse(RegExp(r'Angle=(-?\d+)').firstMatch(opts)?[1] ?? '0') ?? 0;
        var al = c.prop('HorAlignment');
        // Stimulsoft mirrors the alignment of right-to-left text boxes.
        if (opts.contains('RightToLeft=True')) al = switch (al) { 'Right' => 'Left', '' || 'Left' => 'Right', _ => al };
        final border = c.prop('Border');
        items.add(RItem(
          id: _newId(),
          band: band,
          x: x,
          y: y,
          w: w <= 0 ? 1 : w,
          h: h <= 0 ? 1 : h,
          text: _mapText(raw, type).trim(),
          // Sakan's fonts (David, B Nazanin) are smaller than Vazirmatn at the same size.
          fontSize: (size * 0.85).clamp(5, 40).toDouble(),
          bold: font.skip(2).any((f) => f.contains('Bold')),
          align: switch (al) { 'Center' || 'Width' => 'center', 'Right' => 'right', _ => 'left' },
          border: border.isEmpty ? 0 : _sides(border),
          borderWidth: border.isEmpty ? 0.3 : _borderWidth(border),
          vertical: angle == 90 || angle == 270,
          fill: _fill(c.prop('Brush')),
        ));
      case 'HorizontalLinePrimitive':
        items.add(RItem(id: _newId(), band: band, x: x, y: y, w: w <= 0 ? 1 : w, h: 0.6, border: Sides.top));
      case 'VerticalLinePrimitive':
        items.add(RItem(id: _newId(), band: band, x: x, y: y, w: 0.6, h: h <= 0 ? 1 : h, border: Sides.left));
      case 'RectanglePrimitive':
      case 'RoundedRectanglePrimitive':
        items.add(RItem(id: _newId(), band: band, x: x, y: y, w: w, h: h, border: Sides.all));
      case 'Shape':
        final st = c.child('ShapeType')?.attrs['type'] ?? '';
        if (st.contains('Rectangle') || st.contains('Oval')) {
          items.add(RItem(id: _newId(), band: band, x: x, y: y, w: w, h: h, border: Sides.all, fill: _fill(c.prop('Brush'))));
        } else if (st.contains('HorizontalLine')) {
          items.add(RItem(id: _newId(), band: band, x: x, y: y + h / 2, w: w, h: 0.6, border: Sides.top));
        } else {
          skipped++;
        }
      case 'Container':
      case 'Panel':
        for (final cc in c.child('Components')?.children ?? const <_X>[]) {
          addComp(cc, band, x, y, maxH);
        }
      case 'StartPointPrimitive':
      case 'EndPointPrimitive':
        break;
      default:
        skipped++; // images, barcodes, charts, check boxes…
    }
  }

  for (final b in bands) {
    final kind = assign[b];
    if (kind == null) continue;
    for (final c in b.el.child('Components')?.children ?? const <_X>[]) {
      addComp(c, kind, 0, offset[b]!, heights[kind]!);
    }
  }
  // components placed on the page itself (frames drawn across bands…)
  for (final c in loose) {
    final r = _Rect.parse(c.prop('ClientRectangle'));
    // (bands sit 0.4 cm apart in Sakan's designer, so allow a little above the band)
    final band = bands.where((b) => assign[b] != null && r.y >= b.r.y - 0.45 && r.y < b.r.y + b.r.h).firstOrNull;
    if (band == null) {
      if (_sType(c) != 'StartPointPrimitive' && _sType(c) != 'EndPointPrimitive') skipped++;
      continue;
    }
    final kind = assign[band]!;
    addComp(c, kind, -0.0, offset[band]! - band.r.y * k, heights[kind]!);
  }

  final l = ReportLayout(
    id: _newId(),
    type: type,
    variant: variant,
    name: name,
    pageW: pageW,
    pageH: pageH,
    margin: margin,
    bandHeights: {for (final b in BandKind.values) b: heights[b]! <= 0 ? (b == BandKind.data ? 6.0 : 0.0) : heights[b]!},
    items: items,
  );
  return MrtImport(l, items.length, skipped, unknown.toList()..sort());
}
