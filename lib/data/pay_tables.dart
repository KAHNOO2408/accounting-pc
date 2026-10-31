/// «فرم جداول پایه پرسنل» (Sakan): جدول حقوق (مرکز حقوق)، جدول بیمه، جدول
/// مالیات (مرکز مالیات)، جدول کسورات (مرکز کسورات)، جدول مزایای نقدی مستمر،
/// جدول مزایای غیر نقدی مستمر، جدول هزینه های مستمر پرداختی معاف از مالیات
/// توسط مودی، جدول مزایای پایان خدمت و جدول معافیت های مالیاتی (ماده ۹۱/۹۲).
///
/// Each employee points to one table of each kind; with none the table marked
/// «پیش فرض» is used, and without that the general [PayrollRules].
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
double _d(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? d;

enum PayTableKind { salary, insurance, tax, deduction, benefit, nonCash, exemptExpense, severance, taxExemption }

extension PayTableKindX on PayTableKind {
  /// Name of the table («جدول …» / «مرکز …»).
  String get label => switch (this) {
        PayTableKind.salary => 'جدول حقوق',
        PayTableKind.insurance => 'جدول بیمه',
        PayTableKind.tax => 'جدول مالیات',
        PayTableKind.deduction => 'جدول کسورات',
        PayTableKind.benefit => 'جدول مزایای نقدی مستمر',
        PayTableKind.nonCash => 'جدول مزایای غیر نقدی مستمر',
        PayTableKind.exemptExpense => 'جدول هزینه های مستمر پرداختی معاف از مالیات توسط مودی',
        PayTableKind.severance => 'جدول مزایای پایان خدمت کارکنان',
        PayTableKind.taxExemption => 'جدول معافیت های مالیاتی',
      };

  /// Title of its information form («اطلاعات …»).
  String get formTitle => switch (this) {
        PayTableKind.salary => 'اطلاعات مرکز حقوق',
        PayTableKind.insurance => 'اطلاعات جدول بیمه',
        PayTableKind.tax => 'اطلاعات مرکز مالیات',
        PayTableKind.deduction => 'اطلاعات مرکز کسورات',
        PayTableKind.benefit => 'اطلاعات جدول مزایا',
        PayTableKind.nonCash => 'اطلاعات جدول مزایای غیر نقدی مستمر',
        PayTableKind.exemptExpense => 'اطلاعات جدول هزینه های مستمر معاف از مالیات',
        PayTableKind.severance => 'اطلاعات جدول مزایای پایان خدمت',
        PayTableKind.taxExemption => 'اطلاعات جدول معافیت مالیاتی',
      };

  /// Whether the table holds a list of rows.
  bool get hasItems => this == PayTableKind.tax || this == PayTableKind.deduction || this == PayTableKind.benefit || this == PayTableKind.nonCash || this == PayTableKind.exemptExpense;
}

/// One row of a table: a tax bracket ([amount]..[to] at [pct]), a deduction,
/// a benefit (with its insurance / tax flags) or an exempt expense.
class PayTableItem {
  String name;
  int amount;
  int to;
  double pct;
  bool insured;
  bool taxed;
  int exempt; // مبلغ معاف از مالیات
  String kind; // مسکن / وسیله / سایر
  PayTableItem({this.name = '', this.amount = 0, this.to = 0, this.pct = 0, this.insured = true, this.taxed = true, this.exempt = 0, this.kind = ''});
  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        if (to != 0) 'to': to,
        if (pct != 0) 'pct': pct,
        'insured': insured,
        'taxed': taxed,
        if (exempt != 0) 'exempt': exempt,
        if (kind.isNotEmpty) 'kind': kind,
      };
  factory PayTableItem.fromJson(Map<String, dynamic> j) => PayTableItem(
        name: _s(j['name']),
        amount: _i(j['amount']),
        to: _i(j['to']),
        pct: _d(j['pct']),
        insured: j['insured'] != false,
        taxed: j['taxed'] != false,
        exempt: _i(j['exempt']),
        kind: _s(j['kind']),
      );
  PayTableItem copy() => PayTableItem.fromJson(toJson());
}

