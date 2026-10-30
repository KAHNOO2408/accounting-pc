import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show pickPersonId;
import 'txn_dialog.dart' show showTxnDialog;

// ================================================================ کارت هواداری

Future<void> showLoyalty(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Loyalty());

class _Loyalty extends StatefulWidget {
  const _Loyalty();

  @override
  State<_Loyalty> createState() => _LoyaltyState();
}

class _LoyaltyState extends State<_Loyalty> {
  String? _sel;
  String _q = '';

  Future<void> _issue(AppStore s) async {
    final pid = await pickPersonId(context, title: 'صاحب کارت');
    if (pid == null || !mounted) return;
    final no = TextEditingController(text: '${1000 + s.loyaltyCards.length + 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'ثبت کارت — ${s.person(pid)?.name ?? ''}',
        width: 380,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
        child: TextField(controller: no, autofocus: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره کارت (یا کشیدن کارت)')),
      ),
    );
    final n = normalizeDigits(no.text.trim());
    no.dispose();
    if (ok != true || n.isEmpty) return;
    if (s.loyaltyCards.any((c) => c.number == n)) {
      if (mounted) toast(context, 'این شماره کارت قبلا ثبت شده', error: true);
      return;
    }
    s.loyaltyCards.add(LoyaltyCard(number: n, personId: pid, issued: DateTime.now()));
    s.updateSettings((_) {});
    setState(() => _sel = n);
  }

