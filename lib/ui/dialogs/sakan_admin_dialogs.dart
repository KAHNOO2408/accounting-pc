/// Sakan admin tools: «اشتراک گذاری حسابهای ساخته شده»، «انتقال گزارشات از
/// سایر دفاتر»، «جابجایی دفتر تفصیلی»، «تصحیح وضعیت چک ها» and «تعیین حصه
/// بلند مدت دفاتر موجودی کالا».
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/books.dart';
import '../../data/chart.dart';
import '../../data/custom_reports.dart';
import '../../data/journal.dart';
import '../../data/models.dart';
import '../../data/report_layout.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'cheque_dialogs.dart';

// ============================================================ اشتراک گذاری

const shareKinds = [('people', 'اشخاص و سایر اشخاص'), ('products', 'کالا و خدمات'), ('accounts', 'صندوق و بانک')];

/// «اشتراک گذاری حسابهای ساخته شده» of [user]: per kind «دسترسی کامل» (the
/// other users see what he defines) or «حذف دسترسی» (only he and the admin).
Future<void> showShareAccounts(BuildContext context, AppUser user) async {
  final s = StoreScope.read(context);
  final private = {...user.privateKinds};
  String? sel;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SakanWindow(
        title: 'اشتراک گذاری حسابهای ساخته شده — ${user.name}',
        width: 560,
        height: 420,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('لیست انواع حسابها', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Expanded(
              child: SakanGrid(
                header: [sakanHead('نوع حساب', 0), sakanHead('وضعیت دسترسی سایر کاربران', 200)],
                count: shareKinds.length,
                row: (_, i) {
                  final (k, name) = shareKinds[i];
                  return Material(
                    color: sel == k ? const Color(0xFFDDEBFA) : Colors.white,
                    child: InkWell(
                      onTap: () => set(() => sel = k),
                      child: Row(children: [
                        sakanCell(Text(name), 0),
                        sakanCell(
                            Text(private.contains(k) ? 'حذف دسترسی' : 'دسترسی کامل',
                                style: TextStyle(color: private.contains(k) ? Colors.red.shade700 : Colors.green.shade800, fontWeight: FontWeight.w700)),
                            200),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              sakanBtn('دسترسی کامل', sel == null ? null : () => set(() => private.remove(sel))),
              const SizedBox(width: 6),
              sakanBtn('حذف دسترسی', sel == null ? null : () => set(() => private.add(sel!))),
              const Spacer(),
              OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت F10')),
              const SizedBox(width: 6),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok == true) s.setPrivateKinds(user.id, private);
}

// ============================================================ انتقال گزارشات

/// «انتقال گزارشات از سایر دفاتر»: print designs, report layouts and
/// custom statements of another financial book.
Future<void> showImportReportsFromBook(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ImportReports());

class _ImportReports extends StatefulWidget {
  const _ImportReports();
  @override
  State<_ImportReports> createState() => _ImportReportsState();
}

typedef _Rep = (String key, String kind, String name, Object item);

class _ImportReportsState extends State<_ImportReports> {
  String? _book;
  List<_Rep> _items = [];
  final Set<String> _sel = {};

  void _load(AppStore s, BookRegistry reg) {
    if (_book == null) return;
    final other = reg.open(_book!);
    _items = [
      for (final l in other.reportLayouts) ('l:${l.id}', l.type.label, l.name, l),
      for (final t in other.printTemplates) ('t:${t.id}', 'قالب ${t.type.label}', t.name, t),
      for (final c in other.customStatements) ('c:${c.id}', c.balanceSheet ? 'ترازنامه سفارشی' : 'سود و زیان سفارشی', c.name, c),
    ];
    _sel.clear();
    setState(() {});
  }

  void _import(AppStore s) {
    var n = 0;
    for (final r in _items.where((r) => _sel.contains(r.$1))) {
      final it = r.$4;
      if (it is ReportLayout) {
        final c = it.copy()..id = newId();
        if (s.reportLayouts.any((x) => x.type == c.type && x.name == c.name)) c.name = '${c.name} (منتقل شده)';
        s.reportLayouts.add(c);
      } else if (it is PrintTemplate) {
        final c = PrintTemplate.fromJson(it.toJson())..id = newId();
        s.printTemplates.add(c);
      } else if (it is CustomStatement) {
        s.customStatements.add(CustomStatement.fromJson(it.toJson())..id = newId());
      }
      n++;
    }
    s.updateSettings((_) {});
    toast(context, '$n گزارش وارد شد');
    setState(_sel.clear);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final reg = BookRegistry.of(s);
    final cur = BookRegistry.idOf(s.storage.dir);
    final books = reg.active.where((b) => b.id != cur).toList();
    return SakanWindow(
      title: 'انتقال گزارشات از سایر دفاتر',
      width: 820,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('دفتر مالی مبدا: '),
            DropdownButton<String>(
              value: _book,
              hint: Text(books.isEmpty ? 'دفتر مالی دیگری وجود ندارد' : 'انتخاب کنید'),
              items: [for (final b in books) DropdownMenuItem(value: b.id, child: Text(b.title))],
              onChanged: (v) => setState(() => _book = v),
            ),
            sakanBtn('فراخوانی گزارشات ساخته شده', _book == null ? null : () => _load(s, reg), icon: Icons.download_rounded),
            sakanBtn('همه', () => setState(() => _sel.addAll(_items.map((e) => e.$1)))),
            sakanBtn('هیچ', () => setState(_sel.clear)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('', 40), sakanHead('نوع', 200), sakanHead('نام گزارش', 0)],
              count: _items.length,
              empty: 'دفتر مبدا را انتخاب و «فراخوانی گزارشات ساخته شده» را بزنید',
              row: (_, i) {
                final r = _items[i];
                return Row(children: [
                  sakanCell(Checkbox(value: _sel.contains(r.$1), onChanged: (v) => setState(() => v == true ? _sel.add(r.$1) : _sel.remove(r.$1))), 40),
                  sakanCell(Text(r.$2), 200),
                  sakanCell(Text(r.$3), 0, align: Alignment.centerRight),
                ]);
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _sel.isEmpty ? null : () => _import(s), child: const Text('وارد کردن گزارشات منتخب')),
          ]),
        ]),
      ),
    );
  }
}

// ============================================================ جابجایی دفتر تفصیلی

String _entityName(AppStore s, Moeen m, String id) => s.tafsiliName(VoucherLine(moeen: m.code, tafsiliId: id));

/// «جابجایی دفتر تفصیلی»: carries the chosen detail accounts (with all their
/// postings) from one معین to another of the same kind.
Future<void> showMoveTafsili(BuildContext context, {String? from}) => showDialog<void>(context: context, builder: (_) => _MoveTafsili(from: from));

class _MoveTafsili extends StatefulWidget {
  final String? from;
  const _MoveTafsili({this.from});
  @override
  State<_MoveTafsili> createState() => _MoveTafsiliState();
}

class _MoveTafsiliState extends State<_MoveTafsili> {
  late String? _from = widget.from;
  String? _to;
  final Set<String> _sel = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final journal = buildJournal(s);
    final bal = <String, Map<String, int>>{};
    for (final p in journal) {
      if (p.tafsiliId == null) continue;
      final m = bal.putIfAbsent(p.moeen, () => {});
      m[p.tafsiliId!] = (m[p.tafsiliId!] ?? 0) + p.debit - p.credit;
    }
    // people without postings can be moved too
    bal.putIfAbsent(mDebtorsTrade, () => {});
    for (final p in s.people) {
      if (!bal.values.any((m) => m.containsKey(p.id))) bal[mDebtorsTrade]![p.id] = 0;
    }
    final sources = [for (final m in allMoeens) if (m.hasEntity && (bal[m.code]?.isNotEmpty ?? false)) m];
    final src = findMoeen(_from);
    final targets = src == null ? const <Moeen>[] : [for (final m in allMoeens) if (m.kind == src.kind && m.code != src.code) m];
    final q = normalizeDigits(_q.trim());
    final rows = src == null
        ? const <(String, String, int)>[]
        : ([
            for (final e in (bal[src.code] ?? const <String, int>{}).entries)
              if (q.isEmpty || _entityName(s, src, e.key).contains(q)) (e.key, _entityName(s, src, e.key), e.value),
          ]..sort((a, b) => a.$2.compareTo(b.$2)));
    return SakanWindow(
      title: 'جابجایی دفتر تفصیلی',
      width: 820,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('دفتر معین مبدا:'),
            DropdownButton<String>(
              value: src?.code,
              hint: const Text('انتخاب کنید'),
              items: [for (final m in sources) DropdownMenuItem(value: m.code, child: Text('${m.code} - ${m.name}'))],
              onChanged: (v) => setState(() {
                _from = v;
                _to = null;
                _sel.clear();
              }),
            ),
            SizedBox(width: 200, child: TextField(decoration: const InputDecoration(labelText: 'جستجو', isDense: true), onChanged: (v) => setState(() => _q = v))),
            sakanBtn('همه', () => setState(() => _sel.addAll(rows.map((r) => r.$1)))),
            sakanBtn('هیچ', () => setState(_sel.clear)),
            sakanBtn('معکوس', () => setState(() {
                  for (final r in rows) {
                    if (!_sel.remove(r.$1)) _sel.add(r.$1);
                  }
                })),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('', 40), sakanHead('نام دفتر تفصیلی', 0), sakanHead('مانده', 160)],
              count: rows.length,
              empty: 'دفتر معین مبدا را انتخاب کنید',
              row: (_, i) {
                final r = rows[i];
                return Row(children: [
                  sakanCell(Checkbox(value: _sel.contains(r.$1), onChanged: (v) => setState(() => v == true ? _sel.add(r.$1) : _sel.remove(r.$1))), 40),
                  sakanCell(Text(r.$2), 0, align: Alignment.centerRight),
                  sakanCell(Text(groupDigits(r.$3)), 160),
                ]);
              },
            ),
          ),
          const SizedBox(height: 8),
          const Text('دفتر معین مقصد را جهت جابجایی انتخاب نمایید', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _to,
                hint: Text(targets.isEmpty ? 'دفتر معین هم نوع دیگری وجود ندارد' : 'دفتر معین مقصد'),
                items: [for (final m in targets) DropdownMenuItem(value: m.code, child: Text('${m.code} - ${m.name}'))],
                onChanged: (v) => setState(() => _to = v),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _to == null || _sel.isEmpty
                  ? null
                  : () async {
                      if (!await confirm(context, 'جابجایی دفاتر منتخب', '${_sel.length} دفتر تفصیلی با تمام گردش‌ها به «${findMoeen(_to)!.name}» منتقل شود؟', ok: 'جابجایی', danger: false)) return;
                      final e = s.moveTafsili(src!.code, {..._sel}, _to!);
                      if (!context.mounted) return;
                      if (e != null) return toast(context, e, error: true);
                      toast(context, 'جابجایی دفاتر انجام شد');
                      setState(() {
                        _from = _to;
                        _to = null;
                        _sel.clear();
                      });
                    },
              child: const Text('تایید F9'),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ============================================================ تصحیح وضعیت چک ها

/// «تصحیح وضعیت چک ها»: finds an issued / received cheque by number and
/// sets its status («ویرایش وضعیت»).
Future<void> showFixChequeStatus(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _FixCheque());

class _FixCheque extends StatefulWidget {
  const _FixCheque();
  @override
  State<_FixCheque> createState() => _FixChequeState();
}

class _FixChequeState extends State<_FixCheque> {
  ChequeDirection _dir = ChequeDirection.received;
  String _no = '';
  String? _sel;
  ChequeStatus? _status;

  Future<void> _apply(AppStore s, Cheque c) async {
    final st = _status;
    if (st == null || st == c.status) return;
    switch (st) {
      case ChequeStatus.cleared:
        await showClearChequeDialog(context, c);
      case ChequeStatus.deposited:
        await showDepositChequeDialog(context, c);
      case ChequeStatus.endorsed:
        await showEndorseChequeDialog(context, c);
      default:
        s.setChequeStatus(c, st);
    }
    if (mounted) {
      toast(context, 'وضعیت چک ${c.serial}: ${c.status.label}');
      setState(() => _status = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final no = normalizeDigits(_no.trim());
    final list = s.cheques.where((c) => c.direction == _dir && (no.isEmpty || normalizeDigits(c.serial).contains(no))).toList()
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    final sel = list.where((c) => c.id == _sel).firstOrNull;
    final allowed = _dir == ChequeDirection.received
        ? ChequeStatus.values
        : [ChequeStatus.pending, ChequeStatus.cleared, ChequeStatus.bounced, ChequeStatus.cancelled];
    return SakanWindow(
      title: 'تصحیح وضعیت چک ها',
      width: 900,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<ChequeDirection>(
              segments: const [
                ButtonSegment(value: ChequeDirection.issued, label: Text('اصلاح وضعیت چک های صادره')),
                ButtonSegment(value: ChequeDirection.received, label: Text('اصلاح وضعیت چک های وارده')),
              ],
              selected: {_dir},
              onSelectionChanged: (v) => setState(() {
                _dir = v.first;
                _sel = null;
                _status = null;
              }),
            ),
            SizedBox(width: 180, child: TextField(decoration: const InputDecoration(labelText: 'شماره چک:', isDense: true), onChanged: (v) => setState(() => _no = v))),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('شماره چک', 120), sakanHead('مبلغ', 130), sakanHead('سررسید', 100), sakanHead('طرف حساب', 0), sakanHead('بانک', 120), sakanHead('وضعیت', 170)],
              count: list.length,
              empty: 'چکی پیدا نشد',
              row: (_, i) {
                final c = list[i];
                return Material(
                  color: c.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() {
                      _sel = c.id;
                      _status = c.status;
                    }),
                    child: Row(children: [
                      sakanCell(Text(c.serial), 120),
                      sakanCell(Text(groupDigits(c.amount)), 130),
                      sakanCell(Text(jFormat(c.dueDate)), 100),
                      sakanCell(Text(s.person(c.personId)?.name ?? '', overflow: TextOverflow.ellipsis), 0),
                      sakanCell(Text(c.bank, overflow: TextOverflow.ellipsis), 120),
                      sakanCell(Text(c.status.label, style: const TextStyle(fontSize: 12)), 170),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('وضعیت جدید: '),
            DropdownButton<ChequeStatus>(
              value: sel == null ? null : _status,
              hint: const Text('ابتدا چک را انتخاب کنید'),
              items: [for (final st in allowed) DropdownMenuItem(value: st, child: Text(st.label))],
              onChanged: sel == null ? null : (v) => setState(() => _status = v),
            ),
            const Spacer(),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
            const SizedBox(width: 6),
            FilledButton(onPressed: sel == null || _status == null || _status == sel.status ? null : () => _apply(s, sel), child: const Text('ویرایش وضعیت')),
          ]),
        ]),
      ),
    );
  }
}

// ============================================================ حصه بلند مدت

/// «تعیین حصه بلند مدت دفاتر موجودی کالا»: per inventory ledger the percent
/// of its balance reported among the non-current assets.
Future<void> showStockLongTerm(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _LongTerm());

class _LongTerm extends StatefulWidget {
  const _LongTerm();
  @override
  State<_LongTerm> createState() => _LongTermState();
}

class _LongTermState extends State<_LongTerm> {
  Map<String, double>? _pct;
  Map<String, int> _bal = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    if (_pct == null) {
      _pct = {...s.stockLongTerm};
      _bal = stockLedgerBalances(s);
    }
    final pct = _pct!;
    final q = _q.trim();
    final list = s.productsSorted.where((p) => !p.archived && (q.isEmpty || p.name.contains(q) || p.code.contains(q))).toList();
    final total = stockLongTermValue(pct, _bal);
    return SakanWindow(
      title: 'تعیین حصه بلند مدت دفاتر موجودی کالا',
      width: 860,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 220, child: TextField(decoration: const InputDecoration(labelText: 'جستجوی کالا', isDense: true), onChanged: (v) => setState(() => _q = v))),
            const Spacer(),
            Text('جمع حصه بلند مدت: ${groupDigits(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 80), sakanHead('نام کالا', 0), sakanHead('مانده دفتر', 140), sakanHead('درصد بلند مدت', 120), sakanHead('حصه بلند مدت', 140)],
              count: list.length,
              row: (_, i) {
                final p = list[i];
                final b = _bal[p.id] ?? 0;
                final v = pct[p.id] ?? 0;
                return Row(children: [
                  sakanCell(Text(p.code), 80),
                  sakanCell(Text(p.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                  sakanCell(Text(groupDigits(b)), 140),
                  sakanCell(
                    TextFormField(
                      key: ValueKey('lt-${p.id}'),
                      initialValue: v == 0 ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v'),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: '0'),
                      onChanged: (t) => setState(() => pct[p.id] = (double.tryParse(normalizeDigits(t)) ?? 0).clamp(0, 100).toDouble()),
                    ),
                    120,
                  ),
                  sakanCell(Text(b > 0 ? groupDigits((b * v / 100).round()) : '0'), 140),
                ]);
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: () {
                s.setStockLongTerm(pct);
                Navigator.pop(context);
                toast(context, 'حصه بلند مدت موجودی کالا ثبت شد (در «ترازنامه سفارشی» با گزینه حصه بلند مدت)');
              },
              child: const Text('تایید F9'),
            ),
          ]),
        ]),
      ),
    );
  }
}