class PayTable {
  String id;
  PayTableKind kind;
  int code;
  String title;
  bool isDefault; // «انتخاب به عنوان پیش فرض»
  /// Scalar settings (keys per kind, see [payTableParams]).
  Map<String, Object> v;
  List<PayTableItem> items;
  PayTable({required this.id, required this.kind, required this.code, required this.title, this.isDefault = false, Map<String, Object>? v, List<PayTableItem>? items})
      : v = v ?? {},
        items = items ?? [];

  num n(String k) => v[k] is num ? v[k] as num : (num.tryParse('${v[k] ?? ''}') ?? 0);
  bool f(String k, [bool def = false]) => v[k] is bool ? v[k] as bool : def;
  String t(String k) => v[k] is String ? v[k] as String : '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'code': code,
        'title': title,
        if (isDefault) 'default': true,
        'v': v,
        if (items.isNotEmpty) 'items': items.map((e) => e.toJson()).toList(),
      };
  factory PayTable.fromJson(Map<String, dynamic> j) => PayTable(
        id: _s(j['id']),
        kind: PayTableKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => PayTableKind.salary),
        code: _i(j['code']),
        title: _s(j['title']),
        isDefault: j['default'] == true,
        v: j['v'] is Map ? {for (final e in (j['v'] as Map).entries) if (e.value != null) '${e.key}': e.value as Object} : null,
        items: j['items'] is List ? (j['items'] as List).whereType<Map<String, dynamic>>().map(PayTableItem.fromJson).toList() : null,
      );
  PayTable copy() => PayTable.fromJson(toJson());
}

/// A scalar setting of a table form: key, label and type ('money', 'num',
/// 'bool', 'text' or 'choice:a|b|c').
typedef PayParam = (String key, String label, String type);

List<PayParam> payTableParams(PayTableKind k) => switch (k) {
      PayTableKind.salary => const [
          ('dailyWage', 'دستمزد روزانه', 'money'),
          ('overtimeHour', 'هر ساعت اضافه کاری', 'money'),
          ('shortHour', 'هر ساعت کسر کاری', 'money'),
          ('eveningHour', 'هر ساعت حق شیفت عصر کاری', 'money'),
          ('nightHour', 'هر ساعت حق شیفت شب کاری', 'money'),
          ('shiftDay', 'هر روز حق شیفت', 'money'),
          ('missionDay', 'هر روز ماموریت', 'money'),
          ('missionHour', 'هر ساعت ماموریت', 'money'),
          ('absenceDay', 'هر روز جریمه غیبت', 'money'),
          ('unpaidDay', 'هر روز مرخصی بدون حقوق', 'money'),
          ('perf', 'تعیین ضریب عملکرد', 'num'),
          ('basis', 'احتساب دستمزد روزانه بر اساس', 'choice:بر اساس تعداد روزهای دوره|بر اساس روزهای حضور'),
          ('otIns', 'احتساب اضافه کاری در بیمه', 'bool'),
          ('otTax', 'احتساب اضافه کاری در مالیات', 'bool'),
          ('shiftIns', 'احتساب حق شیفت در بیمه', 'bool'),
          ('shiftTax', 'احتساب حق شیفت در مالیات', 'bool'),
          ('missionIns', 'احتساب ماموریت در بیمه', 'bool'),
          ('missionTax', 'احتساب ماموریت در مالیات', 'bool'),
        ],
      PayTableKind.insurance => const [
          ('type', 'نوع بیمه', 'choice:تامین اجتماعی|خدمات درمانی|بیمه سلامت|سایر|ندارد'),
          ('typeDesc', 'شرح نوع بیمه', 'text'),
          ('worker', 'حق بیمه پرداختی سهم کارگر (درصد)', 'num'),
          ('employer', 'حق بیمه پرداختی سهم کارفرما (درصد)', 'num'),
          ('unemployment', 'حق بیمه بیکاری پرداختی سهم کارفرما (درصد)', 'num'),
          ('hard', 'حق بیمه مشاغل سخت و زیان آور (درصد)', 'num'),
          ('capDaily', 'سقف تعلق بیمه برای یک روز کاری', 'money'),
          ('basis', 'محاسبه', 'choice:بر اساس تعداد روزهای حضور|بر اساس تعداد روزهای دوره'),
          ('taxFree', 'حق بیمه سهم کارگر معاف از مالیات', 'bool'),
          ('workshopName', 'نام کارگاه', 'text'),
          ('workshopCode', 'شماره کارگاه', 'text'),
          ('employerName', 'نام کارفرما', 'text'),
          ('workshopAddress', 'نشانی کارگاه', 'text'),
          ('office', 'نام مرکز بیمه', 'text'),
        ],
      PayTableKind.severance => const [
          ('daily', 'مبلغ روزانه مزایای پایان خدمت', 'money'),
          ('diffDaily', 'مبلغ روزانه ما به تفاوت مزایای پایان خدمت سال های گذشته', 'money'),
          ('fromYear', 'از سال', 'num'),
          ('reserve', 'سرفصل جذب حساب ذخیره مزایای پایان خدمت', 'text'),
          ('insured', 'مشمول بیمه', 'bool'),
          ('taxed', 'مشمول مالیات', 'bool'),
        ],
      PayTableKind.taxExemption => const [
          ('pct', 'درصد معافیت', 'num'),
          ('article', 'نوع معافیت', 'choice:معافیت ماده 91|معافیت ماده 92'),
          ('desc', 'توضیحات', 'text'),
        ],
      _ => const [],
    };

