import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/journal.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/chequebook_dialogs.dart';
import '../dialogs/closing_dialogs.dart';
import '../dialogs/invoice_editor.dart';
import '../dialogs/opening_dialog.dart';
import '../dialogs/txn_dialog.dart';
import '../dialogs/voucher_dialog.dart';
import '../dialogs/ledger_dialogs.dart' show DateFilter, showDocDateFilter;
import '../print.dart';
import '../shell.dart' show Nav, AppPage;
import '../theme.dart';
import '../widgets/common.dart';

/// One row of «لیست اسناد».
class _Doc {
  final String key;
  final int number;
  final int fixed;
  final DateTime date;
  final String desc;
  final int amount;
  final int created;
  final DocMeta meta;
  final String center;
  final String archive;
  final String babat;
  const _Doc({
    required this.key,
    required this.number,
    required this.fixed,
    required this.date,
    required this.desc,
    required this.amount,
    required this.created,
    required this.meta,
    this.center = '',
    this.archive = '',
    this.babat = '',
  });
}

/// Row colors of documents («رنگ»); the index is the color number.
const docRowColors = [0, 0xFFFFF59D, 0xFFA5D6A7, 0xFF90CAF9, 0xFFFFAB91, 0xFFCE93D8];

String _stamp(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final pm = d.hour >= 12;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  String two(int x) => x.toString().padLeft(2, '0');
  return '${pm ? 'ب.ظ' : 'ق.ظ'} ${two(h)}:${two(d.minute)}:${two(d.second)} ${jFormat(d)}';
}

/// لیست اسناد — every document of the ledger, laid out like Sakan.
/// Opens the editor of a document of «لیست اسناد» ('v:id', 'inv:id', 'txn:id').
void openDocument(BuildContext context, String key) {
  final s = StoreScope.read(context);
  final id = key.substring(key.indexOf(':') + 1);
  if (key.startsWith('v:')) {
    final v = s.vouchers.where((v) => v.id == id).firstOrNull;
    if (v == null) return;
    switch (v.kind) {
      case 'chequeMove':
        showChequeMoveDialog(context, edit: v);
      case 'manual' || 'composite' || 'expense':
        showVoucherDialog(context, edit: v);
      default:
        showYearEndVoucher(context, v);
    }
  } else if (key.startsWith('inv:')) {
    final inv = s.invoices.where((i) => i.id == id).firstOrNull;
    if (inv != null) showInvoiceEditor(context, edit: inv);
  } else {
    final t = s.txn(id);
    if (t != null) showTxnDialog(context, edit: t);
  }
}

class VouchersPage extends StatefulWidget {
  const VouchersPage({super.key});

