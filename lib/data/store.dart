import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/format.dart' show groupDigits;
import '../core/hash.dart';
import '../core/jalali.dart';
import '../core/xlsx.dart';
import '../core/zip_backup.dart';
import 'books.dart';
import 'chart.dart';
import 'discounts.dart';
import 'marketing.dart';
import 'models.dart';
import 'payroll.dart';
import 'report_layout.dart';
import 'storage.dart';
import 'woo.dart';
import 'custom_reports.dart';
import 'journal.dart' show buildJournal;
import 'scale.dart';

class MonthTotals {
  int income = 0;
  int expense = 0;
  int get net => income - expense;
}

class TxnFilter {
  DateTime? from;
  DateTime? to;
  Set<TxnType> types = {};
  String? accountId;
  String? categoryId;
  String? personId;
  String query = '';
  int? minAmount;
  int? maxAmount;

  bool get isEmpty =>
      from == null &&
      to == null &&
      types.isEmpty &&
      accountId == null &&
      categoryId == null &&
      personId == null &&
      query.trim().isEmpty &&
      minAmount == null &&
      maxAmount == null;
}

class AppStore extends ChangeNotifier {
  final Storage storage;

  List<Account> accounts = [];
  List<TxnCategory> categories = [];
  List<Person> people = [];
  List<Txn> txns = [];
  List<Cheque> cheques = [];
  List<Product> products = [];
  List<Invoice> invoices = [];

  /// «واحدهای شمارش».
  List<CountUnit> units = [];

  /// «امانی» documents.
  List<Consignment> consignments = [];

  /// «ارزهای سیستم».
  List<Currency> currencies = [];

  /// «مدل تخفیفات و اشانتیون»، «تخفیف های عمومی / فردی»، «گروه های یارانه».
  List<DiscountModel> discountModels = [];
  List<AmountDiscount> amountDiscounts = [];
  List<SubsidyGroup> subsidyGroups = [];

  /// «مرکز دفاتر» and their groups; ribbon items hidden by «تنظیم دکمه‌ها».
  List<BookCenter> bookCenters = [];
  List<CenterGroup> centerGroups = [];
  Set<String> hiddenButtons = {};

  /// «ووکامرس»: connection settings and the fetched site orders.
  WooConfig woo = WooConfig();

  /// «تولید»: halls, formulas and production documents.
  List<ProductionHall> halls = [];
  List<ProductionFormula> formulas = [];
  List<Production> productions = [];

  /// «اسناد انتظامی» (سفته، وثیقه، ضمانت نامه).
  List<GuaranteeDoc> guarantees = [];

  /// «گارانتی» and «پذیرش» (repair service).
  List<Warranty> warranties = [];
  List<Reception> receptions = [];

  /// «رستوران»: tables, reservations, open orders and settings.
  List<RestTable> restTables = [];
  List<Reservation> reservations = [];
  List<RestTab> restTabs = [];
  RestConfig restConfig = RestConfig();

  /// «خرید بالانس».
  List<BalanceDeal> balanceDeals = [];

  /// «دفترچه اقساط».
  List<InstallmentPlan> installmentPlans = [];

  /// «مراکز رکورد (هزینه)».
  List<CostCenter> costCenters = [];
  List<CostCenterGroup> costCenterGroups = [];

  /// Automatic SMS, schedules and calendar reminders.
  SmsAuto smsAuto = SmsAuto();
  List<SmsSchedule> smsSchedules = [];
  List<Reminder> reminders = [];

  /// «ترازنامه سفارشی» / «صورتحساب سود/زیان سفارشی» layouts.
  List<CustomStatement> customStatements = [];

  /// «کارت هواداری»، «قرعه کشی»، «پیام های داخلی»، «تسویه فاکتور به فاکتور».
  List<LoyaltyCard> loyaltyCards = [];
  LoyaltyConfig loyalty = LoyaltyConfig();
  List<Redemption> redemptions = [];
  List<DrawCampaign> draws = [];
  List<InternalMessage> messages = [];
  List<InvoiceOffset> offsets = [];

  /// «سندهای تسویه» (تسویه فاکتور به فاکتور).
  List<SettleDoc> settleDocs = [];

  /// «ترازو» (weighted barcodes) settings.
  ScaleConfig scale = ScaleConfig();

  /// «دفترچه تلفن» and «لیست تماس های اخیر».
  List<Contact> contacts = [];
  List<CallLog> calls = [];

  /// «پرینتر های آشپزخانه» / «پرینتر های حواله انبار»: role → Windows printer name.
  Map<String, String> printers = {};
  List<WooOrder> wooOrders = [];

  /// «حقوق و دستمزد».
  List<Employee> employees = [];
  List<PayPeriod> payPeriods = [];
  List<Payslip> payslips = [];
  List<Leave> leaves = [];
  List<Mission> missions = [];
  List<StaffLoan> staffLoans = [];
  PayrollRules payrollRules = PayrollRules();
  Workshop workshop = Workshop();
  List<PayGroup> payGroups = [];

  /// «حضور و غیاب».
  List<Shift> shifts = [];
  List<ClockRecord> clock = [];
  Map<String, String> employeeShift = {}; // employee id → shift id

  /// Set when loading converted the data to a newer format.
  bool _needsSave = false;
  List<Loan> loans = [];
  List<StockAdjust> adjusts = [];
  List<Voucher> vouchers = [];
  List<ChequeBook> chequeBooks = [];
  List<PrintTemplate> printTemplates = [];
  List<ReportLayout> reportLayouts = [];

  /// «لیست اسناد» data keyed by `v:<id>`, `inv:<id>` or `txn:<id>`.
  Map<String, DocMeta> docMeta = {};

  /// دفترچه یادداشت of each account («مشاهده اسناد» F7), keyed by account key.
  Map<String, String> notebooks = {};

  /// Rows marked in «مشاهده اسناد» (علامت گذاری شده ها), keyed by account key.
  Map<String, Set<String>> marks = {};
  Map<String, String> defaultLayouts = {};
  List<Warehouse> warehouses = [_mainWarehouse()];

  static Warehouse _mainWarehouse() => Warehouse(id: 'main', code: 1, name: 'انبار ۱', keeper: 'انباردار');
  List<WarehouseTransfer> transfers = [];
  List<Asset> assets = [];

  /// مراکز اسناد
  List<String> docCenters = ['اصلی'];
  List<AppUser> users = [];
  List<AuditEntry> audit = [];

  /// سطل بازیافت — deleted documents.
  List<RecycleItem> recycle = [];

  /// مدیریت گزارشات — report files.
  List<ReportFile> reportFiles = [];

  /// گزارش پیام‌های ارسالی (newest first).
  List<SmsLogEntry> smsLog = [];

  /// Ledgers hidden in «کدبندی دفاتر کل و معین».
  Set<String> hiddenMoeens = {};

  /// Ledgers (معین) made in «کدبندی دفاتر کل و معین»: code -> name.
  Map<String, String> customMoeens = {};

  /// The signed-in user (not saved).
  String currentUserId = 'owner';

  /// Default template id per print type.
  Map<String, String> defaultTemplates = {};
  AppSettings settings = AppSettings();
  String? lastError;

  AppStore(this.storage);

  // ---------------------------------------------------------------- loading

  static AppStore load() {
    final base = Storage.init();
    final reg = BookRegistry(base.dir);
    return open(reg.storageOf(reg.current));
  }

  /// Opens (or initialises) the data stored in [s].
  static AppStore open(Storage s) {
    final store = AppStore(s);
    final data = s.read();
    if (data == null) {
      extraMoeens = [];
      store._seed();
      store._ensureUnits();
      store._persist();
    } else {
      store._fromJson(data);
      if (store._needsSave) {
        s.backupBefore('sakan-codes');
        store._persist();
        store._needsSave = false;
      }
      s.dailyBackup();
    }
    return store;
  }

