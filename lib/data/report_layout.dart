/// Band based print layouts (طراحی گزارش), modelled on Sakan's report designer.
/// All sizes are in millimetres.
library;

import 'models.dart' show PrintDocType;

/// Band kinds, in print order.
enum BandKind { header, columns, data, footer1, footer2 }

extension BandKindX on BandKind {
  String get title => switch (this) {
        BandKind.header => 'Header1',
        BandKind.columns => 'HeaderPrintKalaFrosh',
        BandKind.data => 'DataPrintKalaFrosh: Data Source: PrintKalaFrosh',
        BandKind.footer1 => 'Footer1',
        BandKind.footer2 => 'Footer2',
      };
}

/// Border sides of an element.
class Sides {
  static const top = 1, right = 2, bottom = 4, left = 8, all = 15;
}

/// One element on the page: a text box (with `{field}` placeholders),
/// a frame, a line or a QR code ([kind] `qr`: [text] is the encoded content).
class RItem {
  String id;
  String kind; // '' = text / frame / line, 'qr' = QR code
  BandKind band;
  double x, y, w, h;
  String text;
  double fontSize;
  bool bold;
  String align; // right | center | left
  int border; // Sides bitmask
  double borderWidth;
  bool vertical; // rotated text
  int fill; // ARGB, 0 = none

  RItem({
    required this.id,
    this.kind = '',
    required this.band,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.text = '',
    this.fontSize = 9,
    this.bold = false,
    this.align = 'right',
    this.border = 0,
    this.borderWidth = 0.3,
    this.vertical = false,
    this.fill = 0,
  });

  bool get isQr => kind == 'qr';

  RItem copy({String? id}) => RItem.fromJson(toJson())..id = id ?? this.id;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (kind.isNotEmpty) 'k': kind,
        'band': band.name,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'text': text,
        'fs': fontSize,
        'b': bold,
        'al': align,
        'bd': border,
        'bw': borderWidth,
        'v': vertical,
        'f': fill,
      };

  static double _d(Object? v, double def) => v is num ? v.toDouble() : def;

  factory RItem.fromJson(Map<String, dynamic> j) => RItem(
        id: '${j['id'] ?? ''}',
        kind: '${j['k'] ?? ''}',
        band: BandKind.values.firstWhere((b) => b.name == j['band'], orElse: () => BandKind.header),
        x: _d(j['x'], 0),
        y: _d(j['y'], 0),
        w: _d(j['w'], 20),
        h: _d(j['h'], 6),
        text: '${j['text'] ?? ''}',
        fontSize: _d(j['fs'], 9),
        bold: j['b'] == true,
        align: '${j['al'] ?? 'right'}',
        border: j['bd'] is int ? j['bd'] as int : 0,
        borderWidth: _d(j['bw'], 0.3),
        vertical: j['v'] == true,
        fill: j['f'] is int ? j['f'] as int : 0,
      );
}

class ReportLayout {
  String id;
  PrintDocType type;

  /// Document the layout is for, e.g. 'sale', 'purchase', 'proforma' ('' = shared).
  String variant;
  String name;
  double pageW, pageH, margin;
  Map<BandKind, double> bandHeights;
  List<RItem> items;

  ReportLayout({
    required this.id,
    required this.type,
    this.variant = '',
    required this.name,
    this.pageW = 148,
    this.pageH = 210,
    this.margin = 8,
    Map<BandKind, double>? bandHeights,
    List<RItem>? items,
  })  : bandHeights = bandHeights ?? {for (final b in BandKind.values) b: 10},
        items = items ?? [];

  double get contentW => pageW - 2 * margin;
  double heightOf(BandKind b) => bandHeights[b] ?? 10;
  List<RItem> itemsOf(BandKind b) => items.where((i) => i.band == b).toList();

