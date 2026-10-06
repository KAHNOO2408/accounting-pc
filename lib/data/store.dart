import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/format.dart' show groupDigits;
import '../core/hash.dart';
import '../core/jalali.dart';
import 'books.dart';
import 'chart.dart';
import 'models.dart';
import 'report_layout.dart';
import 'storage.dart';

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
      store._persist();
    } else {
      store._fromJson(data);
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

  void _applyCustomMoeens() {
    extraMoeens = [for (final e in customMoeens.entries) Moeen(e.key, e.value)];
  }

  /// ساخت دفتر — a new ledger (معین) under kol [kolCode]. Returns its code.
  String addMoeen(String kolCode, String name) {
    final k = chart.firstWhere((k) => k.code == kolCode);
    var n = 1;
    for (final m in k.ledgers) {
      final v = int.tryParse(m.code.substring(3)) ?? 0;
      if (v >= n) n = v + 1;
    }
    final code = '$kolCode${n.toString().padLeft(2, '0')}';
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
        'version': 1,
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
    final u = currentUser;
    return u.admin || !u.denied.contains(label);
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
    if (inv != null && !inv.proforma) {
      final who = person(inv.personId)?.name ?? 'متفرقه';
      _recycle('inv:$id', number: docMeta['inv:$id']?.number ?? inv.number, date: inv.date,
          desc: '${inv.kind.label} ${inv.number}  ${inv.lines.length} قلم کالا  $who', amount: inv.total, payload: {
        'doc': inv.toJson(),
        'vouchers': [for (final v in vouchers.where((v) => v.kind == 'settle' && v.meta['invoice'] == id)) v.toJson()],
        'txns': [for (final t in txns.where((t) => t.invoiceId == id)) t.toJson()],
      });
    }
    if (inv != null) _log('حذف', '${inv.kind.label} ${inv.number}', docDate: inv.date, docNo: inv.number);
    vouchers.removeWhere((v) => v.kind == 'settle' && v.meta['invoice'] == id);
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

  // ---------------------------------------------------------------- stock adjustments

  void addAdjusts(List<StockAdjust> list) {
    if (list.isNotEmpty) _log('ثبت', '${list.first.reason.label} (${list.length} ردیف)', docDate: list.first.date);
    adjusts.addAll(list);
    _commit();
  }

  /// Removes an adjustment and its pair (for conversions).
  void removeAdjust(StockAdjust a) {
    adjusts.removeWhere((x) => x.id == a.id || (a.groupId.isNotEmpty && x.groupId == a.groupId));
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
        r.purchases += inv.total;
        r.purchaseExtra += inv.extra;
        r.purchaseInvoiceDiscounts += inv.discount;
      }
      if (inv.kind == InvoiceKind.purchaseReturn) r.purchaseReturns += inv.total;
      if (sign == 0) continue;
      final net = inv.total - inv.extra; // extra charges on sales count as revenue below
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

  // ---------------------------------------------------------------- backup

  String exportBackup() {
    final n = DateTime.now();
    final j = Jalali.fromDateTime(n);
    final name =
        'taraz-backup-${j.format(sep: '-')}-${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}.json';
    final f = File('${Storage.userFolder.path}${Storage.sep}$name');
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(toJson()), flush: true);
    return f.path;
  }

  /// Replaces all data with the content of [path]. Throws on invalid file.
  void importBackup(String path) {
    final txt = File(path).readAsStringSync();
    final j = jsonDecode(txt);
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
      out.addAll(d.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.json')));
    }
    out.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return out;
  }

  /// Writes any table as CSV for Excel («خروجی به اکسل»); returns the file path.
  String exportTableCsv(List<String> headers, List<List<String>> rows, {String name = 'export'}) {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('\uFEFF');
    b.writeln(headers.map(esc).join(','));
    for (final r in rows) {
      b.writeln(r.map(esc).join(','));
    }
    final n = DateTime.now();
    final j = Jalali.fromDateTime(n);
    final f = File(
        '${Storage.userFolder.path}${Storage.sep}$name-${j.format(sep: '-')}-${n.hour}${n.minute.toString().padLeft(2, '0')}.csv');
    f.writeAsStringSync(b.toString(), flush: true);
    return f.path;
  }

  /// Writes a CSV (UTF-8 with BOM so Excel shows Persian correctly).
  String exportCsv(List<Txn> list, {String name = 'transactions'}) {
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('﻿');
    b.writeln(['تاریخ', 'نوع', 'مبلغ', 'حساب', 'به حساب', 'دسته', 'شخص', 'سررسید', 'توضیحات'].map(esc).join(','));
    for (final t in list) {
      b.writeln([
        jFormat(t.date),
        t.type.label,
        t.amount.toString(),
        account(t.accountId)?.name ?? '',
        account(t.toAccountId)?.name ?? '',
        category(t.categoryId)?.name ?? '',
        person(t.personId)?.name ?? '',
        t.dueDate == null ? '' : jFormat(t.dueDate!),
        t.note,
      ].map(esc).join(','));
    }
    final n = DateTime.now();
    final j = Jalali.fromDateTime(n);
    final f = File(
        '${Storage.userFolder.path}${Storage.sep}$name-${j.format(sep: '-')}-${n.hour}${n.minute.toString().padLeft(2, '0')}.csv');
    f.writeAsStringSync(b.toString(), flush: true);
    return f.path;
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
