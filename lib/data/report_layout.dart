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
  // Sakan fields
  'کد نوع فاکتور',
  'نوع فاکتور',
  'تاریخ فروش',
  'کد خریدار',
  'قیمت تمام شده فاکتور',
  'سود و زیان ناخالص',
  'درصد سود و زیان ناخالص',
  'وزن فاکتور',
  'ارز سیستم',
  'بازاریابان',
  'شماره همراه بازاریاب',
  'هزینه پورسانت',
  'مسئول پخش',
  'شماره همراه مسئول پخش',
  'جمع مالیات',
  'جمع عوارض',
  'جمع مالیات و عوارض',
  'جمع کل قبل از مالیات',
  'کد ملی خریدار',
  'کد اقتصادی خریدار',
  'کد پستی خریدار',
  'نام کاربر',
  'جمع یارانه',
  'شهر خریدار',
  'استان خریدار',
  'نوع خریدار',
  'شماره پیامک خریدار',
  'عنوان معین خریدار',
  'مرکز اسناد',
  'نام کامپیوتر',
  'جمع خدمات',
  'جمع مالیات خدمات',
  'جمع عوارض خدمات',
  'شماره مالیاتی',
  'شماره مالیاتی مرجع',
];

const rowFields = [
  'ردیف', 'کد کالا', 'نام کالا', 'تعداد', 'واحد', 'فی', 'تخفیف', 'جمع', 'جمع بدون تخفیف', 'نام انبار',
  // Sakan fields
  'بارکد', 'شماره فنی', 'مشخصات کالا', 'وزن واحد', 'جمع وزن کالا',
  'قیمت تمام شده', 'سود و زیان ناخالص ردیف', 'درصد سود ردیف', 'درصد تخفیف', 'بهای فروش 1', 'بهای فروش 2', 'بهای فروش 3', 'موجودی',
  'واحد منتخب', 'واحد 1', 'واحد 2', 'واحد 3', 'تعداد واحد 1', 'تعداد واحد 2', 'تعداد واحد 3',
  'فی واحد 1', 'فی واحد 2', 'فی واحد 3', 'نسبت واحد 2 به واحد 1', 'نسبت واحد 3 به واحد 1',
  'درصد بازاریابی', 'سهم بازاریابی',
  'درصد مالیات', 'درصد عوارض', 'مالیات ردیف', 'عوارض ردیف', 'جمع ردیف با مالیات',
  'سریال', 'مشخصه', 'نام لاتین کالا', 'واحد لاتین', 'شناسه کالا', 'انباردار',
];

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
    PrintDocType.voucher || PrintDocType.payslip || PrintDocType.cheque || PrintDocType.guarantee || PrintDocType.trialBalance || PrintDocType.stock || PrintDocType.salaryList =>
      defaultDocLayout(t),
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
List<String> fieldsFor(PrintDocType t) => switch (t) {
      PrintDocType.ledger => [...ledgerFields, ...ledgerRowFields],
      PrintDocType.voucher => [...voucherFields, ...voucherRowFields],
      PrintDocType.payslip => [...payslipFields, ...payslipRowFields],
      PrintDocType.cheque => [...chequeFields, ...chequeRowFields],
      PrintDocType.guarantee => [...guaranteeFields, ...guaranteeRowFields],
      PrintDocType.trialBalance => [...trialFields, ...trialRowFields],
      PrintDocType.stock => [...stockFields, ...stockRowFields],
      PrintDocType.salaryList => [...salaryListFields, ...salaryListRowFields],
      _ => [...invoiceFields, ...rowFields],
    };

/// «چاپ سند حسابداری».
const voucherFields = ['شماره سند', 'شماره ثابت', 'تاریخ سند', 'شرح سند', 'بابت', 'نوع سند', 'مرکز اسناد', 'نام فروشگاه', 'جمع بدهکار', 'جمع بستانکار', 'مبلغ به حروف', 'تنظیم کننده', 'صفحه', 'تاریخ'];
const voucherRowFields = ['ردیف', 'کد کل', 'نام کل', 'کد معین', 'نام معین', 'کد تفصیلی', 'نام تفصیلی', 'نام حساب', 'شرح ردیف', 'بدهکار', 'بستانکار'];

