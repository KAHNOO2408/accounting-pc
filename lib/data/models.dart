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

enum AccountType { cash, bank, card, wallet, savings, other }

extension AccountTypeX on AccountType {
  String get label => switch (this) {
        AccountType.cash => 'صندوق / نقدی',
        AccountType.bank => 'حساب بانکی',
        AccountType.card => 'کارت',
        AccountType.wallet => 'کیف پول',
        AccountType.savings => 'پس‌انداز',
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

  /// Savings target (only meaningful for savings accounts).
  int goal;

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
    this.goal = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goal': goal,
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
        goal: _i(j['goal']),
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

  /// Opening balance from the opening voucher (positive = they owe me).
  int opening;

  Person({required this.id, required this.name, this.phone = '', this.note = '', this.opening = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'note': note, 'opening': opening};

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: _s(j['id']),
        name: _s(j['name']),
        phone: _s(j['phone']),
        note: _s(j['note']),
        opening: _i(j['opening']),
      );
}

// ---------------------------------------------------------------------------

/// One row of a manual accounting voucher (سند حسابداری دستی).
class VoucherLine {
  String moeen;
  String? tafsiliId;
  String desc;
  int debit;
  int credit;

  VoucherLine({required this.moeen, this.tafsiliId, this.desc = '', this.debit = 0, this.credit = 0});

  VoucherLine copy() => VoucherLine.fromJson(toJson());

  Map<String, dynamic> toJson() =>
      {'moeen': moeen, 'tafsiliId': tafsiliId, 'desc': desc, 'debit': debit, 'credit': credit};

  factory VoucherLine.fromJson(Map<String, dynamic> j) => VoucherLine(
        moeen: _s(j['moeen']),
        tafsiliId: _sn(j['tafsiliId']),
        desc: _s(j['desc']),
        debit: _i(j['debit']),
        credit: _i(j['credit']),
      );
}

class Voucher {
  String id;
  int number;
  int fixedNumber;
  DateTime date;
  String desc;
  String center;
  String archivePath;
  DateTime? followDate;
  String followDesc;
  List<VoucherLine> lines;

  /// manual | composite (دریافت پرداخت مرکب) | expense (پرداخت هزینه‌های مرکب)
  String kind;
  int createdAt;

  String get kindLabel => switch (kind) {
        'composite' => 'دریافت و پرداخت مرکب',
        'expense' => 'پرداخت هزینه مرکب',
        _ => 'سند دستی',
      };

  Voucher({
    required this.id,
    required this.number,
    required this.fixedNumber,
    required this.date,
    this.desc = '',
    this.center = 'اصلی',
    this.archivePath = '',
    this.followDate,
    this.followDesc = '',
    List<VoucherLine>? lines,
    this.kind = 'manual',
    int? createdAt,
  })  : lines = lines ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  int get totalDebit => lines.fold(0, (s, l) => s + l.debit);
  int get totalCredit => lines.fold(0, (s, l) => s + l.credit);
  bool get balanced => totalDebit == totalCredit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'fixedNumber': fixedNumber,
        'date': _d(date),
        'desc': desc,
        'center': center,
        'archivePath': archivePath,
        'followDate': followDate == null ? null : _d(followDate!),
        'followDesc': followDesc,
        'lines': lines.map((l) => l.toJson()).toList(),
        'kind': kind,
        'createdAt': createdAt,
      };

  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        id: _s(j['id']),
        number: _i(j['number']),
        fixedNumber: _i(j['fixedNumber']),
        date: _p(j['date']),
        desc: _s(j['desc']),
        center: _s(j['center']).isEmpty ? 'اصلی' : _s(j['center']),
        archivePath: _s(j['archivePath']),
        followDate: _pn(j['followDate']),
        followDesc: _s(j['followDesc']),
        lines: (j['lines'] is List)
            ? (j['lines'] as List).whereType<Map<String, dynamic>>().map(VoucherLine.fromJson).toList()
            : <VoucherLine>[],
        kind: _s(j['kind']).isEmpty ? 'manual' : _s(j['kind']),
        createdAt: _i(j['createdAt']),
      );
}

// ---------------------------------------------------------------------------

enum TxnType {
  income,
  expense,
  transfer,
  lend,
  borrow,
  collect,
  repay,
  // generated by invoices
  sale,
  purchase,
  saleReturn,
  purchaseReturn,
  // discounts
  purchaseDiscount,
  saleDiscount,
  // loans
  loanIn,
  loanPay,
}

