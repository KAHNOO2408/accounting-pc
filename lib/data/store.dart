import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/hash.dart';
import '../core/jalali.dart';
import 'models.dart';
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
  AppSettings settings = AppSettings();
  String? lastError;

  AppStore(this.storage);

  // ---------------------------------------------------------------- loading

  static AppStore load() => open(Storage.init());

  /// Opens (or initialises) the data stored in [s].
  static AppStore open(Storage s) {
    final store = AppStore(s);
    final data = s.read();
    if (data == null) {
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
    final st = j['settings'];
    settings = st is Map<String, dynamic> ? AppSettings.fromJson(st) : AppSettings();
    _sortTxns();
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
    return b;
  }

  int get totalBalance {
    var s = 0;
    for (final a in accounts) {
      s += balance(a.id);
    }
    return s;
  }

  int personBalance(String personId) {
    var b = 0;
    for (final t in txns) {
      if (t.personId == personId) b += t.type.personSign * t.amount;
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

  int get pendingChequesIn => cheques
      .where((c) => c.direction == ChequeDirection.received && c.status == ChequeStatus.pending)
      .fold(0, (s, c) => s + c.amount);

  int get pendingChequesOut => cheques
      .where((c) => c.direction == ChequeDirection.issued && c.status == ChequeStatus.pending)
      .fold(0, (s, c) => s + c.amount);

  /// Net worth = cash + receivables - payables + pending cheques in - out.
  int get netWorth => totalBalance + totalReceivable - totalPayable + pendingChequesIn - pendingChequesOut;

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
        .where((c) => c.status == ChequeStatus.pending && !c.dueDate.isAfter(limit))
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

  bool accountInUse(String id) => txns.any((t) => t.accountId == id || t.toAccountId == id);

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
    final i = people.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      people[i] = p;
    } else {
      people.add(p);
    }
    _commit();
  }

  bool personInUse(String id) =>
      txns.any((t) => t.personId == id) || cheques.any((c) => c.personId == id);

  bool removePerson(String id) {
    if (personInUse(id)) return false;
    people.removeWhere((p) => p.id == id);
    _commit();
    return true;
  }

  void upsertTxn(Txn t) {
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
    if (t.chequeId != null) {
      final c = cheque(t.chequeId);
      if (c != null && c.txnId == id) {
        c.txnId = null;
        if (c.status == ChequeStatus.cleared) c.status = ChequeStatus.pending;
      }
    }
    txns.removeWhere((e) => e.id == id);
    _commit();
  }

  void upsertCheque(Cheque c) {
    final i = cheques.indexWhere((e) => e.id == c.id);
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
    if (c.txnId != null) txns.removeWhere((t) => t.id == c.txnId);
    cheques.removeWhere((e) => e.id == id);
    _commit();
  }

  /// Marks a cheque as cleared and records the money movement.
  void clearCheque(Cheque c, {required String accountId, required TxnType asType, String? categoryId, required DateTime date}) {
    if (c.txnId != null) txns.removeWhere((t) => t.id == c.txnId);
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
    if (s != ChequeStatus.cleared && c.txnId != null) {
      txns.removeWhere((t) => t.id == c.txnId);
      c.txnId = null;
    }
    c.status = s;
    _commit();
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
