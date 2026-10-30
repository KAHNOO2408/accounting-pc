/// «تنظیمات فاکتور فروش / خرید» — Sakan's invoice options (docs/sakan/ui).
class InvoiceOptions {
  // تنظیمات فروش / فاکتور
  bool lastFi; // فراخوانی اتوماتیک آخرین فی
  bool lastFiByPerson; // ... بر اساس خریدار
  bool allowDuplicate; // اجازه ثبت کالای تکراری
  bool latinNames; // زبان نام کالا: لاتین
  int defaultUnit; // 0 = واحد پیش فرض کالا، 1..3
  String? defaultWarehouseId;
  bool autoRequestNo; // شماره درخواست بصورت خودکار
  bool reopenAfterSave; // باز کردن مجدد فرم بعد از ثبت
  // کنترل حداقل و حداکثر فی (فروش)
  bool priceRange;
  double minPct; // درصد پایین تر از فی فروش
  double maxPct; // درصد بالاتر از فی فروش
  bool allowOutOfRange; // مجوز وارد کردن فی خارج از محدوده (با پیغام)
  // فروش منفی و پیغام ها
  bool allowNegative;
  bool msgNegative;
  bool msgMinStock;
  bool msgOrderPoint;
  bool msgLastFi;
  bool msgMaxStock; // خرید بیش از حداکثر موجودی
  // ارزش افزوده
  bool vatAfterDiscount;
  // چاپ
  int invoiceCopies;
  int slipCopies; // حواله / رسید انبار

  InvoiceOptions({
    this.lastFi = true,
    this.lastFiByPerson = false,
    this.allowDuplicate = true,
    this.latinNames = false,
    this.defaultUnit = 0,
    this.defaultWarehouseId,
    this.autoRequestNo = false,
    this.reopenAfterSave = false,
    this.priceRange = false,
    this.minPct = 0,
    this.maxPct = 0,
    this.allowOutOfRange = true,
    this.allowNegative = true,
    this.msgNegative = true,
    this.msgMinStock = false,
    this.msgOrderPoint = false,
    this.msgLastFi = false,
    this.msgMaxStock = false,
    this.vatAfterDiscount = true,
    this.invoiceCopies = 1,
    this.slipCopies = 1,
  });

  Map<String, dynamic> toJson() => {
        'lastFi': lastFi,
        'lastFiByPerson': lastFiByPerson,
        'allowDuplicate': allowDuplicate,
        'latinNames': latinNames,
        'defaultUnit': defaultUnit,
        'defaultWarehouseId': defaultWarehouseId,
        'autoRequestNo': autoRequestNo,
        'reopenAfterSave': reopenAfterSave,
        'priceRange': priceRange,
        'minPct': minPct,
        'maxPct': maxPct,
        'allowOutOfRange': allowOutOfRange,
        'allowNegative': allowNegative,
        'msgNegative': msgNegative,
        'msgMinStock': msgMinStock,
        'msgOrderPoint': msgOrderPoint,
        'msgLastFi': msgLastFi,
        'msgMaxStock': msgMaxStock,
        'vatAfterDiscount': vatAfterDiscount,
        'invoiceCopies': invoiceCopies,
        'slipCopies': slipCopies,
      };

  factory InvoiceOptions.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    double n(String k) => j[k] is num ? (j[k] as num).toDouble() : 0;
    int i(String k, int d) => j[k] is num ? (j[k] as num).toInt() : d;
    return InvoiceOptions(
      lastFi: b('lastFi', true),
      lastFiByPerson: b('lastFiByPerson', false),
      allowDuplicate: b('allowDuplicate', true),
      latinNames: b('latinNames', false),
      defaultUnit: i('defaultUnit', 0),
      defaultWarehouseId: j['defaultWarehouseId'] is String && (j['defaultWarehouseId'] as String).isNotEmpty ? j['defaultWarehouseId'] as String : null,
      autoRequestNo: b('autoRequestNo', false),
      reopenAfterSave: b('reopenAfterSave', false),
      priceRange: b('priceRange', false),
      minPct: n('minPct'),
      maxPct: n('maxPct'),
      allowOutOfRange: b('allowOutOfRange', true),
      allowNegative: b('allowNegative', true),
      msgNegative: b('msgNegative', true),
      msgMinStock: b('msgMinStock', false),
      msgOrderPoint: b('msgOrderPoint', false),
      msgLastFi: b('msgLastFi', false),
      msgMaxStock: b('msgMaxStock', false),
      vatAfterDiscount: b('vatAfterDiscount', true),
      invoiceCopies: i('invoiceCopies', 1),
      slipCopies: i('slipCopies', 1),
    );
  }

  /// «کنترل حداقل و حداکثر فی فروش»: allowed range around [sellPrice].
  (int min, int max)? range(int sellPrice) {
    if (!priceRange || sellPrice <= 0) return null;
    return ((sellPrice * (1 - minPct / 100)).round(), maxPct <= 0 ? 0 : (sellPrice * (1 + maxPct / 100)).round());
  }
}