extension TxnTypeX on TxnType {
  String get label => switch (this) {
        TxnType.income => 'درآمد',
        TxnType.expense => 'هزینه',
        TxnType.transfer => 'انتقال',
        TxnType.lend => 'قرض دادن',
        TxnType.borrow => 'قرض گرفتن',
        TxnType.collect => 'دریافت طلب',
        TxnType.repay => 'پرداخت بدهی',
        TxnType.sale => 'فروش',
        TxnType.purchase => 'خرید',
        TxnType.saleReturn => 'برگشت از فروش',
        TxnType.purchaseReturn => 'برگشت از خرید',
        TxnType.purchaseDiscount => 'تخفیف از خرید',
        TxnType.saleDiscount => 'تخفیف از فروش',
        TxnType.loanIn => 'دریافت وام',
        TxnType.loanPay => 'قسط وام',
      };

  bool get isDebt =>
      this == TxnType.lend || this == TxnType.borrow || this == TxnType.collect || this == TxnType.repay;

  bool get isDiscount => this == TxnType.purchaseDiscount || this == TxnType.saleDiscount;

  bool get isInvoice =>
      this == TxnType.sale || this == TxnType.purchase || this == TxnType.saleReturn || this == TxnType.purchaseReturn;

  bool get isLoan => this == TxnType.loanIn || this == TxnType.loanPay;

  bool get needsPerson => isDebt || isDiscount;

