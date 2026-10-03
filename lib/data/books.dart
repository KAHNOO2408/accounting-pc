import 'dart:convert';
import 'dart:io';

import '../core/jalali.dart';
import 'chart.dart';
import 'journal.dart';
import 'models.dart';
import 'storage.dart';
import 'store.dart';

/// One financial book (دفتر مالی). The book `main` lives in the base data
/// folder; the others in `books/<id>`.
class BookInfo {
  String id;
  String title; // عنوان دفتر مالی
  String latin; // نام لاتین
  DateTime? start; // تاریخ شروع سال مالی
  DateTime? end; // تاریخ پایان سال مالی
  String group; // عنوان گروه
  bool deleted;

  BookInfo({required this.id, required this.title, this.latin = '', this.start, this.end, this.group = '', this.deleted = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'latin': latin,
        if (start != null) 'start': start!.toIso8601String(),
        if (end != null) 'end': end!.toIso8601String(),
        'group': group,
        if (deleted) 'deleted': true,
      };

  factory BookInfo.fromJson(Map<String, dynamic> j) => BookInfo(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        latin: '${j['latin'] ?? ''}',
        start: DateTime.tryParse('${j['start'] ?? ''}'),
        end: DateTime.tryParse('${j['end'] ?? ''}'),
        group: '${j['group'] ?? ''}',
        deleted: j['deleted'] == true,
      );
}

/// The list of financial books kept next to the data (books.json).
class BookRegistry {
  final Directory base;
  List<BookInfo> books = [];
  String current = 'main';

  BookRegistry(this.base) {
    _read();
  }

  /// Registry of the folder a store lives in.
  factory BookRegistry.of(AppStore s) => BookRegistry(baseOf(s.storage.dir));

  static Directory baseOf(Directory dataDir) {
    final parent = dataDir.parent;
    if (parent.path.endsWith('${Storage.sep}books')) return parent.parent;
    return dataDir;
  }

  static String idOf(Directory dataDir) {
    final parent = dataDir.parent;
    if (parent.path.endsWith('${Storage.sep}books')) return dataDir.path.split(Storage.sep).last;
    return 'main';
  }

  File get _file => File('${base.path}${Storage.sep}books.json');

  void _read() {
    try {
      if (_file.existsSync()) {
        final j = jsonDecode(_file.readAsStringSync());
        if (j is Map<String, dynamic>) {
          current = '${j['current'] ?? 'main'}';
          books = [for (final b in (j['books'] as List? ?? const [])) if (b is Map<String, dynamic>) BookInfo.fromJson(b)];
        }
      }
    } catch (_) {
      books = [];
    }
    if (!books.any((b) => b.id == 'main')) {
      final y = Jalali.now().year;
      books.insert(
        0,
        BookInfo(
          id: 'main',
          title: 'دفتر مالی $y',
          latin: 'mali$y',
          start: Jalali(y, 1, 1).toDateTime(),
          end: Jalali(y, 12, Jalali.monthLength(y, 12)).toDateTime(),
        ),
      );
    }
    if (!books.any((b) => b.id == current && !b.deleted)) current = 'main';
  }