/// Defaults of a new table.
Map<String, Object> payTableDefaults(PayTableKind k) => switch (k) {
      PayTableKind.salary => {'perf': 1, 'basis': 'بر اساس روزهای حضور', 'otIns': true, 'otTax': true, 'shiftIns': true, 'shiftTax': true, 'missionIns': false, 'missionTax': true},
      PayTableKind.insurance => {'type': 'تامین اجتماعی', 'worker': 7, 'employer': 20, 'unemployment': 3, 'hard': 4, 'basis': 'بر اساس تعداد روزهای حضور', 'taxFree': true},
      PayTableKind.severance => {'insured': false, 'taxed': false},
      PayTableKind.taxExemption => {'pct': 50, 'article': 'معافیت ماده 92'},
      _ => {},
    };

/// The tables an employee follows (resolved with the defaults).
class PaySetup {
  final Map<PayTableKind, PayTable> t;
  const PaySetup(this.t);
  static const none = PaySetup({});
  PayTable? operator [](PayTableKind k) => t[k];
  bool get isEmpty => t.isEmpty;
}

/// Tax of [taxable] by a bracket table (each row from [PayTableItem.amount]
/// to [PayTableItem.to] (0 = above) at [PayTableItem.pct]).
int bracketTax(PayTable table, int taxable) {
  final rows = [...table.items]..sort((a, b) => a.amount.compareTo(b.amount));
  var t = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final lo = rows[i].amount;
    final hi = rows[i].to > 0 ? rows[i].to : (i + 1 < rows.length ? rows[i + 1].amount : null);
    if (taxable <= lo) break;
    final top = hi == null || taxable < hi ? taxable : hi;
    if (top > lo) t += (top - lo) * rows[i].pct / 100;
  }
  return t.round();
}

/// «مزایای غیر نقدی غیر مستمر» / «هزینه های غیر مستمر پرداختی معاف از
/// مالیات توسط مودی» given to an employee in a period.
class PayOnce {
  String id;
  String periodId;
  String employeeId;
  int code;
  String title;
  int amount;
  bool exemptExpense; // true: هزینه معاف از مالیات؛ false: مزایای غیر نقدی غیر مستمر
  bool insured;
  bool taxed;
  int taxCap; // سقف معافیت مالیاتی
  PayOnce({
    required this.id,
    required this.periodId,
    required this.employeeId,
    this.code = 0,
    this.title = '',
    this.amount = 0,
    this.exemptExpense = false,
    this.insured = false,
    this.taxed = true,
    this.taxCap = 0,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'periodId': periodId,
        'employeeId': employeeId,
        'code': code,
        'title': title,
        'amount': amount,
        if (exemptExpense) 'exemptExpense': true,
        'insured': insured,
        'taxed': taxed,
        if (taxCap != 0) 'taxCap': taxCap,
      };
  factory PayOnce.fromJson(Map<String, dynamic> j) => PayOnce(
        id: _s(j['id']),
        periodId: _s(j['periodId']),
        employeeId: _s(j['employeeId']),
        code: _i(j['code']),
        title: _s(j['title']),
        amount: _i(j['amount']),
        exemptExpense: j['exemptExpense'] == true,
        insured: j['insured'] == true,
        taxed: j['taxed'] != false,
        taxCap: _i(j['taxCap']),
      );
}