  ReportLayout copy() => ReportLayout.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (variant.isNotEmpty) 'v': variant,
        'name': name,
        'pw': pageW,
        'ph': pageH,
        'm': margin,
        'bands': {for (final e in bandHeights.entries) e.key.name: e.value},
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ReportLayout.fromJson(Map<String, dynamic> j) {
    final b = j['bands'];
    return ReportLayout(
      id: '${j['id'] ?? ''}',
      type: PrintDocType.values.firstWhere((t) => t.name == j['type'], orElse: () => PrintDocType.invoice),
      variant: '${j['v'] ?? ''}',
      name: '${j['name'] ?? 'طرح'}',
      pageW: RItem._d(j['pw'], 148),
      pageH: RItem._d(j['ph'], 210),
      margin: RItem._d(j['m'], 8),
      bandHeights: b is Map
          ? {for (final k in BandKind.values) k: RItem._d(b[k.name], 10)}
          : null,
      items: [for (final i in (j['items'] is List ? j['items'] as List : const [])) if (i is Map<String, dynamic>) RItem.fromJson(i)],
    );
  }
}

/// Placeholders usable in layouts, per data band and page.
const invoiceFields = [
  'شماره حواله',
  'شماره فاکتور',
  'شماره سند',
  'تاریخ',
  'عنوان فاکتور',
  'نام فروشگاه',
  'تلفن فروشنده',
  'آدرس فروشگاه',
  'نام خریدار',
  'تلفن خریدار',
  'آدرس خریدار',
  'تحویل گیرنده',
  'بابت',
  'صفحه',
  'جمع اقلام',
  'جمع تخفیف',
  'جمع اقلام با احتساب تخفیف',
  'جمع فاکتور بدون تخفیف',
  'شماره درخواست',
  'هزینه حمل',
  'جمع کل فاکتور',
  'مبلغ به حروف',
  'مانده حساب از قبل',
  'مانده بدهکاری',
  'جمع دریافتی',
  'کل مانده حساب',
  'مبلغ دریافت چک',
  'مبلغ دریافت نقدی',
  'مبلغ تخفیف از فروش',
  'مبلغ حواله بانکی',
  'مبلغ کسر از پیش دریافت',
  'نحوه تسویه',
  'هزینه حمل بعهده خریدار',
  'هزینه حمل بعهده فروشنده',
  'توضیحات',
];

const rowFields = ['ردیف', 'کد کالا', 'نام کالا', 'تعداد', 'واحد', 'فی', 'تخفیف', 'جمع', 'جمع بدون تخفیف', 'نام انبار'];

int _seq = 0;
String _id() => 'i${DateTime.now().microsecondsSinceEpoch}${_seq++}';

RItem _t(BandKind band, double x, double y, double w, double h, String text,
        {double fs = 9, bool bold = false, String align = 'right', int border = 0, bool vertical = false}) =>
    RItem(id: _id(), band: band, x: x, y: y, w: w, h: h, text: text, fontSize: fs, bold: bold, align: align, border: border, vertical: vertical);