/// «فیش حقوقی».
const payslipFields = [
  'نام', 'نام خانوادگی', 'نام و نام خانوادگی', 'نام پدر', 'کد پرسنلی', 'کد ملی', 'شماره بیمه', 'نوع استخدام', 'شغل', 'شماره حساب', 'نام بانک', //
  'دوره', 'سال', 'ماه', 'روزهای کارکرد', 'حقوق ماهیانه', 'دستمزد روزانه', 'اضافه کار', 'ساعت اضافه کار', 'کسر کار', 'ساعت کسر کار', 'حق شیفت',
  'حق ماموریت', 'پاداش', 'عیدی', 'بازخرید مرخصی', 'حق سنوات', 'پرداخت های معوقه', 'مزایای مستمر', 'مزایای غیر نقدی', 'جمع حقوق و مزایا',
  'بیمه سهم بیمه شده', 'مالیات', 'وام', 'مساعده', 'جریمه', 'غیبت', 'روزهای غیبت', 'مرخصی بدون حقوق', 'روزهای مرخصی بدون حقوق', 'سایر کسورات',
  'جمع کسورات', 'خالص پرداختی', 'مبلغ به حروف', 'مانده دفتر', 'نام فروشگاه', 'نام کارگاه', 'تاریخ', 'صفحه',
];
const payslipRowFields = ['ردیف', 'عنوان', 'مزایا', 'کسورات'];

/// «چاپ چک ها».
const chequeFields = ['عنوان', 'نام فروشگاه', 'تاریخ', 'جمع مبلغ', 'تعداد', 'صفحه'];
const chequeRowFields = ['ردیف', 'شماره چک', 'مبلغ', 'سررسید', 'تاریخ صدور', 'بانک', 'طرف حساب', 'دریافت کننده', 'وضعیت', 'نوع', 'شرح', 'واحد پول', 'صندوق', 'شماره حساب'];

/// «چاپ تراز آزمایشی» (Sakan's TarazeAzmayeshi).
const trialFields = [
  'عنوان', 'نام فروشگاه', 'نام دفتر مالی', 'تاریخ', 'از تاریخ', 'تا تاریخ', 'سطح', 'صفحه', //
  'جمع بدهکار ابتدای دوره', 'جمع بستانکار ابتدای دوره', 'جمع گردش بدهکار', 'جمع گردش بستانکار',
  'جمع بدهکار انتهای دوره', 'جمع بستانکار انتهای دوره', 'جمع مانده بدهکار', 'جمع مانده بستانکار',
  'مانده خالص بدهکار', 'مانده خالص بستانکار', 'مانده سود و زیان بدهکار', 'مانده سود و زیان بستانکار',
];
const trialRowFields = [
  'ردیف', 'کد حساب', 'نام حساب', 'بدهکار ابتدای دوره', 'بستانکار ابتدای دوره', 'گردش بدهکار', 'گردش بستانکار', //
  'بدهکار انتهای دوره', 'بستانکار انتهای دوره', 'مانده بدهکار', 'مانده بستانکار', 'مانده سود و زیانی بدهکار', 'مانده سود و زیانی بستانکار', 'تشخیص',
];

/// «چاپ گزارش موجودی کالا» (MojodiKala / MojodiAnbar).
const stockFields = ['عنوان', 'نام فروشگاه', 'تاریخ', 'نام انبار', 'صفحه', 'جمع ارزش موجودی', 'جمع موجودی', 'تعداد اقلام'];
const stockRowFields = [
  'ردیف', 'کد کالا', 'نام کالا', 'واحد', 'موجودی', 'واحد دوم', 'موجودی واحد دوم', 'واحد سوم', 'موجودی واحد سوم', //
  'فی', 'ارزش موجودی', 'بهای فروش', 'بهای مصرف کننده', 'حداقل موجودی', 'حداکثر موجودی', 'نام انبار', 'خرید', 'برگشت از خرید', 'فروش', 'برگشت از فروش',
];