  void save() {
    if (!base.existsSync()) base.createSync(recursive: true);
    _file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'current': current, 'books': books.map((b) => b.toJson()).toList()}));
  }

  List<BookInfo> get active => books.where((b) => !b.deleted).toList();
  List<BookInfo> get deleted => books.where((b) => b.deleted).toList();

  BookInfo? byId(String id) => books.where((b) => b.id == id).firstOrNull;

  Directory dirOf(String id) => id == 'main' ? base : Directory('${base.path}${Storage.sep}books${Storage.sep}$id');

  Storage storageOf(String id) {
    final d = dirOf(id);
    if (!d.existsSync()) d.createSync(recursive: true);
    return Storage(d);
  }

  AppStore open(String id) => AppStore.open(storageOf(id));

  /// ساخت دفتر مالی — an empty book, with the company details and users of [from].
  BookInfo create(BookInfo info, AppStore from, {AppStore? copyOf}) {
    info.id = 'b${DateTime.now().millisecondsSinceEpoch}';
    books.add(info);
    save();
    final s = open(info.id);
    s.settings
      ..ownerName = from.settings.ownerName
      ..businessName = from.settings.businessName
      ..businessPhone = from.settings.businessPhone
      ..businessAddress = from.settings.businessAddress
      ..passwordHash = from.settings.passwordHash
      ..passwordSalt = from.settings.passwordSalt
      ..passwordHint = from.settings.passwordHint
      ..accent = from.settings.accent
      ..openingDate = info.start
      ..setupDone = true;
    s.users = [for (final u in from.users) AppUser.fromJson(u.toJson())];
    final src = copyOf;
    if (src != null) {
      // ساخت دفتر مالی از روی دفتر منتخب — master data without the documents
      s.accounts = [for (final a in src.accounts) Account.fromJson(a.toJson())..opening = 0];
      s.categories = [for (final c in src.categories) TxnCategory.fromJson(c.toJson())];
      s.people = [for (final p in src.people) Person.fromJson(p.toJson())..opening = 0];
      s.products = [
        for (final p in src.products)
          Product.fromJson(p.toJson())
            ..openingQty = 0
            ..openingCost = 0,
      ];
      s.warehouses = [for (final w in src.warehouses) Warehouse.fromJson(w.toJson())];
      s.docCenters = [...src.docCenters];
      s.reportLayouts = [for (final l in src.reportLayouts) l.copy()];
      s.printTemplates = [for (final t in src.printTemplates) PrintTemplate.fromJson(t.toJson())];
    }
    s.saveNow();
    return info;
  }

  /// انتقال حسابهای دفتر به دفتر جدید — carries the closing balances of [from]
  /// into the opening balances of book [toId].
  void transferBalances(AppStore from, String toId) {
    final to = open(toId);
    T upsert<T>(List<T> list, bool Function(T) same, T Function() make) {
      final e = list.where(same).firstOrNull;
      if (e != null) return e;
      final n = make();
      list.add(n);
      return n;
    }

    for (final a in from.accounts) {
      final t = upsert(to.accounts, (x) => x.id == a.id, () => Account.fromJson(a.toJson()));
      t.opening = from.balance(a.id);
    }
    for (final c in from.categories) {
      upsert(to.categories, (x) => x.id == c.id, () => TxnCategory.fromJson(c.toJson()));
    }
    for (final p in from.people) {
      final t = upsert(to.people, (x) => x.id == p.id, () => Person.fromJson(p.toJson()));
      t.opening = from.personBalance(p.id);
    }
    for (final p in from.products) {
      final t = upsert(to.products, (x) => x.id == p.id, () => Product.fromJson(p.toJson()));
      final q = from.stock(p.id);
      t
        ..openingQty = q
        ..openingCost = q > 0 ? from.avgCost(p.id) : 0;
    }
    for (final w in from.warehouses) {
      upsert(to.warehouses, (x) => x.id == w.id, () => Warehouse.fromJson(w.toJson()));
    }
    // cheques still in progress stay open in the new book
    for (final c in from.cheques.where((c) => c.status == ChequeStatus.pending || c.status == ChequeStatus.deposited)) {
      upsert(to.cheques, (x) => x.id == c.id, () => Cheque.fromJson(c.toJson()));
    }
    // free (non-entity) balance sheet ledgers
    final dr = <String, int>{};
    for (final p in buildJournal(from)) {
      dr[p.moeen] = (dr[p.moeen] ?? 0) + p.debit - p.credit;
    }
    final other = <String, int>{};
    for (final m in allMoeens) {
      if (m.hasEntity || m.code == mCapital) continue;
      if (m.side == Side.income || m.side == Side.expense) continue;
      final d = dr[m.code] ?? 0;
      final b = m.debitNature ? d : -d;
      if (b != 0) other[m.code] = b;
    }
    to.settings.openingOther = other;
    final info = byId(toId);
    to.settings
      ..openingDate = info?.start ?? to.settings.openingDate
      ..setupDone = true;
    if (to.settings.businessName.isEmpty) to.settings.businessName = from.settings.businessName;
    if (to.settings.ownerName.isEmpty) to.settings.ownerName = from.settings.ownerName;
    to.saveNow();
  }
}