/// The invoice exactly as Sakan prints it (A5, «فاکتور فروش»).
ReportLayout defaultInvoiceLayout({String id = 'builtin-invoice', String title = '{عنوان فاکتور}', bool buyer = true}) {
  final party = buyer ? 'خریدار' : 'فروشنده';
  const h = BandKind.header, c = BandKind.columns, d = BandKind.data, f1 = BandKind.footer1, f2 = BandKind.footer2;
  // columns from right to left (content width 132)
  const cols = [
    (126.0, 6.0, 'ردیف', '{ردیف}'),
    (78.0, 48.0, 'نام اقلام', '{نام کالا}'),
    (66.0, 12.0, 'تعداد', '{تعداد}'),
    (58.0, 8.0, 'واحد', '{واحد}'),
    (36.0, 22.0, 'فی', '{فی}'),
    (24.0, 12.0, 'تخفیف', '{تخفیف}'),
    (0.0, 24.0, 'جمع', '{جمع}'),
  ];
  final items = <RItem>[
    // ---------------- Header1
    _t(h, 0, 0, 132, 29, '', border: Sides.all, ),
    _t(h, 1, 1, 18, 5.5, 'Page {صفحه}', fs: 9, align: 'left', border: Sides.all),
    _t(h, 44, 1, 44, 6, title, fs: 11, align: 'center'),
    _t(h, 44, 8, 44, 7, '{نام فروشگاه}', fs: 12, align: 'center'),
    _t(h, 100, 1, 31, 8, '{شماره حواله}', fs: 15, bold: true, align: 'left'),
    _t(h, 82, 10, 49, 5.5, 'تاریخ: {تاریخ}', fs: 9, bold: true),
    _t(h, 62, 16, 69, 6, 'نام $party: {نام خریدار}', fs: 11),
    _t(h, 62, 22.5, 69, 6, 'آدرس: {آدرس خریدار}', fs: 9),
    _t(h, 4, 16, 50, 6, 'شماره فاکتور: {شماره فاکتور}', fs: 9, bold: true),
    _t(h, 4, 22.5, 50, 6, 'تلفن: {تلفن فروشنده}', fs: 9),
    // ---------------- column titles
    for (final col in cols) _t(c, col.$1, 0, col.$2, 6, col.$3, fs: 10, align: 'center', border: Sides.all),
    // ---------------- data rows
    for (final col in cols)
      _t(d, col.$1, 0, col.$2, 6, col.$4,
          fs: col.$3 == 'نام اقلام' || col.$3 == 'واحد' ? 9 : 11,
          bold: col.$3 != 'نام اقلام' && col.$3 != 'واحد',
          align: 'center',
          border: Sides.all),
    // ---------------- Footer1: totals on the left
    for (final (i, label, field) in [
      (0, 'جمع تخفیف', '{جمع تخفیف}'),
      (1, 'جمع اقلام با احتساب تخفیف', '{جمع اقلام با احتساب تخفیف}'),
      (2, 'هزینه حمل', '{هزینه حمل}'),
      (3, 'جمع کل فاکتور', '{جمع کل فاکتور}'),
      (4, 'مانده حساب از قبل', '{مانده حساب از قبل}'),
      (5, 'مانده بدهکاری', '{مانده بدهکاری}'),
      (6, 'جمع دریافتی', '{جمع دریافتی}'),
      (7, 'کل مانده حساب', '{کل مانده حساب}'),
    ]) ...[
      _t(f1, 36, i * 6.0, 26, 6, label, fs: i == 1 ? 7 : 10, align: 'center', border: Sides.all),
      _t(f1, 0, i * 6.0, 36, 6, field, fs: 11, bold: true, align: 'center', border: Sides.all),
    ],
    // ---------------- Footer1: settlement on the right
    _t(f1, 62, 0, 70, 48, '', border: Sides.all),
    _t(f1, 126, 0, 6, 24, 'نحوه تسویه', fs: 9, align: 'center', border: Sides.all, vertical: true),
    for (final (i, label, field) in [
      (0, buyer ? 'مبلغ دریافت چک' : 'مبلغ چک', '{مبلغ دریافت چک}'),
      (1, buyer ? 'مبلغ دریافت نقدی' : 'مبلغ پرداخت نقدی', '{مبلغ دریافت نقدی}'),
      (2, 'مبلغ حواله بانکی', '{مبلغ حواله بانکی}'),
      (3, buyer ? 'مبلغ تخفیف از فروش' : 'مبلغ تخفیف از خرید', '{مبلغ تخفیف از فروش}'),
    ]) ...[
      _t(f1, 100, i * 6.0, 26, 6, label, fs: 9, border: Sides.all),
      _t(f1, 62, i * 6.0, 38, 6, field, fs: 9, align: 'center', border: Sides.all),
    ],
    _t(f1, 63, 25, 68, 5, 'کلیه اقلام فاکتور کامل و سالم تحویل $party شده', fs: 9),
    _t(f1, 63, 30, 68, 5, 'و مانده حساب مورد تایید $party می باشد', fs: 9),
    _t(f1, 104, 38, 26, 6, 'مهر امضاء $party', fs: 9),
    _t(f1, 72, 38, 28, 6, 'مهر/امضاء فروشگاه', fs: 9),
    // ---------------- Footer2
    _t(f2, 0, 0, 132, 6, 'تسویه به صورت :   □   چک .................. روز ،  نقدی ،  نسیه', fs: 9, bold: true, border: Sides.left | Sides.right | Sides.bottom),
    _t(f2, 0, 6, 132, 14, '', border: Sides.all),
    _t(f2, 1, 7, 130, 6, 'آدرس - {آدرس فروشگاه}', fs: 9),
  ];
  return ReportLayout(
    id: id,
    type: PrintDocType.invoice,
    name: 'طرح ۱',
    bandHeights: {h: 31, c: 6, d: 6, f1: 49, f2: 22},
    items: items,
  );
}