/// «لیست حقوق»، «لیست بیمه» و «لیست مالیات» of a pay period.
const salaryListFields = [
  'عنوان', 'نام فروشگاه', 'نام کارگاه', 'شماره کارگاه', 'نام کارفرما', 'آدرس کارگاه', 'نام مرکز بیمه', 'دوره', 'سال', 'ماه', 'تاریخ', 'صفحه', //
  'جمع حقوق و مزایا', 'جمع کسورات', 'جمع خالص پرداختی', 'جمع بیمه سهم بیمه شده', 'جمع بیمه سهم کارفرما', 'جمع بیمه بیکاری', 'جمع کل بیمه',
  'جمع دستمزد مشمول بیمه', 'جمع مالیات', 'جمع مشمول مالیات', 'تعداد پرسنل',
];
const salaryListRowFields = [
  'ردیف', 'نام', 'نام خانوادگی', 'نام و نام خانوادگی', 'نام پدر', 'کد ملی', 'شماره شناسنامه', 'شماره بیمه', 'کد پرسنلی', 'شغل', 'جنسیت', 'ملیت', //
  'تاریخ استخدام', 'تاریخ ترک کار', 'روزهای کارکرد', 'دستمزد روزانه', 'حقوق ماهیانه', 'مزایای مستمر', 'اضافه کار', 'جمع حقوق و مزایا',
  'دستمزد مشمول بیمه', 'دستمزد غیر مشمول بیمه', 'بیمه سهم بیمه شده', 'بیمه سهم کارفرما', 'بیمه بیکاری', 'جمع بیمه', 'مشمول مالیات', 'مالیات',
  'جمع کسورات', 'خالص پرداختی', 'شماره حساب',
];

/// «چاپ اسناد انتظامی».
const guaranteeFields = ['شماره سند', 'تاریخ سند', 'نوع سند', 'طرف حساب', 'بابت', 'جمع مبلغ', 'مبلغ به حروف', 'نام فروشگاه', 'تاریخ', 'صفحه'];
const guaranteeRowFields = ['ردیف', 'نوع', 'شماره سریال', 'مبلغ', 'سررسید', 'بانک', 'مکان نگهداری', 'متعلق به', 'وضعیت'];

/// A table layout (A4): a framed header with [header] lines, column titles,
/// one row per record and [footer] lines.
ReportLayout tableLayout(PrintDocType type, String id, List<String> header, List<(double, String, String)> cols, List<String> footer) {
  const h = BandKind.header, c = BandKind.columns, d = BandKind.data, f1 = BandKind.footer1, f2 = BandKind.footer2;
  final total = cols.fold<double>(0, (a, x) => a + x.$1);
  final k = 194 / total;
  final xs = <(double, double, String, String)>[];
  var x = 194.0;
  for (final col in cols) {
    final w = col.$1 * k;
    x -= w;
    xs.add((x, w, col.$2, col.$3));
  }
  final hh = 6.0 + header.length * 6.5;
  return ReportLayout(
    id: id,
    type: type,
    name: 'طرح ۱',
    pageW: 210,
    pageH: 297,
    margin: 8,
    bandHeights: {h: hh, c: 8, d: 8, f1: 8.0 * (footer.isEmpty ? 1 : footer.length), f2: 6},
    items: [
      _t(h, 0, 0, 194, hh - 2, '', border: Sides.all),
      for (var i = 0; i < header.length; i++) _t(h, 2, 2 + i * 6.5, 190, 6, header[i], fs: i == 0 ? 13 : 9.5, bold: i == 0, align: i == 0 ? 'center' : 'right'),
      for (final col in xs) _t(c, col.$1, 0, col.$2, 8, col.$3, fs: 9, bold: true, align: 'center', border: Sides.all),
      for (final col in xs) _t(d, col.$1, 0, col.$2, 8, col.$4, fs: 8.5, align: 'center', border: Sides.all),
      for (var i = 0; i < footer.length; i++) _t(f1, 0, i * 8.0, 194, 8, footer[i], fs: 9.5, bold: true, border: Sides.all),
      _t(f2, 0, 0, 194, 6, 'صفحه {صفحه}', fs: 8, align: 'center'),
    ],
  );
}