  Future<void> _gifts(AppStore s) async {
    final per = TextEditingController(text: groupDigits(s.loyalty.amountPerPoint));
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'تنظیم جدول هدیه',
          width: 620,
          actions: [
            FilledButton(
              onPressed: () {
                s.loyalty.amountPerPoint = parseMoney(per.text);
                s.loyalty.gifts.removeWhere((g) => g.points <= 0);
                s.updateSettings((_) {});
                Navigator.pop(ctx);
              },
              child: const Text('تایید'),
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: per, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'هر چند مبلغ خرید = یک امتیاز')),
            const SizedBox(height: 10),
            for (final g in s.loyalty.gifts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 100, child: TextFormField(initialValue: '${g.points}', textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'امتیاز', isDense: true), onChanged: (v) => g.points = int.tryParse(normalizeDigits(v)) ?? 0)),
                  const SizedBox(width: 6),
                  Expanded(child: TextFormField(initialValue: g.title, decoration: const InputDecoration(labelText: 'هدیه', isDense: true), onChanged: (v) => g.title = v.trim())),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 140,
                    child: TextFormField(
                      initialValue: g.amount == 0 ? '' : groupDigits(g.amount),
                      textDirection: TextDirection.ltr,
                      inputFormatters: [MoneyInputFormatter()],
                      decoration: const InputDecoration(labelText: 'ارزش', isDense: true),
                      onChanged: (v) => g.amount = parseMoney(v),
                    ),
                  ),
                  IconButton(onPressed: () => set(() => s.loyalty.gifts.remove(g)), icon: const Icon(Icons.close_rounded, size: 18)),
                ]),
              ),
            TextButton.icon(onPressed: () => set(() => s.loyalty.gifts.add(GiftRow(points: 100, title: 'تخفیف'))), icon: const Icon(Icons.add_rounded), label: const Text('ردیف هدیه')),
          ]),
        ),
      ),
    );
    per.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final cards = s.loyaltyCards.where((c) => _q.isEmpty || c.number.contains(_q) || (s.person(c.personId)?.name.contains(_q) ?? false)).toList();
    final sel = s.loyaltyCards.where((c) => c.number == _sel).firstOrNull;
    return SakanWindow(
      title: 'کارت هواداری',
      width: 1100,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('ثبت کارت', () => _issue(s), icon: Icons.add_card_rounded),
            sakanBtn('تنظیم جدول هدیه', () => _gifts(s), icon: Icons.card_giftcard_rounded),
            sakanBtn(sel?.active == false ? 'فعال کردن کارت' : 'غیرفعال کردن کارت', sel == null
                ? null
                : () => setState(() {
                      sel.active = !sel.active;
                      s.updateSettings((_) {});
                    }), icon: Icons.block_rounded),
            sakanBtn('لیست کارت‌های استفاده شده', () => printTable(
                  store: s,
                  title: 'لیست کارت های هواداری استفاده شده در عملیات',
                  headers: const ['تاریخ', 'کارت', 'صاحب کارت', 'هدیه', 'امتیاز', 'ارزش'],
                  rows: [
                    for (final r in s.redemptions)
                      [jFormat(r.date), r.card, s.person(s.loyaltyCards.where((c) => c.number == r.card).firstOrNull?.personId)?.name ?? '', r.title, '${r.points}', groupDigits(r.amount)],
                  ],
                  numeric: const {4, 5},
                  fileName: 'kart-havadari',
                ), icon: Icons.print_outlined),
            SizedBox(width: 220, child: TextField(decoration: const InputDecoration(hintText: 'شماره کارت یا نام', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = normalizeDigits(v.trim())))),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: SakanGrid(
                  header: [sakanHead('شماره کارت', 120), sakanHead('صاحب کارت', 0), sakanHead('خرید', 130), sakanHead('امتیاز', 80), sakanHead('وضعیت', 80)],
                  count: cards.length,
                  empty: 'کارتی ثبت نشده',
                  row: (ctx, i) {
                    final c = cards[i];
                    final on = c.number == _sel;
                    final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                    return InkWell(
                      onTap: () => setState(() => _sel = c.number),
                      child: Container(
                        color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                        child: Row(children: [
                          sakanCell(Text(c.number, style: st), 120),
                          sakanCell(Text(s.person(c.personId)?.name ?? '', style: st), 0, align: Alignment.centerRight),
                          sakanCell(Text(groupDigits(s.loyaltyPurchases(c)), style: st), 130),
                          sakanCell(Text('${s.loyaltyPoints(c)}', style: st.copyWith(fontWeight: FontWeight.w800)), 80),
                          sakanCell(Text(c.active ? 'فعال' : 'غیرفعال', style: st), 80),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 330,
                child: Card(
                  child: sel == null
                      ? const Center(child: Text('یک کارت انتخاب کنید'))
                      : ListView(padding: const EdgeInsets.all(10), children: [
                          Text('${s.person(sel.personId)?.name ?? ''} — کارت ${sel.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('امتیاز کسب شده ${s.loyaltyEarned(sel)} — استفاده شده ${s.loyaltyUsed(sel)} — مانده ${s.loyaltyPoints(sel)}'),
                          const Divider(),
                          const Text('هدیه‌های قابل دریافت:'),
                          for (final g in s.loyalty.gifts)
                            ListTile(
                              dense: true,
                              title: Text('${g.title} (${g.points} امتیاز)'),
                              subtitle: g.amount == 0 ? null : Text('ارزش ${groupDigits(g.amount)}'),
                              trailing: FilledButton(
                                onPressed: !sel.active || s.loyaltyPoints(sel) < g.points
                                    ? null
                                    : () {
                                        s.redeem(sel, g);
                                        setState(() {});
                                        toast(context, '«${g.title}» برای ${s.person(sel.personId)?.name ?? ''} ثبت شد');
                                      },
                                child: const Text('اعمال'),
                              ),
                            ),
                          if (s.loyalty.gifts.isEmpty) const Text('جدول هدیه خالی است — «تنظیم جدول هدیه»'),
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

// ================================================================ قرعه کشی

Future<void> showDraws(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Draws());

class _Draws extends StatefulWidget {
  const _Draws();

  @override
  State<_Draws> createState() => _DrawsState();
}

class _DrawsState extends State<_Draws> {
  String? _sel;

  Future<void> _edit(AppStore s, [DrawCampaign? d]) async {
    final name = TextEditingController(text: d?.name ?? '');
    final prefix = TextEditingController(text: d?.prefix ?? 'Q');
    final min = TextEditingController(text: d == null || d.minAmount == 0 ? '' : groupDigits(d.minAmount));
    final note = TextEditingController(text: d?.note ?? '');
    var from = d?.from ?? dateOnly(DateTime.now());
    var to = d?.to ?? dateOnly(DateTime.now()).add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'تعریف کد قرعه کشی',
          width: 520,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'نام کد / عنوان قرعه کشی')),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 100, child: TextField(controller: prefix, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'پیشوند'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: min, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'هر چند مبلغ خرید = یک کد'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DateField(label: 'از تاریخ', value: from, onChanged: (v) => set(() => from = v ?? from))),
              const SizedBox(width: 8),
              Expanded(child: DateField(label: 'تا تاریخ', value: to, onChanged: (v) => set(() => to = v ?? to))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات (جایزه)')),
          ]),
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final x = d ?? DrawCampaign(id: newId(), name: '', from: from, to: to);
      x
        ..name = name.text.trim()
        ..prefix = prefix.text.trim()
        ..minAmount = parseMoney(min.text)
        ..from = from
        ..to = to
        ..note = note.text.trim();
      if (d == null) s.draws.add(x);
      s.updateSettings((_) {});
      setState(() => _sel = x.id);
    }
    for (final c in [name, prefix, min, note]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final d = s.draws.where((x) => x.id == _sel).firstOrNull ?? s.draws.firstOrNull;
    final codes = d == null ? <(String, Invoice)>[] : s.drawCodes(d);
    return SakanWindow(
      title: 'لیست کدهای قرعه کشی',
      width: 1000,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('تعریف کد قرعه کشی', () => _edit(s), icon: Icons.add_rounded),
            if (d != null) ...[
              DropdownButton<String>(value: d.id, items: [for (final x in s.draws) DropdownMenuItem(value: x.id, child: Text(x.name))], onChanged: (v) => setState(() => _sel = v)),
              sakanBtn('ویرایش', () => _edit(s, d), icon: Icons.edit_outlined),
              sakanBtn('انجام قرعه کشی', codes.isEmpty
                  ? null
                  : () {
                      final w = codes[Random.secure().nextInt(codes.length)];
                      d.winner = w.$1;
                      s.updateSettings((_) {});
                      setState(() {});
                    }, icon: Icons.casino_outlined),
              sakanBtn('چاپ', () => printTable(
                    store: s,
                    title: 'جدول ثبت کد قرعه کشی — ${d.name}',
                    headers: const ['کد', 'فاکتور', 'تاریخ', 'خریدار', 'مبلغ'],
                    rows: [for (final (c, i) in codes) [c, '${i.number}', jFormat(i.date), s.person(i.personId)?.name ?? 'متفرقه', groupDigits(i.total)]],
                    numeric: const {4},
                    fileName: 'ghore-keshi',
                  ), icon: Icons.print_outlined),
              sakanBtn('حذف', () {
                s.draws.remove(d);
                s.updateSettings((_) {});
                setState(() => _sel = null);
              }, icon: Icons.delete_outline_rounded),
            ],
          ]),
          if (d != null) ...[
            const SizedBox(height: 6),
            Text('${jFormat(d.from)} تا ${jFormat(d.to)} — ${codes.length} کد${d.note.isEmpty ? '' : ' — ${d.note}'}'),
            if (d.winner != null)
              Text(
                'برنده: ${d.winner} — ${s.person(codes.where((c) => c.$1 == d.winner).firstOrNull?.$2.personId)?.name ?? 'متفرقه'}',
                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2E7D32), fontSize: 16),
              ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 140), sakanHead('فاکتور', 90), sakanHead('تاریخ', 100), sakanHead('خریدار', 0), sakanHead('مبلغ', 130)],
              count: codes.length,
              empty: 'فاکتور فروشی در بازه نیست',
              row: (ctx, i) {
                final (c, inv) = codes[i];
                return Container(
                  color: c == d?.winner ? const Color(0xFFD7F2D7) : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                  child: Row(children: [
                    sakanCell(Text(c, textDirection: TextDirection.ltr), 140),
                    sakanCell(Text('${inv.number}'), 90),
                    sakanCell(Text(jFormat(inv.date)), 100),
                    sakanCell(Text(s.person(inv.personId)?.name ?? 'متفرقه'), 0, align: Alignment.centerRight),
                    sakanCell(Text(groupDigits(inv.total)), 130),
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

// ================================================================ پول شمار

const banknotes = [5000000, 2000000, 1000000, 500000, 200000, 100000, 50000, 20000, 10000, 5000, 2000, 1000];

Future<void> showCashCounter(BuildContext context) {
  final counts = <int, TextEditingController>{for (final b in banknotes) b: TextEditingController()};
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final total = counts.entries.fold<int>(0, (a, e) => a + e.key * (int.tryParse(normalizeDigits(e.value.text)) ?? 0));
      return FormDialog(
        title: 'پول شمار',
        width: 460,
        leading: TextButton(
          onPressed: () => set(() {
            for (final c in counts.values) {
              c.clear();
            }
          }),
          child: const Text('پاک کردن'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('مبالغ به ریال (اسکناس و ایران چک)', style: TextStyle(fontSize: 12)),
          for (final b in banknotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(width: 120, child: Text(groupDigits(b), textDirection: TextDirection.ltr)),
                const Text('×'),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextField(controller: counts[b], textDirection: TextDirection.ltr, decoration: const InputDecoration(isDense: true, hintText: '0'), onChanged: (_) => set(() {}))),
                const Spacer(),
                Text(groupDigits(b * (int.tryParse(normalizeDigits(counts[b]!.text)) ?? 0))),
              ]),
            ),
          const Divider(),
          Text('جمع: ${groupDigits(total)} ریال (${groupDigits(total ~/ 10)} تومان)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      );
    }),
  ).whenComplete(() {
    for (final c in counts.values) {
      c.dispose();
    }
  });
}

// ================================================================ تسویه فاکتور به فاکتور

Future<void> showInvoiceOffset(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Offset());

class _Offset extends StatefulWidget {
  const _Offset();

  @override
  State<_Offset> createState() => _OffsetState();
}

class _OffsetState extends State<_Offset> {
  String? _person, _sale, _purchase;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    int used(String id) => s.offsets.where((o) => o.saleId == id || o.purchaseId == id).fold(0, (a, o) => a + o.amount);
    final sales = s.realInvoices.where((i) => i.personId == _person && i.kind == InvoiceKind.sale && i.total - used(i.id) > 0).toList();
    final buys = s.realInvoices.where((i) => i.personId == _person && i.kind == InvoiceKind.purchase && i.total - used(i.id) > 0).toList();
    final sale = sales.where((i) => i.id == _sale).firstOrNull, buy = buys.where((i) => i.id == _purchase).firstOrNull;
    final amount = sale == null || buy == null ? 0 : min(sale.total - used(sale.id), buy.total - used(buy.id));
    Widget pick(String title, List<Invoice> list, String? v, ValueChanged<String?> on) => Expanded(
          child: Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(
                child: ListView(children: [
                  for (final i in list)
                    ListTile(
                      dense: true,
                      selected: i.id == v,
                      title: Text('فاکتور ${i.number} — ${jFormat(i.date)}'),
                      trailing: Text('${groupDigits(i.total - used(i.id))} از ${groupDigits(i.total)}'),
                      onTap: () => on(i.id),
                    ),
                ]),
              ),
            ]),
          ),
        );
    return FormDialog(
      title: 'تسویه فاکتور به فاکتور',
      width: 900,
      leading: TextButton.icon(
        onPressed: () => printTable(
          store: s,
          title: 'لیست سندهای تسویه',
          headers: const ['تاریخ', 'طرف حساب', 'فاکتور فروش', 'فاکتور خرید', 'مبلغ'],
          rows: [
            for (final o in s.offsets)
              () {
                final a = s.invoices.where((i) => i.id == o.saleId).firstOrNull, b = s.invoices.where((i) => i.id == o.purchaseId).firstOrNull;
                return [jFormat(o.date), s.person(a?.personId)?.name ?? '', '${a?.number ?? ''}', '${b?.number ?? ''}', groupDigits(o.amount)];
              }(),
          ],
          numeric: const {4},
          fileName: 'tasvie-factor',
        ),
        icon: const Icon(Icons.print_outlined),
        label: const Text('لیست سندهای تسویه'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
        FilledButton(
          onPressed: amount <= 0
              ? null
              : () {
                  s.offsets.add(InvoiceOffset(id: newId(), saleId: sale!.id, purchaseId: buy!.id, amount: amount, date: DateTime.now()));
                  s.updateSettings((_) {});
                  setState(() => _sale = _purchase = null);
                  toast(context, 'فاکتور ${sale.number} با فاکتور خرید ${buy.number} به مبلغ ${groupDigits(amount)} تسویه شد');
                },
          child: Text('تسویه ${groupDigits(amount)}'),
        ),
      ],
      child: SizedBox(
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(
            onPressed: () async {
              final id = await pickPersonId(context, title: 'طرف حساب');
              if (id != null) {
                setState(() {
                  _person = id;
                  _sale = null;
                  _purchase = null;
                });
              }
            },
            icon: const Icon(Icons.person_search_rounded),
            label: Text(s.person(_person)?.name ?? 'انتخاب طرف حساب'),
          ),
          if (_person != null) Text('مانده حساب: ${groupDigits(s.personBalance(_person!))} — طلب و بدهی اشخاص در حساب یکجا جمع می‌شود؛ این تسویه پیوند فاکتورها را ثبت می‌کند.', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              pick('فاکتورهای فروش باز', sales, _sale, (v) => setState(() => _sale = v)),
              pick('فاکتورهای خرید باز', buys, _purchase, (v) => setState(() => _purchase = v)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ تسویه پیک

Future<void> showCourierSettle(BuildContext context) {
  final s = StoreScope.read(context);
  final ids = {for (final i in s.realInvoices) if ((i.info['courier'] ?? '').isNotEmpty) i.info['courier']!};
  return showDialog<void>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'تسویه پیک',
      width: 560,
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('سفارش‌های پیک که نقدی دریافت نشده‌اند به حساب پیک ثبت می‌شوند. با «دریافت از پیک» وجه را به صندوق بگیرید.', style: TextStyle(fontSize: 12)),
        for (final id in ids)
          ListTile(
            title: Text(s.person(id)?.name ?? ''),
            subtitle: Text('${s.realInvoices.where((i) => i.info['courier'] == id && dateOnly(i.date) == dateOnly(DateTime.now())).length} سفارش امروز — مانده ${groupDigits(s.personBalance(id))}'),
            trailing: FilledButton(
              onPressed: s.personBalance(id) <= 0 ? null : () => showTxnDialog(ctx, type: TxnType.collect, personId: id, title: 'دریافت از پیک'),
              child: const Text('دریافت از پیک'),
            ),
          ),
        if (ids.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('سفارش پیکی ثبت نشده')),
      ]),
    ),
  );
}

// ================================================================ سرشکن انحراف جذب سربار

Future<void> showOverheadVariance(BuildContext context) {
  final s = StoreScope.read(context);
  var from = DateTime(dateOnly(DateTime.now()).year, 1, 1), to = dateOnly(DateTime.now());
  var ledger = '1170';
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final (absorbed, actual) = s.overheadVariance(from, to, actualLedger: ledger);
      return FormDialog(
        title: 'سرشکن انحراف جذب سربار',
        width: 560,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          FilledButton(
            onPressed: absorbed == 0 && actual == 0
                ? null
                : () {
                    final v = s.postOverheadVariance(from, to, actualLedger: ledger);
                    Navigator.pop(ctx);
                    if (v != null) toast(context, 'سند ${v.number} ثبت شد');
                  },
            child: const Text('صدور سند'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: DateField(label: 'از تاریخ', value: from, onChanged: (v) => set(() => from = v ?? from))),
            const SizedBox(width: 8),
            Expanded(child: DateField(label: 'تا تاریخ', value: to, onChanged: (v) => set(() => to = v ?? to))),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: ledger,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'حساب سربار واقعی'),
            items: [for (final m in allMoeens) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => ledger = v ?? ledger),
          ),
          const SizedBox(height: 10),
          Text('سربار جذب شده (2050): ${groupDigits(absorbed)}'),
          Text('سربار واقعی ($ledger): ${groupDigits(actual)}'),
          Text('انحراف (5030): ${groupDigits(actual - absorbed)} ${actual > absorbed ? '(کم جذب)' : actual < absorbed ? '(بیش جذب)' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );
    }),
  );
}

// ================================================================ حذف بدون تراکنش

Future<void> showCleanup(BuildContext context) {
  final s = StoreScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final ppl = s.unusedPeople(), prd = s.unusedProducts();
      return FormDialog(
        title: 'حذف دفاتر بدون تراکنش',
        width: 560,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            title: Text('حذف دفاتر اشخاص بدون تراکنش (${ppl.length})'),
            subtitle: Text(ppl.take(8).map((p) => p.name).join('، '), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: FilledButton.tonal(
              onPressed: ppl.isEmpty
                  ? null
                  : () async {
                      if (!await confirm(ctx, 'حذف', '${ppl.length} شخص بدون تراکنش حذف شود؟')) return;
                      final n = s.removeUnused(persons: true);
                      set(() {});
                      if (ctx.mounted) toast(ctx, '$n شخص حذف شد');
                    },
              child: const Text('حذف'),
            ),
          ),
          ListTile(
            title: Text('حذف کالاهای بدون تراکنش (${prd.length})'),
            subtitle: Text(prd.take(8).map((p) => p.name).join('، '), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: FilledButton.tonal(
              onPressed: prd.isEmpty
                  ? null
                  : () async {
                      if (!await confirm(ctx, 'حذف', '${prd.length} کالای بدون تراکنش حذف شود؟')) return;
                      final n = s.removeUnused(items: true);
                      set(() {});
                      if (ctx.mounted) toast(ctx, '$n کالا حذف شد');
                    },
              child: const Text('حذف'),
            ),
          ),
          const Text('پیش از حذف، از اطلاعات نسخه پشتیبان بگیرید.', style: TextStyle(fontSize: 12)),
        ]),
      );
    }),
  );
}

// ================================================================ پیام های داخلی

Future<void> showMessages(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Messages());

class _Messages extends StatefulWidget {
  const _Messages();

  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  final _text = TextEditingController();
  String _to = '*';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = StoreScope.read(context);
      s.markRead(s.currentUser.id);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final me = s.currentUser.id;
    final list = s.messages.where((m) => m.to == me || m.to == '*' || m.from == me).toList()..sort((a, b) => b.date.compareTo(a.date));
    return FormDialog(
      title: 'مدیریت پیام های داخلی',
      width: 680,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!s.multiUser) const Text('برای پیام بین کاربران، در «فرم کاربران» کاربر تعریف کنید.', style: TextStyle(fontSize: 12)),
        Row(children: [
          DropdownButton<String>(
            value: _to,
            items: [
              const DropdownMenuItem(value: '*', child: Text('همه کاربران')),
              for (final u in s.allUsers.where((u) => u.id != me)) DropdownMenuItem(value: u.id, child: Text(u.name)),
            ],
            onChanged: (v) => setState(() => _to = v ?? '*'),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _text, decoration: const InputDecoration(hintText: 'متن پیام', isDense: true), onSubmitted: (_) => _send(s))),
          IconButton(onPressed: () => _send(s), icon: const Icon(Icons.send_rounded)),
        ]),
        const SizedBox(height: 8),
        for (final m in list.take(200))
          ListTile(
            dense: true,
            leading: Icon(m.from == me ? Icons.north_east_rounded : Icons.south_west_rounded),
            title: Text(m.text),
            subtitle: Text('${s.userName(m.from)} ← ${m.to == '*' ? 'همه' : s.userName(m.to)} — ${jFormat(m.date)} ${m.date.hour}:${m.date.minute.toString().padLeft(2, '0')}'),
          ),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('پیامی نیست')),
      ]),
    );
  }

  void _send(AppStore s) {
    if (_text.text.trim().isEmpty) return;
    s.sendMessage(_to, _text.text.trim());
    _text.clear();
    setState(() {});
  }
}