/// «حواله انبار» — same frame, no prices.
ReportLayout defaultWarehouseLayout() {
  const h = BandKind.header, c = BandKind.columns, d = BandKind.data, f1 = BandKind.footer1, f2 = BandKind.footer2;
  const cols = [
    (124.0, 8.0, 'ردیف', '{ردیف}'),
    (104.0, 20.0, 'کد کالا', '{کد کالا}'),
    (50.0, 54.0, 'نام اقلام', '{نام کالا}'),
    (34.0, 16.0, 'تعداد', '{تعداد}'),
    (24.0, 10.0, 'واحد', '{واحد}'),
    (0.0, 24.0, 'نام انبار', '{نام انبار}'),
  ];
  return ReportLayout(
    id: 'builtin-warehouse',
    type: PrintDocType.warehouse,
    name: 'طرح ۱',
    bandHeights: {h: 31, c: 6, d: 6, f1: 22, f2: 16},
    items: [
      _t(h, 0, 0, 132, 29, '', border: Sides.all),
      _t(h, 1, 1, 18, 5.5, 'Page {صفحه}', align: 'left', border: Sides.all),
      _t(h, 44, 1, 44, 6, 'حواله انبار', fs: 11, align: 'center'),
      _t(h, 44, 8, 44, 7, '{نام فروشگاه}', fs: 12, align: 'center'),
      _t(h, 100, 1, 31, 8, '{شماره حواله}', fs: 15, bold: true, align: 'left'),
      _t(h, 82, 10, 49, 5.5, 'تاریخ: {تاریخ}', bold: true),
      _t(h, 62, 16, 69, 6, 'تحویل گیرنده: {نام خریدار}', fs: 11),
      _t(h, 4, 16, 50, 6, 'شماره فاکتور: {شماره فاکتور}', bold: true),
      for (final col in cols) _t(c, col.$1, 0, col.$2, 6, col.$3, fs: 10, align: 'center', border: Sides.all),
      for (final col in cols) _t(d, col.$1, 0, col.$2, 6, col.$4, fs: 10, align: 'center', border: Sides.all),
      _t(f1, 0, 0, 132, 6, 'جمع اقلام: {جمع اقلام}', bold: true, border: Sides.all),
      _t(f1, 80, 12, 45, 6, 'امضاء تحویل دهنده', align: 'center'),
      _t(f1, 8, 12, 45, 6, 'امضاء تحویل گیرنده', align: 'center'),
      _t(f2, 0, 0, 132, 12, '', border: Sides.all),
      _t(f2, 1, 1, 130, 6, 'آدرس - {آدرس فروشگاه}'),
    ],
  );
}

/// Documents that can each have their own print layouts.
const layoutVariants = {
  'sale': 'فاکتور فروش',
  'purchase': 'فاکتور خرید',
  'proforma': 'پیش فاکتور',
  'saleReturn': 'برگشت از فروش',
  'purchaseReturn': 'برگشت از خرید',
};

/// Types whose layouts are kept per document ([layoutVariants]).
bool hasVariants(PrintDocType t) => t == PrintDocType.invoice;

String builtinLayoutId(PrintDocType t, String variant) => variant.isEmpty ? 'builtin-${t.name}' : 'builtin-${t.name}-$variant';

ReportLayout defaultLayoutFor(PrintDocType t, [String variant = '']) {
  final l = switch (t) {
    PrintDocType.warehouse => defaultWarehouseLayout(),
    PrintDocType.ledger => defaultLedgerLayout(),
    _ => defaultInvoiceLayout(buyer: variant != 'purchase' && variant != 'saleReturn'),
  };
  l
    ..id = builtinLayoutId(t, variant)
    ..variant = variant;
  return l;
}