/// Sakan-like default layouts of the non-invoice documents.
ReportLayout defaultDocLayout(PrintDocType t) => switch (t) {
      PrintDocType.voucher => tableLayout(t, 'builtin-voucher', [
          'سند حسابداری',
          '{نام فروشگاه}        شماره سند: {شماره سند}    شماره ثابت: {شماره ثابت}    تاریخ: {تاریخ سند}',
          'شرح سند: {شرح سند}    {بابت}',
        ], [
          (8, 'ردیف', '{ردیف}'),
          (12, 'کد معین', '{کد معین}'),
          (34, 'نام حساب', '{نام حساب}'),
          (46, 'شرح', '{شرح ردیف}'),
          (22, 'بدهکار', '{بدهکار}'),
          (22, 'بستانکار', '{بستانکار}'),
        ], [
          'جمع: بدهکار {جمع بدهکار}    بستانکار {جمع بستانکار}    ({مبلغ به حروف})',
          'تنظیم کننده: {تنظیم کننده}                 تایید کننده:                 مدیر مالی:',
        ]),
      PrintDocType.payslip => tableLayout(t, 'builtin-payslip', [
          'فیش حقوقی {دوره}',
          '{نام کارگاه}    نام: {نام و نام خانوادگی}    کد پرسنلی: {کد پرسنلی}    کد ملی: {کد ملی}',
          'روزهای کارکرد: {روزهای کارکرد}    اضافه کار: {ساعت اضافه کار}    کسر کار: {ساعت کسر کار}    شماره حساب: {شماره حساب}',
        ], [
          (10, 'ردیف', '{ردیف}'),
          (60, 'شرح', '{عنوان}'),
          (30, 'مزایا', '{مزایا}'),
          (30, 'کسورات', '{کسورات}'),
        ], [
          'جمع حقوق و مزایا: {جمع حقوق و مزایا}    جمع کسورات: {جمع کسورات}    خالص پرداختی: {خالص پرداختی}',
          '{مبلغ به حروف}',
        ]),
      PrintDocType.cheque => tableLayout(t, 'builtin-cheque', [
          '{عنوان}',
          '{نام فروشگاه}        تاریخ: {تاریخ}',
        ], [
          (8, 'ردیف', '{ردیف}'),
          (18, 'شماره چک', '{شماره چک}'),
          (16, 'سررسید', '{سررسید}'),
          (18, 'بانک', '{بانک}'),
          (32, 'طرف حساب', '{طرف حساب}'),
          (22, 'مبلغ', '{مبلغ}'),
          (20, 'وضعیت', '{وضعیت}'),
        ], [
          'تعداد: {تعداد}    جمع مبلغ: {جمع مبلغ}',
        ]),
      PrintDocType.trialBalance => tableLayout(t, 'builtin-trialBalance', [
          '{عنوان}',
          '{نام فروشگاه}    {نام دفتر مالی}    از {از تاریخ} تا {تا تاریخ}    تاریخ: {تاریخ}',
        ], [
          (8, 'ردیف', '{ردیف}'),
          (14, 'کد', '{کد حساب}'),
          (34, 'نام حساب', '{نام حساب}'),
          (20, 'بدهکار ابتدای دوره', '{بدهکار ابتدای دوره}'),
          (20, 'بستانکار ابتدای دوره', '{بستانکار ابتدای دوره}'),
          (20, 'گردش بدهکار', '{گردش بدهکار}'),
          (20, 'گردش بستانکار', '{گردش بستانکار}'),
          (20, 'مانده بدهکار', '{مانده بدهکار}'),
          (20, 'مانده بستانکار', '{مانده بستانکار}'),
        ], [
          'جمع:  ابتدای دوره {جمع بدهکار ابتدای دوره} / {جمع بستانکار ابتدای دوره}    گردش {جمع گردش بدهکار} / {جمع گردش بستانکار}    مانده {جمع مانده بدهکار} / {جمع مانده بستانکار}',
          'مانده دفاتر سود و زیانی: بدهکار {مانده سود و زیان بدهکار}    بستانکار {مانده سود و زیان بستانکار}',
        ]),
      PrintDocType.stock => tableLayout(t, 'builtin-stock', [
          '{عنوان}',
          '{نام فروشگاه}    {نام انبار}    تاریخ: {تاریخ}',
        ], [
          (8, 'ردیف', '{ردیف}'),
          (14, 'کد', '{کد کالا}'),
          (50, 'نام کالا', '{نام کالا}'),
          (14, 'واحد', '{واحد}'),
          (18, 'موجودی', '{موجودی}'),
          (20, 'فی', '{فی}'),
          (26, 'ارزش موجودی', '{ارزش موجودی}'),
        ], [
          'تعداد اقلام: {تعداد اقلام}    جمع موجودی: {جمع موجودی}    جمع ارزش موجودی: {جمع ارزش موجودی}',
        ]),
      PrintDocType.salaryList => tableLayout(t, 'builtin-salaryList', [
          '{عنوان} {دوره}',
          'کارگاه: {نام کارگاه} ({شماره کارگاه})    کارفرما: {نام کارفرما}    {نام مرکز بیمه}',
        ], [
          (7, 'ردیف', '{ردیف}'),
          (30, 'نام و نام خانوادگی', '{نام و نام خانوادگی}'),
          (16, 'کد ملی', '{کد ملی}'),
          (14, 'شماره بیمه', '{شماره بیمه}'),
          (8, 'روز', '{روزهای کارکرد}'),
          (20, 'جمع حقوق و مزایا', '{جمع حقوق و مزایا}'),
          (18, 'بیمه سهم کارمند', '{بیمه سهم بیمه شده}'),
          (16, 'مالیات', '{مالیات}'),
          (20, 'خالص پرداختی', '{خالص پرداختی}'),
        ], [
          'جمع حقوق و مزایا {جمع حقوق و مزایا}    بیمه کارمند {جمع بیمه سهم بیمه شده}    بیمه کارفرما {جمع بیمه سهم کارفرما}    بیکاری {جمع بیمه بیکاری}',
          'جمع مالیات {جمع مالیات}    جمع خالص پرداختی {جمع خالص پرداختی}    تعداد پرسنل {تعداد پرسنل}',
        ]),
      _ => tableLayout(t, 'builtin-guarantee', [
          '{نوع سند} شماره {شماره سند}',
          '{نام فروشگاه}        تاریخ: {تاریخ سند}    طرف حساب: {طرف حساب}    بابت: {بابت}',
        ], [
          (8, 'ردیف', '{ردیف}'),
          (16, 'نوع', '{نوع}'),
          (22, 'شماره سریال', '{شماره سریال}'),
          (22, 'مبلغ', '{مبلغ}'),
          (16, 'سررسید', '{سررسید}'),
          (24, 'مکان نگهداری', '{مکان نگهداری}'),
          (20, 'متعلق به', '{متعلق به}'),
        ], [
          'جمع: {جمع مبلغ}    ({مبلغ به حروف})',
          'امضای تحویل دهنده:                                   امضای تحویل گیرنده:',
        ]),
    };

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