  /// Created automatically by an invoice or a loan; edited from there.
  bool get isSystem => isInvoice || isLoan;

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
        TxnType.sale => 1,
        TxnType.purchase => -1,
        TxnType.saleReturn => -1,
        TxnType.purchaseReturn => 1,
        TxnType.purchaseDiscount => 1,
        TxnType.saleDiscount => -1,
        TxnType.loanIn => 1,
        TxnType.loanPay => -1,
      };

  /// Effect on a person's balance (positive = they owe me).
  int get personSign => switch (this) {
        TxnType.lend => 1,
        TxnType.collect => -1,
        TxnType.borrow => -1,
        TxnType.repay => 1,
        TxnType.sale => 1,
        TxnType.purchase => -1,
        TxnType.saleReturn => -1,
        TxnType.purchaseReturn => 1,
        TxnType.purchaseDiscount => 1,
        TxnType.saleDiscount => -1,
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
  String? invoiceId;
  String? loanId;
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
    this.invoiceId,
    this.loanId,
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
        'invoiceId': invoiceId,
        'loanId': loanId,
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
        invoiceId: _sn(j['invoiceId']),
        loanId: _sn(j['loanId']),
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

double _dbl(Object? v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? def;
  return def;
}

class Product {
  String id;
  String name;
  String code;
  String unit;
  int buyPrice;
  int sellPrice;
  double openingQty;

  /// Unit cost of the opening quantity (0 = use buy price).
  int openingCost;
  double minQty;
  bool archived;
  String note;

  Product({
    required this.id,
    required this.name,
    this.code = '',
    this.unit = 'عدد',
    this.buyPrice = 0,
    this.sellPrice = 0,
    this.openingQty = 0,
    this.openingCost = 0,
    this.minQty = 0,
    this.archived = false,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'unit': unit,
        'buyPrice': buyPrice,
        'sellPrice': sellPrice,
        'openingQty': openingQty,
        'openingCost': openingCost,
        'minQty': minQty,
        'archived': archived,
        'note': note,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _s(j['id']),
        name: _s(j['name']),
        code: _s(j['code']),
        unit: _s(j['unit']).isEmpty ? 'عدد' : _s(j['unit']),
        buyPrice: _i(j['buyPrice']),
        sellPrice: _i(j['sellPrice']),
        openingQty: _dbl(j['openingQty']),
        openingCost: _i(j['openingCost']),
        minQty: _dbl(j['minQty']),
        archived: j['archived'] == true,
        note: _s(j['note']),
      );
}

enum InvoiceKind { sale, purchase, saleReturn, purchaseReturn }

extension InvoiceKindX on InvoiceKind {
  String get label => switch (this) {
        InvoiceKind.sale => 'فاکتور فروش',
        InvoiceKind.purchase => 'فاکتور خرید',
        InvoiceKind.saleReturn => 'برگشت از فروش',
        InvoiceKind.purchaseReturn => 'برگشت از خرید',
      };

  String get short => switch (this) {
        InvoiceKind.sale => 'فروش',
        InvoiceKind.purchase => 'خرید',
        InvoiceKind.saleReturn => 'برگشت فروش',
        InvoiceKind.purchaseReturn => 'برگشت خرید',
      };

  TxnType get txnType => switch (this) {
        InvoiceKind.sale => TxnType.sale,
        InvoiceKind.purchase => TxnType.purchase,
        InvoiceKind.saleReturn => TxnType.saleReturn,
        InvoiceKind.purchaseReturn => TxnType.purchaseReturn,
      };

  /// Money comes in to me when this invoice is paid.
  bool get moneyIn => this == InvoiceKind.sale || this == InvoiceKind.purchaseReturn;

  /// Effect on stock: +1 increases inventory.
  int get stockSign => switch (this) {
        InvoiceKind.sale => -1,
        InvoiceKind.purchase => 1,
        InvoiceKind.saleReturn => 1,
        InvoiceKind.purchaseReturn => -1,
      };

  /// Uses buy prices (purchases) rather than sell prices.
  bool get buySide => this == InvoiceKind.purchase || this == InvoiceKind.purchaseReturn;

  String get personLabel => buySide ? 'فروشنده / تامین‌کننده' : 'خریدار / مشتری';
}

class InvoiceLine {
  String? productId;
  String title;
  double qty;
  int unitPrice;
  int discount;

  InvoiceLine({this.productId, this.title = '', this.qty = 1, this.unitPrice = 0, this.discount = 0});

  int get total => (qty * unitPrice).round() - discount;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'title': title,
        'qty': qty,
        'unitPrice': unitPrice,
        'discount': discount,
      };

  factory InvoiceLine.fromJson(Map<String, dynamic> j) => InvoiceLine(
        productId: _sn(j['productId']),
        title: _s(j['title']),
        qty: _dbl(j['qty'], 1),
        unitPrice: _i(j['unitPrice']),
        discount: _i(j['discount']),
      );
}

class Invoice {
  String id;
  InvoiceKind kind;
  int number;
  DateTime date;
  String? personId;
  List<InvoiceLine> lines;
  int discount;
  int extra;
  int paid;
  String? accountId;
  DateTime? dueDate;
  String note;
  bool proforma;
  int createdAt;

  Invoice({
    required this.id,
    required this.kind,
    required this.number,
    required this.date,
    this.personId,
    List<InvoiceLine>? lines,
    this.discount = 0,
    this.extra = 0,
    this.paid = 0,
    this.accountId,
    this.dueDate,
    this.note = '',
    this.proforma = false,
    int? createdAt,
  })  : lines = lines ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  int get subtotal => lines.fold(0, (s, l) => s + l.total);
  int get total => subtotal - discount + extra;
  int get remaining => total - paid;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'number': number,
        'date': _d(date),
        'personId': personId,
        'lines': lines.map((l) => l.toJson()).toList(),
        'discount': discount,
        'extra': extra,
        'paid': paid,
        'accountId': accountId,
        'dueDate': dueDate == null ? null : _d(dueDate!),
        'note': note,
        'proforma': proforma,
        'createdAt': createdAt,
      };

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: _s(j['id']),
        kind: _enum(InvoiceKind.values, j['kind'], InvoiceKind.sale),
        number: _i(j['number']),
        date: _p(j['date']),
        personId: _sn(j['personId']),
        lines: (j['lines'] is List)
            ? (j['lines'] as List).whereType<Map<String, dynamic>>().map(InvoiceLine.fromJson).toList()
            : <InvoiceLine>[],
        discount: _i(j['discount']),
        extra: _i(j['extra']),
        paid: _i(j['paid']),
        accountId: _sn(j['accountId']),
        dueDate: _pn(j['dueDate']),
        note: _s(j['note']),
        proforma: j['proforma'] == true,
        createdAt: _i(j['createdAt']),
      );
}

enum AdjustReason { waste, consume, count, convertOut, convertIn }

extension AdjustReasonX on AdjustReason {
  String get label => switch (this) {
        AdjustReason.waste => 'ضایعات',
        AdjustReason.consume => 'مصرف داخلی',
        AdjustReason.count => 'اصلاح انبارگردانی',
        AdjustReason.convertOut => 'تبدیل (خروج)',
        AdjustReason.convertIn => 'تبدیل (ورود)',
      };
}

/// Manual stock movement that is not a purchase or sale.
class StockAdjust {
  String id;
  DateTime date;
  String productId;
  double qty; // signed: + adds to stock
  AdjustReason reason;
  String groupId; // pairs convert in/out
  String note;
  int createdAt;

