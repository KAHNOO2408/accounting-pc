import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../pages/vouchers_page.dart';
import '../print.dart';
import '../report/report_designer.dart';
import '../report/report_render.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'misc_dialogs.dart';
import 'product_dialog.dart';
import 'simple_dialogs.dart';

// ================================================================ colors & small widgets

const _sky = Color(0xFFDCEBFA);
const _skyDark = Color(0xFF9DC3EA);
const _selBlue = Color(0xFF2F6FDE);
const _yellow = Color(0xFFF3E37C);

/// بدهکار (they owe) = blue, بستانکار / طلبکار = red, zero = normal.
const debtorBlue = Color(0xFF1F3BB3);
const creditorRed = Color(0xFFD32F2F);

Color? balanceColor(int debitPositive) => debitPositive > 0 ? debtorBlue : (debitPositive < 0 ? creditorRed : null);

Widget _kb(String label, VoidCallback? onTap, {String key = '', IconData? icon, Color? color, double? height, int lines = 1}) {
  final b = OutlinedButton(
    style: OutlinedButton.styleFrom(
      backgroundColor: color ?? Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      minimumSize: Size(0, height ?? 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: const BorderSide(color: _skyDark),
    ),
    onPressed: onTap,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (key.isNotEmpty) ...[
        Text(key, style: const TextStyle(fontSize: 11, color: Color(0xFFD84315), fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
      ],
      if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
      Flexible(
        child: lines > 1
            ? Text(label, textAlign: TextAlign.center, maxLines: lines, overflow: TextOverflow.ellipsis)
            : FittedBox(fit: BoxFit.scaleDown, child: Text(label, textAlign: TextAlign.center, maxLines: 1)),
      ),
    ]),
  );
  return height == null ? b : SizedBox(height: height, child: b);
}

Widget _lbl(String t) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

Widget _hcell(String t, double w, {Color? color, Color? fg}) {
  final c = Container(
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, border: const Border(left: BorderSide(color: Colors.black12))),
    child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

Widget _cell(Widget child, double w, {Alignment align = Alignment.center}) {
  final c = Container(
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black12))),
    child: child,
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

/// Group box with its caption under the buttons, like Sakan's ribbon groups.
Widget _group(String title, Widget child) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.55), border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        child,
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );

class _Win extends StatelessWidget {
  final String title;
  final Widget body;
  final double width;
  const _Win({required this.title, required this.body, this.width = 1200});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      backgroundColor: _sky,
      child: SizedBox(
        width: width,
        height: (size.height * 0.94).clamp(460.0, 900.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HeaderBand(
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15), overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

// ================================================================ فیلتر تاریخ سند

class DateFilter {
  final DateTime? from;
  final DateTime? to;
  final int? color; // شماره رنگ
  final bool onModified; // اعمال روی تاریخ اصلاح سند
  const DateFilter({this.from, this.to, this.color, this.onModified = false});

  bool get isEmpty => from == null && to == null && color == null;

  bool hasDate(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (from != null && day.isBefore(DateTime(from!.year, from!.month, from!.day))) return false;
    if (to != null && day.isAfter(DateTime(to!.year, to!.month, to!.day))) return false;
    return true;
  }
}

/// «فیلتر تاریخ سند»: روزانه / ماهانه / از تاریخ تا تاریخ / شماره رنگ.
/// Returns null when cancelled; an empty filter for «از ابتدا تا انتها».
Future<DateFilter?> showDocDateFilter(BuildContext context, {DateFilter current = const DateFilter(), bool modifiedOption = false}) {
  var mode = current.color != null ? 3 : (current.from != null || current.to != null ? 2 : 0);
  DateTime? from = current.from, to = current.to;
  var color = current.color ?? 1;
  var modified = current.onModified;
  return showDialog<DateFilter>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      DateFilter result() {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        switch (mode) {
          case 0:
            return DateFilter(from: today, to: today, onModified: modified);
          case 1:
            final j = Jalali.fromDateTime(now);
            return DateFilter(from: Jalali(j.year, j.month, 1).toDateTime(), to: today, onModified: modified);
          case 2:
            return DateFilter(from: from, to: to, onModified: modified);
          default:
            return DateFilter(color: color, onModified: modified);
        }
      }

      Widget radio(int v, String label) => InkWell(
            onTap: () => set(() => mode = v),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(mode == v ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: mode == v ? debtorBlue : Colors.black45),
              const SizedBox(width: 4),
              Text(label),
            ]),
          );
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f9): () => Navigator.pop(ctx, result()),
          const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(ctx),
        },
        child: Dialog(
          backgroundColor: _sky,
          child: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
                child: Row(children: [
                  const Expanded(child: Text('فیلتر تاریخ سند', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(4)),
                      child: const Text('جستجو', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [radio(0, 'روزانه'), const SizedBox(width: 30), radio(1, 'ماهانه')]),
                  const SizedBox(height: 10),
                  Row(children: [
                    SizedBox(width: 130, child: radio(2, 'از تاریخ تا تاریخ')),
                    Expanded(
                      child: DateField(
                          label: 'تاریخ ابتدا',
                          value: from,
                          clearable: true,
                          onChanged: (d) => set(() {
                                from = d;
                                mode = 2;
                              })),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DateField(
                          label: 'تاریخ انتها',
                          value: to,
                          clearable: true,
                          onChanged: (d) => set(() {
                                to = d;
                                mode = 2;
                              })),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    SizedBox(width: 130, child: radio(3, 'شماره رنگ')),
                    Container(
                      height: 34,
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 60, child: Text('$color', textAlign: TextAlign.center)),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          InkWell(onTap: () => set(() {
                                color++;
                                mode = 3;
                              }), child: const Icon(Icons.arrow_drop_up, size: 16)),
                          InkWell(onTap: () => set(() {
                                if (color > 0) color--;
                                mode = 3;
                              }), child: const Icon(Icons.arrow_drop_down, size: 16)),
                        ]),
                      ]),
                    ),
                  ]),
                  if (modifiedOption) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => set(() => modified = !modified),
                      child: Row(children: [
                        Checkbox(value: modified, onChanged: (v) => set(() => modified = v ?? false)),
                        const Text('اعمال روی تاریخ اصلاح سند'),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(children: [
                    _kb('از ابتدا تا انتها', () => Navigator.pop(ctx, const DateFilter())),
                    const Spacer(),
                    _kb('تایید', () => Navigator.pop(ctx, result()), key: 'F9', color: const Color(0xFFD7F2D7), height: 40),
                    const SizedBox(width: 8),
                    _kb('انصراف', () => Navigator.pop(ctx), key: 'F10', height: 40),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      );
    }),
  );
}

