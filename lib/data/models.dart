import 'dart:math';

String newId() {
  final r = Random();
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final s = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  return '$t$s';
}

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _p(Object? v) {
  if (v is String && v.isNotEmpty) {
    final dt = DateTime.tryParse(v);
    if (dt != null) return DateTime(dt.year, dt.month, dt.day);
  }
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime? _pn(Object? v) => (v is String && v.isNotEmpty) ? _p(v) : null;

int _i(Object? v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

String _s(Object? v) => v is String ? v : '';
String? _sn(Object? v) => (v is String && v.isNotEmpty) ? v : null;

T _enum<T extends Enum>(List<T> values, Object? name, T def) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return def;
}

// ---------------------------------------------------------------------------

enum AccountType { cash, bank, card, wallet, other }

extension AccountTypeX on AccountType {
  String get label => switch (this) {
        AccountType.cash => 'صندوق / نقدی',
        AccountType.bank => 'حساب بانکی',
        AccountType.card => 'کارت',
        AccountType.wallet => 'کیف پول',
        AccountType.other => 'سایر',
      };
}

class Account {
  String id;
  String name;
  AccountType type;
  String bank;
  String number;
  int opening;
  int color;
  bool archived;
  String note;

  Account({
    required this.id,
    required this.name,
    this.type = AccountType.bank,
    this.bank = '',
    this.number = '',
    this.opening = 0,
    this.color = 0xFF2F6FED,
    this.archived = false,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'bank': bank,
        'number': number,
        'opening': opening,
        'color': color,
        'archived': archived,
        'note': note,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: _s(j['id']),
        name: _s(j['name']),
        type: _enum(AccountType.values, j['type'], AccountType.other),
        bank: _s(j['bank']),
        number: _s(j['number']),
        opening: _i(j['opening']),
        color: _i(j['color'], 0xFF2F6FED),
        archived: j['archived'] == true,
        note: _s(j['note']),
      );
}

// ---------------------------------------------------------------------------

enum CategoryKind { income, expense }

class TxnCategory {
  String id;
  String name;
  CategoryKind kind;
  int color;
  bool archived;

  TxnCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.color = 0xFF7C8796,
    this.archived = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'color': color,
        'archived': archived,
      };

  factory TxnCategory.fromJson(Map<String, dynamic> j) => TxnCategory(
        id: _s(j['id']),
        name: _s(j['name']),
        kind: _enum(CategoryKind.values, j['kind'], CategoryKind.expense),
        color: _i(j['color'], 0xFF7C8796),
        archived: j['archived'] == true,
      );
}

// ---------------------------------------------------------------------------

class Person {
  String id;
  String name;
  String phone;
  String note;

  Person({required this.id, required this.name, this.phone = '', this.note = ''});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'note': note};

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: _s(j['id']),
        name: _s(j['name']),
        phone: _s(j['phone']),
        note: _s(j['note']),
      );
}

// ---------------------------------------------------------------------------

enum TxnType { income, expense, transfer, lend, borrow, collect, repay }

extension TxnTypeX on TxnType {
  String get label => switch (this) {
        TxnType.income => 'درآمد',
        TxnType.expense => 'هزینه',
        TxnType.transfer => 'انتقال',
        TxnType.lend => 'قرض دادن',
        TxnType.borrow => 'قرض گرفتن',
        TxnType.collect => 'دریافت طلب',
        TxnType.repay => 'پرداخت بدهی',
      };

  bool get needsPerson =>
      this == TxnType.lend || this == TxnType.borrow || this == TxnType.collect || this == TxnType.repay;

  bool get isDebt => needsPerson;

  bool get hasCategory => this == TxnType.income || this == TxnType.expense;

  /// Sign of the effect on the (source) account: +1 money in, -1 money out.
  int get accountSign => switch (this) {
        TxnType.income => 1,
        TxnType.expense => -1,
        TxnType.transfer => -1,
        TxnType.lend => -1,
        TxnType.borrow => 1,
        TxnType.collect => 1,
        TxnType.repay => -1,
      };

  /// Effect on a person's balance (positive = they owe me).
  int get personSign => switch (this) {
        TxnType.lend => 1,
        TxnType.collect => -1,
        TxnType.borrow => -1,
        TxnType.repay => 1,
        _ => 0,
      };
}

class Txn {
  String id;
  TxnType type;
  int amount;
  DateTime date;
  String? accountId;
  String? toAccountId;
  String? categoryId;
  String? personId;
  String note;
  DateTime? dueDate;
  String? chequeId;
  int createdAt;