  void _seed() {
    accounts = [
      Account(id: newId(), name: 'صندوق نقدی', type: AccountType.cash, color: 0xFF0F766E),
    ];
    const exp = [
      ('خوراک و خواربار', 0xFFE07A2F),
      ('رفت‌وآمد', 0xFF2F6FED),
      ('قبوض', 0xFF8B5CF6),
      ('اجاره و مسکن', 0xFFB45309),
      ('خرید کالا', 0xFFDB2777),
      ('درمان', 0xFFDC2626),
      ('تفریح', 0xFF0891B2),
      ('سایر هزینه‌ها', 0xFF64748B),
    ];
    const inc = [
      ('فروش', 0xFF16A34A),
      ('حقوق و دستمزد', 0xFF059669),
      ('خدمات', 0xFF0D9488),
      ('سایر درآمدها', 0xFF4D7C0F),
    ];
    categories = [
      for (final e in exp) TxnCategory(id: newId(), name: e.$1, kind: CategoryKind.expense, color: e.$2),
      for (final e in inc) TxnCategory(id: newId(), name: e.$1, kind: CategoryKind.income, color: e.$2),
    ];
  }

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) {
      final v = j[k];
      if (v is List) return v.whereType<Map<String, dynamic>>().toList();
      return [];
    }

    accounts = list('accounts').map(Account.fromJson).toList();
    categories = list('categories').map(TxnCategory.fromJson).toList();
    people = list('people').map(Person.fromJson).toList();
    txns = list('txns').map(Txn.fromJson).toList();
    cheques = list('cheques').map(Cheque.fromJson).toList();
    products = list('products').map(Product.fromJson).toList();
    invoices = list('invoices').map(Invoice.fromJson).toList();
    loans = list('loans').map(Loan.fromJson).toList();
    adjusts = list('adjusts').map(StockAdjust.fromJson).toList();
    vouchers = list('vouchers').map(Voucher.fromJson).toList();
    chequeBooks = list('chequeBooks').map(ChequeBook.fromJson).toList();
    printTemplates = list('printTemplates').map(PrintTemplate.fromJson).toList();
    reportLayouts = list('reportLayouts').map(ReportLayout.fromJson).toList();
    final dm = j['docMeta'];
    docMeta = dm is Map ? {for (final e in dm.entries) if (e.value is Map<String, dynamic>) '${e.key}': DocMeta.fromJson(e.value as Map<String, dynamic>)} : {};
    final nb = j['notebooks'];
    notebooks = nb is Map ? {for (final e in nb.entries) '${e.key}': '${e.value}'} : {};
    final mk = j['marks'];
    marks = mk is Map ? {for (final e in mk.entries) if (e.value is List) '${e.key}': {for (final x in e.value as List) '$x'}} : {};
    final dl = j['defaultLayouts'];
    defaultLayouts = dl is Map ? {for (final e in dl.entries) '${e.key}': '${e.value}'} : {};
    warehouses = list('warehouses').map(Warehouse.fromJson).toList();
    if (warehouses.isEmpty) warehouses.add(_mainWarehouse());
    transfers = list('transfers').map(WarehouseTransfer.fromJson).toList();
    assets = list('assets').map(Asset.fromJson).toList();
    users = list('users').map(AppUser.fromJson).toList();
    audit = list('audit').map(AuditEntry.fromJson).toList();
    recycle = list('recycle').map(RecycleItem.fromJson).toList();
    reportFiles = list('reportFiles').map(ReportFile.fromJson).toList();
    smsLog = list('smsLog').map(SmsLogEntry.fromJson).toList();
    units = list('units').map(CountUnit.fromJson).toList();
    consignments = list('consignments').map(Consignment.fromJson).toList();
    currencies = list('currencies').map(Currency.fromJson).toList();
    discountModels = list('discountModels').map(DiscountModel.fromJson).toList();
    amountDiscounts = list('amountDiscounts').map(AmountDiscount.fromJson).toList();
    subsidyGroups = list('subsidyGroups').map(SubsidyGroup.fromJson).toList();
    bookCenters = list('bookCenters').map(BookCenter.fromJson).toList();
    centerGroups = list('centerGroups').map(CenterGroup.fromJson).toList();
    final hb = j['hiddenButtons'];
    hiddenButtons = hb is List ? {for (final x in hb) '$x'} : {};
    woo = j['woo'] is Map<String, dynamic> ? WooConfig.fromJson(j['woo'] as Map<String, dynamic>) : WooConfig();
    wooOrders = list('wooOrders').map(WooOrder.fromJson).toList();
    halls = list('halls').map(ProductionHall.fromJson).toList();
    formulas = list('formulas').map(ProductionFormula.fromJson).toList();
    productions = list('productions').map(Production.fromJson).toList();
    guarantees = list('guarantees').map(GuaranteeDoc.fromJson).toList();
    warranties = list('warranties').map(Warranty.fromJson).toList();
    receptions = list('receptions').map(Reception.fromJson).toList();
    restTables = list('restTables').map(RestTable.fromJson).toList();
    balanceDeals = list('balanceDeals').map(BalanceDeal.fromJson).toList();
    installmentPlans = list('installmentPlans').map(InstallmentPlan.fromJson).toList();
    costCenters = list('costCenters').map(CostCenter.fromJson).toList();
    costCenterGroups = list('costCenterGroups').map(CostCenterGroup.fromJson).toList();
    smsAuto = j['smsAuto'] is Map<String, dynamic> ? SmsAuto.fromJson(j['smsAuto'] as Map<String, dynamic>) : SmsAuto();
    smsSchedules = list('smsSchedules').map(SmsSchedule.fromJson).toList();
    reminders = list('reminders').map(Reminder.fromJson).toList();
    customStatements = list('customStatements').map(CustomStatement.fromJson).toList();
    loyaltyCards = list('loyaltyCards').map(LoyaltyCard.fromJson).toList();
    loyalty = j['loyalty'] is Map<String, dynamic> ? LoyaltyConfig.fromJson(j['loyalty'] as Map<String, dynamic>) : LoyaltyConfig();
    redemptions = list('redemptions').map(Redemption.fromJson).toList();
    draws = list('draws').map(DrawCampaign.fromJson).toList();
    messages = list('messages').map(InternalMessage.fromJson).toList();
    offsets = list('offsets').map(InvoiceOffset.fromJson).toList();
    settleDocs = list('settleDocs').map(SettleDoc.fromJson).toList();
    contacts = list('contacts').map(Contact.fromJson).toList();
    calls = list('calls').map(CallLog.fromJson).toList();
    printers = j['printers'] is Map ? {for (final e in (j['printers'] as Map).entries) '${e.key}': '${e.value}'} : {};
    scale = j['scale'] is Map<String, dynamic> ? ScaleConfig.fromJson(j['scale'] as Map<String, dynamic>) : ScaleConfig();
    reservations = list('reservations').map(Reservation.fromJson).toList();
    restTabs = list('restTabs').map(RestTab.fromJson).toList();
    restConfig = j['restConfig'] is Map<String, dynamic> ? RestConfig.fromJson(j['restConfig'] as Map<String, dynamic>) : RestConfig();
    employees = list('employees').map(Employee.fromJson).toList();
    payPeriods = list('payPeriods').map(PayPeriod.fromJson).toList();
    payslips = list('payslips').map(Payslip.fromJson).toList();
    leaves = list('leaves').map(Leave.fromJson).toList();
    missions = list('missions').map(Mission.fromJson).toList();
    staffLoans = list('staffLoans').map(StaffLoan.fromJson).toList();
    payGroups = list('payGroups').map(PayGroup.fromJson).toList();
    shifts = list('shifts').map(Shift.fromJson).toList();
    clock = list('clock').map(ClockRecord.fromJson).toList();
    employeeShift = j['employeeShift'] is Map ? {for (final e in (j['employeeShift'] as Map).entries) '${e.key}': '${e.value}'} : {};
    payrollRules = j['payrollRules'] is Map<String, dynamic> ? PayrollRules.fromJson(j['payrollRules'] as Map<String, dynamic>) : PayrollRules();
    workshop = j['workshop'] is Map<String, dynamic> ? Workshop.fromJson(j['workshop'] as Map<String, dynamic>) : Workshop();
    _ensureUnits();
    final cm = j['customMoeens'];
    customMoeens = cm is Map ? {for (final e in cm.entries) '${e.key}': '${e.value}'} : {};
    _applyCustomMoeens();
    final hm = j['hiddenMoeens'];
    hiddenMoeens = hm is List ? {for (final x in hm) '$x'} : {};
    final dc = j['docCenters'];
    docCenters = dc is List && dc.isNotEmpty ? [for (final x in dc) '$x'] : ['اصلی'];
    final dt = j['defaultTemplates'];
    defaultTemplates = dt is Map ? {for (final e in dt.entries) '${e.key}': '${e.value}'} : {};
    final st = j['settings'];
    settings = st is Map<String, dynamic> ? AppSettings.fromJson(st) : AppSettings();
    if (_i0(j['version']) < 2) _migrateToSakanCodes();
    _sortTxns();
    _ensureDocNumbers();
    _ensureTafsiliCodes();
    _migrateLayouts();
  }

  /// Next free کد حساب تفصیلی (persons and products share one range, from 7001).
  int nextTafsiliCode() {
    var n = 7000;
    for (final p in people) {
      if (p.code > n) n = p.code;
    }
    for (final a in accounts) {
      final v = int.tryParse(a.info['code'] ?? '');
      if (v != null && v > n && v < 1000000) n = v;
    }
    for (final p in products) {
      final v = int.tryParse(normalizeDigits(p.code));
      if (v != null && v > n && v < 1000000) n = v;
    }
    return n + 1;
  }

  void _ensureTafsiliCodes() {
    for (final p in people) {
      if (p.code == 0) p.code = nextTafsiliCode();
    }
  }

  /// Sakan starts with «عدد / Number»; units already typed on products are added.
  void _ensureUnits() {
    if (units.isEmpty) units.add(CountUnit(id: newId(), name: 'عدد', latin: 'Number'));
    for (final p in products) {
      for (final n in [p.unit, p.unit2, p.unit3]) {
        if (n.trim().isNotEmpty && !units.any((u) => u.name == n.trim())) units.add(CountUnit(id: newId(), name: n.trim()));
      }
    }
  }

  /// Adds or renames a unit; renaming also updates the products using it.
  String? saveUnit(CountUnit u, {String? oldName}) {
    final name = u.name.trim();
    if (name.isEmpty) return 'نام واحد را وارد کنید';
    if (units.any((x) => x.id != u.id && x.name == name)) return 'واحد «$name» قبلاً تعریف شده است';
    u.name = name;
    final i = units.indexWhere((x) => x.id == u.id);
    if (i < 0) {
      units.add(u);
    } else {
      units[i] = u;
    }
    if (oldName != null && oldName != name) {
      for (final p in products) {
        if (p.unit == oldName) p.unit = name;
        if (p.unit2 == oldName) p.unit2 = name;
        if (p.unit3 == oldName) p.unit3 = name;
      }
    }
    _commit();
    return null;
  }

  /// Removes an unused unit.
  String? removeUnit(CountUnit u) {
    if (products.any((p) => p.unit == u.name || p.unit2 == u.name || p.unit3 == u.name)) {
      return 'واحد «${u.name}» در تعریف کالاها استفاده شده و حذف نمی‌شود';
    }
    units.removeWhere((x) => x.id == u.id);
    _commit();
    return null;
  }

  static int _i0(Object? v) => v is int ? v : int.tryParse('$v') ?? 1;

  /// Data version 2: ledger codes follow Sakan's coding (صندوق 1010, اشخاص
  /// 1125…) instead of the former 5-digit codes. Converts every stored code.
  void _migrateToSakanCodes() {
    final map = <String, String>{...legacyCodeMap};
    // ledgers the user made get the next free code of their new group
    final oldCustom = Map.of(customMoeens);
    customMoeens = {};
    _applyCustomMoeens();
    for (final e in oldCustom.entries) {
      if (e.key.length != 5) {
        customMoeens[e.key] = e.value;
        _applyCustomMoeens();
        continue;
      }
      final kol = legacyKolMap[e.key.substring(0, 3)] ?? '11';
      final code = nextLedgerCode(kol) ?? e.key;
      map[e.key] = code;
      customMoeens[code] = e.value;
      _applyCustomMoeens();
    }
    String conv(String c) => map[c] ?? c;
    for (final v in vouchers) {
      for (final l in v.lines) {
        l.moeen = conv(l.moeen);
      }
    }
    hiddenMoeens = {for (final c in hiddenMoeens) conv(c)};
    // opening amounts are kept on the natural side: re-sign when the side changes
    final other = <String, int>{};
    settings.openingOther.forEach((c, v) {
      final n = conv(c);
      final oldDebit = c.startsWith('1') || c.startsWith('5');
      final newDebit = findMoeen(n)?.debitNature ?? oldDebit;
      final dr = oldDebit ? v : -v;
      other[n] = (other[n] ?? 0) + (newDebit ? dr : -dr);
    });
    settings.openingOther
      ..clear()
      ..addAll(other);
    _needsSave = true;
  }

  void _applyCustomMoeens() {
    extraMoeens = [for (final e in customMoeens.entries) Moeen(e.key, e.value)];
  }

  /// ساخت دفتر — a new ledger (معین) under kol [kolCode]. Returns its code.
  String addMoeen(String kolCode, String name) {
    final code = nextLedgerCode(kolCode);
    if (code == null) throw StateError('کدهای این گروه پر شده است');
    customMoeens[code] = name.trim();
    _applyCustomMoeens();
    _commit();
    return code;
  }

  /// Renames or removes (when unused) a ledger made by the user.
  String? editMoeen(String code, {String? name, bool remove = false}) {
    if (!customMoeens.containsKey(code)) return 'دفاتر پیش فرض قابل تغییر نیستند';
    if (remove) {
      final used = vouchers.any((v) => v.lines.any((l) => l.moeen == code)) || settings.openingOther.containsKey(code);
      if (used) return 'این دفتر در اسناد استفاده شده است';
      customMoeens.remove(code);
    } else if (name != null && name.trim().isNotEmpty) {
      customMoeens[code] = name.trim();
    }
    _applyCustomMoeens();
    _commit();
    return null;
  }

  void toggleMoeenHidden(String code) {
    if (!hiddenMoeens.remove(code)) hiddenMoeens.add(code);
    _commit();
  }

  void saveNotebook(String key, String text) {
    if (text.trim().isEmpty) {
      notebooks.remove(key);
    } else {
      notebooks[key] = text;
    }
    _commit();
  }

  void toggleMark(String account, String row) {
    final m = marks.putIfAbsent(account, () => <String>{});
    if (!m.remove(row)) m.add(row);
    _commit();
  }

  Map<String, dynamic> toJson() => {
        'app': 'taraz',
        'version': 2,
        'savedAt': DateTime.now().toIso8601String(),
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'people': people.map((e) => e.toJson()).toList(),
        'txns': txns.map((e) => e.toJson()).toList(),
        'cheques': cheques.map((e) => e.toJson()).toList(),
        'products': products.map((e) => e.toJson()).toList(),
        'invoices': invoices.map((e) => e.toJson()).toList(),
        'loans': loans.map((e) => e.toJson()).toList(),
        'adjusts': adjusts.map((e) => e.toJson()).toList(),
        'vouchers': vouchers.map((e) => e.toJson()).toList(),
        'chequeBooks': chequeBooks.map((e) => e.toJson()).toList(),
        'printTemplates': printTemplates.map((e) => e.toJson()).toList(),
        'reportLayouts': reportLayouts.map((e) => e.toJson()).toList(),
        'docMeta': {for (final e in docMeta.entries) e.key: e.value.toJson()},
        'recycle': recycle.map((e) => e.toJson()).toList(),
        'reportFiles': reportFiles.map((e) => e.toJson()).toList(),
        'smsLog': smsLog.map((e) => e.toJson()).toList(),
        'units': units.map((e) => e.toJson()).toList(),
        'consignments': consignments.map((e) => e.toJson()).toList(),
        'currencies': currencies.map((e) => e.toJson()).toList(),
        'discountModels': discountModels.map((e) => e.toJson()).toList(),
        'amountDiscounts': amountDiscounts.map((e) => e.toJson()).toList(),
        'subsidyGroups': subsidyGroups.map((e) => e.toJson()).toList(),
        'bookCenters': bookCenters.map((e) => e.toJson()).toList(),
        'centerGroups': centerGroups.map((e) => e.toJson()).toList(),
        'hiddenButtons': hiddenButtons.toList(),
        'woo': woo.toJson(),
        'wooOrders': wooOrders.map((e) => e.toJson()).toList(),
        'halls': halls.map((e) => e.toJson()).toList(),
        'formulas': formulas.map((e) => e.toJson()).toList(),
        'productions': productions.map((e) => e.toJson()).toList(),
        'guarantees': guarantees.map((e) => e.toJson()).toList(),
        'warranties': warranties.map((e) => e.toJson()).toList(),
        'receptions': receptions.map((e) => e.toJson()).toList(),
        'restTables': restTables.map((e) => e.toJson()).toList(),
        'balanceDeals': balanceDeals.map((e) => e.toJson()).toList(),
        'installmentPlans': installmentPlans.map((e) => e.toJson()).toList(),
        'costCenters': costCenters.map((e) => e.toJson()).toList(),
        'costCenterGroups': costCenterGroups.map((e) => e.toJson()).toList(),
        'smsAuto': smsAuto.toJson(),
        'smsSchedules': smsSchedules.map((e) => e.toJson()).toList(),
        'reminders': reminders.map((e) => e.toJson()).toList(),
        'customStatements': customStatements.map((e) => e.toJson()).toList(),
        'loyaltyCards': loyaltyCards.map((e) => e.toJson()).toList(),
        'loyalty': loyalty.toJson(),
        'redemptions': redemptions.map((e) => e.toJson()).toList(),
        'draws': draws.map((e) => e.toJson()).toList(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'offsets': offsets.map((e) => e.toJson()).toList(),
        'settleDocs': settleDocs.map((e) => e.toJson()).toList(),
        'scale': scale.toJson(),
        'contacts': contacts.map((e) => e.toJson()).toList(),
        'calls': calls.map((e) => e.toJson()).toList(),
        'printers': printers,
        'reservations': reservations.map((e) => e.toJson()).toList(),
        'restTabs': restTabs.map((e) => e.toJson()).toList(),
        'restConfig': restConfig.toJson(),
        'employees': employees.map((e) => e.toJson()).toList(),
        'payPeriods': payPeriods.map((e) => e.toJson()).toList(),
        'payslips': payslips.map((e) => e.toJson()).toList(),
        'leaves': leaves.map((e) => e.toJson()).toList(),
        'missions': missions.map((e) => e.toJson()).toList(),
        'staffLoans': staffLoans.map((e) => e.toJson()).toList(),
        'payrollRules': payrollRules.toJson(),
        'payGroups': payGroups.map((e) => e.toJson()).toList(),
        'shifts': shifts.map((e) => e.toJson()).toList(),
        'clock': clock.map((e) => e.toJson()).toList(),
        'employeeShift': employeeShift,
        'workshop': workshop.toJson(),
        'hiddenMoeens': hiddenMoeens.toList(),
        'customMoeens': customMoeens,
        'notebooks': notebooks,
        'marks': {for (final e in marks.entries) if (e.value.isNotEmpty) e.key: e.value.toList()},
        'defaultLayouts': defaultLayouts,
        'warehouses': warehouses.map((e) => e.toJson()).toList(),
        'transfers': transfers.map((e) => e.toJson()).toList(),
        'assets': assets.map((e) => e.toJson()).toList(),
        'docCenters': docCenters,
        'users': users.map((e) => e.toJson()).toList(),
        'audit': audit.map((e) => e.toJson()).toList(),
        'defaultTemplates': defaultTemplates,
        'settings': settings.toJson(),
      };

  void _sortTxns() {
    txns.sort((a, b) {
      final c = b.date.compareTo(a.date);
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  void _persist() {
    // another computer on the network saved first: take its data, do not overwrite
    if (storage.changedExternally()) {
      final d = storage.read();
      if (d != null) {
        _fromJson(d);
        lastError = 'اطلاعات همزمان در کامپیوتر دیگری (${storage.lastWriter.split(' ').first}) تغییر کرده بود؛ اطلاعات تازه بارگذاری شد و آخرین تغییر شما ذخیره نشد. لطفا دوباره ثبت کنید.';
        return;
      }
    }
    try {
      storage.save(toJson());
      lastError = null;
    } catch (e) {
      lastError = 'خطا در ذخیره اطلاعات: $e';
    }
  }

  void _commit() {
    _sortTxns();
    _persist();
    notifyListeners();
  }

  /// «شبکه»: reloads when another computer saved the shared data. Returns true when reloaded.
  bool syncFromDisk() {
    if (!storage.changedExternally()) return false;
    final d = storage.read();
    if (d == null) return false;
    _fromJson(d);
    notifyListeners();
    return true;
  }

  /// Saves and notifies (used when another component edits fields directly).
  void saveNow() => _commit();

  // ---------------------------------------------------------------- lookups

  Account? account(String? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  TxnCategory? category(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Person? person(String? id) {
    if (id == null) return null;
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  Cheque? cheque(String? id) {
    if (id == null) return null;
    for (final c in cheques) {
      if (c.id == id) return c;
    }
    return null;
  }

  Product? product(String? id) {
    if (id == null) return null;
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Invoice? invoice(String? id) {
    if (id == null) return null;
    for (final i in invoices) {
      if (i.id == id) return i;
    }
    return null;
  }

  Loan? loan(String? id) {
    if (id == null) return null;
    for (final l in loans) {
      if (l.id == id) return l;
    }
    return null;
  }

  Txn? txn(String? id) {
    if (id == null) return null;
    for (final t in txns) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();

  List<TxnCategory> categoriesOf(CategoryKind kind, {bool includeArchived = false}) =>
      categories.where((c) => c.kind == kind && (includeArchived || !c.archived)).toList();

  List<Person> get peopleSorted => [...people]..sort((a, b) => a.name.compareTo(b.name));

  // ---------------------------------------------------------------- balances

  int balance(String accountId, {DateTime? upTo}) {
    final a = account(accountId);
    var b = a?.opening ?? 0;
    for (final t in txns) {
      if (upTo != null && t.date.isAfter(upTo)) continue;
      b += t.effectOn(accountId);
    }
    for (final v in vouchers) {
      if (upTo != null && v.date.isAfter(upTo)) continue;
      for (final l in v.lines) {
        if (l.tafsiliId == accountId) b += l.debit - l.credit;
      }
    }
    return b;
  }

  int get totalBalance {
    var s = 0;
    for (final a in accounts) {
      s += balance(a.id);
    }
    return s;
  }

  int personBalance(String personId, {String? excludeInvoiceId}) {
    var b = person(personId)?.opening ?? 0;
    for (final t in txns) {
      if (excludeInvoiceId != null && t.invoiceId == excludeInvoiceId) continue;
      if (t.personId == personId) b += t.type.personSign * t.amount;
    }
    for (final v in vouchers) {
      for (final l in v.lines) {
        if (l.tafsiliId == personId) b += l.debit - l.credit;
      }
    }
    // «پورسانت»: the marketer is owed his share of each sale
    if (settings.commissionExpense) {
      for (final inv in realInvoices) {
        if (inv.id == excludeInvoiceId || !inv.marketers.any((m) => m.personId == personId)) continue;
        for (final (m, _, amount) in commissions(inv)) {
          if (m.personId == personId) b += inv.kind == InvoiceKind.saleReturn ? amount : -amount;
        }
      }
    }
    return b;
  }

  int get totalReceivable {
    var s = 0;
    for (final p in people) {
      final b = personBalance(p.id);
      if (b > 0) s += b;
    }
    return s;
  }

  int get totalPayable {
    var s = 0;
    for (final p in people) {
      final b = personBalance(p.id);
      if (b < 0) s += -b;
    }
    return s;
  }

  static bool _open(Cheque c) => c.status == ChequeStatus.pending || c.status == ChequeStatus.deposited;

  int get pendingChequesIn => cheques
      .where((c) => c.direction == ChequeDirection.received && _open(c))
      .fold(0, (s, c) => s + c.amount);

  int get pendingChequesOut => cheques
      .where((c) => c.direction == ChequeDirection.issued && _open(c))
      .fold(0, (s, c) => s + c.amount);

  /// Net worth = cash + receivables - payables + cheques in - out + stock - loans left.
  int get netWorth =>
      totalBalance +
      totalReceivable -
      totalPayable +
      pendingChequesIn -
      pendingChequesOut +
      stockValue() -
      totalLoanRemaining;

  MonthTotals totalsBetween(DateTime from, DateTime to) {
    final m = MonthTotals();
    for (final t in txns) {
      if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
      if (t.type == TxnType.income) m.income += t.amount;
      if (t.type == TxnType.expense) m.expense += t.amount;
    }
    return m;
  }

  MonthTotals monthTotals(Jalali month) =>
      totalsBetween(month.firstOfMonth.toDateTime(), month.lastOfMonth.toDateTime());

  /// Category totals for a range, sorted descending.
  List<MapEntry<String?, int>> categoryTotals(DateTime from, DateTime to, TxnType type) {
    final map = <String?, int>{};
    for (final t in txns) {
      if (t.type != type) continue;
      if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
      map[t.categoryId] = (map[t.categoryId] ?? 0) + t.amount;
    }
    final list = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  // ---------------------------------------------------------------- filters

  List<Txn> filter(TxnFilter f) {
    final q = normalizeDigits(f.query.trim()).toLowerCase();
    return txns.where((t) {
      if (f.from != null && t.date.isBefore(f.from!)) return false;
      if (f.to != null && t.date.isAfter(f.to!)) return false;
      if (f.types.isNotEmpty && !f.types.contains(t.type)) return false;
      if (f.accountId != null && t.accountId != f.accountId && t.toAccountId != f.accountId) {
        return false;
      }
      if (f.categoryId != null && t.categoryId != f.categoryId) return false;
      if (f.personId != null && t.personId != f.personId) return false;
      if (f.minAmount != null && t.amount < f.minAmount!) return false;
      if (f.maxAmount != null && t.amount > f.maxAmount!) return false;
      if (q.isNotEmpty) {
        final hay = [
          t.note,
          t.type.label,
          account(t.accountId)?.name ?? '',
          account(t.toAccountId)?.name ?? '',
          category(t.categoryId)?.name ?? '',
          person(t.personId)?.name ?? '',
          t.amount.toString(),
          jFormat(t.date),
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  /// Debts with due date that are still open for that person.
  List<Txn> upcomingDue({int days = 30}) {
    final today = dateOnly(DateTime.now());
    final limit = today.add(Duration(days: days));
    return txns
        .where((t) =>
            (t.type == TxnType.lend || t.type == TxnType.borrow) &&
            t.dueDate != null &&
            !t.dueDate!.isAfter(limit) &&
            t.personId != null &&
            personBalance(t.personId!) != 0)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  List<Cheque> upcomingCheques({int days = 30}) {
    final limit = dateOnly(DateTime.now()).add(Duration(days: days));
    return cheques
        .where((c) => _open(c) && !c.dueDate.isAfter(limit))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  // ---------------------------------------------------------------- mutations

  void upsertAccount(Account a) {
    final i = accounts.indexWhere((e) => e.id == a.id);
    if (i >= 0) {
      accounts[i] = a;
    } else {
      accounts.add(a);
    }
    _commit();
  }

  bool accountInUse(String id) =>
      txns.any((t) => t.accountId == id || t.toAccountId == id) ||
      vouchers.any((v) => v.lines.any((l) => l.tafsiliId == id));

  /// Deletes when unused; otherwise archives. Returns true if deleted.
  bool removeAccount(String id) {
    if (accountInUse(id)) {
      account(id)?.archived = true;
      _commit();
      return false;
    }
    accounts.removeWhere((a) => a.id == id);
    _commit();
    return true;
  }

  void upsertCategory(TxnCategory c) {
    final i = categories.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      categories[i] = c;
    } else {
      categories.add(c);
    }
    _commit();
  }

  bool removeCategory(String id) {
    if (txns.any((t) => t.categoryId == id)) {
      category(id)?.archived = true;
      _commit();
      return false;
    }
    categories.removeWhere((c) => c.id == id);
    _commit();
    return true;
  }

  void upsertPerson(Person p) {
    if (p.code == 0) p.code = nextTafsiliCode();
    final i = people.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      people[i] = p;
    } else {
      people.add(p);
    }
    _commit();
  }

  bool personInUse(String id) =>
      txns.any((t) => t.personId == id) ||
      cheques.any((c) => c.personId == id) ||
      (person(id)?.opening ?? 0) != 0 ||
      vouchers.any((v) => v.lines.any((l) => l.tafsiliId == id));

  bool removePerson(String id) {
    if (personInUse(id)) return false;
    people.removeWhere((p) => p.id == id);
    _commit();
    return true;
  }

  void upsertTxn(Txn t) {
    if (t.invoiceId == null) _touchDoc('txn:${t.id}');
    _log(txn(t.id) == null ? 'ثبت' : 'ویرایش', '${t.type.label} ${groupDigits(t.amount)}', docDate: t.date);
    if (t.type != TxnType.transfer) t.toAccountId = null;
    if (!t.type.hasCategory) t.categoryId = null;
    if (!(t.type == TxnType.lend || t.type == TxnType.borrow)) t.dueDate = null;
    final i = txns.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      txns[i] = t;
    } else {
      txns.add(t);
    }
    _commit();
  }

  void removeTxn(String id) {
    final t = txn(id);
    if (t == null) return;
    if (t.invoiceId == null) {
      _recycle('txn:$id', number: docMeta['txn:$id']?.number ?? 0, date: t.date, desc: '${t.type.label} ${t.note}'.trim(), amount: t.amount, payload: {'doc': t.toJson()});
    }
    _log('حذف', '${t.type.label} ${groupDigits(t.amount)}', docDate: t.date);
    if (t.chequeId != null) {
      final c = cheque(t.chequeId);
      if (c != null && c.txnId == id) {
        c.txnId = null;
        if (c.status == ChequeStatus.cleared) c.status = ChequeStatus.pending;
      }
    }
    txns.removeWhere((e) => e.id == id);
    docMeta.remove('txn:$id');
    final l = loan(t.loanId);
    if (l != null && l.closed && loanPaidCount(l.id) < l.installments) l.closed = false;
    _commit();
  }

  void upsertCheque(Cheque c) {
    final i = cheques.indexWhere((e) => e.id == c.id);
    _log(i >= 0 ? 'ویرایش' : 'ثبت', 'چک ${c.serial} ${groupDigits(c.amount)}', docDate: c.issueDate);
    if (i >= 0) {
      cheques[i] = c;
    } else {
      cheques.add(c);
    }
    // keep linked transaction amount in sync
    final linked = txn(c.txnId);
    if (linked != null) {
      linked.amount = c.amount;
      if (c.personId != null) linked.personId = c.personId;
    }
    _commit();
  }

  void removeCheque(String id) {
    final c = cheque(id);
    if (c == null) return;
    _log('حذف', 'چک ${c.serial} ${groupDigits(c.amount)}', docDate: c.issueDate);
    txns.removeWhere((t) => t.chequeId == c.id);
    cheques.removeWhere((e) => e.id == id);
    _commit();
  }

  /// Marks a cheque as cleared and records the money movement.
  void clearCheque(Cheque c, {required String accountId, required TxnType asType, String? categoryId, required DateTime date}) {
    txns.removeWhere((t) => t.chequeId == c.id);
    final t = Txn(
      id: newId(),
      type: asType,
      amount: c.amount,
      date: date,
      accountId: accountId,
      categoryId: asType.hasCategory ? categoryId : null,
      personId: c.personId,
      note: 'چک ${c.direction == ChequeDirection.received ? 'دریافتی' : 'پرداختی'}'
          '${c.serial.isNotEmpty ? ' شماره ${c.serial}' : ''}'
          '${c.bank.isNotEmpty ? ' - ${c.bank}' : ''}',
      chequeId: c.id,
    );
    txns.add(t);
    c.txnId = t.id;
    c.status = ChequeStatus.cleared;
    _commit();
  }

  void setChequeStatus(Cheque c, ChequeStatus s) {
    if (s != ChequeStatus.cleared && s != ChequeStatus.endorsed) {
      txns.removeWhere((t) => t.chequeId == c.id);
      c.txnId = null;
      c.endorsedTo = null;
    }
    if (s == ChequeStatus.pending) c.depositAccountId = null;
    c.status = s;
    _commit();
  }

  /// Hands a received cheque to the bank for collection.
  void depositCheque(Cheque c, String accountId) {
    c
      ..status = ChequeStatus.deposited
      ..depositAccountId = accountId;
    _commit();
  }

  /// Passes a received cheque on to another person (واگذاری).
  /// Settles the issuer's debt and what I owe the receiver.
  void endorseCheque(Cheque c, {required String toPersonId, required DateTime date}) {
    txns.removeWhere((t) => t.chequeId == c.id);
    final label = 'چک ${c.serial.isEmpty ? '' : '${c.serial} '}${c.bank}'.trim();
    if (c.personId != null) {
      txns.add(Txn(
        id: newId(),
        type: TxnType.collect,
        amount: c.amount,
        date: date,
        personId: c.personId,
        note: 'دریافت با $label (واگذار شد)',
        chequeId: c.id,
      ));
    }
    txns.add(Txn(
      id: newId(),
      type: TxnType.repay,
      amount: c.amount,
      date: date,
      personId: toPersonId,
      note: 'پرداخت با واگذاری $label',
      chequeId: c.id,
    ));
    c
      ..status = ChequeStatus.endorsed
      ..endorsedTo = toPersonId
      ..txnId = null;
    _commit();
  }

  /// Weighted average due date of the given cheques (راس‌گیری).
  DateTime? averageDue(List<Cheque> list) {
    var total = 0;
    var weighted = 0.0;
    final base = dateOnly(DateTime.now());
    for (final c in list) {
      total += c.amount;
      weighted += c.amount * c.dueDate.difference(base).inDays;
    }
    if (total == 0) return null;
    return base.add(Duration(days: (weighted / total).round()));
  }

  void updateSettings(void Function(AppSettings s) fn) {
    fn(settings);
    _commit();
  }

  // ---------------------------------------------------------------- login

  bool checkPassword(String password) {
    if (!settings.hasPassword) return true;
    return hashPassword(password, settings.passwordSalt) == settings.passwordHash;
  }

  void setPassword(String password, {String hint = ''}) {
    final salt = newSalt();
    settings
      ..passwordSalt = salt
      ..passwordHash = hashPassword(password, salt)
      ..passwordHint = hint;
    _commit();
  }

  void removePassword() {
    settings
      ..passwordSalt = ''
      ..passwordHash = ''
      ..passwordHint = '';
    _commit();
  }

  void completeSetup({required String ownerName, String? password, String hint = ''}) {
    settings
      ..ownerName = ownerName
      ..setupDone = true;
    if (password != null && password.isNotEmpty) {
      setPassword(password, hint: hint);
    } else {
      _commit();
    }
  }

  // ---------------------------------------------------------------- products & stock

  /// Invoices that affect stock and the ledger (pro-formas excluded).
  Iterable<Invoice> get realInvoices => invoices.where((i) => !i.proforma);

  List<Product> get productsSorted => [...products]..sort((a, b) => a.name.compareTo(b.name));

  void upsertProduct(Product p) {
    final i = products.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      products[i] = p;
    } else {
      products.add(p);
    }
    _ensureUnits();
    _commit();
  }

  bool productInUse(String id) =>
      invoices.any((inv) => inv.lines.any((l) => l.productId == id)) || adjusts.any((a) => a.productId == id);

  /// Deletes when unused; otherwise archives. Returns true if deleted.
  bool removeProduct(String id) {
    if (productInUse(id)) {
      product(id)?.archived = true;
      _commit();
      return false;
    }
    products.removeWhere((p) => p.id == id);
    _commit();
    return true;
  }

  /// Current stock of a product (optionally excluding one invoice being edited).
  /// Stock of a product; with [warehouseId] only that warehouse is counted.
  double stock(String productId, {String? excludeInvoiceId, String? warehouseId, String? excludeTransferId}) {
    final w = warehouseId;
    bool inW(String? id) => w == null || whId(id) == w;
    var q = inW(null) ? (product(productId)?.openingQty ?? 0) : 0.0;
    for (final a in adjusts) {
      if (a.productId == productId && inW(a.warehouseId)) q += a.qty;
    }
    for (final inv in realInvoices) {
      if (inv.id == excludeInvoiceId) continue;
      for (final l in inv.lines) {
        if (l.productId == productId && inW(l.warehouseId)) q += inv.kind.stockSign * l.qty;
      }
    }
    if (w != null) {
      for (final t in transfers) {
        if (t.id == excludeTransferId) continue;
        for (final l in t.lines) {
          if (l.productId != productId) continue;
          if (whId(t.fromId) == w) q -= l.qty;
          if (whId(l.toId) == w) q += l.qty;
        }
      }
    }
    return q;
  }

  // ---------------------------------------------------------------- warehouses

  String get mainWarehouseId => warehouses.first.id;

  /// Effective warehouse id (unknown/null → main warehouse).
  String whId(String? id) => id != null && warehouses.any((w) => w.id == id) ? id : mainWarehouseId;

  Warehouse? warehouse(String? id) => warehouses.where((w) => w.id == whId(id)).firstOrNull;

  int nextWarehouseCode() => warehouses.fold<int>(1, (n, w) => w.code >= n ? w.code + 1 : n);

  void saveWarehouse(Warehouse w) {
    final i = warehouses.indexWhere((x) => x.id == w.id);
    if (i >= 0) {
      warehouses[i] = w;
    } else {
      warehouses.add(w);
    }
    _commit();
  }

  bool warehouseUsed(String id) =>
      id == mainWarehouseId ||
      adjusts.any((a) => a.warehouseId == id) ||
      invoices.any((i) => i.lines.any((l) => l.warehouseId == id)) ||
      transfers.any((t) => t.fromId == id || t.lines.any((l) => l.toId == id));

  bool removeWarehouse(String id) {
    if (warehouseUsed(id)) return false;
    warehouses.removeWhere((w) => w.id == id);
    _commit();
    return true;
  }

  int nextTransferNumber() => transfers.fold<int>(1, (n, t) => t.number >= n ? t.number + 1 : n);
  int nextReceiptNumber() => transfers.fold<int>(1, (n, t) => t.receiptNo >= n ? t.receiptNo + 1 : n);

  void saveTransfer(WarehouseTransfer t) {
    final i = transfers.indexWhere((x) => x.id == t.id);
    _log(i >= 0 ? 'ویرایش' : 'ثبت', 'انتقال بین انبارها ${t.number}', docDate: t.date, docNo: t.number);
    if (i >= 0) {
      transfers[i] = t;
    } else {
      transfers.add(t);
    }
    _commit();
  }

  void removeTransfer(String id) {
    final t = transfers.where((x) => x.id == id).firstOrNull;
    if (t != null) _log('حذف', 'انتقال بین انبارها ${t.number}', docDate: t.date, docNo: t.number);
    transfers.removeWhere((t) => t.id == id);
    _commit();
  }

  // ---------------------------------------------------------------- امانی

  int nextConsignNumber(ConsignDir d) =>
      consignments.where((c) => c.dir == d).fold<int>(1, (n, c) => c.number >= n ? c.number + 1 : n);

  Consignment? consignment(String? id) => consignments.where((c) => c.id == id).firstOrNull;

  /// The consignment and row a [lineId] belongs to.
  (Consignment, ConsignLine)? consignLine(String? lineId) {
    if (lineId == null) return null;
    for (final c in consignments) {
      for (final l in c.lines) {
        if (l.id == lineId) return (c, l);
      }
    }
    return null;
  }

  /// Quantity (unit 1) of a consignment row settled by invoices («تسویه کل»).
  double consignInvoiced(String lineId, {String? excludeInvoiceId}) {
    var q = 0.0;
    for (final inv in realInvoices) {
      if (inv.id == excludeInvoiceId) continue;
      for (final l in inv.lines) {
        if (l.consignRef == lineId) q += l.qty;
      }
    }
    return q;
  }

  /// «مانده» (unit 1) of a consignment row.
  double consignRemaining(Consignment c, ConsignLine l, {String? excludeInvoiceId}) =>
      l.qty - c.returnedQty(l.id) - consignInvoiced(l.id, excludeInvoiceId: excludeInvoiceId);

  /// Goods of others held by us («موجودی امانی») or ours held by others.
  double consignOpen(String productId, ConsignDir dir, {String? warehouseId}) {
    var q = 0.0;
    for (final c in consignments.where((c) => c.dir == dir)) {
      for (final l in c.lines) {
        if (l.productId != productId) continue;
        if (warehouseId != null && whId(l.warehouseId) != warehouseId) continue;
        q += consignRemaining(c, l);
      }
    }
    return q;
  }

  String? saveConsignment(Consignment c) {
    if (c.lines.isEmpty) return 'حداقل یک ردیف کالا وارد کنید';
    if (c.lines.any((l) => l.qty <= 0)) return 'تعداد هر ردیف باید بیشتر از صفر باشد';
    final old = consignment(c.id);
    if (old != null) {
      for (final l in old.lines) {
        final settled = old.returnedQty(l.id) + consignInvoiced(l.id);
        if (settled == 0) continue;
        final n = c.lines.where((x) => x.id == l.id).firstOrNull;
        if (n == null) return 'ردیفی که تسویه شده قابل حذف نیست';
        if (n.qty < settled - 1e-9) return 'تعداد ردیف ${product(n.productId)?.name ?? ''} از مقدار تسویه شده کمتر است';
        if (n.productId != l.productId) return 'کالای ردیف تسویه شده قابل تغییر نیست';
      }
      c.returns = old.returns;
    }
    final i = consignments.indexWhere((x) => x.id == c.id);
    _log(i >= 0 ? 'ویرایش' : 'ثبت', '${c.dir.label} ${c.number}', docDate: c.date, docNo: c.number);
    if (i >= 0) {
      consignments[i] = c;
    } else {
      consignments.add(c);
    }
    _commit();
    return null;
  }

  String? removeConsignment(String id) {
    final c = consignment(id);
    if (c == null) return null;
    if (c.returns.isNotEmpty || c.lines.any((l) => consignInvoiced(l.id) > 0)) {
      return 'این سند امانی تسویه شده است؛ ابتدا تسویه‌ها را حذف کنید';
    }
    _log('حذف', '${c.dir.label} ${c.number}', docDate: c.date, docNo: c.number);
    consignments.removeWhere((x) => x.id == id);
    _commit();
    return null;
  }

  /// «تسویه انبار» — returns [qty] (unit 1) of a consignment row.
  String? addConsignReturn(String lineId, double qty, DateTime date, {String note = ''}) {
    final r = consignLine(lineId);
    if (r == null) return 'ردیف امانی پیدا نشد';
    if (qty <= 0) return 'تعداد را وارد کنید';
    if (qty > consignRemaining(r.$1, r.$2) + 1e-9) return 'تعداد از مانده امانی بیشتر است';
    r.$1.returns.add(ConsignReturn(id: newId(), lineId: lineId, date: date, qty: qty, note: note));
    _log('ثبت', 'تسویه انبار ${r.$1.dir.label} ${r.$1.number}', docDate: date, docNo: r.$1.number);
    _commit();
    return null;
  }

  void removeConsignReturn(String consignId, String returnId) {
    consignment(consignId)?.returns.removeWhere((r) => r.id == returnId);
    _commit();
  }

  // ---------------------------------------------------------------- تخفیفات و یارانه

  void saveDiscountModel(DiscountModel m) {
    final i = discountModels.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      discountModels[i] = m;
    } else {
      discountModels.add(m);
    }
    _commit();
  }

  void removeDiscountModel(String id) {
    discountModels.removeWhere((m) => m.id == id);
    _commit();
  }

  void saveAmountDiscounts(List<AmountDiscount> list, {String? personId}) {
    amountDiscounts
      ..removeWhere((d) => d.personId == personId)
      ..addAll(list.map((d) => d..personId = personId));
    _commit();
  }

  void saveSubsidyGroup(SubsidyGroup g) {
    if (g.isDefault) {
      for (final x in subsidyGroups) {
        x.isDefault = false;
      }
    }
    final i = subsidyGroups.indexWhere((x) => x.id == g.id);
    if (i >= 0) {
      subsidyGroups[i] = g;
    } else {
      subsidyGroups.add(g);
    }
    _commit();
  }

  String? removeSubsidyGroup(String id) {
    if (products.any((p) => p.info['subsidyGroup'] == id)) return 'این گروه به کالاها تخصیص داده شده است';
    subsidyGroups.removeWhere((g) => g.id == id);
    _commit();
    return null;
  }

  SubsidyGroup? subsidyGroupOf(Product? p) {
    final id = p?.info['subsidyGroup'];
    return subsidyGroups.where((g) => g.id == id).firstOrNull;
  }

  /// The best model for a sale row at [t]: (model, off, free units, gift, gift qty).
  (DiscountModel, int, double, String?, double)? bestModel(InvoiceLine l, DateTime t, {int priceType = 0}) {
    final p = product(l.productId);
    if (p == null) return null;
    (DiscountModel, int, double, String?, double)? best;
    for (final m in discountModels) {
      if (m.productId != null && m.productId != l.productId) continue;
      if (!m.appliesAt(t, priceType: priceType)) continue;
      final measure = switch (m.base) {
        DiscountBase.amount => l.gross.toDouble(),
        DiscountBase.unit2 => p.hasUnit(2) ? l.qty / p.unitFactor(2) : 0.0,
        DiscountBase.unit3 => p.hasUnit(3) ? l.qty / p.unitFactor(3) : 0.0,
        DiscountBase.unit1 => l.qty,
      };
      final r = m.evaluate(measure: measure, baseQty: l.qty, unitPrice: l.unitPrice, gross: l.gross);
      final value = r.$1 + (r.$2 * l.unitPrice).round();
      if (r.$1 == 0 && r.$2 == 0 && r.$3 == null) continue;
      if (best == null || value > best.$2 + (best.$3 * l.unitPrice).round()) best = (m, r.$1, r.$2, r.$3, r.$4);
    }
    return best;
  }

  /// Invoice-level percent from «تخفیف های عمومی» and the buyer's «تخفیفات فردی» (the larger).
  (double, String)? amountDiscountFor(int amount, String? personId) {
    (double, String)? best;
    for (final d in amountDiscounts) {
      if (d.personId != null && d.personId != personId) continue;
      if (!d.contains(amount)) continue;
      if (best == null || d.pct > best.$1) best = (d.pct, d.personId != null ? 'تخفیف فردی' : (d.name.isEmpty ? 'تخفیف عمومی' : d.name));
    }
    return best;
  }

  // ---------------------------------------------------------------- ارز

  Currency? currency(String? id) => currencies.where((c) => c.id == id).firstOrNull;

  String? saveCurrency(Currency c) {
    if (c.name.trim().isEmpty) return 'نام ارز را وارد کنید';
    if (currencies.any((x) => x.id != c.id && x.name == c.name.trim())) return 'ارز «${c.name}» تکراری است';
    c.name = c.name.trim();
    if (c.isDefault) {
      for (final x in currencies) {
        x.isDefault = false;
      }
    }
    final i = currencies.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      currencies[i] = c;
    } else {
      currencies.add(c);
    }
    _commit();
    return null;
  }

  String? removeCurrency(String id) {
    if (people.any((p) => p.currencyId == id) || vouchers.any((v) => v.lines.any((l) => l.currencyId == id))) {
      return 'این ارز در حساب‌ها یا اسناد استفاده شده و حذف نمی‌شود';
    }
    currencies.removeWhere((c) => c.id == id);
    _commit();
    return null;
  }

  /// Foreign balances: key «moeen|tafsili|currency» → (fx amount, book value in system currency), up to [to].
  Map<String, (double, int)> fxBalances({DateTime? to}) {
    final out = <String, (double, int)>{};
    for (final v in vouchers) {
      if (to != null && v.date.isAfter(to)) continue;
      for (final l in v.lines) {
        if (l.currencyId == null) continue;
        final k = '${l.moeen}|${l.tafsiliId ?? ''}|${l.currencyId}';
        final o = out[k] ?? (0.0, 0);
        out[k] = (o.$1 + l.fx, o.$2 + l.debit - l.credit);
      }
    }
    return out;
  }

  /// «تسعیر نرخ ارز»: one voucher bringing every foreign balance to [rates]
  /// (currency id → new rate); differences go to [gainAcc] / [lossAcc].
  Voucher? revalue(DateTime date, Map<String, int> rates, {String gainAcc = mFxGain, String lossAcc = mFxLoss}) {
    final lines = <VoucherLine>[];
    var net = 0;
    fxBalances(to: date).forEach((k, b) {
      final p = k.split('|');
      final rate = rates[p[2]];
      if (rate == null || b.$1 == 0) return;
      final diff = (b.$1 * rate).round() - b.$2;
      if (diff == 0) return;
      final cur = currency(p[2]);
      lines.add(VoucherLine(
        moeen: p[0],
        tafsiliId: p[1].isEmpty ? null : p[1],
        desc: 'تسعیر ${cur?.name ?? ''} به نرخ ${groupDigits(rate)}',
        debit: diff > 0 ? diff : 0,
        credit: diff < 0 ? -diff : 0,
        currencyId: p[2],
      ));
      net += diff;
    });
    if (lines.isEmpty) return null;
    if (net > 0) lines.add(VoucherLine(moeen: gainAcc, desc: 'درآمد ناشی از نوسانات نرخ ارز', credit: net));
    if (net < 0) lines.add(VoucherLine(moeen: lossAcc, desc: 'هزینه ناشی از نوسانات نرخ ارز', debit: -net));
    final v = Voucher(id: newId(), number: nextVoucherNumber(), fixedNumber: nextFixedNumber(), date: date, desc: 'تسعیر نرخ ارز', lines: lines, kind: 'revaluation');
    for (final e in rates.entries) {
      final c = currency(e.key);
      if (c != null) c.rate = e.value;
    }
    saveVoucher(v);
    return v;
  }

  // ---------------------------------------------------------------- حقوق و دستمزد

  Employee? employee(String? id) => employees.where((e) => e.id == id).firstOrNull;
  PayPeriod? payPeriod(String? id) => payPeriods.where((p) => p.id == id).firstOrNull;
  List<Employee> get activeEmployees => employees.where((e) => e.active).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
  List<PayPeriod> get periodsSorted => [...payPeriods]..sort((a, b) => b.start.compareTo(a.start));

  String nextPersonnelCode() {
    var n = 1000;
    for (final e in employees) {
      final v = int.tryParse(e.personnelCode) ?? 0;
      if (v > n) n = v;
    }
    return '${n + 1}';
  }

  /// Saves an employee; creates the person account (حساب تفصیلی) when needed.
  String? saveEmployee(Employee e) {
    if (e.fullName.isEmpty) return 'نام و نام خانوادگی را وارد کنید';
    if (e.personnelCode.isNotEmpty && employees.any((x) => x.id != e.id && x.personnelCode == e.personnelCode)) {
      return 'کد پرسنلی ${e.personnelCode} تکراری است';
    }
    var p = person(e.personId);
    if (p == null) {
      p = Person(id: newId(), name: e.fullName, phone: e.phone);
      e.personId = p.id;
    } else {
      p
        ..name = e.fullName
        ..phone = e.phone.isEmpty ? p.phone : e.phone;
    }
    upsertPerson(p);
    final i = employees.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      employees[i] = e;
    } else {
      employees.add(e);
    }
    _commit();
    return null;
  }

  String? removeEmployee(String id) {
    if (payslips.any((p) => p.employeeId == id)) return 'برای این پرسنل فیش حقوقی ثبت شده؛ به جای حذف، غیرفعالش کنید';
    employees.removeWhere((e) => e.id == id);
    leaves.removeWhere((l) => l.employeeId == id);
    missions.removeWhere((m) => m.employeeId == id);
    _commit();
    return null;
  }

  /// Adds the period of Jalali [year]/[month] (or returns the existing one).
  PayPeriod addPayPeriod(int year, int month) {
    final ex = payPeriods.where((p) => p.year == year && p.month == month).firstOrNull;
    if (ex != null) return ex;
    final start = Jalali(year, month, 1).toDateTime();
    final days = month <= 6 ? 31 : (month <= 11 ? 30 : (Jalali.isLeapYear(year) ? 30 : 29));
    final p = PayPeriod(id: newId(), year: year, month: month, days: days, start: start, end: start.add(Duration(days: days - 1)));
    payPeriods.add(p);
    // every active employee gets a payslip with a full month of work
    for (final e in activeEmployees) {
      payslips.add(Payslip(id: newId(), periodId: p.id, employeeId: e.id, workDays: p.days.toDouble()));
    }
    _commit();
    return p;
  }

  String? removePayPeriod(String id) {
    final p = payPeriod(id);
    if (p == null) return null;
    if (p.voucherId != null && vouchers.any((v) => v.id == p.voucherId)) return 'سند حقوق این دوره صادر شده؛ ابتدا سند را حذف کنید';
    payPeriods.removeWhere((x) => x.id == id);
    payslips.removeWhere((x) => x.periodId == id);
    _commit();
    return null;
  }

  /// «افزودن پرسنل به دوره» — a payslip for every active employee.
  int addEmployeesToPeriod(PayPeriod p) {
    var n = 0;
    for (final e in activeEmployees) {
      if (payslips.any((x) => x.periodId == p.id && x.employeeId == e.id)) continue;
      payslips.add(Payslip(id: newId(), periodId: p.id, employeeId: e.id, workDays: p.days.toDouble()));
      n++;
    }
    _commit();
    return n;
  }

  Payslip payslipOf(PayPeriod p, Employee e) {
    var s = payslips.where((x) => x.periodId == p.id && x.employeeId == e.id).firstOrNull;
    if (s == null) {
      s = Payslip(id: newId(), periodId: p.id, employeeId: e.id, workDays: p.days.toDouble());
      payslips.add(s);
    }
    return s;
  }

  void savePayslip(Payslip p) {
    final i = payslips.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      payslips[i] = p;
    } else {
      payslips.add(p);
    }
    _commit();
  }

  bool _inPeriod(DateTime d, PayPeriod p) => !d.isBefore(p.start) && !d.isAfter(p.end);

  List<Leave> leavesIn(Employee e, PayPeriod p) => leaves.where((l) => l.employeeId == e.id && _inPeriod(l.start, p)).toList();
  List<Mission> missionsIn(Employee e, PayPeriod p) => missions.where((m) => m.employeeId == e.id && _inPeriod(m.start, p)).toList();

  /// Loan balance of an employee before [period] (all earlier payslips' installments repaid).
  int loanRemaining(Employee e, {PayPeriod? before}) {
    var given = staffLoans.where((l) => l.employeeId == e.id && (before == null || !l.date.isAfter(before.end))).fold<int>(0, (a, l) => a + l.amount);
    for (final s in payslips.where((s) => s.employeeId == e.id)) {
      final p = payPeriod(s.periodId);
      if (p == null || (before != null && !p.start.isBefore(before.start))) continue;
      given -= _installment(e, p, s);
    }
    return given < 0 ? 0 : given;
  }

  int _installment(Employee e, PayPeriod p, Payslip s) => s.loanInstallment != 0 ? s.loanInstallment : autoInstallment(e, p);

  /// Installment of the open loans in [p], limited to the remaining balance.
  int autoInstallment(Employee e, PayPeriod p) {
    final open = staffLoans.where((l) => l.employeeId == e.id && !l.date.isAfter(p.end)).toList();
    if (open.isEmpty) return 0;
    final rem = loanRemaining(e, before: p);
    final inst = open.fold<int>(0, (a, l) => a + l.installment);
    return inst < rem ? inst : rem;
  }

  PayResult payResult(PayPeriod p, Employee e) {
    final s = payslipOf(p, e);
    return computePayslip(
      e: e,
      period: p,
      p: s,
      rules: payrollRules,
      leaves: leavesIn(e, p),
      missions: missionsIn(e, p),
      loanInstallment: _installment(e, p, s),
    );
  }

  /// Employees with a payslip in [p].
  List<Employee> employeesIn(PayPeriod p) {
    final ids = {for (final s in payslips.where((s) => s.periodId == p.id)) s.employeeId};
    return employees.where((e) => ids.contains(e.id)).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  /// «صدور سند حقوق» — one voucher for the whole period (replaces the previous one).
  Voucher postPayroll(PayPeriod p) {
    final lines = <VoucherLine>[];
    final desc = 'سند حقوق ${p.name}';
    var gross = 0, employer = 0, insurance = 0, tax = 0;
    for (final e in employeesIn(p)) {
      final r = payResult(p, e);
      gross += r.jamKol;
      employer += r.bimeSahmKarfarma + r.bimeBikari + r.bimeMashagheleSakht;
      insurance += r.bimeSahmBimeShode + r.bimeSahmKarfarma + r.bimeBikari + r.bimeMashagheleSakht;
      tax += r.maliat;
      if (r.vam != 0) lines.add(VoucherLine(moeen: mStaff, tafsiliId: e.personId, desc: 'قسط وام ${e.fullName}', credit: r.vam));
      if (r.jarime != 0) lines.add(VoucherLine(moeen: mOtherIncome, desc: 'جریمه ${e.fullName}', credit: r.jarime));
      if (r.kosoratSabet != 0) lines.add(VoucherLine(moeen: mOtherLiab, desc: 'کسورات ${e.fullName}', credit: r.kosoratSabet));
      if (r.gheirNaghdi != 0) lines.add(VoucherLine(moeen: mOtherLiab, desc: 'مزایای غیر نقدی ${e.fullName}', credit: r.gheirNaghdi));
      // the advance was already paid to the person account: it is not deducted twice
      final net = r.khales + r.mosaede;
      if (net != 0) lines.add(VoucherLine(moeen: mDebtorsTrade, tafsiliId: e.personId, desc: 'حقوق ${p.name} ${e.fullName}', credit: net));
    }
    lines.insertAll(0, [
      if (gross != 0) VoucherLine(moeen: mSalaryExpense, desc: desc, debit: gross),
      if (employer != 0) VoucherLine(moeen: mInsuranceExpense, desc: 'بیمه سهم کارفرما ${p.name}', debit: employer),
      if (insurance != 0) VoucherLine(moeen: mInsurancePayable, desc: 'بیمه ${p.name}', credit: insurance),
      if (tax != 0) VoucherLine(moeen: mSalaryTaxPayable, desc: 'مالیات حقوق ${p.name}', credit: tax),
    ]);
    final old = vouchers.where((v) => v.id == p.voucherId).firstOrNull;
    final v = Voucher(
      id: old?.id ?? newId(),
      number: old?.number ?? nextVoucherNumber(),
      fixedNumber: old?.fixedNumber ?? nextFixedNumber(),
      date: p.end,
      desc: desc,
      lines: lines,
      kind: 'payroll',
      meta: {'period': p.id},
      createdAt: old?.createdAt,
    );
    p.voucherId = v.id;
    saveVoucher(v);
    return v;
  }

  // ------------------------------------------------------------ حضور و غیاب

  Shift shiftOf(Employee e) =>
      shifts.where((x) => x.id == employeeShift[e.id]).firstOrNull ?? shifts.firstOrNull ?? Shift(id: '', name: 'پیش فرض');

  ClockRecord? clockOf(String employeeId, DateTime d) =>
      clock.where((c) => c.employeeId == employeeId && c.date.year == d.year && c.date.month == d.month && c.date.day == d.day).firstOrNull;

  void saveClock(ClockRecord r) {
    clock.removeWhere((c) => c.employeeId == r.employeeId && c.date.year == r.date.year && c.date.month == r.date.month && c.date.day == r.date.day);
    if (r.inMin != null || r.outMin != null || r.note.isNotEmpty) clock.add(r);
    _commit();
  }

  /// Imports punches (personnel / card code, day, minutes): first punch = entry,
  /// last = exit. Returns (days imported, unknown codes).
  (int, Set<String>) importPunches(List<(String, DateTime, int)> punches) {
    final unknown = <String>{};
    final days = <String, List<int>>{};
    final who = <String, (Employee, DateTime)>{};
    for (final (code, d, m) in punches) {
      final e = employees.where((e) => normalizeDigits(e.personnelCode) == code || normalizeDigits(e.cardCode) == code).firstOrNull;
      if (e == null) {
        unknown.add(code);
        continue;
      }
      final k = '${e.id}|${d.toIso8601String()}';
      (days[k] ??= []).add(m);
      who[k] = (e, d);
    }
    for (final e in days.entries) {
      final t = e.value..sort();
      final (emp, d) = who[e.key]!;
      final old = clockOf(emp.id, d);
      if (old != null && old.edited) continue; // keep manual corrections
      clock.removeWhere((c) => identical(c, old));
      clock.add(ClockRecord(employeeId: emp.id, date: d, inMin: t.first, outMin: t.length > 1 ? t.last : null));
    }
    _commit();
    return (days.length, unknown);
  }

  AttendanceResult attendance(Employee e, PayPeriod p) =>
      attendanceOf(clock.where((c) => c.employeeId == e.id && !c.date.isBefore(p.start) && !c.date.isAfter(p.end)).toList(), shiftOf(e), p.start, p.end);

  /// «انتقال به کارکرد»: absences, overtime and short hours into the payslips of [p].
  int applyAttendance(PayPeriod p) {
    var n = 0;
    for (final e in employeesIn(p)) {
      if (!clock.any((c) => c.employeeId == e.id && !c.date.isBefore(p.start) && !c.date.isAfter(p.end))) continue;
      final r = attendance(e, p);
      final s = payslipOf(p, e);
      s
        ..workDays = (p.days - r.absentDays).clamp(0, 31).toDouble()
        ..overtimeHours = (r.overtimeMinutes / 60 * 100).round() / 100
        ..shortHours = (r.shortMinutes / 60 * 100).round() / 100;
      savePayslip(s);
      n++;
    }
    return n;
  }

  /// «سند اتوماتیک ذخیره»: the end-of-service reserve of a period (Dr salary expense, Cr 2130).
  Voucher? postServiceReserve(PayPeriod p) {
    vouchers.removeWhere((v) => v.kind == 'serviceReserve' && v.meta['period'] == p.id);
    var total = 0;
    for (final e in employeesIn(p)) {
      total += serviceReserve(e, payResult(p, e));
    }
    if (total == 0) {
      _commit();
      return null;
    }
    final desc = 'ذخیره مزایای پایان خدمت ${p.name}';
    final v = Voucher(
      id: newId(),
      number: nextVoucherNumber(),
      fixedNumber: nextFixedNumber(),
      date: p.end,
      desc: desc,
      kind: 'serviceReserve',
      meta: {'period': p.id},
      lines: [VoucherLine(moeen: mSalaryExpense, desc: desc, debit: total), VoucherLine(moeen: '2130', desc: desc, credit: total)],
    );
    saveVoucher(v);
    return v;
  }

  /// «پرداخت وام پرسنل» — pays the loan out of [accountId] (cash box or bank).
  void saveStaffLoan(StaffLoan l) {
    final e = employee(l.employeeId);
    final i = staffLoans.indexWhere((x) => x.id == l.id);
    if (i >= 0) {
      staffLoans[i] = l;
    } else {
      staffLoans.add(l);
    }
    vouchers.removeWhere((v) => v.kind == 'staffLoan' && v.meta['loan'] == l.id);
    final a = account(l.accountId);
    if (e != null && a != null && l.amount > 0) {
      saveVoucher(Voucher(
        id: newId(),
        number: nextVoucherNumber(),
        fixedNumber: nextFixedNumber(),
        date: l.date,
        desc: 'پرداخت وام به ${e.fullName}',
        kind: 'staffLoan',
        meta: {'loan': l.id},
        lines: [
          VoucherLine(moeen: mStaff, tafsiliId: e.personId, desc: 'وام ${e.fullName}', debit: l.amount),
          VoucherLine(moeen: a.type == AccountType.cash ? mCash : mBank, tafsiliId: a.id, desc: 'وام ${e.fullName}', credit: l.amount),
        ],
      ));
    } else {
      _commit();
    }
  }

  void removeStaffLoan(String id) {
    staffLoans.removeWhere((l) => l.id == id);
    vouchers.removeWhere((v) => v.kind == 'staffLoan' && v.meta['loan'] == id);
    _commit();
  }

  void saveLeave(Leave l) {
    final i = leaves.indexWhere((x) => x.id == l.id);
    if (i >= 0) {
      leaves[i] = l;
    } else {
      leaves.add(l);
    }
    _commit();
  }

  void saveMission(Mission m) {
    final i = missions.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      missions[i] = m;
    } else {
      missions.add(m);
    }
    _commit();
  }

  void removeLeave(String id) {
    leaves.removeWhere((l) => l.id == id);
    _commit();
  }

  void removeMission(String id) {
    missions.removeWhere((m) => m.id == id);
    _commit();
  }

  /// «مانده مرخصی» of the Jalali [year]: allowed, used and remaining days.
  (double allowed, double used, double remaining) leaveBalance(Employee e, int year) {
    final from = Jalali(year, 1, 1).toDateTime();
    final to = Jalali(year + 1, 1, 1).toDateTime();
    final used = leaves
        .where((l) => l.employeeId == e.id && l.kind == LeaveKind.paid && !l.start.isBefore(from) && l.start.isBefore(to))
        .fold<double>(0, (a, l) => a + l.days + l.hours / 8);
    final bought = payslips.where((s) {
      final p = payPeriod(s.periodId);
      return s.employeeId == e.id && p != null && p.year == year;
    }).fold<double>(0, (a, s) => a + s.leaveBuybackDays);
    final allowed = e.annualLeaveDays.toDouble();
    return (allowed, used + bought, allowed - used - bought);
  }

  void updatePayrollRules(PayrollRules r) {
    payrollRules = r;
    _commit();
  }

  void updateWorkshop(Workshop w) {
    workshop = w;
    _commit();
  }

  // ---------------------------------------------------------------- users & audit

  AppUser get owner => AppUser(
        id: 'owner',
        code: 1,
        name: settings.ownerName.trim().isEmpty ? 'مدیر' : settings.ownerName.trim(),
        login: 'admin',
        admin: true,
      );

  List<AppUser> get allUsers => [owner, ...users];
  AppUser get currentUser => allUsers.where((u) => u.id == currentUserId).firstOrNull ?? owner;
  String userName(String id) => allUsers.where((u) => u.id == id).firstOrNull?.name ?? id;
  bool get multiUser => users.isNotEmpty;

  /// Whether the signed-in user may use a ribbon button.
  bool canUse(String label) {
    if (hiddenButtons.contains(label)) return false;
    final u = currentUser;
    return u.admin || !u.denied.contains(label);
  }

  void setHiddenButtons(Set<String> labels) {
    hiddenButtons = labels;
    _commit();
  }

  int nextUserCode() => allUsers.fold<int>(1, (n, u) => u.code >= n ? u.code + 1 : n);

  String? saveUser(AppUser u, {String? password}) {
    u
      ..name = u.name.trim()
      ..login = u.login.trim();
    if (u.name.isEmpty) return 'نام کاربر را وارد کنید';
    if (u.login.isEmpty) return 'نام ورود کاربر را وارد کنید';
    if (u.login.toLowerCase() == 'admin' || users.any((x) => x.id != u.id && x.login.toLowerCase() == u.login.toLowerCase())) {
      return 'این نام ورود قبلا استفاده شده است';
    }
    if (password != null) {
      final salt = newSalt();
      u
        ..passwordSalt = salt
        ..passwordHash = password.isEmpty ? '' : hashPassword(password, salt);
    }
    final i = users.indexWhere((x) => x.id == u.id);
    if (i >= 0) {
      users[i] = u;
    } else {
      users.add(u);
    }
    _log(i >= 0 ? 'ویرایش' : 'ثبت', 'کاربر ${u.name}');
    _commit();
    return null;
  }

  void removeUser(String id) {
    final u = users.where((x) => x.id == id).firstOrNull;
    if (u == null) return;
    users.remove(u);
    _log('حذف', 'کاربر ${u.name}');
    _commit();
  }

  /// Returns the user for a login name + password, or null.
  AppUser? login(String loginName, String password) {
    final l = loginName.trim().toLowerCase();
    AppUser? u;
    if (l == 'admin' || l == owner.name.toLowerCase()) {
      if (checkPassword(password)) u = owner;
    } else {
      final x = users.where((x) => x.login.toLowerCase() == l || x.name.toLowerCase() == l).firstOrNull;
      if (x != null && (x.passwordHash.isEmpty ? password.isEmpty : hashPassword(password, x.passwordSalt) == x.passwordHash)) u = x;
    }
    if (u != null) {
      currentUserId = u.id;
      _log('ورود', 'ورود به برنامه');
      _commit();
    }
    return u;
  }

  static String get _computer {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------- سطل بازیافت

  void _recycle(String key, {required int number, required DateTime date, required String desc, required int amount, required Map<String, dynamic> payload}) {
    final m = docMeta[key];
    recycle.add(RecycleItem(
      id: newId(),
      key: key,
      deletedAt: DateTime.now(),
      userId: currentUserId,
      number: number,
      date: date,
      desc: desc,
      amount: amount,
      payload: {...payload, if (m != null) 'meta': m.toJson()},
    ));
  }

  /// Voucher kinds that change other records and so cannot simply be put back.
  static const _noRestore = {'assetBuy', 'assetSell', 'depreciation', 'chequeMove', 'closing', 'reopen'};

  /// بازیابی سند. Returns an error message, or null when restored.
  String? restoreRecycled(String id) {
    final r = recycle.where((x) => x.id == id).firstOrNull;
    if (r == null) return 'سند پیدا نشد';
    final doc = r.payload['doc'];
    if (doc is! Map<String, dynamic>) return 'اطلاعات سند ناقص است';
    final key = r.key;
    switch (r.kind) {
      case 'v':
        final v = Voucher.fromJson(doc);
        if (_noRestore.contains(v.kind)) return 'این نوع سند قابل بازیابی نیست';
        if (vouchers.any((x) => x.id == v.id)) return 'این سند قبلاً بازیابی شده است';
        if (vouchers.any((x) => x.number == v.number)) v.number = nextVoucherNumber();
        vouchers.add(v);
      case 'inv':
        final inv = Invoice.fromJson(doc);
        if (invoices.any((x) => x.id == inv.id)) return 'این سند قبلاً بازیابی شده است';
        invoices.add(inv);
        for (final x in (r.payload['vouchers'] as List? ?? const [])) {
          if (x is Map<String, dynamic>) vouchers.add(Voucher.fromJson(x));
        }
        for (final x in (r.payload['txns'] as List? ?? const [])) {
          if (x is Map<String, dynamic>) txns.add(Txn.fromJson(x));
        }
      default:
        final t = Txn.fromJson(doc);
        if (txns.any((x) => x.id == t.id)) return 'این سند قبلاً بازیابی شده است';
        txns.add(t);
    }
    final m = r.payload['meta'];
    if (m is Map<String, dynamic>) {
      final meta = DocMeta.fromJson(m);
      if (!key.startsWith('v:') && docMeta.values.any((x) => x.number == meta.number)) meta.number = 0;
      docMeta[key] = meta;
    }
    _touchDoc(key);
    recycle.remove(r);
    _sortTxns();
    _log('بازیابی', r.desc, docDate: r.date, docNo: r.number);
    _commit();
    return null;
  }

  /// حذف سند from the bin (permanent).
  void purgeRecycled(String id) {
    recycle.removeWhere((x) => x.id == id);
    _commit();
  }

  /// پاک کردن سطل بازیافت
  void clearRecycle() {
    recycle.clear();
    _log('حذف', 'پاک کردن سطل بازیافت');
    _commit();
  }

  void _log(String action, String desc, {DateTime? docDate, int? docNo}) {
    audit.add(AuditEntry(userId: currentUserId, at: DateTime.now(), docDate: docDate, action: action, desc: desc, computer: _computer, docNo: docNo));
    if (audit.length > 20000) audit.removeRange(0, audit.length - 20000);
  }

  // ---------------------------------------------------------------- document centers

  bool centerUsed(String name) => vouchers.any((v) => v.center == name);

  /// Adds or renames a document center (vouchers follow the new name).
  String? saveCenter(String name, {String? old}) {
    name = name.trim();
    if (name.isEmpty) return 'نام مرکز اسناد را وارد کنید';
    if (docCenters.contains(name) && name != old) return 'این نام قبلا ثبت شده است';
    if (old == null) {
      docCenters.add(name);
    } else {
      final i = docCenters.indexOf(old);
      if (i < 0) return 'مرکز اسناد پیدا نشد';
      docCenters[i] = name;
      for (final v in vouchers.where((v) => v.center == old)) {
        v.center = name;
      }
    }
    _commit();
    return null;
  }

  String? removeCenter(String name) {
    if (docCenters.length <= 1) return 'حداقل یک مرکز اسناد لازم است';
    if (centerUsed(name)) return 'این مرکز اسناد در اسناد استفاده شده است';
    docCenters.remove(name);
    _commit();
    return null;
  }

  // ---------------------------------------------------------------- assets

  int nextAssetCode() => assets.fold<int>(1, (n, a) => a.code >= n ? a.code + 1 : n);
  Asset? asset(String? id) => assets.where((a) => a.id == id).firstOrNull;

  /// Saves an asset and keeps its depreciation document in sync.
  void saveAsset(Asset a) {
    final i = assets.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      assets[i] = a;
    } else {
      assets.add(a);
    }
    final dep = vouchers.where((v) => v.kind == 'depreciation' && v.meta['asset'] == a.id).firstOrNull;
    if (a.depreciation > 0 && !a.sold) {
      final lines = [
        VoucherLine(moeen: mDepreciation, desc: 'استهلاک ${a.name}', debit: a.depreciation),
        VoucherLine(moeen: mAccDepreciation, desc: 'استهلاک ${a.name}', credit: a.depreciation),
      ];
      if (dep != null) {
        dep.lines = lines;
      } else {
        final n = DateTime.now();
        vouchers.add(Voucher(
          id: newId(),
          number: nextVoucherNumber(),
          fixedNumber: nextFixedNumber(),
          date: DateTime(n.year, n.month, n.day),
          desc: 'استهلاک انباشته ${a.name}',
          lines: lines,
          kind: 'depreciation',
          meta: {'asset': a.id},
        ));
      }
    } else if (dep != null && !a.sold) {
      vouchers.remove(dep);
    }
    _commit();
  }

  /// Deletes an asset that has no purchase or sale document.
  bool removeAsset(String id) {
    final a = asset(id);
    if (a == null || a.buyVoucherId != null || a.sold) return false;
    vouchers.removeWhere((v) => v.kind == 'depreciation' && v.meta['asset'] == id);
    assets.removeWhere((x) => x.id == id);
    _commit();
    return true;
  }

  /// خرید اموال و تجهیزات — [items] are new assets (cost = net price);
  /// [payLines] come from the settlement window.
  Voucher buyAssets({
    required DateTime date,
    int? number,
    String desc = '',
    String? personId,
    required List<Asset> items,
    List<VoucherLine> payLines = const [],
  }) {
    final total = items.fold<int>(0, (s, a) => s + a.cost);
    final d = desc.isEmpty ? 'خرید اموال و تجهیزات' : desc;
    final lines = <VoucherLine>[
      for (final a in items) VoucherLine(moeen: mAssets, desc: 'خرید ${a.name}', debit: a.cost),
      if (personId != null) VoucherLine(moeen: mDebtorsTrade, tafsiliId: personId, desc: d, credit: total),
      ...payLines,
    ];
    final v = Voucher(
      id: newId(),
      number: number ?? nextVoucherNumber(),
      fixedNumber: nextFixedNumber(),
      date: date,
      desc: d,
      lines: lines,
      kind: 'assetBuy',
      meta: {'assets': [for (final a in items) a.id], 'person': personId},
    );
    vouchers.add(v);
    _log('ثبت', '${v.kindLabel} ${v.desc}'.trim(), docDate: v.date, docNo: v.number);
    for (final a in items) {
      a
        ..buyVoucherId = v.id
        ..purchaseDate ??= date;
      if (a.code == 0) a.code = nextAssetCode();
      assets.add(a);
    }
    _commit();
    return v;
  }

  /// فروش اموال و تجهیزات — books the gain or loss against the book value.
  Voucher sellAssets({
    required DateTime date,
    int? number,
    String desc = '',
    String? personId,
    required List<(Asset, int)> sales,
    List<VoucherLine> payLines = const [],
  }) {
    final total = sales.fold<int>(0, (s, x) => s + x.$2);
    final d = desc.isEmpty ? 'فروش اموال و تجهیزات' : desc;
    final lines = <VoucherLine>[
      if (personId != null) VoucherLine(moeen: mDebtorsTrade, tafsiliId: personId, desc: d, debit: total),
    ];
    for (final (a, price) in sales) {
      lines.add(VoucherLine(moeen: mAssets, desc: 'فروش ${a.name}', credit: a.cost));
      if (a.depreciation > 0) lines.add(VoucherLine(moeen: mAccDepreciation, desc: 'استهلاک ${a.name}', debit: a.depreciation));
      final gain = price - a.bookValue;
      if (gain > 0) lines.add(VoucherLine(moeen: mOtherIncome, desc: 'سود فروش ${a.name}', credit: gain));
      if (gain < 0) lines.add(VoucherLine(moeen: mOtherExpense, desc: 'زیان فروش ${a.name}', debit: -gain));
    }
    lines.addAll(payLines);
    final v = Voucher(
      id: newId(),
      number: number ?? nextVoucherNumber(),
      fixedNumber: nextFixedNumber(),
      date: date,
      desc: d,
      lines: lines,
      kind: 'assetSell',
      meta: {'assets': [for (final x in sales) x.$1.id], 'person': personId},
    );
    vouchers.add(v);
    _log('ثبت', '${v.kindLabel} ${v.desc}'.trim(), docDate: v.date, docNo: v.number);
    for (final (a, price) in sales) {
      a
        ..sellVoucherId = v.id
        ..salePrice = price;
    }
    _commit();
    return v;
  }

  /// Weighted average purchase cost (net of line discounts).
  int avgCost(String productId) {
    final p = product(productId);
    var qty = 0.0;
    var cost = 0.0;
    if (p != null && p.openingQty > 0 && openingCost(p) > 0) {
      qty = p.openingQty;
      cost = p.openingQty * openingCost(p);
    }
    for (final inv in realInvoices) {
      if (inv.kind != InvoiceKind.purchase) continue;
      for (final l in inv.lines) {
        if (l.productId == productId && l.qty > 0) {
          qty += l.qty;
          cost += l.total;
        }
      }
    }
    // «تولید»: produced units at their production cost
    for (final pr in productions) {
      if (pr.productId == productId && pr.qty > 0) {
        qty += pr.qty;
        cost += pr.totalCost;
      }
    }
    // costs charged to the product by vouchers (e.g. freight in a composite expense)
    for (final v in vouchers) {
      if (v.isYearEnd) continue;
      for (final l in v.lines) {
        if (l.moeen == mStock && l.tafsiliId == productId) cost += l.debit - l.credit;
      }
    }
    if (qty <= 0) return product(productId)?.buyPrice ?? 0;
    return (cost / qty).round();
  }

  int stockValue() {
    var v = 0;
    for (final p in products) {
      final q = stock(p.id);
      if (q > 0) v += (q * avgCost(p.id)).round();
    }
    return v;
  }

  // ---------------------------------------------------------------- invoices

  int nextInvoiceNumber(InvoiceKind kind, {bool proforma = false}) {
    var n = 1000;
    for (final i in invoices) {
      if (i.kind == kind && i.proforma == proforma && i.number > n) n = i.number;
    }
    return n + 1;
  }

  /// Turns a pro-forma into a real sale invoice; returns the new invoice.
  Invoice convertProforma(Invoice pf) {
    final inv = Invoice(
      id: newId(),
      kind: InvoiceKind.sale,
      number: nextInvoiceNumber(InvoiceKind.sale),
      date: dateOnly(DateTime.now()),
      personId: pf.personId,
      lines: pf.lines.map((l) => InvoiceLine.fromJson(l.toJson())).toList(),
      discount: pf.discount,
      extra: pf.extra,
      note: pf.note.isEmpty ? 'از پیش‌فاکتور ${pf.number}' : '${pf.note} (پیش‌فاکتور ${pf.number})',
      info: {'fromProforma': '${pf.number}', if (pf.info['subsidyAcc'] != null) 'subsidyAcc': pf.info['subsidyAcc']!},
      marketers: pf.marketers,
    );
    invoices.removeWhere((i) => i.id == pf.id);
    saveInvoice(inv);
    return inv;
  }

  List<Invoice> get invoicesSorted => [...invoices]
    ..sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });

  /// Saves an invoice and regenerates its ledger entries.
  void saveInvoice(Invoice inv) {
    if (!inv.proforma) _touchDoc('inv:${inv.id}');
    _log(invoices.any((e) => e.id == inv.id) ? 'ویرایش' : 'ثبت', '${inv.proforma ? 'پیش‌فاکتور' : inv.kind.label} ${inv.number}',
        docDate: inv.date, docNo: inv.number);
    final i = invoices.indexWhere((e) => e.id == inv.id);
    if (i >= 0) {
      invoices[i] = inv;
    } else {
      invoices.add(inv);
    }
    txns.removeWhere((t) => t.invoiceId == inv.id);
    if (inv.proforma) {
      _commit();
      return;
    }
    final title = '${inv.kind.label} شماره ${inv.number}';
    txns.add(Txn(
      id: newId(),
      type: inv.kind.txnType,
      amount: inv.total,
      date: inv.date,
      personId: inv.personId,
      note: inv.note.isEmpty ? title : '$title — ${inv.note}',
      dueDate: inv.dueDate,
      invoiceId: inv.id,
      createdAt: inv.createdAt,
    ));
    // «سهم یارانه»: moved from the buyer to the subsidy account
    final oldSub = vouchers.where((v) => v.kind == 'subsidy' && v.meta['invoice'] == inv.id).firstOrNull;
    vouchers.removeWhere((v) => v.kind == 'subsidy' && v.meta['invoice'] == inv.id);
    final sub = inv.subsidyTotal;
    final subP = inv.subsidyPersonId;
    if (sub != 0 && subP != null && inv.personId != null && !inv.kind.buySide) {
      final ret = inv.kind == InvoiceKind.saleReturn;
      vouchers.add(Voucher(
        id: oldSub?.id ?? newId(),
        number: oldSub?.number ?? nextVoucherNumber(),
        fixedNumber: oldSub?.fixedNumber ?? nextFixedNumber(),
        date: inv.date,
        desc: 'سهم یارانه $title',
        kind: 'subsidy',
        meta: {'invoice': inv.id},
        lines: [
          VoucherLine(moeen: mDebtorsTrade, tafsiliId: subP, desc: 'سهم یارانه $title', debit: ret ? 0 : sub, credit: ret ? sub : 0),
          VoucherLine(moeen: mDebtorsTrade, tafsiliId: inv.personId, desc: 'سهم یارانه $title', debit: ret ? sub : 0, credit: ret ? 0 : sub),
        ],
      ));
    }
    if (inv.paid > 0 && inv.accountId != null) {
      txns.add(Txn(
        id: newId(),
        type: inv.kind.moneyIn ? TxnType.collect : TxnType.repay,
        amount: inv.paid,
        date: inv.date,
        accountId: inv.accountId,
        personId: inv.personId,
        note: 'تسویه $title',
        invoiceId: inv.id,
        createdAt: inv.createdAt + 1,
      ));
    }
    // هزینه حمل بعهده فروشنده — we pay the shipping of our own sale from a cash box / bank
    final ship = inv.shipBySeller;
    final shipAcc = account(inv.info['shipAcc']);
    if (ship > 0 && shipAcc != null && !inv.kind.buySide) {
      txns.add(Txn(
        id: newId(),
        type: TxnType.expense,
        amount: ship,
        date: inv.date,
        accountId: shipAcc.id,
        categoryId: shippingCategory().id,
        note: 'هزینه حمل بعهده فروشنده — $title',
        invoiceId: inv.id,
        createdAt: inv.createdAt + 2,
      ));
    }
    // remember last prices on products
    for (final l in inv.lines) {
      final p = product(l.productId);
      if (p == null || l.qty <= 0) continue;
      if (inv.kind == InvoiceKind.purchase) p.buyPrice = l.unitPrice;
      if (inv.kind == InvoiceKind.sale && p.sellPrice == 0) p.sellPrice = l.unitPrice;
    }
    _commit();
  }

  /// The expense category of seller-paid shipping («هزینه حمل»), created on first use.
  TxnCategory shippingCategory() {
    final c = categories.where((c) => c.kind == CategoryKind.expense && c.name == 'هزینه حمل').firstOrNull;
    if (c != null) return c;
    final n = TxnCategory(id: newId(), name: 'هزینه حمل', kind: CategoryKind.expense, color: 0xFF8D6E63);
    categories.add(n);
    return n;
  }

  /// «نحوه تسویه» of an invoice: amount per settlement method (cash, cheque, bank…).
  Map<String, int> settlementSummary(Invoice inv) {
    final out = <String, int>{};
    void add(String k, int v) {
      if (v != 0) out[k] = (out[k] ?? 0) + v;
    }

    for (final t in txns.where((t) => t.invoiceId == inv.id && (t.type == TxnType.collect || t.type == TxnType.repay))) {
      final a = account(t.accountId);
      add(a?.type == AccountType.cash ? (inv.kind.moneyIn ? 'دریافت نقدی' : 'پرداخت از صندوق') : (inv.kind.moneyIn ? 'دریافت حواله بانکی' : 'پرداخت بانکی'), t.amount);
    }
    for (final v in settlementsOf(inv.id)) {
      final pays = v.meta['pays'];
      if (pays is Map) {
        pays.forEach((k, x) => add('$k', (x as num).toInt()));
        continue;
      }
      // older settlements: group by ledger
      for (final l in v.lines) {
        if (l.tafsiliId != null && l.tafsiliId == inv.personId) continue;
        if (l.moeen == mDebtorsOther) continue;
        final v = (l.debit - l.credit).abs();
        final inn = inv.kind.moneyIn;
        switch (l.moeen) {
          case mCash || mPettyCash:
            add(inn ? 'دریافت نقدی' : 'پرداخت از صندوق', v);
          case mBank:
            add(inn ? 'واریز به بانک' : 'پرداخت بانکی', v);
          case mChequesAtCash || mChequesAtBank || mChequesPayable:
            add(inn ? 'دریافت چک' : 'صدور چک', v);
          case mSaleDiscount:
            add('تخفیف از فروش', v);
          case mPurchaseDiscount:
            add('تخفیف از خرید', v);
          default:
            add(findMoeen(l.moeen)?.name ?? l.moeen, v);
        }
      }
    }
    return out;
  }

  /// Settlement documents (تسویه) created for an invoice.
  List<Voucher> settlementsOf(String invoiceId) => vouchers.where((v) => v.kind == 'settle' && v.meta['invoice'] == invoiceId).toList();

  void removeInvoice(String id) {
    final inv = invoices.where((i) => i.id == id).firstOrNull;
    for (final o in wooOrders) {
      if (o.invoiceId == id) o.invoiceId = null;
    }
    for (final r in receptions) {
      if (r.invoiceId == id) r.invoiceId = null;
    }
    for (final d in settleDocs) {
      d.rows.removeWhere((r) => r.invoiceId == id);
    }
    settleDocs.removeWhere((d) => d.rows.isEmpty);
    offsets.removeWhere((o) => o.saleId == id || o.purchaseId == id);
    if (inv != null && !inv.proforma) {
      final who = person(inv.personId)?.name ?? 'متفرقه';
      _recycle('inv:$id', number: docMeta['inv:$id']?.number ?? inv.number, date: inv.date,
          desc: '${inv.kind.label} ${inv.number}  ${inv.lines.length} قلم کالا  $who', amount: inv.total, payload: {
        'doc': inv.toJson(),
        'vouchers': [for (final v in vouchers.where((v) => (v.kind == 'settle' || v.kind == 'subsidy') && v.meta['invoice'] == id)) v.toJson()],
        'txns': [for (final t in txns.where((t) => t.invoiceId == id)) t.toJson()],
      });
    }
    if (inv != null) _log('حذف', '${inv.kind.label} ${inv.number}', docDate: inv.date, docNo: inv.number);
    vouchers.removeWhere((v) => (v.kind == 'settle' || v.kind == 'subsidy') && v.meta['invoice'] == id);
    invoices.removeWhere((i) => i.id == id);
    docMeta.remove('inv:$id');
    txns.removeWhere((t) => t.invoiceId == id);
    _commit();
  }

  // ---------------------------------------------------------------- vouchers & opening

  List<Voucher> get vouchersSorted => [...vouchers]..sort((a, b) => a.number.compareTo(b.number));

  int nextVoucherNumber() {
    var n = vouchers.fold<int>(1, (n, v) => v.number >= n ? v.number + 1 : n);
    for (final e in docMeta.entries) {
      if (!e.key.startsWith('v:') && e.value.number >= n) n = e.value.number + 1;
    }
    return n;
  }

  int nextFixedNumber() {
    var n = vouchers.fold<int>(1, (n, v) => v.fixedNumber >= n ? v.fixedNumber + 1 : n);
    for (final e in docMeta.entries) {
      if (!e.key.startsWith('v:') && e.value.fixed >= n) n = e.value.fixed + 1;
    }
    return n;
  }

  // ---------------------------------------------------------------- document register

  /// Keys of every document shown in «لیست اسناد».
  Iterable<String> get docKeys sync* {
    for (final v in vouchers) {
      yield 'v:${v.id}';
    }
    for (final i in realInvoices) {
      yield 'inv:${i.id}';
    }
    for (final t in txns) {
      if (t.invoiceId == null) yield 'txn:${t.id}';
    }
  }

  DocMeta meta(String key) => docMeta.putIfAbsent(key, () => DocMeta(userId: currentUserId));

  int? docNumberOf(String key) {
    if (key.startsWith('v:')) return vouchers.where((v) => 'v:${v.id}' == key).firstOrNull?.number;
    return docMeta[key]?.number;
  }

  int? docFixedOf(String key) {
    if (key.startsWith('v:')) return vouchers.where((v) => 'v:${v.id}' == key).firstOrNull?.fixedNumber;
    return docMeta[key]?.fixed;
  }

  DateTime? docDateOf(String key) {
    final id = key.substring(key.indexOf(':') + 1);
    if (key.startsWith('v:')) return vouchers.where((v) => v.id == id).firstOrNull?.date;
    if (key.startsWith('inv:')) return invoices.where((v) => v.id == id).firstOrNull?.date;
    return txn(id)?.date;
  }

  int _createdOf(String key) {
    final id = key.substring(key.indexOf(':') + 1);
    if (key.startsWith('v:')) return vouchers.where((v) => v.id == id).firstOrNull?.createdAt ?? 0;
    if (key.startsWith('inv:')) return invoices.where((v) => v.id == id).firstOrNull?.createdAt ?? 0;
    return txn(id)?.createdAt ?? 0;
  }

  /// Gives a document number to a new invoice / operation and stamps the editor.
  void _touchDoc(String key) {
    final m = meta(key);
    if (!key.startsWith('v:') && m.number == 0) {
      m
        ..number = nextVoucherNumber()
        ..fixed = nextFixedNumber();
    }
    m
      ..modifiedAt = DateTime.now().millisecondsSinceEpoch
      ..userId = m.userId.isEmpty ? currentUserId : m.userId;
  }

  void _ensureDocNumbers() {
    final missing = docKeys.where((k) => !k.startsWith('v:') && (docMeta[k]?.number ?? 0) == 0).toList()
      ..sort((a, b) {
        final c = (docDateOf(a) ?? DateTime(2000)).compareTo(docDateOf(b) ?? DateTime(2000));
        return c != 0 ? c : _createdOf(a).compareTo(_createdOf(b));
      });
    for (final k in missing) {
      final m = meta(k);
      m
        ..number = nextVoucherNumber()
        ..fixed = nextFixedNumber()
        ..modifiedAt = _createdOf(k);
    }
  }

  void _setDocNumber(String key, int n) {
    if (key.startsWith('v:')) {
      final v = vouchers.where((v) => 'v:${v.id}' == key).firstOrNull;
      if (v != null) v.number = n;
    } else {
      meta(key).number = n;
    }
  }

  List<String> get _docsByNumber => docKeys.toList()..sort((a, b) => (docNumberOf(a) ?? 0).compareTo(docNumberOf(b) ?? 0));

  /// مرتب سازی — renumbers all documents by date.
  void sortDocuments() {
    final keys = docKeys.toList()
      ..sort((a, b) {
        final c = (docDateOf(a) ?? DateTime(2000)).compareTo(docDateOf(b) ?? DateTime(2000));
        if (c != 0) return c;
        final n = (docNumberOf(a) ?? 0).compareTo(docNumberOf(b) ?? 0);
        return n != 0 ? n : _createdOf(a).compareTo(_createdOf(b));
      });
    for (var i = 0; i < keys.length; i++) {
      _setDocNumber(keys[i], i + 1);
    }
    _commit();
  }

  /// برش و چسباندن — moves [cut] right after [after] and renumbers.
  void moveDocument(String cut, String after) {
    if (cut == after) return;
    final keys = _docsByNumber..remove(cut);
    final i = keys.indexOf(after);
    keys.insert(i < 0 ? keys.length : i + 1, cut);
    for (var j = 0; j < keys.length; j++) {
      _setDocNumber(keys[j], j + 1);
    }
    _commit();
  }

  void updateDocMeta(String key, void Function(DocMeta m) fn) {
    fn(meta(key));
    _commit();
  }

  bool isLocked(String key) => docMeta[key]?.locked ?? false;

  void saveVoucher(Voucher v) {
    _touchDoc('v:${v.id}');
    final i = vouchers.indexWhere((e) => e.id == v.id);
    _log(i >= 0 ? 'ویرایش' : 'ثبت', '${v.kindLabel} ${v.desc}'.trim(), docDate: v.date, docNo: v.number);
    if (i >= 0) {
      vouchers[i] = v;
    } else {
      vouchers.add(v);
    }
    _commit();
  }

  // ---------------------------------------------------------------- print templates

  /// Templates of a print type; a built-in «طرح ۱» is used when none exist.
  List<PrintTemplate> templatesOf(PrintDocType t) {
    final list = printTemplates.where((x) => x.type == t).toList();
    if (list.isEmpty) list.add(builtinTemplate(t));
    return list;
  }

  PrintTemplate builtinTemplate(PrintDocType t) => PrintTemplate(
        id: 'builtin-${t.name}',
        type: t,
        name: 'طرح ۱',
        paper: t == PrintDocType.barcode ? 'A4' : 'A5',
        columns: t == PrintDocType.warehouse ? ['idx', 'code', 'name', 'qty', 'unit'] : null,
      );

  PrintTemplate defaultTemplate(PrintDocType t) {
    final list = templatesOf(t);
    return list.where((x) => x.id == defaultTemplates[t.name]).firstOrNull ?? list.first;
  }

  void saveTemplate(PrintTemplate t) {
    final i = printTemplates.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      printTemplates[i] = t;
    } else {
      printTemplates.add(t);
    }
    _commit();
  }

  void removeTemplate(String id) {
    printTemplates.removeWhere((x) => x.id == id);
    defaultTemplates.removeWhere((_, v) => v == id);
    _commit();
  }

  void setDefaultTemplate(PrintTemplate t) {
    defaultTemplates[t.type.name] = t.id;
    _commit();
  }

  // ---------------------------------------------------------------- report layouts

  /// Layouts of a print type; the built-in Sakan-like layout is used when none were saved.
  String _layoutKey(PrintDocType t, String variant) => variant.isEmpty ? t.name : '${t.name}:$variant';

  /// Layouts of [t]; invoices keep their own per document ([variant] = sale, purchase, proforma…).
  List<ReportLayout> layoutsOf(PrintDocType t, {String variant = ''}) {
    final v = hasVariants(t) ? variant : '';
    final list = reportLayouts.where((x) => x.type == t && x.variant == v).toList();
    if (!list.any((x) => x.id == builtinLayoutId(t, v))) list.insert(0, defaultLayoutFor(t, v));
    return list;
  }

  ReportLayout defaultLayout(PrintDocType t, {String variant = ''}) {
    final v = hasVariants(t) ? variant : '';
    final list = layoutsOf(t, variant: v);
    return list.where((x) => x.id == defaultLayouts[_layoutKey(t, v)]).firstOrNull ?? list.first;
  }

  /// Layouts saved before they were kept per document belonged to the sale invoice.
  void _migrateLayouts() {
    for (final l in reportLayouts) {
      if (hasVariants(l.type) && l.variant.isEmpty) {
        if (l.id == builtinLayoutId(l.type, '')) l.id = builtinLayoutId(l.type, 'sale');
        l.variant = 'sale';
      }
    }
    for (final t in PrintDocType.values.where(hasVariants)) {
      final d = defaultLayouts.remove(t.name);
      if (d != null) defaultLayouts['${t.name}:sale'] = d == builtinLayoutId(t, '') ? builtinLayoutId(t, 'sale') : d;
    }
  }

  void saveLayout(ReportLayout l) {
    final i = reportLayouts.indexWhere((x) => x.id == l.id);
    if (i >= 0) {
      reportLayouts[i] = l;
    } else {
      reportLayouts.add(l);
    }
    _commit();
  }

  void removeLayout(String id) {
    reportLayouts.removeWhere((x) => x.id == id);
    defaultLayouts.removeWhere((_, v) => v == id);
    _commit();
  }

  void setDefaultLayout(ReportLayout l) {
    defaultLayouts[_layoutKey(l.type, l.variant)] = l.id;
    _commit();
  }

  // ---------------------------------------------------------------- year end

  /// The latest closing document whose balances were not transferred yet.
  Voucher? get pendingClosing {
    final list = vouchers.where((v) => v.kind == 'closing' && v.meta['reopen'] == null).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.firstOrNull;
  }

  /// انتقال تراز اختتامیه به تراز افتتاحیه — re-opens the balance-sheet
  /// accounts of [closing] (net profit goes to «سود و زیان انباشته»).
  Voucher transferClosing(Voucher closing, {required DateTime date, int? number, String desc = ''}) {
    final lines = <VoucherLine>[];
    var profit = 0;
    for (final l in closing.lines) {
      final m = findMoeen(l.moeen);
      if (m == null) continue;
      if (m.side == Side.income || m.side == Side.expense) {
        profit += l.debit - l.credit;
      } else {
        lines.add(VoucherLine(moeen: l.moeen, tafsiliId: l.tafsiliId, desc: 'انتقال از تراز اختتامیه', debit: l.credit, credit: l.debit));
      }
    }
    if (profit > 0) lines.add(VoucherLine(moeen: mRetained, desc: 'سود سال قبل', credit: profit));
    if (profit < 0) lines.add(VoucherLine(moeen: mRetained, desc: 'زیان سال قبل', debit: -profit));
    final v = Voucher(
      id: newId(),
      number: number ?? nextVoucherNumber(),
      fixedNumber: nextFixedNumber(),
      date: date,
      desc: desc.isEmpty ? 'انتقال تراز اختتامیه به تراز افتتاحیه' : desc,
      lines: lines,
      kind: 'reopen',
      meta: {'closing': closing.id},
    );
    closing.meta['reopen'] = v.id;
    vouchers.add(v);
    _log('ثبت', '${v.kindLabel} ${v.desc}'.trim(), docDate: v.date, docNo: v.number);
    _commit();
    return v;
  }

  void removeVoucher(String id, {bool recycleIt = true}) {
    final v = vouchers.where((x) => x.id == id).firstOrNull;
    if (v != null && recycleIt) {
      _recycle('v:$id', number: v.number, date: v.date, desc: '${v.kindLabel} ${v.desc}'.trim(), amount: v.totalDebit, payload: {'doc': v.toJson()});
    }
    if (v != null) _log('حذف', '${v.kindLabel} ${v.desc}'.trim(), docDate: v.date, docNo: v.number);
    if (v != null && v.kind == 'assetBuy') {
      final ids = {for (final a in assets.where((a) => a.buyVoucherId == id)) a.id};
      assets.removeWhere((a) => ids.contains(a.id));
      vouchers.removeWhere((x) => x.kind == 'depreciation' && ids.contains(x.meta['asset']));
    }
    if (v != null && v.kind == 'assetSell') {
      for (final a in assets.where((a) => a.sellVoucherId == id)) {
        a
          ..sellVoucherId = null
          ..salePrice = 0;
      }
    }
    if (v != null && v.kind == 'reopen') {
      for (final c in vouchers.where((c) => c.meta['reopen'] == id)) {
        c.meta.remove('reopen');
      }
    }
    if (v != null && v.kind == 'chequeMove') {
      // put moved cheques back in the source box
      final from = v.meta['from'] as String?;
      for (final cid in (v.meta['cheques'] as List? ?? const [])) {
        cheque('$cid')?.holderId = from;
      }
    }
    vouchers.removeWhere((v) => v.id == id);
    docMeta.remove('v:$id');
    _commit();
  }

  // ---------------------------------------------------------------- cheque boxes & books

  /// Cash box holding a received cheque (defaults to the first cash account).
  String? holderOf(Cheque c) {
    if (c.holderId != null && account(c.holderId) != null) return c.holderId;
    for (final a in accounts) {
      if (a.type == AccountType.cash) return a.id;
    }
    return null;
  }

  /// Received cheques that are physically in [boxId].
  List<Cheque> chequesInBox(String boxId) => cheques
      .where((c) => c.direction == ChequeDirection.received && c.status == ChequeStatus.pending && holderOf(c) == boxId)
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// Saves a "جا به جایی چک" document and moves the cheques.
  Voucher moveCheques({
    Voucher? edit,
    required String fromId,
    required String toId,
    required List<String> chequeIds,
    required DateTime date,
    int? number,
    String desc = '',
  }) {
    if (edit != null) removeVoucher(edit.id, recycleIt: false);
    for (final id in chequeIds) {
      cheque(id)?.holderId = toId;
    }
    final v = Voucher(
      id: edit?.id ?? newId(),
      number: number ?? nextVoucherNumber(),
      fixedNumber: edit?.fixedNumber ?? nextFixedNumber(),
      date: date,
      desc: desc.isEmpty ? 'جا به جایی ${chequeIds.length} چک از ${account(fromId)?.name ?? ''} به ${account(toId)?.name ?? ''}' : desc,
      kind: 'chequeMove',
      meta: {'from': fromId, 'to': toId, 'cheques': chequeIds},
    );
    vouchers.add(v);
    _log('ثبت', '${v.kindLabel} ${v.desc}'.trim(), docDate: v.date, docNo: v.number);
    _commit();
    return v;
  }

  List<ChequeLeaf> leavesOf(String accountId) {
    final out = <ChequeLeaf>[];
    for (final b in chequeBooks.where((b) => b.accountId == accountId)) {
      for (final n in b.numbers) {
        final serial = b.serialOf(n);
        final c = cheques
            .where((c) => c.direction == ChequeDirection.issued && c.serial == serial && (c.bankAccountId == null || c.bankAccountId == accountId))
            .firstOrNull;
        final st = c != null ? LeafState.used : (b.voided.contains(n) ? LeafState.voided : LeafState.free);
        out.add(ChequeLeaf(b, n, st, c));
      }
    }
    return out;
  }

  List<String> freeSerials(String accountId) =>
      leavesOf(accountId).where((l) => l.state == LeafState.free).map((l) => l.serial).toList();

  void saveChequeBook(ChequeBook b) {
    final i = chequeBooks.indexWhere((x) => x.id == b.id);
    if (i >= 0) {
      chequeBooks[i] = b;
    } else {
      chequeBooks.add(b);
    }
    _commit();
  }

  /// Deletes a cheque book when none of its leaves has been used.
  bool removeChequeBook(String id) {
    final b = chequeBooks.where((x) => x.id == id).firstOrNull;
    if (b == null) return false;
    if (leavesOf(b.accountId).any((l) => l.book.id == id && l.state == LeafState.used)) return false;
    chequeBooks.removeWhere((x) => x.id == id);
    _commit();
    return true;
  }

  void setLeafVoid(ChequeBook b, int number, bool voided, {String note = ''}) {
    if (voided) {
      b.voided.add(number);
      if (note.isNotEmpty) b.notes['$number'] = note;
    } else {
      b.voided.remove(number);
      b.notes.remove('$number');
    }
    _commit();
  }

  /// Name of the detail (تفصیلی) a voucher line points to.
  String tafsiliName(VoucherLine l) {
    final m = findMoeen(l.moeen);
    if (m == null || l.tafsiliId == null) return '';
    return switch (m.kind) {
      TafsiliKind.cash || TafsiliKind.bank => account(l.tafsiliId)?.name ?? '',
      TafsiliKind.person => person(l.tafsiliId)?.name ?? '',
      TafsiliKind.product => product(l.tafsiliId)?.name ?? '',
      TafsiliKind.incomeCat || TafsiliKind.expenseCat => category(l.tafsiliId)?.name ?? '',
      TafsiliKind.none => '',
    };
  }

  /// Balance of a free (non-entity) ledger: opening + voucher lines, on its natural side.
  int ledgerBalance(String moeenCode) {
    final m = findMoeen(moeenCode);
    if (m == null) return 0;
    var b = settings.openingOther[moeenCode] ?? 0;
    for (final v in vouchers) {
      for (final l in v.lines) {
        if (l.moeen != moeenCode || (m.hasEntity && l.tafsiliId != null)) continue;
        b += m.debitNature ? l.debit - l.credit : l.credit - l.debit;
      }
    }
    return b;
  }

  /// Saves the opening voucher (سند افتتاحیه).
  void applyOpening({
    required DateTime date,
    required Map<String, int> accountOpenings,
    required Map<String, int> personOpenings,
    required Map<String, double> productQty,
    required Map<String, int> productCost,
    required Map<String, int> other,
    bool updateBuyPrice = false,
  }) {
    settings.openingDate = date;
    accountOpenings.forEach((id, v) => account(id)?.opening = v);
    personOpenings.forEach((id, v) => person(id)?.opening = v);
    productQty.forEach((id, q) => product(id)?.openingQty = q);
    productCost.forEach((id, c) {
      final p = product(id);
      if (p == null) return;
      p.openingCost = c;
      if (updateBuyPrice && c > 0) p.buyPrice = c;
    });
    settings.openingOther
      ..clear()
      ..addAll(Map.of(other)..removeWhere((k, v) => v == 0));
    _commit();
  }

  /// Opening cost per unit of a product (used for opening stock value).
  int openingCost(Product p) => p.openingCost > 0 ? p.openingCost : p.buyPrice;

  // ---------------------------------------------------------------- کارت هواداری

  /// Sales (net of returns) of the card owner since the card was issued.
  int loyaltyPurchases(LoyaltyCard c) {
    var t = 0;
    for (final i in realInvoices.where((i) => i.personId == c.personId && !i.date.isBefore(dateOnly(c.issued)))) {
      if (i.kind == InvoiceKind.sale) t += i.total;
      if (i.kind == InvoiceKind.saleReturn) t -= i.total;
    }
    return t;
  }

  int loyaltyEarned(LoyaltyCard c) => loyalty.amountPerPoint <= 0 ? 0 : loyaltyPurchases(c) ~/ loyalty.amountPerPoint;
  int loyaltyUsed(LoyaltyCard c) => redemptions.where((r) => r.card == c.number).fold(0, (a, r) => a + r.points);
  int loyaltyPoints(LoyaltyCard c) => loyaltyEarned(c) - loyaltyUsed(c);

  /// Uses [g] on card [c]; false when the points are not enough.
  bool redeem(LoyaltyCard c, GiftRow g) {
    if (loyaltyPoints(c) < g.points) return false;
    redemptions.add(Redemption(id: newId(), card: c.number, date: DateTime.now(), points: g.points, title: g.title, amount: g.amount));
    _commit();
    return true;
  }

  // ---------------------------------------------------------------- تسویه فاکتور

  int nextSettleNumber() => settleDocs.fold<int>(1, (n, d) => d.number >= n ? d.number + 1 : n);

  /// Paid part of an invoice outside settlement docs: paid at issue, its
  /// «تسویه» voucher and «تسویه فاکتور به فاکتور» links.
  int invoiceDirectPaid(Invoice inv) {
    var t = inv.paid;
    for (final v in vouchers.where((v) => v.kind == 'settle' && v.meta['invoice'] == inv.id)) {
      final pays = v.meta['pays'];
      if (pays is Map) t += pays.values.fold<int>(0, (a, x) => a + (x is num ? x.toInt() : 0));
    }
    t += offsets.where((o) => o.saleId == inv.id || o.purchaseId == inv.id).fold<int>(0, (a, o) => a + o.amount);
    return t;
  }

  /// «مبلغ پرداخت شده فاکتور» (all settlement docs except [excludeDoc]).
  int invoicePaidTotal(Invoice inv, {String? excludeDoc}) =>
      invoiceDirectPaid(inv) +
      settleDocs.where((d) => d.id != excludeDoc).expand((d) => d.rows).where((r) => r.invoiceId == inv.id).fold<int>(0, (a, r) => a + r.amount);

  int invoiceUnsettled(Invoice inv, {String? excludeDoc}) => inv.total - invoicePaidTotal(inv, excludeDoc: excludeDoc);

  /// «لیست سندهای تسویه» of an invoice: (doc, row, remain before, remain after).
  List<(SettleDoc, SettleRow, int, int)> settleHistory(Invoice inv) {
    var remain = inv.total - invoiceDirectPaid(inv);
    final out = <(SettleDoc, SettleRow, int, int)>[];
    final docs = settleDocs.where((d) => d.rows.any((r) => r.invoiceId == inv.id)).toList()..sort((a, b) => a.number.compareTo(b.number));
    for (final d in docs) {
      for (final r in d.rows.where((r) => r.invoiceId == inv.id)) {
        out.add((d, r, remain, remain - r.amount));
        remain -= r.amount;
      }
    }
    return out;
  }

  /// Money of the person not yet allocated to invoices (for automatic allocation).
  int unallocatedPayments(String personId, {bool sales = true}) {
    final kinds = sales ? {InvoiceKind.sale} : {InvoiceKind.purchase};
    final invs = realInvoices.where((i) => i.personId == personId && kinds.contains(i.kind));
    final owed = invs.fold<int>(0, (a, i) => a + i.total);
    final settled = invs.fold<int>(0, (a, i) => a + invoicePaidTotal(i));
    final bal = personBalance(personId);
    // balance = what is still owed (sales) or owed to them (purchases); what the
    // invoices still show as open beyond that has been paid but not allocated
    final open = owed - settled;
    final free = sales ? open - bal : open + bal;
    return free < 0 ? 0 : free;
  }

  void saveSettleDoc(SettleDoc d) {
    d.rows.removeWhere((r) => r.amount == 0);
    settleDocs.removeWhere((x) => x.id == d.id);
    if (d.rows.isNotEmpty) settleDocs.add(d);
    _commit();
  }

  void removeSettleDoc(String id) {
    settleDocs.removeWhere((d) => d.id == id);
    _commit();
  }

  // ---------------------------------------------------------------- قرعه کشی

  /// Codes of a campaign: (code, invoice). One code per [minAmount] of each qualifying sale.
  List<(String, Invoice)> drawCodes(DrawCampaign d) {
    final out = <(String, Invoice)>[];
    final list = realInvoices.where((i) => i.kind == InvoiceKind.sale && !i.date.isBefore(dateOnly(d.from)) && !i.date.isAfter(d.to)).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    for (final i in list) {
      if (i.total < d.minAmount || i.total <= 0) continue;
      final n = d.minAmount <= 0 ? 1 : (i.total ~/ d.minAmount).clamp(1, 100);
      for (var k = 1; k <= n; k++) {
        out.add(('${d.prefix}${i.number}${n > 1 ? '-$k' : ''}', i));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- پیام های داخلی

  List<InternalMessage> inbox(String userId) => messages.where((m) => m.to == userId || (m.to == '*' && m.from != userId)).toList()..sort((a, b) => b.date.compareTo(a.date));
  int unreadFor(String userId) => inbox(userId).where((m) => !m.readBy.contains(userId)).length;

  void sendMessage(String to, String text) {
    messages.add(InternalMessage(id: newId(), from: currentUser.id, to: to, date: DateTime.now(), text: text));
    if (messages.length > 2000) messages.removeAt(0);
    _commit();
  }

  void markRead(String userId) {
    for (final m in inbox(userId)) {
      m.readBy.add(userId);
    }
    _commit();
  }

  // ---------------------------------------------------------------- تماس ها

  static String _tail(String n) {
    final d = normalizeDigits(n).replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  /// The person (or contact) a phone number belongs to.
  (Person?, Contact?) whoCalls(String number) {
    final t = _tail(number);
    if (t.length < 5) return (null, null);
    final p = people.where((p) => p.phone.split(RegExp(r'[,،/;]')).any((x) => _tail(x) == t)).firstOrNull;
    if (p != null) return (p, null);
    return (null, contacts.where((c) => _tail(c.phone) == t).firstOrNull);
  }

  /// «تماس جدید»: records an incoming call and returns who it is.
  CallLog logCall(String number, {String note = ''}) {
    final c = CallLog(number: normalizeDigits(number.trim()), date: DateTime.now(), personId: whoCalls(number).$1?.id, note: note);
    calls.insert(0, c);
    if (calls.length > 500) calls.removeRange(500, calls.length);
    _commit();
    return c;
  }

  // ---------------------------------------------------------------- پاکسازی

  /// «حذف دفاتر اشخاص بدون تراکنش» / «حذف کالاهای بدون تراکنش».
  List<Person> unusedPeople() => people.where((p) => !personInUse(p.id) && !invoices.any((i) => i.personId == p.id) && !employees.any((e) => e.personId == p.id)).toList();
  List<Product> unusedProducts() => products.where((p) => !productInUse(p.id) && p.openingQty == 0 && !formulas.any((f) => f.productId == p.id || f.lines.any((l) => l.productId == p.id))).toList();

  int removeUnused({bool persons = false, bool items = false}) {
    var n = 0;
    if (persons) {
      final ids = {for (final p in unusedPeople()) p.id};
      n += ids.length;
      people.removeWhere((p) => ids.contains(p.id));
    }
    if (items) {
      final ids = {for (final p in unusedProducts()) p.id};
      n += ids.length;
      products.removeWhere((p) => ids.contains(p.id));
    }
    _commit();
    return n;
  }

  // ---------------------------------------------------------------- سربار

  /// «سرشکن انحراف جذب سربار»: absorbed overhead (credits on 2050) against the
  /// actual overhead on [actualLedger] in the range; the voucher closes both
  /// and posts the difference to 5030.
  (int, int) overheadVariance(DateTime from, DateTime to, {String actualLedger = '1170'}) {
    var absorbed = 0, actual = 0;
    for (final p in buildJournal(this)) {
      if (p.date.isBefore(from) || p.date.isAfter(to)) continue;
      if (p.moeen == '2050') absorbed += p.credit - p.debit;
      if (p.moeen == actualLedger) actual += p.debit - p.credit;
    }
    return (absorbed, actual);
  }

  Voucher? postOverheadVariance(DateTime from, DateTime to, {String actualLedger = '1170'}) {
    final (absorbed, actual) = overheadVariance(from, to, actualLedger: actualLedger);
    if (absorbed == 0 && actual == 0) return null;
    const desc = 'سرشکن انحراف جذب سربار';
    final diff = actual - absorbed; // + : under-absorbed (expense)
    final v = Voucher(
      id: newId(),
      number: nextVoucherNumber(),
      fixedNumber: nextFixedNumber(),
      date: to,
      desc: desc,
      kind: 'overheadVariance',
      lines: [
        if (absorbed != 0) VoucherLine(moeen: '2050', desc: desc, debit: absorbed > 0 ? absorbed : 0, credit: absorbed < 0 ? -absorbed : 0),
        if (actual != 0) VoucherLine(moeen: actualLedger, desc: desc, debit: actual < 0 ? -actual : 0, credit: actual > 0 ? actual : 0),
        if (diff != 0) VoucherLine(moeen: '5030', desc: desc, debit: diff > 0 ? diff : 0, credit: diff < 0 ? -diff : 0),
      ],
    );
    saveVoucher(v);
    return v;
  }

  // ---------------------------------------------------------------- مراکز هزینه

  int nextCostCenterCode() => costCenters.fold<int>(1, (n, c) => c.code >= n ? c.code + 1 : n);

  /// Rows charged to cost centers: (center id, date, title, debit, credit).
  /// Expense transactions are debits, income transactions credits; voucher
  /// rows keep their own side.
  List<(String, DateTime, String, int, int)> costCenterRows({DateTime? from, DateTime? to}) {
    bool inRange(DateTime d) => (from == null || !d.isBefore(from)) && (to == null || !d.isAfter(to));
    final out = <(String, DateTime, String, int, int)>[];
    for (final t in txns) {
      final c = t.costCenterId;
      if (c == null || !inRange(t.date)) continue;
      final title = '${t.type.label}${category(t.categoryId) == null ? '' : ' — ${category(t.categoryId)!.name}'}${t.note.isEmpty ? '' : ' — ${t.note}'}';
      if (t.type == TxnType.income) {
        out.add((c, t.date, title, 0, t.amount));
      } else {
        out.add((c, t.date, title, t.amount, 0));
      }
    }
    for (final v in vouchers) {
      if (!inRange(v.date)) continue;
      for (final l in v.lines.where((l) => l.costCenterId != null)) {
        out.add((l.costCenterId!, v.date, 'سند ${v.number} — ${findMoeen(l.moeen)?.name ?? l.moeen}${l.desc.isEmpty ? '' : ' — ${l.desc}'}', l.debit, l.credit));
      }
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  // ---------------------------------------------------------------- دفترچه اقساط

  void saveInstallmentPlan(InstallmentPlan p) {
    final i = installmentPlans.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      installmentPlans[i] = p;
    } else {
      installmentPlans.add(p);
    }
    _commit();
  }

  void removeInstallmentPlan(String id) {
    installmentPlans.removeWhere((p) => p.id == id);
    _commit();
  }

  // ---------------------------------------------------------------- خرید بالانس

  int nextBalanceNumber(bool isReturn) => balanceDeals.where((d) => d.isReturn == isReturn).fold<int>(1, (n, d) => d.number >= n ? d.number + 1 : n);

  /// Saves a deal and (re)writes its voucher: Dr buyer / Cr seller / Cr margin.
  void saveBalanceDeal(BalanceDeal d) {
    final old = vouchers.where((v) => v.id == d.voucherId).firstOrNull;
    vouchers.removeWhere((v) => v.id == d.voucherId);
    final desc = '${d.label} ${d.number}${d.note.isEmpty ? '' : ' — ${d.note}'}';
    final sign = d.isReturn ? -1 : 1;
    final lines = <VoucherLine>[];
    void add(String m, String? t, int amount) {
      if (amount == 0) return;
      lines.add(VoucherLine(moeen: m, tafsiliId: t, desc: desc, debit: amount > 0 ? amount : 0, credit: amount < 0 ? -amount : 0));
    }

    add(mDebtorsTrade, d.buyerId, sign * d.sellTotal);
    add(mDebtorsTrade, d.sellerId, -sign * d.buyTotal);
    add(d.incomeAcc, null, -sign * d.margin);
    final v = Voucher(
      id: old?.id ?? newId(),
      number: old?.number ?? nextVoucherNumber(),
      fixedNumber: old?.fixedNumber ?? nextFixedNumber(),
      date: d.date,
      desc: desc,
      kind: 'balance',
      meta: {'deal': d.id},
      lines: lines,
    );
    vouchers.add(v);
    d.voucherId = v.id;
    final i = balanceDeals.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      balanceDeals[i] = d;
    } else {
      balanceDeals.add(d);
      _log('ثبت', desc, docDate: d.date);
    }
    _commit();
  }

  void removeBalanceDeal(String id) {
    final d = balanceDeals.where((x) => x.id == id).firstOrNull;
    if (d == null) return;
    vouchers.removeWhere((v) => v.id == d.voucherId);
    balanceDeals.remove(d);
    _commit();
  }

  // ---------------------------------------------------------------- رستوران

  int nextTableNumber() => restTables.fold<int>(1, (n, t) => t.number >= n ? t.number + 1 : n);

  RestTab? tabOfTable(String tableId) => restTabs.where((t) => t.tableId == tableId).firstOrNull;

  void saveTab(RestTab t) {
    if (!restTabs.any((x) => x.id == t.id)) restTabs.add(t);
    restTabs.removeWhere((x) => x.lines.isEmpty && x.id != t.id && x.tableId == null);
    _commit();
  }

  void dropTab(String id) {
    restTabs.removeWhere((t) => t.id == id);
    _commit();
  }

  /// Rows not yet sent to the kitchen; marks them sent.
  List<(TabLine, double)> takeKitchenRows(RestTab t) {
    final out = <(TabLine, double)>[];
    for (final l in t.lines) {
      final d = l.qty - l.sent;
      if (d.abs() > 1e-9) out.add((l, d));
      l.sent = l.qty;
    }
    _commit();
    return out;
  }

  /// «تسویه»: turns an open order into a sale invoice (consuming recipe
  /// ingredients when «ترکیب و مونتاژ رستورانی» is on) and closes it.
  Invoice settleTab(RestTab t, {String? accountId, int discount = 0, bool paid = true}) {
    final table = restTables.where((x) => x.id == t.tableId).firstOrNull;
    final service = (t.total * restConfig.servicePct / 100).round();
    final fee = t.mode == TabMode.delivery ? restConfig.deliveryFee : 0;
    final inv = Invoice(
      id: newId(),
      kind: InvoiceKind.sale,
      number: nextInvoiceNumber(InvoiceKind.sale),
      date: DateTime.now(),
      // «تسویه پیک»: an unpaid delivery is owed by the courier until settled
      personId: t.personId ?? (!paid && t.mode == TabMode.delivery ? t.courierId : null),
      lines: [for (final l in t.lines.where((l) => l.qty > 0)) InvoiceLine(productId: l.productId, qty: l.qty, unitPrice: l.price)],
      discount: discount,
      extra: service + fee,
      accountId: paid ? (accountId ?? restConfig.accountId) : null,
      note: [t.mode == TabMode.dineIn ? (table?.title ?? '') : t.mode.label, if (t.note.isNotEmpty) t.note].where((x) => x.isNotEmpty).join(' — '),
      info: {
        'restaurant': t.mode.name,
        if (table != null) 'desk': '${table.number}',
        if (t.courierId != null) 'courier': t.courierId!,
      },
    );
    inv.paid = inv.accountId == null ? 0 : inv.total;
    if (restConfig.autoAssemble) {
      for (final l in inv.lines) {
        final f = formulas.where((x) => x.productId == l.productId).firstOrNull;
        if (f == null) continue;
        saveProduction(Production(
          id: newId(),
          number: nextProductionNumber(),
          date: inv.date,
          productId: f.productId,
          qty: l.qty,
          formulaId: f.id,
          hallId: f.hallId,
          lines: f.scaled(l.qty),
          overhead: f.overheadFor(l.qty),
          note: 'مونتاژ رستورانی فاکتور ${inv.number}',
        ));
      }
    }
    saveInvoice(inv);
    restTabs.removeWhere((x) => x.id == t.id);
    _commit();
    return inv;
  }

  // ---------------------------------------------------------------- گارانتی و پذیرش

  int nextWarrantyCode() => warranties.fold<int>(1, (n, w) => w.code >= n ? w.code + 1 : n);
  int nextReceptionNumber() => receptions.fold<int>(1, (n, r) => r.number >= n ? r.number + 1 : n);

  /// Warranty by code or serial (current or original).
  Warranty? findWarranty(String q) {
    final t = q.trim();
    if (t.isEmpty) return null;
    return warranties.where((w) => '${w.code}' == t || w.serial == t || w.currentSerial == t).firstOrNull;
  }

  void saveWarranty(Warranty w) {
    final i = warranties.indexWhere((x) => x.id == w.id);
    if (i >= 0) {
      warranties[i] = w;
    } else {
      warranties.add(w);
    }
    _commit();
  }

  void saveReception(Reception r) {
    final i = receptions.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      receptions[i] = r;
    } else {
      if (r.user.isEmpty) r.user = currentUser.name;
      receptions.add(r);
      _log('ثبت', 'پذیرش ${r.number}', docDate: r.date);
    }
    _commit();
  }

  /// «صدور فاکتور» of a repair: a service sale with the repair cost.
  Invoice receptionInvoice(Reception r) {
    final old = invoices.where((i) => i.id == r.invoiceId).firstOrNull;
    final inv = old ??
        Invoice(id: newId(), kind: InvoiceKind.sale, number: nextInvoiceNumber(InvoiceKind.sale), date: DateTime.now(), personId: r.personId, info: {'reception': '${r.number}'});
    inv.personId = r.personId;
    inv.lines = [
      InvoiceLine(title: 'تعمیر ${r.productName}${r.serial.isEmpty ? '' : ' سریال ${r.serial}'} — پذیرش ${r.number}', qty: 1, unitPrice: r.cost),
    ];
    inv.note = r.repairNote;
    r.invoiceId = inv.id;
    saveInvoice(inv);
    return inv;
  }

  // ---------------------------------------------------------------- اسناد انتظامی

  int nextGuaranteeNumber() => guarantees.fold<int>(1, (n, g) => g.number >= n ? g.number + 1 : n);

  void saveGuarantee(GuaranteeDoc g) {
    final i = guarantees.indexWhere((x) => x.id == g.id);
    if (i >= 0) {
      guarantees[i] = g;
    } else {
      guarantees.add(g);
      _log('ثبت', '${g.label} ${g.number}', docDate: g.date);
    }
    _commit();
  }

  void removeGuarantee(String id) {
    guarantees.removeWhere((g) => g.id == id);
    _commit();
  }

  /// «عودت انتظامی»: returns (or with null, un-returns) one item.
  void returnGuarantee(GuaranteeItem it, DateTime? date, [String note = '']) {
    it.returnedOn = date;
    it.returnNote = date == null ? '' : note;
    _commit();
  }

  // ---------------------------------------------------------------- production

  int nextProductionNumber() => productions.fold<int>(1, (n, p) => p.number >= n ? p.number + 1 : n);

  /// «برآورد قیمت تمام شده»: (material cost, overhead) of producing [qty] with [f].
  (int, int) estimateProduction(ProductionFormula f, double qty) {
    var m = 0;
    for (final l in f.scaled(qty)) {
      m += (l.qty * avgCost(l.productId)).round();
    }
    return (m, f.overheadFor(qty));
  }

  /// Saves a production: freezes material costs and writes its stock movements.
  void saveProduction(Production p) {
    adjusts.removeWhere((a) => a.groupId == p.id);
    productions.removeWhere((x) => x.id == p.id);
    for (final l in p.lines) {
      l.cost = (l.qty * avgCost(l.productId)).round();
    }
    productions.add(p);
    final note = 'تولید شماره ${p.number}${p.note.isEmpty ? '' : ' — ${p.note}'}';
    for (final l in p.lines.where((l) => l.qty != 0)) {
      adjusts.add(StockAdjust(id: newId(), date: p.date, productId: l.productId, qty: -l.qty, reason: AdjustReason.produceOut, groupId: p.id, note: note, warehouseId: p.warehouseId, createdAt: p.createdAt));
    }
    adjusts.add(StockAdjust(id: newId(), date: p.date, productId: p.productId, qty: p.qty, reason: AdjustReason.produceIn, groupId: p.id, note: note, warehouseId: p.warehouseId, createdAt: p.createdAt + 1));
    _log('ثبت', note, docDate: p.date);
    _commit();
  }

  void removeProduction(String id) {
    adjusts.removeWhere((a) => a.groupId == id);
    productions.removeWhere((p) => p.id == id);
    _commit();
  }

  void saveFormula(ProductionFormula f) {
    final i = formulas.indexWhere((x) => x.id == f.id);
    if (i >= 0) {
      formulas[i] = f;
    } else {
      formulas.add(f);
    }
    _commit();
  }

  void saveHall(ProductionHall h) {
    final i = halls.indexWhere((x) => x.id == h.id);
    if (i >= 0) {
      halls[i] = h;
    } else {
      halls.add(h);
    }
    _commit();
  }

  // ---------------------------------------------------------------- stock adjustments

  void addAdjusts(List<StockAdjust> list) {
    if (list.isNotEmpty) _log('ثبت', '${list.first.reason.label} (${list.length} ردیف)', docDate: list.first.date);
    adjusts.addAll(list);
    _commit();
  }

  /// Removes an adjustment and its pair (for conversions).
  void removeAdjust(StockAdjust a) {
    adjusts.removeWhere((x) => x.id == a.id || (a.groupId.isNotEmpty && x.groupId == a.groupId));
    productions.removeWhere((p) => p.id == a.groupId);
    _commit();
  }

  /// Stock count: records the difference between counted and system quantity.
  int applyCount(Map<String, double> counted, DateTime date) {
    final list = <StockAdjust>[];
    counted.forEach((pid, q) {
      final diff = q - stock(pid);
      if (diff.abs() > 1e-9) {
        list.add(StockAdjust(id: newId(), date: date, productId: pid, qty: diff, reason: AdjustReason.count));
      }
    });
    if (list.isNotEmpty) addAdjusts(list);
    return list.length;
  }

  // ---------------------------------------------------------------- loans

  List<Txn> loanPayments(String loanId) =>
      txns.where((t) => t.loanId == loanId && t.type == TxnType.loanPay).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  int loanPaid(String loanId) => loanPayments(loanId).fold(0, (s, t) => s + t.amount);

  int loanPaidCount(String loanId) => loanPayments(loanId).length;

  DateTime installmentDue(Loan l, int index) =>
      Jalali.fromDateTime(l.firstDue).addMonths(index).toDateTime();

  /// Next unpaid installment due date, or null when finished.
  DateTime? loanNextDue(Loan l) {
    final n = loanPaidCount(l.id);
    if (n >= l.installments || l.closed) return null;
    return installmentDue(l, n);
  }

  int get totalLoanRemaining {
    var s = 0;
    for (final l in loans) {
      if (l.closed) continue;
      final r = l.totalPayable - loanPaid(l.id);
      if (r > 0) s += r;
    }
    return s;
  }

  void saveLoan(Loan l, {bool recordReceive = false, DateTime? receiveDate}) {
    final i = loans.indexWhere((e) => e.id == l.id);
    if (i >= 0) {
      loans[i] = l;
    } else {
      loans.add(l);
    }
    if (recordReceive && l.accountId != null && l.principal > 0) {
      txns.removeWhere((t) => t.loanId == l.id && t.type == TxnType.loanIn);
      txns.add(Txn(
        id: newId(),
        type: TxnType.loanIn,
        amount: l.principal,
        date: receiveDate ?? dateOnly(DateTime.now()),
        accountId: l.accountId,
        note: 'دریافت ${l.title}',
        loanId: l.id,
      ));
    }
    _commit();
  }

  void payInstallment(Loan l, {required String accountId, required int amount, required DateTime date}) {
    final n = loanPaidCount(l.id) + 1;
    txns.add(Txn(
      id: newId(),
      type: TxnType.loanPay,
      amount: amount,
      date: date,
      accountId: accountId,
      note: 'قسط $n از ${l.installments} — ${l.title}',
      loanId: l.id,
    ));
    if (n >= l.installments) l.closed = true;
    _commit();
  }

  void removeLoan(String id) {
    loans.removeWhere((l) => l.id == id);
    txns.removeWhere((t) => t.loanId == id);
    _commit();
  }

  // ---------------------------------------------------------------- profit

  ProfitReport profit(DateTime from, DateTime to) {
    final r = ProfitReport();
    final cost = <String, int>{};
    int c(String id) => cost.putIfAbsent(id, () => avgCost(id));
    for (final a in adjusts) {
      if (a.date.isBefore(from) || a.date.isAfter(to)) continue;
      if (a.reason == AdjustReason.convertIn || a.reason == AdjustReason.convertOut) continue;
      if (a.reason == AdjustReason.produceIn || a.reason == AdjustReason.produceOut) continue;
      r.stockLoss += (-a.qty * c(a.productId)).round();
    }
    for (final inv in realInvoices) {
      if (inv.date.isBefore(from) || inv.date.isAfter(to)) continue;
      final sign = switch (inv.kind) {
        InvoiceKind.sale => 1,
        InvoiceKind.saleReturn => -1,
        _ => 0,
      };
      if (inv.kind == InvoiceKind.purchase) {
        r.purchases += inv.total - inv.vatTotal; // VAT is not a cost
        r.purchaseExtra += inv.extra;
        r.purchaseInvoiceDiscounts += inv.discount;
      }
      if (inv.kind == InvoiceKind.purchaseReturn) r.purchaseReturns += inv.total - inv.vatTotal;
      if (sign == 0) continue;
      final net = inv.total - inv.extra - inv.vatTotal; // extra charges count as revenue below; VAT is owed to the state
      if (sign > 0) {
        r.sales += net;
        r.saleExtra += inv.extra;
      } else {
        r.saleReturns += net;
      }
      // spread the invoice-level discount over lines for per-product profit
      final sub = inv.subtotal;
      for (final l in inv.lines) {
        final share = sub == 0 ? 0 : (inv.discount * l.total / sub).round();
        final revenue = l.total - share;
        final unitCost = l.productId == null ? 0 : c(l.productId!);
        final lineCost = (l.qty * unitCost).round();
        r.cogs += sign * lineCost;
        final key = l.productId ?? 'free:${l.title}';
        final row = r.byProduct.putIfAbsent(
            key, () => ProductProfit(product(l.productId)?.name ?? (l.title.isEmpty ? 'بدون نام' : l.title)));
        row.qty += sign * l.qty;
        row.revenue += sign * revenue;
        row.cost += sign * lineCost;
      }
    }
    for (final t in txns) {
      if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
      switch (t.type) {
        case TxnType.income:
          r.otherIncome += t.amount;
        case TxnType.expense:
          r.expenses += t.amount;
        case TxnType.purchaseDiscount:
          r.discountsReceived += t.amount;
        case TxnType.saleDiscount:
          r.discountsGiven += t.amount;
        default:
          break;
      }
    }
    for (final v in vouchers) {
      if (v.date.isBefore(from) || v.date.isAfter(to) || v.isYearEnd) continue;
      for (final l in v.lines) {
        final m = findMoeen(l.moeen);
        if (m == null) continue;
        final dr = l.debit - l.credit;
        switch (m.code) {
          case mSaleDiscount:
            r.discountsGiven += dr;
          case mPurchaseDiscount:
            r.discountsReceived -= dr;
          case mStockLoss:
            r.stockLoss += dr;
          case mCogs:
            r.cogs += dr;
          default:
            if (m.side == Side.income) r.otherIncome -= dr;
            if (m.side == Side.expense) r.expenses += dr;
        }
      }
    }
    return r;
  }

  // ---------------------------------------------------------------- sms

  /// Records sent messages (keeps the last 1000).
  void logSms(Iterable<SmsLogEntry> entries) {
    smsLog.insertAll(0, entries);
    if (smsLog.length > 1000) smsLog.removeRange(1000, smsLog.length);
    _commit();
  }

  /// True when a message about [ref] was delivered to the panel.
  bool smsSentFor(String ref) => smsLog.any((e) => e.ok && e.ref == ref);

  void clearSmsLog() {
    smsLog.clear();
    _commit();
  }

  // ---------------------------------------------------------------- backup

  /// «تهیه کپی نسخه پشتیبان»: a compressed .zip holding the data file
  /// (AES-encrypted when a backup password is set in the settings).
  String exportBackup({String? password}) {
    final n = DateTime.now();
    final j = Jalali.fromDateTime(n);
    final name =
        'taraz-backup-${j.format(sep: '-')}-${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
    final f = File('${Storage.userFolder.path}${Storage.sep}$name.zip');
    final pass = password ?? settings.backupPassword;
    f.writeAsBytesSync(zipBackup(const JsonEncoder.withIndent(' ').convert(toJson()), password: pass), flush: true);
    return f.path;
  }

  /// Replaces all data with the content of [path] (.zip or .json).
  /// Throws [BackupPasswordException] when a protected backup needs its
  /// password, [FormatException] on an invalid file.
  void importBackup(String path, {String? password}) {
    final file = File(path);
    final String txt;
    if (path.toLowerCase().endsWith('.zip')) {
      txt = unzipBackup(file.readAsBytesSync(), password: password ?? (settings.backupPassword.isEmpty ? null : settings.backupPassword));
    } else {
      txt = file.readAsStringSync();
    }
    final Object? j;
    try {
      j = jsonDecode(txt);
    } catch (_) {
      throw const FormatException('فایل پشتیبان معتبر نیست');
    }
    if (j is! Map<String, dynamic> || j['accounts'] is! List || j['txns'] is! List) {
      throw const FormatException('فایل پشتیبان معتبر نیست');
    }
    // safety copy of current data before replacing
    try {
      final n = DateTime.now().millisecondsSinceEpoch;
      if (!storage.backupDir.existsSync()) storage.backupDir.createSync(recursive: true);
      File('${storage.backupDir.path}${Storage.sep}before-import-$n.json')
          .writeAsStringSync(jsonEncode(toJson()));
    } catch (_) {}
    _fromJson(j);
    _commit();
  }

  List<File> availableBackups() {
    final out = <File>[];
    for (final d in [Storage.userFolder, storage.backupDir]) {
      if (!d.existsSync()) continue;
      out.addAll(d.listSync().whereType<File>().where((f) {
        final p = f.path.toLowerCase();
        return p.endsWith('.json') || (p.endsWith('.zip') && p.contains('taraz'));
      }));
    }
    out.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return out;
  }

  String _exportName(String name, String ext) {
    final n = DateTime.now();
    final j = Jalali.fromDateTime(n);
    return '${Storage.userFolder.path}${Storage.sep}$name-${j.format(sep: '-')}-${n.hour}${n.minute.toString().padLeft(2, '0')}${n.second.toString().padLeft(2, '0')}.$ext';
  }

  /// «خروجی به اکسل»: writes any table as a real Excel workbook (.xlsx);
  /// returns the file path.
  String exportTableXlsx(List<String> headers, List<List<String>> rows,
      {String name = 'export', String sheet = 'گزارش', List<String> titleLines = const []}) {
    final f = File(_exportName(name, 'xlsx'));
    f.writeAsBytesSync(buildXlsx([XlsxSheet(sheet, headers, rows, titleLines: titleLines)]), flush: true);
    return f.path;
  }

  /// Transactions as an Excel workbook.
  String exportTxnsXlsx(List<Txn> list, {String name = 'transactions', List<String> titleLines = const []}) {
    final rows = [
      for (final t in list)
        [
          jFormat(t.date),
          t.type.label,
          groupDigits(t.amount),
          account(t.accountId)?.name ?? '',
          account(t.toAccountId)?.name ?? '',
          category(t.categoryId)?.name ?? '',
          person(t.personId)?.name ?? '',
          t.dueDate == null ? '' : jFormat(t.dueDate!),
          t.note,
        ]
    ];
    return exportTableXlsx(
      ['تاریخ', 'نوع', 'مبلغ (${settings.currency})', 'حساب', 'به حساب', 'دسته', 'شخص', 'سررسید', 'توضیحات'],
      rows,
      name: name,
      sheet: 'تراکنش‌ها',
      titleLines: titleLines,
    );
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

class ProductProfit {
  final String name;
  double qty = 0;
  int revenue = 0;
  int cost = 0;
  ProductProfit(this.name);
  int get profit => revenue - cost;
}

class ProfitReport {
  int sales = 0; // net of invoice discounts, excluding extra charges
  int saleExtra = 0;
  int saleReturns = 0;
  int cogs = 0;
  int purchases = 0;
  int purchaseExtra = 0;
  int purchaseInvoiceDiscounts = 0;
  int purchaseReturns = 0;
  int discountsReceived = 0;
  int discountsGiven = 0;
  int otherIncome = 0;
  int expenses = 0;
  int stockLoss = 0; // waste, internal use and count differences at cost
  final Map<String, ProductProfit> byProduct = {};

  int get netSales => sales - saleReturns;
  int get grossProfit => netSales - cogs;
  int get netProfit =>
      grossProfit + saleExtra - purchaseExtra + purchaseInvoiceDiscounts + discountsReceived - discountsGiven + otherIncome - expenses - stockLoss;
}

/// Plain-text slip for a 80mm printer (42 columns).
String textSlip(String title, List<(String, String)> fields, List<List<String>> rows, {String footer = ''}) {
  final b = StringBuffer()
    ..writeln(title)
    ..writeln('-' * 32);
  for (final (k, v) in fields) {
    b.writeln('$k: $v');
  }
  if (rows.isNotEmpty) b.writeln('-' * 32);
  for (final r in rows) {
    b.writeln(r.where((c) => c.isNotEmpty).join('  '));
  }
  if (footer.isNotEmpty) {
    b
      ..writeln('-' * 32)
      ..writeln(footer);
  }
  return b.toString();
}