/// «جستجو» — asks «جستجو بر اساس:».
Future<String?> showSearchBy(BuildContext context, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => Navigator.pop(ctx, c.text),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(ctx),
      },
      child: Dialog(
        backgroundColor: _sky,
        child: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HeaderBand(
              padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
              child: Row(children: [
                const Expanded(child: Text('جستجو', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('جستجو بر اساس:', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: c,
                  autofocus: true,
                  decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, hintText: 'شرح، شماره سند یا مبلغ'),
                  onSubmitted: (_) => Navigator.pop(ctx, c.text),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  const Spacer(),
                  _kb('تایید', () => Navigator.pop(ctx, c.text), key: 'F9', color: const Color(0xFFD7F2D7), height: 40),
                  const SizedBox(width: 8),
                  _kb('انصراف', () => Navigator.pop(ctx), key: 'F10', height: 40),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ================================================================ account categories

class AccCat {
  final String label;
  final String shortcut;
  final List<String> moeens;
  final bool people;
  const AccCat(this.label, this.moeens, {this.shortcut = '', this.people = false});
}

const _personMoeens = [mDebtorsTrade, mCreditorsTrade];

/// The category buttons of «انتخاب دفتر تفصیلی», in Sakan's order (3 rows).
const List<List<AccCat>> accCategories = [
  [
    AccCat('صندوق', [mCash]),
    AccCat('اسناد وصولی نزد صندوق', [mChequesAtCash]),
    AccCat('بانک', [mBank], shortcut: 'F5'),
    AccCat('اسناد پرداختنی بانک', [mChequesPayable]),
    AccCat('اسناد دریافتنی نزد بانک', [mChequesAtBank], shortcut: 'F6'),
    AccCat('اشخاص', _personMoeens, people: true),
    AccCat('سایر اشخاص', [mDebtorsOther, mOtherPersonsDr, mCreditorsOther, mOtherPersonsCr], shortcut: 'F7'),
    AccCat('سایر کل ها', [], shortcut: 'F8'),
    AccCat('پیش دریافت ها', ['20501'], shortcut: 'F11'),
    AccCat('پیش پرداخت ها', ['10701']),
  ],
  [
    AccCat('صاحبان سهام', [mCapital, mPartners]),
    AccCat('تنخواه گردان', [mPettyCash]),
    AccCat('صندوق ارزی', [mCashFx]),
    AccCat('اسناد دریافتنی نزد صندوق ارزی', []),
    AccCat('بانک ارزی', [mBankFx]),
    AccCat('اسناد پرداختنی بانکی ارزی', []),
    AccCat('اسناد دریافتنی نزد بانک ارزی', []),
    AccCat('اشخاص ارزی', [mDebtorsFx, mCreditorsFx]),
    AccCat('پیش پرداخت های ارزی', []),
    AccCat('پیش دریافت های ارزی', []),
  ],
  [
    AccCat('حساب های انتظامی', []),
    AccCat('طرف حساب های انتظامی', []),
    AccCat('مجموعه اشخاص', [..._personMoeens, mPartners], people: true),
    AccCat('پرسنل', []),
    AccCat('سایر حقوق صاحبان سهام', ['30102', mRetained]),
  ],
];

/// Moeens of «سایر کل ها»: every ledger no other button covers.
List<String> _otherMoeens() {
  final used = <String>{for (final row in accCategories) for (final c in row) ...c.moeens};
  return [for (final m in allMoeens) if (!used.contains(m.code)) m.code];
}

/// One account (دفتر) in the table.
class AccRow {
  final String key;
  final String code;
  final String kol;
  final String moeen;
  final String name;
  final int balance; // debit positive
  final Set<String> moeens;
  final String? tafsili;
  final Person? person;
  final Account? account;
  final Product? product;
  const AccRow({
    required this.key,
    required this.code,
    required this.kol,
    required this.moeen,
    required this.name,
    required this.balance,
    required this.moeens,
    this.tafsili,
    this.person,
    this.account,
    this.product,
  });

  bool owns(Posting p) => moeens.contains(p.moeen) && (tafsili == null || p.tafsiliId == tafsili);
}

Map<String, int> _balances(List<Posting> journal) {
  final m = <String, int>{};
  for (final p in journal) {
    final k = '${p.moeen}|${p.tafsiliId ?? ''}';
    m[k] = (m[k] ?? 0) + p.debit - p.credit;
    m[p.moeen] = (m[p.moeen] ?? 0) + p.debit - p.credit;
  }
  return m;
}

List<AccRow> accountRows(AppStore s, AccCat c, Map<String, int> bal) {
  final out = <AccRow>[];
  if (c.people) {
    for (final p in s.peopleSorted) {
      final b = c.moeens.fold<int>(0, (a, m) => a + (bal['$m|${p.id}'] ?? 0));
      out.add(AccRow(
          key: 'p:${p.id}', code: '${p.code}', kol: c.label == 'اشخاص' ? 'اشخاص' : 'مجموعه اشخاص', moeen: 'اشخاص', name: p.name, balance: b,
          moeens: c.moeens.toSet(), tafsili: p.id, person: p));
    }
    return out;
  }
  final moeens = c.label == 'سایر کل ها' ? _otherMoeens() : c.moeens;
  for (final code in moeens) {
    final m = findMoeen(code);
    if (m == null) continue;
    switch (m.kind) {
      case TafsiliKind.cash || TafsiliKind.bank:
        final type = m.kind == TafsiliKind.cash ? AccountType.cash : null;
        var i = 0;
        for (final a in s.accounts) {
          final isCash = a.type == AccountType.cash;
          if ((type == AccountType.cash) != isCash) continue;
          i++;
          out.add(AccRow(
              key: 'a:${a.id}', code: '${m.kind == TafsiliKind.cash ? 100 + i : 200 + i}', kol: m.kol.name, moeen: m.name, name: a.name,
              balance: bal['$code|${a.id}'] ?? 0, moeens: {code}, tafsili: a.id, account: a));
        }
      case TafsiliKind.person:
        for (final p in s.peopleSorted) {
          final b = bal['$code|${p.id}'];
          if (b == null) continue;
          out.add(AccRow(
              key: '$code|${p.id}', code: '${p.code}', kol: m.kol.name, moeen: m.name, name: p.name, balance: b, moeens: {code}, tafsili: p.id, person: p));
        }
      case TafsiliKind.product:
        for (final p in s.productsSorted) {
          final b = bal['$code|${p.id}'];
          if (b == null) continue;
          out.add(AccRow(
              key: '$code|${p.id}', code: p.code, kol: m.kol.name, moeen: m.name, name: p.name, balance: b, moeens: {code}, tafsili: p.id, product: p));
        }
      case TafsiliKind.incomeCat || TafsiliKind.expenseCat:
        for (final cat in s.categoriesOf(m.kind == TafsiliKind.incomeCat ? CategoryKind.income : CategoryKind.expense)) {
          final b = bal['$code|${cat.id}'];
          if (b == null) continue;
          out.add(AccRow(key: '$code|${cat.id}', code: code, kol: m.kol.name, moeen: m.name, name: cat.name, balance: b, moeens: {code}, tafsili: cat.id));
        }
        final rest = bal['$code|'];
        if (rest != null) {
          out.add(AccRow(key: '$code|', code: code, kol: m.kol.name, moeen: m.name, name: m.name, balance: rest, moeens: {code}, tafsili: ''));
        }
      case TafsiliKind.none:
        out.add(AccRow(key: code, code: code, kol: m.kol.name, moeen: m.name, name: m.name, balance: bal[code] ?? 0, moeens: {code}));
    }
  }
  return out;
}

// ================================================================ انتخاب دفتر تفصیلی (جدول و مشاهده حسابها)

/// Sakan's «انتخاب دفتر تفصیلی» window. With [pick] تایید returns the chosen account.
Future<AccRow?> showAccountSelector(BuildContext context, {bool pick = false, String category = 'اشخاص'}) =>
    showDialog<AccRow>(context: context, builder: (_) => _AccountSelector(pick: pick, category: category));

class _AccountSelector extends StatefulWidget {
  final bool pick;
  final String category;
  const _AccountSelector({this.pick = false, this.category = 'اشخاص'});

  @override
  State<_AccountSelector> createState() => _AccountSelectorState();
}

class _AccountSelectorState extends State<_AccountSelector> {
  late AccCat _cat = accCategories.expand((r) => r).firstWhere((c) => c.label == widget.category, orElse: () => accCategories[0][5]);
  final _search = TextEditingController();
  final _codeSearch = TextEditingController();
  final _scroll = ScrollController();
  String? _sel;

  static const double _bw = 190; // one button column on the left edge
  static const double _bh = 36;
  static const double _gap = 4;

  Widget _fixed(Widget child) => SizedBox(width: _bw, height: _bh, child: child);
  int _side = 0; // 0 همه، 1 بدهکاران (آبی)، 2 بستانکاران (قرمز)
  bool _nonZero = false; // فیلتر
  bool _sortByBalance = false; // مانده دفتر
  String? _kolFilter, _moeenFilter;
  int _code = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _codeSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _codeSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<AccRow> _rows(AppStore s) {
    final all = accountRows(s, _cat, _balances(buildJournal(s)));
    final q = normalizeDigits(_search.text.trim()).toLowerCase();
    var list = all.where((r) {
      if (_kolFilter != null && r.kol != _kolFilter) return false;
      if (_moeenFilter != null && r.moeen != _moeenFilter) return false;
      if (_nonZero && r.balance == 0) return false;
      if (_side == 1 && r.balance <= 0) return false;
      if (_side == 2 && r.balance >= 0) return false;
      final code = normalizeDigits(_codeSearch.text.trim());
      if (code.isNotEmpty && !r.code.startsWith(code)) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) || r.code.contains(q);
    }).toList();
    if (_sortByBalance) list.sort((a, b) => b.balance.compareTo(a.balance));
    return list;
  }

  AccRow? _current(List<AccRow> rows) => rows.where((r) => r.key == _sel).firstOrNull ?? rows.firstOrNull;

  void _select(AccCat c) => setState(() {
        _cat = c;
        _sel = null;
        _kolFilter = null;
        _moeenFilter = null;
      });

  void _view(AccRow? r) {
    if (r == null) return toast(context, 'حسابی انتخاب نشده', error: true);
    showAccountLedger(context, r);
  }

  Future<void> _info(AccRow? r) async {
    if (r == null) return;
    if (r.person != null) {
      await showPersonDialog(context, edit: r.person);
    } else if (r.account != null) {
      await showAccountDialog(context, edit: r.account);
    } else if (r.product != null) {
      await showProductDialog(context, edit: r.product);
    } else {
      toast(context, 'این دفتر اطلاعات قابل ویرایش ندارد');
    }
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final m = _cat.moeens.isEmpty ? null : findMoeen(_cat.moeens.first);
    if (_cat.people || m?.kind == TafsiliKind.person) {
      final id = await showPersonDialog(context);
      if (id != null) setState(() => _sel = 'p:$id');
    } else if (m?.kind == TafsiliKind.cash) {
      await showAccountDialog(context, type: AccountType.cash);
    } else if (m?.kind == TafsiliKind.bank) {
      await showAccountDialog(context);
    } else {
      toast(context, 'برای این گروه دفتر جدید از «کدبندی دفاتر» اضافه می‌شود');
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(AppStore s, AccRow? r) async {
    if (r?.person == null) return toast(context, 'فقط دفتر اشخاص از اینجا حذف می‌شود', error: true);
    final p = r!.person!;
    if (s.personInUse(p.id)) return toast(context, '«${p.name}» در اسناد استفاده شده و حذف نمی‌شود', error: true);
    final ok = await confirm(context, 'حذف دفتر', '«${p.name}» حذف شود؟');
    if (ok) {
      s.removePerson(p.id);
      setState(() => _sel = null);
    }
  }

  void _related(AppStore s, AccRow? r) {
    if (r?.tafsili == null) return toast(context, 'این دفتر حساب مربوطه ندارد');
    final bal = _balances(buildJournal(s));
    final rows = <(Moeen, int)>[];
    for (final m in allMoeens) {
      final b = bal['${m.code}|${r!.tafsili}'];
      if (b != null) rows.add((m, b));
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'حسابهای مربوطه — ${r!.name}',
        width: 560,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: rows.isEmpty
            ? const Text('گردشی ثبت نشده')
            : Column(children: [
                for (final (m, b) in rows)
                  ListTile(
                    dense: true,
                    title: Text('${m.kol.name} / ${m.name}'),
                    subtitle: Text(m.code),
                    trailing: Text(groupDigits(b.abs()) + (b < 0 ? '-' : ''),
                        textDirection: TextDirection.ltr, style: TextStyle(color: balanceColor(b), fontWeight: FontWeight.w800)),
                  ),
              ]),
      ),
    );
  }

  void _centers(AppStore s, AccRow? r) {
    if (r == null) return;
    final keys = buildJournal(s).where(r.owns).map((p) => p.docKey).whereType<String>().toSet();
    final c = <String, int>{};
    for (final k in keys) {
      final n = s.docMeta[k]?.center ?? '';
      c[n.isEmpty ? 'بدون مرکز' : n] = (c[n.isEmpty ? 'بدون مرکز' : n] ?? 0) + 1;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'مراکز دفاتر مربوطه — ${r.name}',
        width: 460,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: c.isEmpty
            ? const Text('سندی برای این دفتر ثبت نشده')
            : Column(children: [for (final e in c.entries) ListTile(dense: true, title: Text(e.key), trailing: Text('${e.value} سند'))]),
      ),
    );
  }

  void _installments(AppStore s, AccRow? r) {
    if (r?.person == null) return toast(context, 'اقساط فقط برای اشخاص است');
    final list = s.cheques.where((c) => c.personId == r!.person!.id && c.status == ChequeStatus.pending).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'اقساط مربوطه — ${r!.name}',
        width: 560,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: list.isEmpty
            ? const Text('قسط یا چک سررسید نشده‌ای وجود ندارد')
            : Column(children: [
                for (final c in list)
                  ListTile(
                    dense: true,
                    leading: Icon(c.direction == ChequeDirection.received ? Icons.call_received_rounded : Icons.call_made_rounded),
                    title: Text('${c.direction == ChequeDirection.received ? 'چک دریافتی' : 'چک پرداختی'} ${c.serial}'),
                    subtitle: Text('سررسید ${jFormat(c.dueDate)}'),
                    trailing: Text(groupDigits(c.amount), textDirection: TextDirection.ltr),
                  ),
              ]),
      ),
    );
  }

  void _notebook(AppStore s, AccRow? r) {
    if (r == null) return;
    showNotebook(context, r);
  }

  void _ok(List<AccRow> rows) {
    final r = _current(rows);
    if (widget.pick) {
      if (r != null) Navigator.pop(context, r);
    } else {
      _view(r);
    }
  }

  void _move(List<AccRow> rows, int d) {
    if (rows.isEmpty) return;
    final i = (rows.indexWhere((r) => r.key == _current(rows)?.key) + d).clamp(0, rows.length - 1);
    setState(() => _sel = rows[i].key);
    if (_scroll.hasClients) _scroll.jumpTo((i * 34.0 - 140).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = _rows(s);
    final cur = _current(rows);
    final debit = rows.fold<int>(0, (a, r) => a + (r.balance > 0 ? r.balance : 0));
    final credit = rows.fold<int>(0, (a, r) => a + (r.balance < 0 ? -r.balance : 0));
    final allRows = accountRows(s, _cat, _balances(buildJournal(s)));
    final kols = {for (final r in allRows) r.kol}.toList();
    final moeens = {for (final r in allRows) if (_kolFilter == null || r.kol == _kolFilter) r.moeen}.toList();
    AccCat? byKey(String k) => accCategories.expand((r) => r).where((c) => c.shortcut == k).firstOrNull;

    Widget catButton(AccCat c) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: SizedBox(
              height: 54,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: identical(c, _cat) ? const Color(0xFFFFC77A) : const Color(0xFFEAF3FC),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  side: const BorderSide(color: _skyDark),
                ),
                onPressed: () => _select(c),
                child: Text('${c.label}${c.shortcut.isEmpty ? '' : ' ${c.shortcut}'}',
                    textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ),
            ),
          ),
        );

    Widget sideBar(int side, int value, Color color) => InkWell(
          onTap: () => setState(() => _side = _side == side ? 0 : side),
          child: Container(
            height: _bh,
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black26)),
            child: Row(children: [
              Icon(_side == side ? Icons.radio_button_checked : Icons.circle, size: 14, color: Colors.white),
              const Spacer(),
              Text(groupDigits(value), textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        );

    Widget dd(String? value, List<String> items, String hint, ValueChanged<String?> on) => SizedBox(
          width: 210,
          height: _bh,
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
            hint: Text(hint),
            items: [DropdownMenuItem<String>(value: null, child: Text(hint)), for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
            onChanged: on,
          ),
        );

    const w = [44.0, 90.0, 150.0, 150.0, 0.0, 190.0];
    return CallbackShortcuts(
      bindings: {
        for (final k in ['F5', 'F6', 'F7', 'F8', 'F11'])
          SingleActivator(switch (k) {
            'F5' => LogicalKeyboardKey.f5,
            'F6' => LogicalKeyboardKey.f6,
            'F7' => LogicalKeyboardKey.f7,
            'F8' => LogicalKeyboardKey.f8,
            _ => LogicalKeyboardKey.f11,
          }): () {
            final c = byKey(k);
            if (c != null) _select(c);
          },
        const SingleActivator(LogicalKeyboardKey.f2): () => showComingSoon(context, 'رویت امانی های دریافتی'),
        const SingleActivator(LogicalKeyboardKey.f3): () => _view(cur),
        const SingleActivator(LogicalKeyboardKey.f9): () => _ok(rows),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(rows, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(rows, -1),
      },
      child: _Win(
        title: 'انتخاب دفتر تفصیلی',
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final row in accCategories)
              Row(children: [
                for (final c in row) catButton(c),
                if (row.length < 10) Spacer(flex: 10 - row.length),
              ]),
            const SizedBox(height: 6),
            // ---------------------------------------------------- filters and totals
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      SizedBox(width: 90, child: _kb(_nonZero ? 'فیلتر ✓' : 'فیلتر', () => setState(() => _nonZero = !_nonZero), height: _bh * 2 + _gap)),
                      const SizedBox(width: _gap),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 90, height: _bh, child: _kb('عنوان حساب', () {}, color: const Color(0xFFF1F1F1))),
                          const SizedBox(width: 2),
                          dd(_kolFilter, kols, 'کل ها', (v) => setState(() {
                                _kolFilter = v;
                                _moeenFilter = null;
                              })),
                        ]),
                        const SizedBox(height: _gap),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 90, height: _bh, child: _kb('عنوان حساب', () {}, color: const Color(0xFFF1F1F1))),
                          const SizedBox(width: 2),
                          dd(_moeenFilter, moeens, 'معین ها', (v) => setState(() => _moeenFilter = v)),
                        ]),
                      ]),
                      const SizedBox(width: _gap),
                      SizedBox(
                        width: 80,
                        child: _kb('خالی', () {
                          _search.clear();
                          _codeSearch.clear();
                          setState(() {
                            _kolFilter = null;
                            _moeenFilter = null;
                            _side = 0;
                            _nonZero = false;
                          });
                        }, height: _bh * 2 + _gap),
                      ),
                      const SizedBox(width: _gap),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        sideBar(1, debit, const Color(0xFF2346D8)),
                        const SizedBox(height: _gap),
                        sideBar(2, credit, const Color(0xFFC62828)),
                      ]),
                      const SizedBox(width: _gap),
                      InkWell(
                        onTap: () => setState(() => _side = 0),
                        child: Container(
                          width: 44,
                          height: _bh,
                          color: Colors.black12,
                          child: Icon(_side == 0 ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              // buttons pinned to the left edge, all the same size
              Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _fixed(_kb('رویت امانی های پرداختی', () => showComingSoon(context, 'رویت امانی های پرداختی'), height: _bh)),
                  const SizedBox(width: _gap),
                  _fixed(_kb('اطلاعات دفتر', () => _info(cur), height: _bh)),
                  const SizedBox(width: _gap),
                  _fixed(_kb('افزودن', _add, height: _bh)),
                ]),
                const SizedBox(height: _gap),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _fixed(_kb('رویت امانی های دریافتی', () => showComingSoon(context, 'رویت امانی های دریافتی'), key: 'F2', height: _bh)),
                  const SizedBox(width: _gap),
                  _fixed(_kb('رویت حساب', () => _view(cur), key: 'F3', color: const Color(0xFFFFE0B2), height: _bh)),
                  const SizedBox(width: _gap),
                  _fixed(_kb('حذف', () => _delete(s, cur), height: _bh)),
                ]),
              ]),
            ]),
            const SizedBox(height: _gap),
            Row(children: [
              _lbl('کد دفتر:'),
              Container(
                height: _bh,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 70, child: Text('$_code', textAlign: TextAlign.center)),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    InkWell(onTap: () => setState(() => _jumpCode(rows, _code + 1)), child: const Icon(Icons.arrow_drop_up, size: 16)),
                    InkWell(onTap: () => setState(() => _jumpCode(rows, _code > 0 ? _code - 1 : 0)), child: const Icon(Icons.arrow_drop_down, size: 16)),
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              _lbl('جستجو:'),
              Expanded(
                child: SizedBox(
                  height: _bh,
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white),
                    onSubmitted: (_) => _ok(rows),
                  ),
                ),
              ),
              const SizedBox(width: _gap),
              Tooltip(
                message: 'نام یا کد دفتر را تایپ کنید؛ Enter یا F3 حساب را باز می‌کند',
                child: SizedBox(width: 40, child: _kb('?', () {}, height: _bh)),
              ),
              const SizedBox(width: _gap),
              SizedBox(width: 120, child: _kb(_sortByBalance ? 'مانده دفتر ↓' : 'مانده دفتر', () => setState(() => _sortByBalance = !_sortByBalance), height: _bh)),
              const SizedBox(width: _gap),
              // pinned to the left edge, aligned with the button columns above
              _fixed(_kb('عنوان حساب', () => _codeSearch.clear(), color: const Color(0xFFF1F1F1), height: _bh)),
              const SizedBox(width: _gap),
              _fixed(SizedBox(
                height: _bh,
                child: TextField(
                  controller: _codeSearch,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, hintText: 'شناسه'),
                  onSubmitted: (_) => _ok(rows),
                ),
              )),
              const SizedBox(width: _gap),
              _fixed(_kb('تنظیم جمع مبالغ اسناد', () {
                setState(() {});
                toast(context, 'جمع مبالغ اسناد دوباره محاسبه شد');
              }, height: _bh)),
            ]),
            const SizedBox(height: 6),
            // ---------------------------------------------------- grid
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    color: const Color(0xFFEFF5FC),
                    child: Row(children: [
                      _hcell('چاپ', w[0], color: const Color(0xFFE53935), fg: Colors.white),
                      _hcell('کد', w[1]),
                      _hcell('عنوان کل', w[2]),
                      _hcell('عنوان معین', w[3]),
                      _hcell('عنوان حساب', w[4]),
                      _hcell('مانده حساب', w[5]),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: rows.isEmpty
                        ? const EmptyState(icon: Icons.account_tree_outlined, text: 'دفتری در این گروه وجود ندارد')
                        : ListView.builder(
                            controller: _scroll,
                            itemExtent: 34,
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final sel = r.key == cur?.key;
                              final fg = balanceColor(r.balance);
                              return Material(
                                color: sel ? _yellow : (i.isOdd ? const Color(0xFFF6FAFE) : Colors.white),
                                child: InkWell(
                                  onTap: () => setState(() => _sel = r.key),
                                  onDoubleTap: () {
                                    setState(() => _sel = r.key);
                                    widget.pick ? Navigator.pop(context, r) : _view(r);
                                  },
                                  child: DefaultTextStyle.merge(
                                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                                    child: Row(children: [
                                      _cell(const SizedBox(), w[0]),
                                      _cell(Text(r.code), w[1]),
                                      _cell(Text(r.kol, maxLines: 1, overflow: TextOverflow.ellipsis), w[2]),
                                      _cell(Text(r.moeen, maxLines: 1, overflow: TextOverflow.ellipsis), w[3]),
                                      _cell(Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis), w[4], align: Alignment.centerRight),
                                      _cell(
                                          Text(r.balance == 0 ? '0' : '${groupDigits(r.balance.abs())}${r.balance < 0 ? '-' : ''}',
                                              textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
                                          w[5],
                                          align: Alignment.centerLeft),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              for (final (i, b) in [
                _kb('رویت امانی های دریافتی پرداختی', () => showComingSoon(context, 'رویت امانی های دریافتی پرداختی'), height: _bh),
                _kb('یادداشت کالا', () => _notebook(s, cur), height: _bh),
                _kb('رویت مراکز هزینه(رکورد)', () => showCostCenterPicker(context), height: _bh),
                _kb('رویت مراکز دفاتر مربوطه', () => _centers(s, cur), height: _bh),
                _kb('رویت حسابهای مربوطه', () => _related(s, cur), height: _bh),
                _kb('رویت اقساط مربوطه', () => _installments(s, cur), height: _bh),
                _kb('تایید', () => _ok(rows), key: 'F9', color: const Color(0xFFD7F2D7), height: _bh),
                _kb('انصراف', () => Navigator.pop(context), key: 'F10', color: const Color(0xFFFBE0E0), height: _bh),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: _gap),
                Expanded(child: b),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  void _jumpCode(List<AccRow> rows, int code) {
    _code = code;
    final r = rows.where((r) => r.code == '$code').firstOrNull;
    if (r != null) _sel = r.key;
  }
}

/// دفترچه یادداشت of an account.
Future<void> showNotebook(BuildContext context, AccRow r) async {
  final s = StoreScope.read(context);
  final c = TextEditingController(text: s.notebooks[r.key] ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'دفترچه یادداشت — ${r.name}',
      width: 560,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
      ],
      child: TextField(controller: c, autofocus: true, minLines: 8, maxLines: 14, decoration: const InputDecoration(hintText: 'یادداشت های این حساب')),
    ),
  );
  if (ok == true) s.saveNotebook(r.key, c.text);
  c.dispose();
}

// ================================================================ مشاهده اسناد (ledger of one account)

Future<void> showAccountLedger(BuildContext context, AccRow r) =>
    showDialog<void>(context: context, builder: (_) => _Ledger(acc: r));

class _LRow {
  final Posting p;
  final int index; // ردیف (1-based, over the whole account)
  final int balance; // running, debit positive
  final String mark;
  _LRow(this.p, this.index, this.balance, this.mark);
}

class _Ledger extends StatefulWidget {
  final AccRow acc;
  const _Ledger({required this.acc});

  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  int? _sel;
  DateFilter _date = const DateFilter();
  String _type = 'تمامی اسناد';
  String _center = '*';
  final _desc = TextEditingController();
  String _descApplied = '';
  String _find = '';
  bool _onlyMarked = false;
  final _hidden = <int>{};
  final _scroll = ScrollController();
  bool _printNotes = false, _printSpec = false;
  CostFilter? _cost; // فیلتر مرکز هزینه(رکورد)
  final _specCtl = TextEditingController();
  String? _specKey;

  static const _types = ['تمامی اسناد', 'بدون مشخصه', 'با مشخصه'];
  static const _cols = ['ردیف', 'رنگ', 'ش س', 'تاریخ', 'شرح سند', 'بدهکار', 'بستانکار', 'ت', 'مانده', 'شماره ثابت'];
  static const _w = [56.0, 44.0, 70.0, 96.0, 0.0, 130.0, 130.0, 36.0, 140.0, 80.0];

  @override
  void dispose() {
    _specCtl.dispose();
    _desc.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_LRow> _all(AppStore s) {
    final marks = s.marks[widget.acc.key] ?? const <String>{};
    final out = <_LRow>[];
    var run = 0;
    var i = 0;
    for (final p in buildJournal(s).where(widget.acc.owns)) {
      run += p.debit - p.credit;
      i++;
      final mark = '${p.docKey ?? 'open'}|${p.order}|${p.debit}|${p.credit}|${p.desc}';
      out.add(_LRow(p, i, run, marks.contains(mark) ? mark : '#$mark'));
    }
    return out;
  }

  bool _isMarked(_LRow r) => !r.mark.startsWith('#');
  String _markKey(_LRow r) => r.mark.startsWith('#') ? r.mark.substring(1) : r.mark;

  String _descOf(AppStore s, Posting p) {
    final d = p.desc.trim();
    if (p.isOpening) return d.isEmpty ? 'سند افتتاحیه' : 'سند افتتاحیه — $d';
    final k = p.docKey;
    if (k != null && k.startsWith('inv:')) {
      final inv = s.invoices.where((i) => 'inv:${i.id}' == k).firstOrNull;
      if (inv != null) {
        final word = switch (inv.kind) {
          InvoiceKind.sale => 'فروش',
          InvoiceKind.purchase => 'خرید',
          InvoiceKind.saleReturn => 'برگشت از فروش',
          InvoiceKind.purchaseReturn => 'برگشت از خرید',
        };
        final first = inv.lines.isEmpty ? '' : (s.product(inv.lines.first.productId)?.name ?? inv.lines.first.title);
        return 'فاکتور ${groupDigits(inv.number)}  $word  $first${d.isEmpty || d == inv.note ? '' : '  $d'}';
      }
    }
    return d.isEmpty ? p.docLabel : (d.contains(p.docLabel) ? d : '${p.docLabel} — $d');
  }

  bool _typeOk(AppStore s, Posting p) {
    final spec = p.docKey == null ? '' : (s.docMeta[p.docKey]?.spec ?? '');
    return switch (_type) {
      'بدون مشخصه' => spec.isEmpty,
      'با مشخصه' => spec.isNotEmpty,
      _ => true,
    };
  }

  List<_LRow> _shown(AppStore s, List<_LRow> all) {
    final q = normalizeDigits(_descApplied.trim()).toLowerCase();
    return all.where((r) {
      final p = r.p;
      if (!_typeOk(s, p)) return false;
      if (_onlyMarked && !_isMarked(r)) return false;
      final meta = p.docKey == null ? null : s.docMeta[p.docKey];
      if (_center != '*') {
        final c = meta?.center ?? '';
        if (_center == '-' && c.isNotEmpty) return false;
        if (_center != '-' && c != _center) return false;
      }
      if (_cost != null) {
        final cc = meta?.costCenter ?? '';
        if (cc.isEmpty ? !_cost!.none : !_cost!.centers.contains(cc)) return false;
      }
      if (_date.color != null && (meta?.color ?? 0) != _colorValue(_date.color!)) return false;
      if (!_date.hasDate(_date.onModified && meta != null && meta.modifiedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(meta.modifiedAt) : p.date)) return false;
      if (q.isNotEmpty && !normalizeDigits(_descOf(s, p)).toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  int _colorValue(int n) => n < docRowColors.length ? docRowColors[n] : -1;

  void _goTo(int i) {
    setState(() => _sel = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo((i * 34.0 - 120).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  bool _matches(AppStore s, _LRow r, String q) {
    final t = normalizeDigits(q.trim()).toLowerCase().replaceAll(',', '');
    if (t.isEmpty) return false;
    final p = r.p;
    final no = p.docKey == null ? null : s.docNumberOf(p.docKey!);
    return normalizeDigits(_descOf(s, p)).toLowerCase().contains(t) || '${no ?? p.docNo ?? ''}' == t || '${p.debit}' == t || '${p.credit}' == t;
  }

  void _findNext(AppStore s, List<_LRow> rows) {
    if (_find.isEmpty) return toast(context, 'ابتدا «گزینه های جستجو» را بزنید');
    final start = (_sel ?? -1) + 1;
    for (var k = 0; k < rows.length; k++) {
      final i = (start + k) % rows.length;
      if (_matches(s, rows[i], _find)) return _goTo(i);
    }
    toast(context, 'موردی پیدا نشد');
  }

  Future<void> _searchOptions(AppStore s, List<_LRow> rows) async {
    final q = await showSearchBy(context, initial: _find);
    if (q == null || !mounted) return;
    setState(() {
      _find = q;
      _sel = null;
    });
    _findNext(s, rows);
  }

  Future<void> _dateFilter() async {
    final r = await showDocDateFilter(context, current: _date);
    if (r != null) {
      setState(() {
        _date = r;
        _sel = null;
      });
    }
  }

  void _edit(AppStore s, _LRow? r) {
    final k = r?.p.docKey;
    if (k == null) return toast(context, 'این ردیف سند قابل ویرایش ندارد', error: true);
    if (s.docMeta[k]?.locked == true) return toast(context, 'سند قفل است', error: true);
    openDocument(context, k);
  }

  void _inDocs(_LRow? r) {
    final k = r?.p.docKey;
    if (k == null) return toast(context, 'این ردیف در لیست اسناد نیست', error: true);
    VouchersPage.focusKey = k;
    final nav = Nav.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    nav.go(AppPage.vouchers);
  }

  void _cheques(AppStore s) {
    final a = widget.acc;
    final list = s.cheques
        .where((c) => (a.person != null && c.personId == a.person!.id) || (a.account != null && (c.bankAccountId == a.account!.id || c.holderId == a.account!.id)))
        .toList()
      ..sort((x, y) => x.dueDate.compareTo(y.dueDate));
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'لیست چکها — ${a.name}',
        width: 720,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت'))],
        child: list.isEmpty
            ? const Text('چکی برای این حساب ثبت نشده')
            : Column(children: [
                for (final c in list)
                  ListTile(
                    dense: true,
                    leading: Icon(c.direction == ChequeDirection.received ? Icons.call_received_rounded : Icons.call_made_rounded,
                        color: c.direction == ChequeDirection.received ? debtorBlue : creditorRed),
                    title: Text('${c.direction == ChequeDirection.received ? 'دریافتی' : 'پرداختی'} — ${c.serial}  ${c.bank}'),
                    subtitle: Text('سررسید ${jFormat(c.dueDate)} — ${c.status.label}'),
                    trailing: Text(groupDigits(c.amount), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
      ),
    );
  }

  void _display() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'تنظیم نمایش',
          width: 380,
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
          child: Column(children: [
            for (var i = 0; i < _cols.length; i++)
              CheckboxListTile(
                dense: true,
                value: !_hidden.contains(i),
                title: Text(_cols[i]),
                onChanged: i == 4
                    ? null
                    : (v) {
                        set(() => v == true ? _hidden.remove(i) : _hidden.add(i));
                        setState(() {});
                      },
              ),
          ]),
        ),
      ),
    );
  }

  void _reconcile(AppStore s, List<_LRow> all) {
    final a = widget.acc;
    final book = all.isEmpty ? 0 : all.last.balance;
    final pending = s.cheques
        .where((c) =>
            c.status == ChequeStatus.pending &&
            ((a.person != null && c.personId == a.person!.id) || (a.account != null && c.bankAccountId == a.account!.id)))
        .toList();
    var adj = 0;
    for (final c in pending) {
      adj += c.direction == ChequeDirection.received ? -c.amount : c.amount;
    }
    String m(int v) => '${groupDigits(v.abs())}${v < 0 ? '-' : ''}';
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'صورت مغایرت — ${a.name}',
        width: 560,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(dense: true, title: const Text('مانده طبق دفاتر'), trailing: Text(m(book), textDirection: TextDirection.ltr, style: TextStyle(color: balanceColor(book)))),
          for (final c in pending)
            ListTile(
              dense: true,
              title: Text('چک ${c.direction == ChequeDirection.received ? 'دریافتی' : 'پرداختی'} وصول نشده ${c.serial}'),
              subtitle: Text('سررسید ${jFormat(c.dueDate)}'),
              trailing: Text(m(c.direction == ChequeDirection.received ? -c.amount : c.amount), textDirection: TextDirection.ltr),
            ),
          const Divider(),
          ListTile(
            dense: true,
            title: const Text('مانده پس از اعمال مغایرت ها', style: TextStyle(fontWeight: FontWeight.w800)),
            trailing: Text(m(book + adj), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: balanceColor(book + adj))),
          ),
        ]),
      ),
    );
  }

  List<String> _cells(AppStore s, _LRow r) {
    final p = r.p;
    final meta = p.docKey == null ? null : s.docMeta[p.docKey];
    final no = p.docKey == null ? null : s.docNumberOf(p.docKey!);
    final fixed = p.docKey == null ? null : s.docFixedOf(p.docKey!);
    final colorIdx = meta == null ? 0 : docRowColors.indexOf(meta.color).clamp(0, 99);
    return [
      '${r.index}',
      '$colorIdx',
      no == null ? (p.docNo == null ? '' : groupDigits(p.docNo!)) : groupDigits(no),
      jFormat(p.date),
      _descOf(s, p),
      p.debit == 0 ? '' : groupDigits(p.debit),
      p.credit == 0 ? '' : groupDigits(p.credit),
      r.balance > 0 ? 'بد' : (r.balance < 0 ? 'بس' : '-'),
      groupDigits(r.balance.abs()),
      fixed == null || fixed == 0 ? '' : '$fixed',
    ];
  }

  /// Data of «پرینت حساب»; with [carried] the first row is «منقول از قبل».
  ReportData _reportData(AppStore s, List<_LRow> all, List<_LRow> shown, {bool carried = false}) {
    final a = widget.acc;
    final st = s.settings;
    final rows = <Map<String, String>>[];
    if (carried) {
      final i = shown.isEmpty ? -1 : all.indexOf(shown.first);
      final before = i <= 0 ? 0 : all[i - 1].balance;
      rows.add({
        'ردیف': '',
        'ش س': '',
        'تاریخ سند': '',
        'شرح سند': 'منقول از قبل',
        'بدهکار': before > 0 ? groupDigits(before) : '0',
        'بستانکار': before < 0 ? groupDigits(-before) : '0',
        'مانده ردیف': groupDigits(before.abs()),
        'ت': before > 0 ? 'بد' : (before < 0 ? 'بس' : '-'),
        'شماره ثابت': '',
      });
    }
    for (final r in shown) {
      final c = _cells(s, r);
      rows.add({
        'ردیف': c[0],
        'ش س': c[2],
        'تاریخ سند': c[3],
        'شرح سند': c[4],
        'بدهکار': c[5].isEmpty ? '0' : c[5],
        'بستانکار': c[6].isEmpty ? '0' : c[6],
        'ت': c[7],
        'مانده ردیف': c[8],
        'شماره ثابت': c[9],
      });
    }
    final d = shown.fold<int>(0, (x, r) => x + r.p.debit);
    final c = shown.fold<int>(0, (x, r) => x + r.p.credit);
    return ReportData(
      title: 'گزارش حساب ${a.name}',
      fields: {
        'نام حساب': a.name,
        'کد حساب': a.code,
        'عنوان کل': a.kol,
        'عنوان معین': a.moeen,
        'نام فروشگاه': st.businessName.isEmpty ? st.ownerName : st.businessName,
        'تاریخ': jFormat(DateTime.now()),
        'از تاریخ': _date.from == null ? '' : jFormat(_date.from!),
        'تا تاریخ': _date.to == null ? '' : jFormat(_date.to!),
        'جمع بدهکار': groupDigits(d),
        'جمع بستانکار': groupDigits(c),
        'مانده': groupDigits((d - c).abs()),
        'تشخیص': d - c > 0 ? 'بد' : (d - c < 0 ? 'بس' : '-'),
      },
      rows: rows,
    );
  }

  void _print(AppStore s, List<_LRow> all, List<_LRow> shown, {bool carried = false}) {
    showReportPreview(context, s.defaultLayout(PrintDocType.ledger), _reportData(s, all, shown, carried: carried), fileName: 'ledger');
  }

  /// طراحی ▸ — edits the account print layout in the band designer.
  Future<void> _design(AppStore s, List<_LRow> all, List<_LRow> shown, {bool create = false}) async {
    final cur = s.defaultLayout(PrintDocType.ledger);
    final base = create
        ? (cur.copy()
          ..id = newId()
          ..name = 'طرح ${s.layoutsOf(PrintDocType.ledger).length + 1}')
        : cur;
    final r = await showReportDesigner(context, base, _reportData(s, all, shown));
    if (r != null) {
      s.saveLayout(r);
      s.setDefaultLayout(r);
    }
  }

  void _excel(AppStore s, List<_LRow> shown) {
    try {
      final path = s.exportTableCsv(_cols, [for (final r in shown) _cells(s, r)], name: 'ledger');
      openFile(path);
      toast(context, 'فایل اکسل ساخته شد');
    } catch (e) {
      toast(context, 'خروجی ناموفق: $e', error: true);
    }
  }

  Future<void> _printMenu(BuildContext anchor, AppStore s, List<_LRow> all, List<_LRow> shown) async {
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final rect = RelativeRect.fromLTRB(pos.dx, pos.dy + box.size.height, pos.dx + box.size.width, 0);
    final top = await showMenu<String>(context: context, position: rect, items: const [
      PopupMenuItem(value: 'show', child: Text('نمایش  ◂')),
      PopupMenuItem(value: 'design', child: Text('طراحی  ◂')),
      PopupMenuItem(value: 'excel', child: Text('خروجی به اکسل')),
    ]);
    if (!mounted || top == null) return;
    if (top == 'excel') return _excel(s, shown);
    final sub = await showMenu<String>(context: context, position: rect, items: [
      if (top == 'design') const PopupMenuItem(value: 'new', child: Text('افزودن جدید')),
      const PopupMenuItem(value: 'acc', child: Text('پرینت حساب')),
      const PopupMenuItem(value: 'carried', child: Text('پرینت حساب با منقول جدیداز قبل')),
      const PopupMenuItem(value: 'fx', child: Text('گزارش از گردش ارزی')),
    ]);
    if (!mounted || sub == null) return;
    if (sub == 'fx') return showComingSoon(context, 'گزارش از گردش ارزی');
    if (top == 'design') return _design(s, all, shown, create: sub == 'new');
    _print(s, all, shown, carried: sub == 'carried');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final a = widget.acc;
    final all = _all(s);
    final rows = _shown(s, all);
    if (_sel != null && _sel! >= rows.length) _sel = null;
    final cur = _sel == null ? null : rows[_sel!];
    final debit = rows.fold<int>(0, (x, r) => x + r.p.debit);
    final credit = rows.fold<int>(0, (x, r) => x + r.p.credit);
    final bal = debit - credit;
    final meta = cur?.p.docKey == null ? null : s.docMeta[cur!.p.docKey];
    final curInv = cur?.p.docKey?.startsWith('inv:') == true ? s.invoices.where((i) => 'inv:${i.id}' == cur!.p.docKey).firstOrNull : null;
    final curKey = cur?.p.docKey;
    if (curKey != _specKey) {
      _specKey = curKey;
      _specCtl.text = meta?.spec ?? '';
    }
    final notes = cur == null ? (s.notebooks[a.key] ?? '') : _descOf(s, cur.p) + (curInv != null && curInv.note.isNotEmpty ? '\n${curInv.note}' : '');
    final visible = [for (var i = 0; i < _cols.length; i++) if (!_hidden.contains(i)) i];

    Widget dd(String value, List<(String, String)> items, ValueChanged<String> on) => SizedBox(
          width: 160,
          height: 30,
          child: DropdownButtonFormField<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5)),
            items: [for (final (v, t) in items) DropdownMenuItem(value: v, child: Text(t, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => on(v ?? value),
          ),
        );

    Widget tall(String label, String key, VoidCallback? on, {Color? color}) => SizedBox(
          width: 104,
          height: 88,
          child: _kb(label, on, key: key, color: color, height: 88, lines: 3),
        );

    Widget sumBox(int v, {Color? color}) => Container(
          width: 170,
          height: 30,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
          child: Text(groupDigits(v.abs()), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _edit(s, cur),
        const SingleActivator(LogicalKeyboardKey.f2, control: true): () => _reconcile(s, all),
        const SingleActivator(LogicalKeyboardKey.f3): () => setState(() {
              _onlyMarked = !_onlyMarked;
              _sel = null;
            }),
        const SingleActivator(LogicalKeyboardKey.f4): () => _inDocs(cur),
        const SingleActivator(LogicalKeyboardKey.f5): () => _cheques(s),
        const SingleActivator(LogicalKeyboardKey.f6): _display,
        const SingleActivator(LogicalKeyboardKey.f7): () => showNotebook(context, a),
        const SingleActivator(LogicalKeyboardKey.f8): () => _searchOptions(s, rows),
        const SingleActivator(LogicalKeyboardKey.f9): () => _findNext(s, rows),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f11): _dateFilter,
        const SingleActivator(LogicalKeyboardKey.f12): () => setState(() {
              _descApplied = _desc.text;
              _sel = null;
            }),
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (cur != null) s.toggleMark(a.key, _markKey(cur));
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (rows.isNotEmpty) _goTo(((_sel ?? -1) + 1).clamp(0, rows.length - 1));
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (rows.isNotEmpty) _goTo(((_sel ?? rows.length) - 1).clamp(0, rows.length - 1));
        },
      },
      child: Focus(
        autofocus: true,
        child: _Win(
          title: 'مشاهده اسناد   -----   ${a.kol} ----> ${a.name}',
          width: 1460,
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ---------------------------------------------------- ribbon
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _group(
                    'فیلتر کردن',
                    Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(width: 62, child: Text('مشخصه:')),
                          dd(_type, [for (final t in _types) (t, t)], (v) => setState(() {
                                _type = v;
                                _sel = null;
                              })),
                        ]),
                        const SizedBox(height: 3),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(width: 62, child: Text('شرح:')),
                          SizedBox(
                            width: 160,
                            height: 30,
                            child: TextField(
                              controller: _desc,
                              decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                              onSubmitted: (v) => setState(() {
                                _descApplied = v;
                                _sel = null;
                              }),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 3),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(width: 62, child: Text('مرکز سند')),
                          dd(_center, [('*', 'تمامی اسناد'), ('-', 'بدون مرکز'), for (final c in s.docCenters.where((c) => c != 'اصلی')) (c, c)],
                              (v) => setState(() {
                                    _center = v;
                                    _sel = null;
                                  })),
                        ]),
                      ]),
                      const SizedBox(width: 6),
                      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _kb(_cost == null ? 'فیلتر مرکز هزینه(رکورد)' : 'فیلتر مرکز هزینه(رکورد) ✓', () async {
                          final r = await showCostCenterPicker(context, current: _cost, select: true);
                          if (r != null && mounted) {
                            setState(() {
                              _cost = r.isAll ? null : r;
                              _sel = null;
                            });
                          }
                        }, height: 30, color: _cost == null ? null : const Color(0xFFFFE082)),
                        const SizedBox(height: 3),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          _kb('گزینه های جستجو', () => _searchOptions(s, rows), key: 'F8', height: 30),
                          const SizedBox(width: 3),
                          _kb('ادامه جستجو', () => _findNext(s, rows), key: 'F9', height: 30),
                          const SizedBox(width: 3),
                          _kb(_date.isEmpty ? 'محدوده تاریخی' : 'محدوده تاریخی ✓', _dateFilter,
                              key: 'F11', height: 30, color: _date.isEmpty ? null : const Color(0xFFFFE082)),
                        ]),
                        const SizedBox(height: 3),
                        _kb('جستجو', () => setState(() {
                              _descApplied = _desc.text;
                              _sel = null;
                            }), key: 'F12', height: 30),
                      ]),
                    ]),
                  ),
                  _group(
                    'عملیات',
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      tall('ویرایش سند', 'F2', () => _edit(s, cur)),
                      const SizedBox(width: 4),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 170, child: _kb('تنظیم نمایش', _display, key: 'F6', height: 28)),
                        const SizedBox(height: 2),
                        SizedBox(width: 170, child: _kb('لیست چکها', () => _cheques(s), key: 'F5', height: 28)),
                        const SizedBox(height: 2),
                        SizedBox(width: 170, child: _kb('مشاهده در لیست اسناد', () => _inDocs(cur), key: 'F4', height: 28)),
                      ]),
                    ]),
                  ),
                  _group(
                    'سایر',
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      tall(_onlyMarked ? 'علامت گذاری شده ها ✓' : 'علامت گذاری شده ها', 'F3', () => setState(() {
                            _onlyMarked = !_onlyMarked;
                            _sel = null;
                          }), color: _onlyMarked ? const Color(0xFFFFE082) : null),
                      const SizedBox(width: 4),
                      tall('دفترچه یادداشت', 'F7', () => showNotebook(context, a)),
                    ]),
                  ),
                  _group('صورت مغایرت', tall('صورت مغایرت', 'Ctrl+F2', () => _reconcile(s, all))),
                  _group('امانی', tall('صورت امانی های طرف حساب', '', () => showComingSoon(context, 'صورت امانی های طرف حساب'), color: const Color(0xFFFFD970))),
                ]),
              ),
              const SizedBox(height: 6),
              // ---------------------------------------------------- grid
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      color: const Color(0xFFEFF5FC),
                      child: Row(children: [
                        Builder(
                          builder: (bctx) => InkWell(
                            onTap: () => _printMenu(bctx, s, all, rows),
                            child: _hcell('چاپ', 44, color: const Color(0xFFE53935), fg: Colors.white),
                          ),
                        ),
                        for (final i in visible) _hcell(_cols[i], _w[i]),
                      ]),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: rows.isEmpty
                          ? const EmptyState(icon: Icons.receipt_long_outlined, text: 'سندی برای این حساب ثبت نشده')
                          : ListView.builder(
                              controller: _scroll,
                              itemExtent: 34,
                              itemCount: rows.length,
                              itemBuilder: (_, i) {
                                final r = rows[i];
                                final sel = i == _sel;
                                final cells = _cells(s, r);
                                final m = r.p.docKey == null ? null : s.docMeta[r.p.docKey];
                                final rowColor = m == null || m.color == 0 ? null : Color(m.color).withValues(alpha: 0.5);
                                final balColor = sel ? Colors.white : balanceColor(r.balance);
                                return Material(
                                  color: sel ? _selBlue : (rowColor ?? (i.isOdd ? const Color(0xFFF6FAFE) : Colors.white)),
                                  child: InkWell(
                                    onTap: () => setState(() => _sel = i),
                                    onDoubleTap: () => _edit(s, r),
                                    child: DefaultTextStyle.merge(
                                      style: TextStyle(color: sel ? Colors.white : null, fontWeight: sel ? FontWeight.w700 : null),
                                      child: Row(children: [
                                        _cell(
                                            InkWell(
                                              onTap: () => s.toggleMark(a.key, _markKey(r)),
                                              child: Icon(_isMarked(r) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                                  size: 18, color: _isMarked(r) ? const Color(0xFFE53935) : Colors.black26),
                                            ),
                                            44),
                                        for (final c in visible)
                                          _cell(
                                            Text(
                                              cells[c],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textDirection: c >= 5 && c != 7 ? TextDirection.ltr : null,
                                              style: TextStyle(
                                                fontWeight: c == 8 || c == 2 ? FontWeight.w800 : null,
                                                color: c == 8 || c == 7 ? balColor : null,
                                              ),
                                            ),
                                            _w[c],
                                            align: c == 4 ? Alignment.centerRight : (c >= 5 && c <= 8 && c != 7 ? Alignment.centerLeft : Alignment.center),
                                          ),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              // ---------------------------------------------------- bottom
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const SizedBox(width: 70, child: Text('مشخصه:')),
                      Expanded(
                        child: SizedBox(
                          height: 32,
                          child: TextField(
                            controller: _specCtl,
                            enabled: curKey != null,
                            decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                            onChanged: (v) {
                              if (curKey != null) s.updateDocMeta(curKey, (m) => m.spec = v.trim());
                            },
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(width: 70, child: Text('ملاحظات:')),
                      Expanded(
                        child: Container(
                          height: 66,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
                          child: SingleChildScrollView(child: Text(notes)),
                        ),
                      ),
                    ]),
                    Row(children: [
                      Checkbox(value: _printNotes, visualDensity: VisualDensity.compact, onChanged: (v) => setState(() => _printNotes = v ?? false)),
                      const Text('ملاحظات چاپ شود'),
                      const SizedBox(width: 14),
                      Checkbox(value: _printSpec, visualDensity: VisualDensity.compact, onChanged: (v) => setState(() => _printSpec = v ?? false)),
                      const Text('مشخصه چاپ شود'),
                    ]),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 40, child: Text('ریال:')),
                    sumBox(debit),
                    const SizedBox(width: 4),
                    sumBox(credit),
                    const SizedBox(width: 4),
                    sumBox(bal, color: balanceColor(bal)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 40, child: Text('ارزی:')),
                    for (var k = 0; k < 3; k++) ...[
                      if (k > 0) const SizedBox(width: 4),
                      Container(width: 170, height: 30, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26))),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  _kb('بازگشت', () => Navigator.pop(context), key: 'F10', icon: Icons.reply_rounded, color: const Color(0xFFFFE0B2), height: 40),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ================================================================ انتخاب مرکز هزینه(رکورد)

class CostFilter {
  final Set<String> centers;
  final bool none; // ردیف های بدون مرکز هزینه
  final bool isAll;
  const CostFilter(this.centers, {this.none = false, this.isAll = false});
}

/// «انتخاب مرکز هزینه(رکورد)». With [select] the choice is returned on تایید.
Future<CostFilter?> showCostCenterPicker(BuildContext context, {CostFilter? current, bool select = false}) {
  final s = StoreScope.read(context);
  final all = {for (final m in s.docMeta.values) if (m.costCenter.isNotEmpty) m.costCenter}.toList()..sort();
  final chosen = <String>{...(current?.centers ?? (current == null ? all.toSet() : const <String>{}))};
  var none = current?.none ?? true;
  final search = TextEditingController();
  return showDialog<CostFilter>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final q = normalizeDigits(search.text.trim());
      final shown = all.where((c) => q.isEmpty || normalizeDigits(c).contains(q)).toList();
      void ok() => Navigator.pop(ctx, CostFilter(chosen, none: none, isAll: chosen.length == all.length && none));
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f9): ok,
          const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(ctx),
        },
        child: Dialog(
          backgroundColor: _sky,
          child: SizedBox(
            width: 380,
            height: 520,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(children: [
                  const Expanded(child: Text('انتخاب مرکز هزینه(رکورد)', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(child: _kb('همه', () => set(() {
                        chosen.addAll(all);
                        none = true;
                      }), icon: Icons.check_rounded, height: 38)),
                  const SizedBox(width: 4),
                  Expanded(child: _kb('هیچ', () => set(() {
                        chosen.clear();
                        none = false;
                      }), icon: Icons.check_rounded, height: 38)),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: _kb('ردیف های بدون مرکز هزینه', () => set(() => none = !none),
                        color: none ? const Color(0xFFFFE082) : null, height: 38),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: search,
                    onChanged: (_) => set(() {}),
                    decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      color: const Color(0xFFEFF5FC),
                      child: Row(children: [_hcell('انتخاب', 70), _hcell('نام مرکز هزینه(رکورد)', 0)]),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(child: Text('مرکز هزینه ای ثبت نشده', style: TextStyle(color: Colors.black45)))
                          : ListView(children: [
                              for (final c in shown)
                                InkWell(
                                  onTap: () => set(() => chosen.contains(c) ? chosen.remove(c) : chosen.add(c)),
                                  child: SizedBox(
                                    height: 32,
                                    child: Row(children: [
                                      _cell(Checkbox(value: chosen.contains(c), onChanged: (v) => set(() => v == true ? chosen.add(c) : chosen.remove(c))), 70),
                                      _cell(Text(c), 0, align: Alignment.centerRight),
                                    ]),
                                  ),
                                ),
                            ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  if (select) Expanded(child: _kb('تایید', ok, key: 'F9', icon: Icons.check_rounded, color: const Color(0xFFD7F2D7), height: 38)),
                  if (select) const SizedBox(width: 6),
                  Expanded(child: _kb('بازگشت', () => Navigator.pop(ctx), key: 'F10', icon: Icons.reply_rounded, height: 38)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }),
  );
}