/// Placeholders of «پرینت حساب».
const ledgerFields = ['نام حساب', 'کد حساب', 'عنوان کل', 'عنوان معین', 'نام فروشگاه', 'تاریخ', 'از تاریخ', 'تا تاریخ', 'صفحه', 'جمع بدهکار', 'جمع بستانکار', 'مانده', 'تشخیص'];
const ledgerRowFields = ['ردیف', 'ش س', 'تاریخ سند', 'شرح سند', 'بدهکار', 'بستانکار', 'مانده ردیف', 'ت', 'شماره ثابت'];

/// Starting content of a new QR code element.
String defaultQrText(PrintDocType t) => t == PrintDocType.ledger
    ? '{نام فروشگاه}\nحساب {نام حساب}\nمانده {مانده}'
    : '{نام فروشگاه}\n{عنوان فاکتور} {شماره فاکتور}\nتاریخ {تاریخ}\nمبلغ {جمع کل فاکتور}';

/// Fields offered by the designer for a layout type.
List<String> fieldsFor(PrintDocType t) => t == PrintDocType.ledger ? [...ledgerFields, ...ledgerRowFields] : [...invoiceFields, ...rowFields];

/// «گزارش حساب» as Sakan prints it (A4).
ReportLayout defaultLedgerLayout() {
  const h = BandKind.header, c = BandKind.columns, d = BandKind.data, f1 = BandKind.footer1, f2 = BandKind.footer2;
  // content width 194, columns from right to left
  const cols = [
    (184.0, 10.0, 'ردیف', '{ردیف}'),
    (164.0, 20.0, 'تاریخ', '{تاریخ سند}'),
    (98.0, 66.0, 'شرح سند', '{شرح سند}'),
    (72.0, 26.0, 'بدهکار', '{بدهکار}'),
    (46.0, 26.0, 'بستانکار', '{بستانکار}'),
    (12.0, 34.0, 'مانده', '{مانده ردیف}'),
    (0.0, 12.0, 'ت', '{ت}'),
  ];
  return ReportLayout(
    id: 'builtin-ledger',
    type: PrintDocType.ledger,
    name: 'طرح ۱',
    pageW: 210,
    pageH: 297,
    margin: 8,
    bandHeights: {h: 26, c: 8, d: 9, f1: 9, f2: 6},
    items: [
      _t(h, 0, 0, 194, 24, '', border: Sides.all),
      _t(h, 80, 2, 112, 8, 'گزارش حساب:   {نام حساب}', fs: 13, bold: true),
      _t(h, 120, 11, 72, 6, 'Page {صفحه}', fs: 11, align: 'right'),
      _t(h, 2, 2, 70, 7, '{نام فروشگاه}', fs: 12, align: 'left'),
      _t(h, 2, 10, 70, 6, 'تاریخ: {تاریخ}', fs: 9, align: 'left'),
      _t(h, 80, 17, 112, 6, '{عنوان کل} / {عنوان معین}   کد: {کد حساب}', fs: 9),
      for (final col in cols) _t(c, col.$1, 0, col.$2, 8, col.$3, fs: 10, bold: true, align: 'center', border: Sides.all),
      for (final col in cols)
        _t(d, col.$1, 0, col.$2, 9, col.$4,
            fs: col.$3 == 'شرح سند' ? 8 : 9, align: col.$3 == 'شرح سند' ? 'right' : 'center', border: Sides.all),
      _t(f1, 98, 0, 96, 9, 'جمع', fs: 10, bold: true, align: 'center', border: Sides.all),
      _t(f1, 72, 0, 26, 9, '{جمع بدهکار}', fs: 9, bold: true, align: 'center', border: Sides.all),
      _t(f1, 46, 0, 26, 9, '{جمع بستانکار}', fs: 9, bold: true, align: 'center', border: Sides.all),
      _t(f1, 12, 0, 34, 9, '{مانده}', fs: 9, bold: true, align: 'center', border: Sides.all),
      _t(f1, 0, 0, 12, 9, '{تشخیص}', fs: 9, bold: true, align: 'center', border: Sides.all),
    ],
  );
}