  Txn({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.accountId,
    this.toAccountId,
    this.categoryId,
    this.personId,
    this.note = '',
    this.dueDate,
    this.chequeId,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Txn copy() => Txn.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'date': _d(date),
        'accountId': accountId,
        'toAccountId': toAccountId,
        'categoryId': categoryId,
        'personId': personId,
        'note': note,
        'dueDate': dueDate == null ? null : _d(dueDate!),
        'chequeId': chequeId,
        'createdAt': createdAt,
      };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: _s(j['id']),
        type: _enum(TxnType.values, j['type'], TxnType.expense),
        amount: _i(j['amount']),
        date: _p(j['date']),
        accountId: _sn(j['accountId']),
        toAccountId: _sn(j['toAccountId']),
        categoryId: _sn(j['categoryId']),
        personId: _sn(j['personId']),
        note: _s(j['note']),
        dueDate: _pn(j['dueDate']),
        chequeId: _sn(j['chequeId']),
        createdAt: _i(j['createdAt']),
      );

  /// Effect of this transaction on a given account's balance.
  int effectOn(String accId) {
    var e = 0;
    if (accountId == accId) e += type.accountSign * amount;
    if (type == TxnType.transfer && toAccountId == accId) e += amount;
    return e;
  }
}

// ---------------------------------------------------------------------------

enum ChequeDirection { received, issued }

enum ChequeStatus { pending, cleared, bounced, cancelled }

extension ChequeStatusX on ChequeStatus {
  String get label => switch (this) {
        ChequeStatus.pending => 'در انتظار',
        ChequeStatus.cleared => 'پاس شده',
        ChequeStatus.bounced => 'برگشتی',
        ChequeStatus.cancelled => 'باطل / عودت',
      };
}

class Cheque {
  String id;
  ChequeDirection direction;
  int amount;
  DateTime dueDate;
  DateTime issueDate;
  String? personId;
  String bank;
  String serial;
  ChequeStatus status;
  String? txnId;
  String note;

  Cheque({
    required this.id,
    required this.direction,
    required this.amount,
    required this.dueDate,
    required this.issueDate,
    this.personId,
    this.bank = '',
    this.serial = '',
    this.status = ChequeStatus.pending,
    this.txnId,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': direction.name,
        'amount': amount,
        'dueDate': _d(dueDate),
        'issueDate': _d(issueDate),
        'personId': personId,
        'bank': bank,
        'serial': serial,
        'status': status.name,
        'txnId': txnId,
        'note': note,
      };

  factory Cheque.fromJson(Map<String, dynamic> j) => Cheque(
        id: _s(j['id']),
        direction: _enum(ChequeDirection.values, j['direction'], ChequeDirection.received),
        amount: _i(j['amount']),
        dueDate: _p(j['dueDate']),
        issueDate: _p(j['issueDate']),
        personId: _sn(j['personId']),
        bank: _s(j['bank']),
        serial: _s(j['serial']),
        status: _enum(ChequeStatus.values, j['status'], ChequeStatus.pending),
        txnId: _sn(j['txnId']),
        note: _s(j['note']),
      );
}

// ---------------------------------------------------------------------------

class AppSettings {
  String themeMode; // system | light | dark
  String currency;
  int accent;
  String ownerName;
  String passwordHash;
  String passwordSalt;
  String passwordHint;
  bool setupDone;

  AppSettings({
    this.themeMode = 'light',
    this.currency = 'تومان',
    this.accent = 0xFF4F46E5,
    this.ownerName = '',
    this.passwordHash = '',
    this.passwordSalt = '',
    this.passwordHint = '',
    this.setupDone = false,
  });

  bool get hasPassword => passwordHash.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'currency': currency,
        'accent': accent,
        'ownerName': ownerName,
        'passwordHash': passwordHash,
        'passwordSalt': passwordSalt,
        'passwordHint': passwordHint,
        'setupDone': setupDone,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: _s(j['themeMode']).isEmpty ? 'light' : _s(j['themeMode']),
        currency: _s(j['currency']).isEmpty ? 'تومان' : _s(j['currency']),
        accent: _i(j['accent'], 0xFF4F46E5),
        ownerName: _s(j['ownerName']),
        passwordHash: _s(j['passwordHash']),
        passwordSalt: _s(j['passwordSalt']),
        passwordHint: _s(j['passwordHint']),
        setupDone: j['setupDone'] == true,
      );
}