  /// Document to select when the page opens next («رویت در لیست اسناد»).
  static String? focusKey;

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> {
  String? _sel = VouchersPage.focusKey;
  String? _cut;
  String _centerFilter = '*';
  DateFilter _dates = const DateFilter();
  String _searchText = '';
  int _searchField = 0; // 0 all, 1 number, 2 desc, 3 amount
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Doc> _docs(AppStore s) {
    final out = <_Doc>[];
    for (final v in s.vouchers) {
      final k = 'v:${v.id}';
      out.add(_Doc(
        key: k,
        number: v.number,
        fixed: v.fixedNumber,
        date: v.date,
        desc: v.desc.isEmpty ? (v.lines.isEmpty ? v.kindLabel : '${v.kindLabel} — ${v.lines.first.desc}') : v.desc,
        amount: v.totalDebit,
        created: v.createdAt,
        meta: s.docMeta[k] ?? DocMeta(modifiedAt: v.createdAt),
        center: v.center,
        archive: v.archivePath,
        babat: v.desc,
      ));
    }
    for (final inv in s.realInvoices) {
      final k = 'inv:${inv.id}';
      final m = s.docMeta[k] ?? DocMeta(modifiedAt: inv.createdAt);
      final kindWord = switch (inv.kind) {
        InvoiceKind.sale => 'فروش',
        InvoiceKind.purchase => 'خرید',
        InvoiceKind.saleReturn => 'برگشت از فروش',
        InvoiceKind.purchaseReturn => 'برگشت از خرید',
      };
      final to = inv.kind.buySide ? 'از' : 'به';
      out.add(_Doc(
        key: k,
        number: m.number,
        fixed: m.fixed,
        date: inv.date,
        desc: 'فاکتور ${groupDigits(inv.number)}  $kindWord  ${inv.lines.length} قلم کالا $to  ${s.person(inv.personId)?.name ?? 'متفرقه'}',
        amount: inv.total,
        created: inv.createdAt,
        meta: m,
        center: m.center,
        archive: m.archive,
        babat: inv.info['babat']?.isNotEmpty == true ? inv.info['babat']! : inv.note,
      ));
    }
    for (final t in s.txns) {
      if (t.invoiceId != null) continue;
      final k = 'txn:${t.id}';
      final m = s.docMeta[k] ?? DocMeta(modifiedAt: t.createdAt);
      out.add(_Doc(
        key: k,
        number: m.number,
        fixed: m.fixed,
        date: t.date,
        desc: [t.type.label, s.person(t.personId)?.name ?? '', s.account(t.accountId)?.name ?? ''].where((x) => x.isNotEmpty).join('  '),
        amount: t.amount,
        created: t.createdAt,
        meta: m,
        center: m.center,
        archive: m.archive,
        babat: t.note,
      ));
    }
    out.sort((a, b) {
      final c = a.number.compareTo(b.number);
      return c != 0 ? c : a.created.compareTo(b.created);
    });
    return out.where((d) {
      if (_centerFilter == '-' && d.center.isNotEmpty && d.center != 'اصلی') return false;
      if (_centerFilter == '+' && (d.center.isEmpty || d.center == 'اصلی')) return false;
      if (!{'*', '-', '+'}.contains(_centerFilter) && d.center != _centerFilter) return false;
      final when = _dates.onModified && d.meta.modifiedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(d.meta.modifiedAt) : d.date;
      if (!_dates.hasDate(when)) return false;
      if (_dates.color != null && d.meta.color != (_dates.color! < docRowColors.length ? docRowColors[_dates.color!] : -1)) return false;
      return true;
    }).toList();
  }

  _Doc? _current(List<_Doc> list) => list.where((d) => d.key == _sel).firstOrNull;

  bool _matches(_Doc d) {
    final q = normalizeDigits(_searchText.trim()).replaceAll(',', '').toLowerCase();
    if (q.isEmpty) return false;
    final parts = switch (_searchField) {
      1 => ['${d.number}', '${d.fixed}'],
      2 => [d.desc, d.babat],
      3 => ['${d.amount}'],
      _ => ['${d.number}', '${d.fixed}', d.desc, d.babat, '${d.amount}', jFormat(d.date)],
    };
    return parts.any((p) => normalizeDigits(p).replaceAll(',', '').toLowerCase().contains(q));
  }

  void _findNext(List<_Doc> list, {bool fromStart = false}) {
    if (_searchText.trim().isEmpty) return;
    var start = fromStart ? 0 : list.indexWhere((d) => d.key == _sel) + 1;
    for (var n = 0; n < list.length; n++) {
      final i = (start + n) % list.length;
      if (_matches(list[i])) {
        setState(() => _sel = list[i].key);
        _scrollTo(i);
        return;
      }
    }
    toast(context, 'موردی یافت نشد', error: true);
  }

  void _scrollTo(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (i * 36.0 - 120).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _searchOptions(List<_Doc> list) async {
    final c = TextEditingController(text: _searchText);
    var field = _searchField;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'گزینه های جستجو',
          width: 460,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('جستجو')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'عبارت مورد جستجو'), onSubmitted: (_) => Navigator.pop(ctx, true)),
            const SizedBox(height: 10),
            FieldDropdown<int>(
              label: 'جستجو در',
              value: field,
              items: const [
                DropdownMenuItem(value: 0, child: Text('همه ستون ها')),
                DropdownMenuItem(value: 1, child: Text('شماره سند / شماره ثابت')),
                DropdownMenuItem(value: 2, child: Text('شرح سند')),
                DropdownMenuItem(value: 3, child: Text('مبلغ سند')),
              ],
              onChanged: (v) => set(() => field = v ?? 0),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _searchText = c.text;
        _searchField = field;
      });
      _findNext(list, fromStart: true);
    }
    c.dispose();
  }

  Future<void> _dateRange() async {
    final r = await showDocDateFilter(context, current: _dates, modifiedOption: true);
    if (r != null) setState(() => _dates = r);
  }

  void _clearFilter() => setState(() {
        _dates = const DateFilter();
        _centerFilter = '*';
        _searchText = '';
      });

  void _open(AppStore s, _Doc d, {bool view = false}) {
    if (!view && d.meta.locked) {
      toast(context, 'سند ${d.number} قفل است', error: true);
      return;
    }
    if (view) {
      _showPostings(s, d);
      return;
    }
    openDocument(context, d.key);
  }

  void _showPostings(AppStore s, _Doc d) {
    final id = d.key.substring(d.key.indexOf(':') + 1);
    List<(String, String, int, int)> rows;
    if (d.key.startsWith('v:')) {
      final v = s.vouchers.firstWhere((v) => v.id == id);
      rows = [for (final l in v.lines) (l.moeen, accountName(s, '${l.moeen}|${l.tafsiliId ?? ''}'), l.debit, l.credit)];
    } else {
      rows = [
        for (final p in buildJournal(s).where((p) => p.docKey == d.key))
          (p.moeen, accountName(s, '${p.moeen}|${p.tafsiliId ?? ''}'), p.debit, p.credit),
      ];
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final th = Theme.of(ctx);
        return FormDialog(
          title: 'رویت سند ${d.number} — ${jFormat(d.date)}',
          width: 760,
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(d.desc, style: th.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 70, child: Text(r.$1, style: TextStyle(color: th.hintColor))),
                  Expanded(child: Text(r.$2)),
                  SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: r.$3 == 0 ? const SizedBox() : Money(r.$3))),
                  SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: r.$4 == 0 ? const SizedBox() : Money(r.$4))),
                ]),
              ),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('جمع', style: TextStyle(fontWeight: FontWeight.w800))),
              SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: Money(rows.fold<int>(0, (a, r) => a + r.$3)))),
              SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: Money(rows.fold<int>(0, (a, r) => a + r.$4)))),
            ]),
          ]),
        );
      },
    );
  }

  Future<void> _delete(AppStore s, _Doc? d) async {
    if (d == null) return toast(context, 'سندی انتخاب نشده', error: true);
    if (d.meta.locked) return toast(context, 'سند ${d.number} قفل است', error: true);
    final ok = await confirm(context, 'حذف سند', 'سند شماره ${d.number} حذف شود؟');
    if (!ok || !mounted) return;
    final id = d.key.substring(d.key.indexOf(':') + 1);
    if (d.key.startsWith('v:')) {
      final v = s.vouchers.firstWhere((v) => v.id == id);
      if (v.kind == 'depreciation') return toast(context, 'استهلاک را از «جدول اموال» ویرایش کنید', error: true);
      if (v.kind == 'closing' && v.meta['reopen'] != null) {
        return toast(context, 'ابتدا سند افتتاحیه انتقالی این اختتامیه را حذف کنید', error: true);
      }
      s.removeVoucher(id);
    } else if (d.key.startsWith('inv:')) {
      s.removeInvoice(id);
    } else {
      s.removeTxn(id);
    }
    setState(() => _sel = null);
  }

  Future<void> _follow(AppStore s, _Doc d) async {
    final c = TextEditingController(text: d.meta.followDesc);
    DateTime? date = d.meta.followDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'پیگرد سند ${d.number}',
          width: 460,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: Column(children: [
            DateField(label: 'تاریخ پیگرد', value: date, clearable: true, onChanged: (v) => set(() => date = v)),
            const SizedBox(height: 10),
            TextField(controller: c, maxLines: 2, decoration: const InputDecoration(labelText: 'شرح پیگرد')),
          ]),
        ),
      ),
    );
    if (ok == true) {
      s.updateDocMeta(d.key, (m) {
        m
          ..followDate = date
          ..followDesc = c.text.trim();
      });
    }
    c.dispose();
  }

  void _printList(AppStore s, List<_Doc> list) => printTable(
        store: s,
        title: 'لیست اسناد',
        headers: const ['شماره ثابت', 'شماره سند', 'تاریخ سند', 'شرح سند', 'مبلغ سند'],
        rows: [for (final d in list) ['${d.fixed}', '${d.number}', jFormat(d.date), d.desc, groupDigits(d.amount)]],
        numeric: const {4},
        footer: ['', '', '', 'جمع', groupDigits(list.fold<int>(0, (a, d) => a + d.amount))],
        fileName: 'documents',
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final list = _docs(s);
    VouchersPage.focusKey = null;
    if (_sel != null && !list.any((d) => d.key == _sel)) _sel = null;
    if (_sel == null && list.isNotEmpty) _sel = list.last.key;
    if (!_scrolled && list.isNotEmpty) {
      _scrolled = true;
      final i = list.indexWhere((d) => d.key == _sel);
      _scrollTo(i < 0 ? list.length - 1 : i);
    }
    final cur = _current(list);

    void cut() {
      if (cur == null) return;
      if (cur.meta.locked) return toast(context, 'سند ${cur.number} قفل است', error: true);
      setState(() => _cut = cur.key);
      toast(context, 'سند ${cur.number} برش خورد؛ سند مقصد را انتخاب و «چسباندن» را بزنید');
    }

    void paste() {
      if (_cut == null || cur == null) return toast(context, 'ابتدا سندی را برش بزنید', error: true);
      s.moveDocument(_cut!, cur.key);
      setState(() => _cut = null);
    }

    Future<void> sort() async {
      final ok = await confirm(context, 'مرتب سازی', 'شماره همه اسناد بر اساس تاریخ از نو مرتب شود؟', ok: 'مرتب سازی', danger: false);
      if (ok) s.sortDocuments();
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f9, control: true): sort,
      const SingleActivator(LogicalKeyboardKey.f11): () => setState(() => _cut = null),
      const SingleActivator(LogicalKeyboardKey.f11, control: true): cut,
      const SingleActivator(LogicalKeyboardKey.f12): paste,
      const SingleActivator(LogicalKeyboardKey.f2): () {
        if (cur != null) _open(s, cur);
      },
      const SingleActivator(LogicalKeyboardKey.f5): () {
        if (cur != null) _open(s, cur, view: true);
      },
      const SingleActivator(LogicalKeyboardKey.f6): () => _delete(s, cur),
      const SingleActivator(LogicalKeyboardKey.f1): _dateRange,
      const SingleActivator(LogicalKeyboardKey.f7): () => _searchOptions(list),
      const SingleActivator(LogicalKeyboardKey.f8): () => _findNext(list),
      const SingleActivator(LogicalKeyboardKey.f4): _clearFilter,
      const SingleActivator(LogicalKeyboardKey.f10): () => Nav.of(context).go(AppPage.home),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        final i = list.indexWhere((d) => d.key == _sel);
        if (i + 1 < list.length) {
          setState(() => _sel = list[i + 1].key);
          _scrollTo(i + 1);
        }
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        final i = list.indexWhere((d) => d.key == _sel);
        if (i > 0) {
          setState(() => _sel = list[i - 1].key);
          _scrollTo(i - 1);
        }
      },
    };

    Widget group(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Brand.of(context).accent.withValues(alpha: 0.2)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: children),
            const SizedBox(height: 2),
            Text(title, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
          ]),
        );

    Widget btn(String label, String key, VoidCallback? onTap, {IconData? icon, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              foregroundColor: color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
              Text(label),
              if (key.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(key, style: TextStyle(fontSize: 10, color: AppColors.expense.withValues(alpha: 0.85))),
              ],
            ]),
          ),
        );

    const widths = [42.0, 46.0, 80.0, 80.0, 96.0, 170.0, 0.0, 130.0, 96.0, 170.0];
    const titles = ['قفل', 'رنگ', 'شماره ثابت', 'شماره سند', 'تاریخ سند', 'آخرین اصلاح', 'شرح سند', 'مبلغ سند', 'تاریخ پیگرد', 'تاریخ ثبت'];
    Widget cell(int i, Widget child) => widths[i] == 0 ? Expanded(child: child) : SizedBox(width: widths[i], child: child);

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: DefaultTabController(
          length: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                HeaderBand(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                  child: Row(children: [
                    const Icon(Icons.list_alt_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Text('لیست اسناد', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 20),
                    const SizedBox(
                      width: 220,
                      child: TabBar(
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white70,
                        indicatorColor: Colors.white,
                        tabs: [Tab(text: 'عملیات', height: 34), Tab(text: 'سایر', height: 34)],
                      ),
                    ),
                    const Spacer(),
                    Text('${list.length} سند', style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                Container(
                  color: Brand.of(context).accent.withValues(alpha: 0.06),
                  height: 102,
                  child: TabBarView(children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(6),
                      child: Row(children: [
                        group('جا به جایی', [
                          btn('مرتب سازی', 'Ctrl+F9', sort),
                          btn('انصراف از برش', 'F11', _cut == null ? null : () => setState(() => _cut = null)),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(height: 26, child: btn('برش', 'Ctrl+F11', cut)),
                            const SizedBox(height: 2),
                            SizedBox(height: 26, child: btn('چسباندن', 'F12', _cut == null ? null : paste)),
                          ]),
                        ]),
                        group('عملیات', [
                          btn('ویرایش سند', 'F2', cur == null ? null : () => _open(s, cur), icon: Icons.edit_outlined),
                          btn('رویت سند', 'F5', cur == null ? null : () => _open(s, cur, view: true), icon: Icons.visibility_outlined),
                          btn('حذف', 'F6', cur == null ? null : () => _delete(s, cur), icon: Icons.delete_outline, color: th.colorScheme.error),
                        ]),
                        group('فیلتر', [
                          const Text('مرکز اسناد'),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String>(
                              value: _centerFilter,
                              isDense: true,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                              items: [
                                const DropdownMenuItem(value: '*', child: Text('تمامی اسناد')),
                                const DropdownMenuItem(value: '-', child: Text('بدون مرکز')),
                                const DropdownMenuItem(value: '+', child: Text('با مرکز')),
                                for (final c in s.docCenters.where((c) => c != 'اصلی')) DropdownMenuItem(value: c, child: Text(c)),
                              ],
                              onChanged: (v) => setState(() => _centerFilter = v ?? '*'),
                            ),
                          ),
                          btn(_dates.isEmpty ? 'محدوده تاریخی' : 'محدوده تاریخی ✓', 'F1', _dateRange),
                        ]),
                        group('جستجو', [
                          btn('گزینه های جستجو', 'F7', () => _searchOptions(list), icon: Icons.search_rounded),
                          btn('ادامه جستجو', 'F8', _searchText.isEmpty ? null : () => _findNext(list)),
                          btn('برداشتن فیلتر', 'F4', _clearFilter),
                        ]),
                      ]),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(6),
                      child: Row(children: [
                        group('سند', [
                          btn('سند حسابداری دستی', 'Alt+F2', () => showVoucherDialog(context), icon: Icons.edit_note_rounded),
                          btn('سند افتتاحیه', '', () => openOpeningVoucher(context), icon: Icons.flag_outlined),
                        ]),
                        group('وضعیت سند', [
                          btn(cur?.meta.locked == true ? 'باز کردن قفل' : 'قفل سند', '', cur == null ? null : () => s.updateDocMeta(cur.key, (m) => m.locked = !m.locked),
                              icon: cur?.meta.locked == true ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                          btn('پیگرد سند', '', cur == null ? null : () => _follow(s, cur), icon: Icons.event_note_outlined),
                          const SizedBox(width: 6),
                          const Text('رنگ: '),
                          for (final c in docRowColors)
                            InkWell(
                              onTap: cur == null ? null : () => s.updateDocMeta(cur.key, (m) => m.color = c),
                              child: Container(
                                width: 22,
                                height: 22,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: c == 0 ? Colors.white : Color(c),
                                  border: Border.all(color: cur?.meta.color == c ? th.colorScheme.primary : Colors.black26, width: cur?.meta.color == c ? 2 : 1),
                                ),
                              ),
                            ),
                        ]),
                        group('چاپ', [btn('چاپ لیست اسناد', '', () => _printList(s, list), icon: Icons.print_outlined)]),
                      ]),
                    ),
                  ]),
                ),
                // header row
                Container(
                  color: th.colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: DefaultTextStyle(
                    style: th.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w800),
                    child: Row(children: [
                      SizedBox(
                        width: 44,
                        child: Material(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(4),
                          child: InkWell(
                            onTap: () => _printList(s, list),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('چاپ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ),
                      for (var i = 0; i < titles.length; i++) cell(i, Text(titles[i], textAlign: TextAlign.center)),
                    ]),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(icon: Icons.list_alt_rounded, text: 'سندی ثبت نشده')
                      : ListView.builder(
                          controller: _scroll,
                          itemExtent: 36,
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final d = list[i];
                            final sel = d.key == _sel;
                            final isCut = d.key == _cut;
                            final bg = sel
                                ? th.colorScheme.primary
                                : (d.meta.color != 0 ? Color(d.meta.color).withValues(alpha: 0.55) : (i.isOdd ? th.colorScheme.surfaceContainerLowest : null));
                            final fg = sel ? Colors.white : null;
                            return Material(
                              color: bg ?? Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  _focus.requestFocus();
                                  setState(() => _sel = d.key);
                                },
                                onDoubleTap: () => _open(s, d),
                                child: Container(
                                  decoration: isCut ? BoxDecoration(border: Border.all(color: AppColors.expense, width: 2)) : null,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: DefaultTextStyle.merge(
                                    style: TextStyle(color: fg, fontWeight: sel ? FontWeight.w700 : null),
                                    child: Row(children: [
                                      const SizedBox(width: 44),
                                      cell(
                                        0,
                                        Center(
                                          child: Checkbox(
                                            value: d.meta.locked,
                                            visualDensity: VisualDensity.compact,
                                            onChanged: (v) => s.updateDocMeta(d.key, (m) => m.locked = v ?? false),
                                          ),
                                        ),
                                      ),
                                      cell(1, Text('${docRowColors.indexOf(d.meta.color).clamp(0, 9)}', textAlign: TextAlign.center)),
                                      cell(2, Text('${d.fixed}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                                      cell(3, Text(groupDigits(d.number), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                                      cell(4, Text(jFormat(d.date), textAlign: TextAlign.center)),
                                      cell(5, Text(_stamp(d.meta.modifiedAt), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                                      cell(6, Text(d.desc, overflow: TextOverflow.ellipsis)),
                                      cell(7, Text(groupDigits(d.amount), textAlign: TextAlign.left, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700))),
                                      cell(8, Text(d.meta.followDate == null ? '' : jFormat(d.meta.followDate!), textAlign: TextAlign.center)),
                                      cell(9, Text(_stamp(d.created), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                // bottom info
                Container(
                  color: th.colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: Column(children: [
                        _info('شرح پیگرد:', cur?.meta.followDesc ?? ''),
                        const SizedBox(height: 4),
                        _info('بابت سند:', cur?.babat ?? ''),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: Column(children: [
                        _info('مرکز اسناد:', cur?.center ?? ''),
                        const SizedBox(height: 4),
                        _info('مسیر بایگانی:', cur?.archive ?? ''),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _info('کاربر ثبت کننده:', cur == null ? '' : s.userName(cur.meta.userId)),
                        const SizedBox(height: 4),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: OutlinedButton.icon(
                            onPressed: () => Nav.of(context).go(AppPage.home),
                            icon: const Icon(Icons.reply_rounded, size: 18),
                            label: const Text('بازگشت F10'),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(String label, String value) => Row(children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black12)),
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ]);
}