  StockAdjust({
    required this.id,
    required this.date,
    required this.productId,
    required this.qty,
    required this.reason,
    this.groupId = '',
    this.note = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': _d(date),
        'productId': productId,
        'qty': qty,
        'reason': reason.name,
        'groupId': groupId,
        'note': note,
        'createdAt': createdAt,
      };

  factory StockAdjust.fromJson(Map<String, dynamic> j) => StockAdjust(
        id: _s(j['id']),
        date: _p(j['date']),
        productId: _s(j['productId']),
        qty: _dbl(j['qty']),
        reason: _enum(AdjustReason.values, j['reason'], AdjustReason.waste),
        groupId: _s(j['groupId']),
        note: _s(j['note']),
        createdAt: _i(j['createdAt']),
      );
}

class Loan {
  String id;
  String title;
  String lender;
  int principal;
  int installmentAmount;
  int installments;
  DateTime firstDue;
  String? accountId;
  String note;
  bool closed;

  Loan({
    required this.id,
    required this.title,
    this.lender = '',
    this.principal = 0,
    this.installmentAmount = 0,
    this.installments = 12,
    required this.firstDue,
    this.accountId,
    this.note = '',
    this.closed = false,
  });

  int get totalPayable => installmentAmount * installments;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'lender': lender,
        'principal': principal,
        'installmentAmount': installmentAmount,
        'installments': installments,
        'firstDue': _d(firstDue),
        'accountId': accountId,
        'note': note,
        'closed': closed,
      };

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        id: _s(j['id']),
        title: _s(j['title']),
        lender: _s(j['lender']),
        principal: _i(j['principal']),
        installmentAmount: _i(j['installmentAmount']),
        installments: _i(j['installments'], 12),
        firstDue: _p(j['firstDue']),
        accountId: _sn(j['accountId']),
        note: _s(j['note']),
        closed: j['closed'] == true,
      );
}

// ---------------------------------------------------------------------------

enum ChequeDirection { received, issued }

enum ChequeStatus { pending, deposited, cleared, bounced, endorsed, cancelled }

extension ChequeStatusX on ChequeStatus {
  String get label => switch (this) {
        ChequeStatus.pending => 'در انتظار',
        ChequeStatus.deposited => 'نزد بانک (در جریان وصول)',
        ChequeStatus.cleared => 'وصول / پاس شده',
        ChequeStatus.bounced => 'برگشتی (عدم وصول)',
        ChequeStatus.endorsed => 'واگذار شده',
        ChequeStatus.cancelled => 'عودت / باطل',
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
  String? depositAccountId;
  String? endorsedTo;
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
    this.depositAccountId,
    this.endorsedTo,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'depositAccountId': depositAccountId,
        'endorsedTo': endorsedTo,
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
        depositAccountId: _sn(j['depositAccountId']),
        endorsedTo: _sn(j['endorsedTo']),
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
  String businessName;
  String businessPhone;
  String businessAddress;

  /// Opening voucher date and free-amount ledgers (moeen code -> amount on its natural side).
  DateTime? openingDate;
  Map<String, int> openingOther;

  /// Start screen: preset gradient index and optional picture file.
  int backgroundPreset;
  String backgroundImage;

  AppSettings({
    this.themeMode = 'light',
    this.currency = 'تومان',
    this.accent = 0xFF4F46E5,
    this.ownerName = '',
    this.passwordHash = '',
    this.passwordSalt = '',
    this.passwordHint = '',
    this.setupDone = false,
    this.businessName = '',
    this.businessPhone = '',
    this.businessAddress = '',
    this.openingDate,
    Map<String, int>? openingOther,
    this.backgroundPreset = 0,
    this.backgroundImage = '',
  }) : openingOther = openingOther ?? {};

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
        'businessName': businessName,
        'businessPhone': businessPhone,
        'businessAddress': businessAddress,
        'openingDate': openingDate == null ? null : _d(openingDate!),
        'openingOther': openingOther,
        'backgroundPreset': backgroundPreset,
        'backgroundImage': backgroundImage,
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
        businessName: _s(j['businessName']),
        businessPhone: _s(j['businessPhone']),
        businessAddress: _s(j['businessAddress']),
        openingDate: _pn(j['openingDate']),
        openingOther: (j['openingOther'] is Map)
            ? {for (final e in (j['openingOther'] as Map).entries) '${e.key}': _i(e.value)}
            : <String, int>{},
        backgroundPreset: _i(j['backgroundPreset']),
        backgroundImage: _s(j['backgroundImage']),
      );
}
