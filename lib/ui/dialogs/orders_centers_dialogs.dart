import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty, showInvoiceEditor;

// ================================================================ سفارشات

/// «سفارشات» — pro-formas as orders with «وضعیت سفارش».
Future<void> showOrders(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Orders());

class _Orders extends StatefulWidget {
  const _Orders();

  @override
  State<_Orders> createState() => _OrdersState();
}

class _OrdersState extends State<_Orders> {
  String? _sel;
  bool _hideClosed = true;

  Future<void> _setState(AppStore s, Invoice o) async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'تعیین وضعیت سفارش ${o.number}',
        width: 360,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
        child: Column(children: [
          for (final st in orderStatuses)
            ListTile(dense: true, selected: (o.info['orderStatus'] ?? orderStatuses.first) == st, title: Text(st), onTap: () => Navigator.pop(ctx, st)),
        ]),
      ),
    );
    if (r != null) {
      o.info['orderStatus'] = r;
      s.saveInvoice(o);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.invoices.where((i) => i.proforma).where((i) {
      final st = i.info['orderStatus'] ?? orderStatuses.first;
      return !_hideClosed || !(st == 'خاتمه یافته' || st == 'بلوکه شده' || st == 'منتفی شده');
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final sel = list.where((i) => i.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'سفارشات',
      width: 1100,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('سفارش جدید', () => showInvoiceEditor(context, proforma: true), icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => showInvoiceEditor(context, edit: sel), icon: Icons.edit_outlined),
            sakanBtn('تعیین وضعیت', sel == null ? null : () => _setState(s, sel), key: 'F2', icon: Icons.flag_outlined),
            sakanBtn('اعمال سفارش', sel == null
                ? null
                : () {
                    final inv = s.convertProforma(sel);
                    showInvoiceEditor(context, edit: inv);
                  }, icon: Icons.receipt_long_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف سفارش', 'سفارش ${sel.number} حذف شود؟')) s.removeInvoice(sel.id);
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('تعیین سفارش روزانه', () => showDailyQuota(context), icon: Icons.today_outlined),
            FilterChip(label: const Text('عدم نمایش خاتمه یافته‌ها، بلوکه شده‌ها و منتفی شده‌ها'), selected: _hideClosed, onSelected: (v) => setState(() => _hideClosed = v)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('شماره سفارش', 90),
                sakanHead('تاریخ سفارش', 100),
                sakanHead('نام سفارش دهنده', 0),
                sakanHead('نام بازاریاب', 150),
                sakanHead('جمع کالا', 120),
                sakanHead('جمع خدمت', 110),
                sakanHead('مبلغ سفارش', 130),
                sakanHead('وضعیت سفارش', 120),
              ],
              count: list.length,
              empty: 'سفارشی ثبت نشده',
              row: (ctx, i) {
                final o = list[i];
                final on = o.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                final goods = o.lines.where((l) => l.productId != null).fold<int>(0, (a, l) => a + l.total);
                final services = o.lines.where((l) => l.productId == null).fold<int>(0, (a, l) => a + l.total);
                return InkWell(
                  onTap: () => setState(() => _sel = o.id),
                  onDoubleTap: () => showInvoiceEditor(context, edit: o),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text('${o.number}', style: st), 90),
                      sakanCell(Text(jFormat(o.date), style: st), 100),
                      sakanCell(Text(s.person(o.personId)?.name ?? 'متفرقه', style: st), 0, align: Alignment.centerRight),
                      sakanCell(Text(o.marketers.map((m) => s.person(m.personId)?.name ?? '').join('، '), style: st, overflow: TextOverflow.ellipsis), 150),
                      sakanCell(Text(groupDigits(goods), style: st), 120),
                      sakanCell(Text(groupDigits(services), style: st), 110),
                      sakanCell(Text(groupDigits(o.total), style: st.copyWith(fontWeight: FontWeight.w700)), 130),
                      sakanCell(Text(o.info['orderStatus'] ?? orderStatuses.first, style: st), 120),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// «وضعیت سفارش» of a product: open orders that contain it.
Future<void> showProductOrders(BuildContext context, Product p) {
  final s = StoreScope.read(context);
  final rows = <(Invoice, InvoiceLine)>[
    for (final o in s.invoices.where((i) => i.proforma && !['خاتمه یافته', 'منتفی شده'].contains(i.info['orderStatus'])))
      for (final l in o.lines.where((l) => l.productId == p.id)) (o, l),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'وضعیت سفارش — ${p.name}',
      width: 640,
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (o, l) in rows)
          ListTile(
            dense: true,
            title: Text('سفارش ${o.number} — ${s.person(o.personId)?.name ?? 'متفرقه'}'),
            subtitle: Text('${jFormat(o.date)} — ${o.info['orderStatus'] ?? orderStatuses.first}'),
            trailing: Text('${fmtQty(l.qty)} ${p.unit}'),
          ),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('سفارش بازی برای این کالا نیست')),
        const Divider(),
        Text('جمع سفارش‌های باز: ${fmtQty(rows.fold<double>(0, (a, r) => a + r.$2.qty))} ${p.unit}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    ),
  );
}

/// «تعیین سفارش روزانه»: daily order quota per product (info['dailyQuota'], -1 = نامحدود).
Future<void> showDailyQuota(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Quota());

class _Quota extends StatefulWidget {
  const _Quota();

  @override
  State<_Quota> createState() => _QuotaState();
}

class _QuotaState extends State<_Quota> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final today = dateOnly(DateTime.now());
    double orderedToday(Product p) => s.invoices
        .where((i) => i.proforma && dateOnly(i.date) == today)
        .expand((i) => i.lines)
        .where((l) => l.productId == p.id)
        .fold(0.0, (a, l) => a + l.qty);
    final list = s.productsSorted.where((p) => !p.archived && (_q.isEmpty || p.name.contains(_q))).toList();
    return SakanWindow(
      title: 'تعیین سفارش روزانه',
      width: 980,
      height: 620,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 260, child: TextField(decoration: const InputDecoration(labelText: 'نام کالا', isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            const SizedBox(width: 12),
            const Expanded(child: Text('خالی یعنی نامحدود. «کنترل» یعنی ثبت سفارش بیش از سقف روزانه مجاز نیست.')),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('نام کالا', 0), sakanHead('تعداد کل موجودی', 120), sakanHead('تعداد مجاز سفارش روزانه', 160), sakanHead('کنترل', 70), sakanHead('سفارش ثبت شده امروز', 140), sakanHead('مانده سفارش', 110)],
              count: list.length,
              row: (ctx, i) {
                final p = list[i];
                final quota = double.tryParse(p.info['dailyQuota'] ?? '');
                final done = orderedToday(p);
                return Container(
                  color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                  child: Row(children: [
                    sakanCell(Text(p.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                    sakanCell(Text(fmtQty(s.stock(p.id))), 120),
                    sakanCell(
                      TextFormField(
                        key: ValueKey(p.id),
                        initialValue: quota == null ? '' : fmtQty(quota),
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                        onFieldSubmitted: (v) {
                          final q = parseQty(v);
                          if (v.trim().isEmpty) {
                            p.info.remove('dailyQuota');
                          } else {
                            p.info['dailyQuota'] = fmtQty(q);
                          }
                          s.upsertProduct(p);
                        },
                      ),
                      160,
                    ),
                    sakanCell(
                      Checkbox(
                        value: p.info['dailyQuotaControl'] == '1',
                        onChanged: (v) {
                          if (v == true) {
                            p.info['dailyQuotaControl'] = '1';
                          } else {
                            p.info.remove('dailyQuotaControl');
                          }
                          s.upsertProduct(p);
                        },
                      ),
                      70,
                    ),
                    sakanCell(Text(fmtQty(done)), 140),
                    sakanCell(Text(quota == null ? 'نامحدود' : fmtQty(quota - done)), 110),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Checks «تعیین سفارش روزانه» for an order being saved; returns an error or null.
String? checkDailyQuota(AppStore s, DateTime date, String? orderId, List<(String, double)> lines) {
  final day = dateOnly(date);
  final want = <String, double>{};
  for (final (id, q) in lines) {
    want[id] = (want[id] ?? 0) + q;
  }
  for (final e in want.entries) {
    final p = s.product(e.key);
    if (p == null || p.info['dailyQuotaControl'] != '1') continue;
    final quota = double.tryParse(p.info['dailyQuota'] ?? '');
    if (quota == null) continue;
    final other = s.invoices
        .where((i) => i.proforma && i.id != orderId && dateOnly(i.date) == day)
        .expand((i) => i.lines)
        .where((x) => x.productId == p.id)
        .fold<double>(0, (a, x) => a + x.qty);
    if (other + e.value > quota + 1e-9) return 'سقف سفارش روزانه ${p.name} ${fmtQty(quota)} است (ثبت شده امروز: ${fmtQty(other)})';
  }
  return null;
}

// ================================================================ مرکز دفاتر

Future<void> showBookCenters(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Centers());

/// Ledgers and detail accounts that can belong to a center: (key, title).
List<(String, String)> centerCandidates(AppStore s) => [
      for (final m in allMoeens) (m.code, '${m.code}  ${m.name}'),
      for (final p in s.peopleSorted) ('$mDebtorsTrade|${p.id}', 'اشخاص / ${p.name}'),
      for (final a in s.accounts) ('${a.type == AccountType.cash ? mCash : mBank}|${a.id}', '${a.type == AccountType.cash ? 'صندوق' : 'بانک'} / ${a.name}'),
      for (final p in s.productsSorted) ('$mStock|${p.id}', 'کالا / ${p.name}'),
    ];

class _Centers extends StatefulWidget {
  const _Centers();

  @override
  State<_Centers> createState() => _CentersState();
}

class _CentersState extends State<_Centers> {
  String? _sel;
  String _q = '';

  void _save(AppStore s, BookCenter c) {
    final i = s.bookCenters.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      s.bookCenters[i] = c;
    } else {
      s.bookCenters.add(c);
    }
    s.updateSettings((_) {});
    setState(() {});
  }

  Future<void> _edit(AppStore s, [BookCenter? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final note = TextEditingController(text: c?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: c == null ? 'تعریف مرکز دفتر' : 'ویرایش مرکز دفتر',
        width: 420,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت F10')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
        ],
        child: Column(children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام')),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final x = c ?? BookCenter(id: newId(), name: '');
      _save(s, x
        ..name = name.text.trim()
        ..note = note.text.trim());
      _sel = x.id;
    }
    name.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final sel = s.bookCenters.where((c) => c.id == _sel).firstOrNull;
    final cand = centerCandidates(s).where((c) => _q.isEmpty || c.$2.contains(_q)).toList();
    return SakanWindow(
      title: 'مدیریت دفاتر مرکزی',
      width: 1100,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 360,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('لیست مراکز دفتر', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                sakanBtn('تعریف', () => _edit(s), icon: Icons.add_rounded),
                sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
                sakanBtn('حذف', sel == null
                    ? null
                    : () {
                        s.bookCenters.removeWhere((c) => c.id == sel.id);
                        for (final g in s.centerGroups) {
                          g.centerIds.remove(sel.id);
                        }
                        s.updateSettings((_) {});
                        setState(() => _sel = null);
                      }, icon: Icons.delete_outline_rounded),
              ]),
              const SizedBox(height: 6),
              Expanded(
                child: Card(
                  child: ListView(children: [
                    for (final c in s.bookCenters)
                      ListTile(
                        dense: true,
                        selected: c.id == _sel,
                        title: Text(c.name),
                        subtitle: Text('${c.members.length} دفتر${c.note.isEmpty ? '' : ' — ${c.note}'}'),
                        onTap: () => setState(() => _sel = c.id),
                      ),
                    if (s.bookCenters.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('مرکز دفتری تعریف نشده')),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              sakanBtn('مدیریت گروه مراکز دفتر', () => showCenterGroups(context), icon: Icons.hub_outlined),
              const SizedBox(height: 6),
              sakanBtn('گزارش دفاتر به تفکیک مرکز', () => printCenterReport(s), icon: Icons.print_outlined),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(sel == null ? 'یک مرکز دفتر انتخاب کنید' : 'لیست دفاتر مرتبط با «${sel.name}»', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(decoration: const InputDecoration(hintText: 'جستجوی دفتر', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = v.trim())),
              const SizedBox(height: 6),
              Expanded(
                child: Card(
                  child: ListView(children: [
                    for (final c in cand.take(400))
                      CheckboxListTile(
                        dense: true,
                        value: sel?.members.contains(c.$1) ?? false,
                        title: Text(c.$2),
                        onChanged: sel == null
                            ? null
                            : (v) {
                                if (v == true) {
                                  sel.members.add(c.$1);
                                } else {
                                  sel.members.remove(c.$1);
                                }
                                _save(s, sel);
                              },
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Balance of a center from the journal (debit positive).
int centerBalance(AppStore s, BookCenter c, List<Posting> journal) {
  var b = 0;
  for (final p in journal) {
    if (c.members.contains(p.moeen) || c.members.contains('${p.moeen}|${p.tafsiliId ?? ''}')) b += p.debit - p.credit;
  }
  return b;
}

void printCenterReport(AppStore s) {
  final j = buildJournal(s);
  final rows = <List<String>>[];
  for (final c in s.bookCenters) {
    final b = centerBalance(s, c, j);
    final groups = s.centerGroups.where((g) => g.centerIds.contains(c.id)).map((g) => g.name).join('، ');
    rows.add([c.name, groups, '${c.members.length}', groupDigits(b > 0 ? b : 0), groupDigits(b < 0 ? -b : 0)]);
  }
  printTable(
    store: s,
    title: 'گزارش دفاتر موجود در دفاتر مرکزی به تفکیک',
    headers: const ['مرکز دفتر', 'گروه', 'تعداد دفتر', 'مانده بدهکار', 'مانده بستانکار'],
    rows: rows,
    numeric: const {2, 3, 4},
    fileName: 'markaz-daftar',
  );
}

/// «مدیریت گروه های دفاتر مرکزی».
Future<void> showCenterGroups(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Groups());

class _Groups extends StatefulWidget {
  const _Groups();

  @override
  State<_Groups> createState() => _GroupsState();
}

class _GroupsState extends State<_Groups> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final sel = s.centerGroups.where((g) => g.id == _sel).firstOrNull;
    Future<void> add() async {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => FormDialog(
          title: 'تعریف گروه دفاتر مرکزی',
          width: 380,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
          ],
          child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'نام گروه')),
        ),
      );
      if (ok == true && c.text.trim().isNotEmpty) {
        s.centerGroups.add(CenterGroup(id: newId(), name: c.text.trim()));
        s.updateSettings((_) {});
        setState(() {});
      }
      c.dispose();
    }

    return FormDialog(
      title: 'مدیریت گروه های دفاتر مرکزی',
      width: 780,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت F10'))],
      child: SizedBox(
        height: 420,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Text('لیست گروه مراکز دفتر', style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(onPressed: add, icon: const Icon(Icons.add_rounded)),
                IconButton(
                  onPressed: sel == null
                      ? null
                      : () {
                          s.centerGroups.removeWhere((g) => g.id == sel.id);
                          s.updateSettings((_) {});
                          setState(() => _sel = null);
                        },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]),
              Expanded(
                child: ListView(children: [
                  for (final g in s.centerGroups)
                    ListTile(dense: true, selected: g.id == _sel, title: Text(g.name), subtitle: Text('${g.centerIds.length} مرکز'), onTap: () => setState(() => _sel = g.id)),
                ]),
              ),
            ]),
          ),
          const VerticalDivider(),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('لیست مراکز دفتر هر گروه', style: TextStyle(fontWeight: FontWeight.w800)),
              Expanded(
                child: ListView(children: [
                  for (final c in s.bookCenters)
                    CheckboxListTile(
                      dense: true,
                      value: sel?.centerIds.contains(c.id) ?? false,
                      title: Text(c.name),
                      onChanged: sel == null
                          ? null
                          : (v) {
                              if (v == true) {
                                sel.centerIds.add(c.id);
                              } else {
                                sel.centerIds.remove(c.id);
                              }
                              s.updateSettings((_) {});
                              setState(() {});
                            },
                    ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// «انتخاب مرکز دفتر» for a product (its stock detail account).
Future<void> pickProductCenters(BuildContext context, Product p) async {
  final s = StoreScope.read(context);
  final key = '$mStock|${p.id}';
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => FormDialog(
        title: 'انتخاب دفتر مرکزی — ${p.name}',
        width: 420,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید F9'))],
        child: Column(children: [
          for (final c in s.bookCenters)
            CheckboxListTile(
              dense: true,
              value: c.members.contains(key),
              title: Text(c.name),
              onChanged: (v) => set(() {
                if (v == true) {
                  c.members.add(key);
                } else {
                  c.members.remove(key);
                }
                s.updateSettings((_) {});
              }),
            ),
          if (s.bookCenters.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('مرکز دفتری تعریف نشده (متفرقه ← مرکز دفاتر)')),
        ]),
      ),
    ),
  );
}

// ================================================================ تعدیل قیمت تمام شده

/// «اعمال افزایش / کاهش در قیمت تمام شده کالا»: changes the stock value of a
/// product (and so its average cost) against a chosen ledger.
Future<void> showCostAdjust(BuildContext context, {required bool increase}) =>
    showDialog<void>(context: context, builder: (_) => _CostAdjust(increase: increase));

class _CostAdjust extends StatefulWidget {
  final bool increase;
  const _CostAdjust({required this.increase});

  @override
  State<_CostAdjust> createState() => _CostAdjustState();
}

class _CostAdjustState extends State<_CostAdjust> {
  String? _product;
  String _acc = mOtherExpense;
  DateTime _date = DateTime.now();
  bool _perUnit = false;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final p = s.product(_product);
    final qty = p == null ? 0.0 : s.stock(p.id);
    final entered = parseMoney(_amount.text);
    final total = _perUnit ? (entered * qty).round() : entered;
    final title = widget.increase ? 'اعمال افزایش در قیمت تمام شده کالا' : 'اعمال کاهش در قیمت تمام شده کالا';
    return FormDialog(
      title: title,
      width: 620,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            if (p == null) return setState(() => _err = 'کالا را انتخاب کنید');
            if (total <= 0) return setState(() => _err = 'مبلغ را وارد کنید');
            if (qty <= 0) return setState(() => _err = 'کالا موجودی ندارد؛ قیمت تمام شده فقط روی موجودی فعلی اعمال می‌شود');
            final desc = _note.text.trim().isEmpty ? '$title — ${p.name}' : _note.text.trim();
            s.saveVoucher(Voucher(
              id: newId(),
              number: s.nextVoucherNumber(),
              fixedNumber: s.nextFixedNumber(),
              date: _date,
              desc: desc,
              kind: 'costAdjust',
              meta: {'product': p.id},
              lines: [
                VoucherLine(moeen: mStock, tafsiliId: p.id, desc: desc, debit: widget.increase ? total : 0, credit: widget.increase ? 0 : total),
                VoucherLine(moeen: _acc, desc: desc, debit: widget.increase ? 0 : total, credit: widget.increase ? total : 0),
              ],
            ));
            Navigator.pop(context);
            toast(context, 'قیمت تمام شده ${p.name} اکنون ${groupDigits(s.avgCost(p.id))} است');
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String?>(
          value: _product,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'کالا'),
          items: [for (final x in s.productsSorted) DropdownMenuItem<String?>(value: x.id, child: Text(x.name))],
          onChanged: (v) => setState(() => _product = v),
        ),
        if (p != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('موجودی ${fmtQty(qty)} ${p.unit} — قیمت تمام شده فعلی ${groupDigits(s.avgCost(p.id))}')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _amount,
              textDirection: TextDirection.ltr,
              inputFormatters: [MoneyInputFormatter()],
              decoration: InputDecoration(labelText: _perUnit ? 'مبلغ برای هر واحد' : 'مبلغ کل'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(label: const Text('برای هر واحد'), selected: _perUnit, onSelected: (v) => setState(() => _perUnit = v)),
        ]),
        if (p != null && qty > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('قیمت تمام شده جدید: ${groupDigits(((s.avgCost(p.id) * qty + (widget.increase ? total : -total)) / qty).round())}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _acc,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'حساب مقابل'),
          items: [for (final m in allMoeens) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _acc = v ?? _acc),
        ),
        const SizedBox(height: 10),
        SizedBox(width: 220, child: DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
        const SizedBox(height: 10),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'شرح')),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}

// ================================================================ تنظیم دکمه‌ها

/// «تنظیم دکمه‌ها» — which ribbon buttons are shown.
Future<void> showButtonSettings(BuildContext context, List<(String, List<String>)> catalog) =>
    showDialog<void>(context: context, builder: (_) => _Buttons(catalog: catalog));

class _Buttons extends StatefulWidget {
  final List<(String, List<String>)> catalog;
  const _Buttons({required this.catalog});

  @override
  State<_Buttons> createState() => _ButtonsState();
}

class _ButtonsState extends State<_Buttons> {
  late Set<String> _hidden;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _hidden = {...StoreScope.read(context).hiddenButtons};
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'تنظیم دکمه‌ها',
      width: 760,
      leading: TextButton(onPressed: () => setState(_hidden.clear), child: const Text('نمایش همه')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            _hidden.remove('تنظیم دکمه‌ها');
            StoreScope.read(context).setHiddenButtons(_hidden);
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('دکمه‌هایی که تیک ندارند در نوار منو نمایش داده نمی‌شوند.'),
        for (final (tab, items) in widget.catalog) ...[
          const SizedBox(height: 8),
          Text(tab, style: const TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final i in items)
              FilterChip(
                label: Text(i),
                selected: !_hidden.contains(i),
                onSelected: i == 'تنظیم دکمه‌ها' ? null : (v) => setState(() => v ? _hidden.remove(i) : _hidden.add(i)),
              ),
          ]),
        ],
      ]),
    );
  }
}

// ================================================================ ارتباط از راه دور

/// «ارتباط از راه دور» — opens Windows «Quick Assist» for remote support.
Future<void> showRemoteSupport(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'ارتباط از راه دور',
        width: 520,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          FilledButton.icon(
            onPressed: () async {
              try {
                if (Platform.isWindows) {
                  await Process.start('explorer.exe', ['ms-quick-assist:']);
                }
              } catch (_) {
                if (ctx.mounted) toast(ctx, 'Quick Assist باز نشد', error: true);
              }
            },
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('باز کردن Quick Assist'),
          ),
        ],
        child: const Text(
          'برای پشتیبانی از راه دور، «Quick Assist» ویندوز باز می‌شود. کد ۶ رقمی را از پشتیبان بگیرید و وارد کنید تا بتواند صفحه شما را ببیند. '
          'اطلاعات تراز روی همین کامپیوتر می‌ماند و فقط تصویر صفحه به اشتراک گذاشته می‌شود.',
        ),
      ),
    );
