import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printInvoice, printSlip;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, pickPersonId;

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// «فاکتور رستورانی» — tables, open orders, kitchen slips and settlement.
Future<void> showRestaurant(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Restaurant());

class _Restaurant extends StatefulWidget {
  const _Restaurant();

  @override
  State<_Restaurant> createState() => _RestaurantState();
}

class _RestaurantState extends State<_Restaurant> {
  String? _tab; // RestTab id
  String _q = '';

  RestTab _openFor(AppStore s, RestTable t) {
    final cur = s.tabOfTable(t.id);
    if (cur != null) return cur;
    final n = RestTab(id: newId(), tableId: t.id, opened: DateTime.now());
    s.saveTab(n);
    return n;
  }

  void _add(AppStore s, RestTab t, Product p) {
    final l = t.lines.where((x) => x.productId == p.id && x.note.isEmpty).firstOrNull;
    if (l != null) {
      l.qty += 1;
    } else {
      t.lines.add(TabLine(productId: p.id, price: p.sellPrice));
    }
    s.saveTab(t);
  }

  void _kitchen(AppStore s, RestTab t) {
    final rows = s.takeKitchenRows(t);
    if (rows.isEmpty) return toast(context, 'ردیف جدیدی برای آشپزخانه نیست');
    final table = s.restTables.where((x) => x.id == t.tableId).firstOrNull;
    printSlip(
      store: s,
      title: 'فیش آشپزخانه',
      copies: s.restConfig.kitchenCopies,
      fields: [
        ('نوع', t.mode.label),
        if (table != null) ('میز', table.title),
        ('ساعت', _hm(DateTime.now())),
        if (t.note.isNotEmpty) ('هشدار', t.note),
      ],
      itemHeaders: const ['نام کالا', 'تعداد', 'توضیح'],
      items: [
        for (final (l, d) in rows) [s.product(l.productId)?.name ?? '', d < 0 ? 'لغو ${fmtQty(-d)}' : fmtQty(d), l.note],
      ],
      fileName: 'kitchen',
    );
  }

  Future<void> _settle(AppStore s, RestTab t) async {
    if (t.lines.every((l) => l.qty <= 0)) return toast(context, 'سفارش خالی است', error: true);
    final cash = s.activeAccounts;
    String? acc = s.restConfig.accountId ?? cash.firstOrNull?.id;
    var paid = true;
    final disc = TextEditingController();
    final service = (t.total * s.restConfig.servicePct / 100).round();
    final fee = t.mode == TabMode.delivery ? s.restConfig.deliveryFee : 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final total = t.total + service + fee - parseMoney(disc.text);
        return FormDialog(
          title: 'تسویه سفارش',
          width: 440,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت و چاپ F9')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('جمع سفارش: ${groupDigits(t.total)}'),
            if (service != 0) Text('حق سرویس: ${groupDigits(service)}'),
            if (fee != 0) Text('هزینه پیک: ${groupDigits(fee)}'),
            const SizedBox(height: 8),
            TextField(controller: disc, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'تخفیف'), onChanged: (_) => set(() {})),
            const SizedBox(height: 8),
            Text('قابل پرداخت: ${groupDigits(total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: paid, onChanged: (v) => set(() => paid = v), title: const Text('دریافت نقدی / کارتخوان')),
            if (paid)
              DropdownButtonFormField<String?>(
                value: acc,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'صندوق / بانک'),
                items: [for (final a in cash) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
                onChanged: (v) => set(() => acc = v),
              ),
            if (!paid && t.personId == null) const Text('برای ثبت نسیه، مشترک را انتخاب کنید', style: TextStyle(color: Colors.red)),
          ]),
        );
      }),
    );
    final discount = parseMoney(disc.text);
    disc.dispose();
    if (ok != true || !mounted) return;
    if (!paid && t.personId == null) return toast(context, 'برای ثبت نسیه، مشترک را انتخاب کنید', error: true);
    final inv = s.settleTab(t, accountId: acc, discount: discount, paid: paid);
    printInvoice(s, inv);
    setState(() => _tab = null);
  }

  Future<void> _move(AppStore s, RestTab t) async {
    final free = s.restTables.where((x) => s.tabOfTable(x.id) == null).toList();
    final to = await showDialog<String>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'انتقال به میز',
        width: 360,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
        child: Wrap(spacing: 6, runSpacing: 6, children: [for (final x in free) ActionChip(label: Text(x.title), onPressed: () => Navigator.pop(ctx, x.id))]),
      ),
    );
    if (to != null) {
      t
        ..tableId = to
        ..mode = TabMode.dineIn;
      s.saveTab(t);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final tab = s.restTabs.where((t) => t.id == _tab).firstOrNull;
    final menu = () {
      final flagged = s.productsSorted.where((p) => !p.archived && p.info['restaurant'] == '1').toList();
      final base = flagged.isEmpty ? s.productsSorted.where((p) => !p.archived).toList() : flagged;
      return base.where((p) => _q.isEmpty || p.name.contains(_q) || p.code == _q).toList();
    }();
    final today = dateOnly(DateTime.now());
    final others = s.restTabs.where((t) => t.tableId == null).toList();
    return SakanWindow(
      title: 'فاکتور رستورانی',
      width: 1240,
      height: 720,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // tables
          SizedBox(
            width: 430,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                sakanBtn('بیرون بر', () {
                  final t = RestTab(id: newId(), mode: TabMode.takeAway, opened: DateTime.now());
                  s.saveTab(t);
                  setState(() => _tab = t.id);
                }, icon: Icons.takeout_dining_outlined),
                sakanBtn('پیک', () {
                  final t = RestTab(id: newId(), mode: TabMode.delivery, opened: DateTime.now());
                  s.saveTab(t);
                  setState(() => _tab = t.id);
                }, icon: Icons.delivery_dining_outlined),
                sakanBtn('تعریف میز', () => showTables(context), icon: Icons.table_restaurant_outlined),
                sakanBtn('رزرو میز', () => showReservations(context), icon: Icons.event_seat_outlined),
                sakanBtn('تنظیمات', () => showRestSettings(context), icon: Icons.settings_outlined),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in [...s.restTables]..sort((a, b) => a.number.compareTo(b.number)))
                        () {
                          final open = s.tabOfTable(t.id);
                          final res = s.reservations.where((r) => r.tableId == t.id && !r.done && dateOnly(r.at) == today).firstOrNull;
                          final color = open != null ? const Color(0xFFF8D7D7) : (res != null ? const Color(0xFFFFF0C2) : const Color(0xFFDDF3DD));
                          final on = open != null && open.id == _tab;
                          return InkWell(
                            onTap: () => setState(() => _tab = _openFor(s, t).id),
                            child: Container(
                              width: 92,
                              height: 78,
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? sakanSel : Colors.black26, width: on ? 3 : 1)),
                              padding: const EdgeInsets.all(4),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                if (open != null) Text(groupDigits(open.total), style: const TextStyle(fontSize: 12)),
                                if (open == null && res != null) Text('رزرو ${_hm(res.at)}', style: const TextStyle(fontSize: 11)),
                                if (open == null && res == null) Text('${t.capacity} نفر', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ]),
                            ),
                          );
                        }(),
                      if (s.restTables.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('میزی تعریف نشده — «تعریف میز» را بزنید')),
                    ]),
                  ),
                ),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text('سفارش‌های بیرون بر و پیک', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(
                  height: 120,
                  child: ListView(children: [
                    for (final t in others)
                      ListTile(
                        dense: true,
                        selected: t.id == _tab,
                        title: Text('${t.mode.label} — ${_hm(t.opened)}'),
                        subtitle: Text(s.person(t.personId)?.name ?? ''),
                        trailing: Text(groupDigits(t.total)),
                        onTap: () => setState(() => _tab = t.id),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          // menu
          SizedBox(
            width: 300,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(decoration: const InputDecoration(hintText: 'جستجوی منو', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = v.trim())),
              const SizedBox(height: 6),
              Expanded(
                child: Card(
                  child: ListView(children: [
                    for (final p in menu)
                      ListTile(
                        dense: true,
                        enabled: tab != null,
                        title: Text(p.name),
                        trailing: Text(groupDigits(p.sellPrice)),
                        onTap: tab == null ? null : () => setState(() => _add(s, tab, p)),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          // order
          Expanded(
            child: tab == null
                ? const Center(child: Text('یک میز یا سفارش را انتخاب کنید'))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${tab.mode == TabMode.dineIn ? (s.restTables.where((x) => x.id == tab.tableId).firstOrNull?.title ?? '') : tab.mode.label} — از ساعت ${_hm(tab.opened)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final id = await pickPersonId(context, title: 'مشترک');
                          if (id != null) setState(() => s.saveTab(tab..personId = id));
                        },
                        icon: const Icon(Icons.person_outline_rounded),
                        label: Text(s.person(tab.personId)?.name ?? 'مشترک'),
                      ),
                      if (tab.mode == TabMode.delivery)
                        TextButton.icon(
                          onPressed: () async {
                            final id = await pickPersonId(context, title: 'پیک');
                            if (id != null) setState(() => s.saveTab(tab..courierId = id));
                          },
                          icon: const Icon(Icons.delivery_dining_outlined),
                          label: Text(s.person(tab.courierId)?.name ?? 'پیک'),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Card(
                        child: ListView(children: [
                          for (final l in tab.lines)
                            ListTile(
                              dense: true,
                              title: Text(s.product(l.productId)?.name ?? ''),
                              subtitle: Text([
                                '${groupDigits(l.price)} × ${fmtQty(l.qty)} = ${groupDigits(l.total)}',
                                if (l.note.isNotEmpty) l.note,
                                if (l.qty > l.sent + 1e-9) 'ارسال نشده',
                              ].join(' — ')),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  onPressed: () => setState(() {
                                    l.qty -= 1;
                                    if (l.qty <= 0 && l.sent <= 0) tab.lines.remove(l);
                                    if (l.qty < 0) l.qty = 0;
                                    s.saveTab(tab);
                                  }),
                                  icon: const Icon(Icons.remove_circle_outline_rounded),
                                ),
                                IconButton(
                                  onPressed: () => setState(() {
                                    l.qty += 1;
                                    s.saveTab(tab);
                                  }),
                                  icon: const Icon(Icons.add_circle_outline_rounded),
                                ),
                                IconButton(
                                  tooltip: 'توضیح برای آشپزخانه',
                                  onPressed: () async {
                                    final c = TextEditingController(text: l.note);
                                    final r = await showDialog<String>(
                                      context: context,
                                      builder: (ctx) => FormDialog(
                                        title: 'توضیح',
                                        width: 360,
                                        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('تایید'))],
                                        child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'مثلا بدون پیاز')),
                                      ),
                                    );
                                    c.dispose();
                                    if (r != null) {
                                      setState(() {
                                        l.note = r;
                                        s.saveTab(tab);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.sticky_note_2_outlined),
                                ),
                              ]),
                            ),
                          if (tab.lines.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('از منو اضافه کنید')),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('جمع: ${groupDigits(tab.total)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      sakanBtn('ارسال به آشپزخانه', tab.hasUnsent ? () => setState(() => _kitchen(s, tab)) : null, key: 'F8', icon: Icons.soup_kitchen_outlined),
                      sakanBtn('تسویه و چاپ فاکتور', () => _settle(s, tab), key: 'F9', icon: Icons.point_of_sale_rounded),
                      if (tab.tableId != null) sakanBtn('انتقال میز', () => _move(s, tab), icon: Icons.swap_horiz_rounded),
                      sakanBtn('لغو سفارش', () async {
                        if (await confirm(context, 'لغو سفارش', 'سفارش بدون ثبت فاکتور بسته شود؟')) {
                          s.dropTab(tab.id);
                          setState(() => _tab = null);
                        }
                      }, icon: Icons.cancel_outlined),
                    ]),
                  ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- تعریف میز

Future<void> showTables(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final s = StoreScope.of(ctx);
        return StatefulBuilder(
          builder: (ctx, set) => FormDialog(
            title: 'تعریف میز',
            width: 520,
            leading: TextButton.icon(
              onPressed: () => set(() {
                s.restTables.add(RestTable(id: newId(), number: s.nextTableNumber()));
                s.updateSettings((_) {});
              }),
              icon: const Icon(Icons.add_rounded),
              label: const Text('میز جدید'),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
            child: Column(children: [
              for (final t in s.restTables)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(width: 60, child: Text('${t.number}', textAlign: TextAlign.center)),
                    Expanded(
                      child: TextFormField(
                        initialValue: t.name,
                        decoration: const InputDecoration(labelText: 'نام', isDense: true),
                        onChanged: (v) {
                          t.name = v.trim();
                          s.updateSettings((_) {});
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        initialValue: '${t.capacity}',
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'ظرفیت', isDense: true),
                        onChanged: (v) {
                          t.capacity = int.tryParse(normalizeDigits(v)) ?? t.capacity;
                          s.updateSettings((_) {});
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        initialValue: t.hall,
                        decoration: const InputDecoration(labelText: 'سالن', isDense: true),
                        onChanged: (v) {
                          t.hall = v.trim();
                          s.updateSettings((_) {});
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: s.tabOfTable(t.id) != null
                          ? null
                          : () => set(() {
                                s.restTables.removeWhere((x) => x.id == t.id);
                                s.updateSettings((_) {});
                              }),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ]),
                ),
            ]),
          ),
        );
      },
    );

// ---------------------------------------------------------------- رزرو میز

Future<void> showReservations(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Reservations());

class _Reservations extends StatefulWidget {
  const _Reservations();

  @override
  State<_Reservations> createState() => _ReservationsState();
}

class _ReservationsState extends State<_Reservations> {
  bool _showDone = false;

  Future<void> _edit(AppStore s, [Reservation? r]) async {
    String? table = r?.tableId ?? s.restTables.firstOrNull?.id;
    var date = r?.at ?? DateTime.now();
    var time = TimeOfDay.fromDateTime(r?.at ?? DateTime.now().add(const Duration(hours: 1)));
    final name = TextEditingController(text: r?.name ?? '');
    final phone = TextEditingController(text: r?.phone ?? '');
    final people = TextEditingController(text: '${r?.people ?? 2}');
    final note = TextEditingController(text: r?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'رزرو میز',
          width: 460,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String?>(
              value: table,
              decoration: const InputDecoration(labelText: 'میز'),
              items: [for (final t in s.restTables) DropdownMenuItem<String?>(value: t.id, child: Text(t.title))],
              onChanged: (v) => set(() => table = v),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DateField(label: 'تاریخ', value: date, onChanged: (d) => set(() => date = d ?? date))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: time);
                  if (t != null) set(() => time = t);
                },
                child: Text('ساعت ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'نام رزرو کننده')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تلفن'))),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: TextField(controller: people, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تعداد نفرات'))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
          ]),
        ),
      ),
    );
    if (ok == true && table != null && name.text.trim().isNotEmpty) {
      final x = r ?? Reservation(id: newId(), tableId: table!, at: date);
      x
        ..tableId = table!
        ..at = DateTime(date.year, date.month, date.day, time.hour, time.minute)
        ..name = name.text.trim()
        ..phone = phone.text.trim()
        ..people = int.tryParse(normalizeDigits(people.text)) ?? 2
        ..note = note.text.trim();
      if (r == null) s.reservations.add(x);
      s.updateSettings((_) {});
      setState(() {});
    }
    for (final c in [name, phone, people, note]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.reservations.where((r) => _showDone || !r.done).toList()..sort((a, b) => a.at.compareTo(b.at));
    return FormDialog(
      title: 'لیست رزرویات میز',
      width: 760,
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton.icon(onPressed: s.restTables.isEmpty ? null : () => _edit(s), icon: const Icon(Icons.add_rounded), label: const Text('رزرو جدید')),
        FilterChip(label: const Text('نمایش انجام شده‌ها'), selected: _showDone, onSelected: (v) => setState(() => _showDone = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
      child: Column(children: [
        for (final r in list)
          ListTile(
            dense: true,
            leading: Icon(r.done ? Icons.check_circle_rounded : Icons.event_seat_outlined),
            title: Text('${s.restTables.where((t) => t.id == r.tableId).firstOrNull?.title ?? ''} — ${r.name} (${r.people} نفر)'),
            subtitle: Text('${jFormat(r.at)} ساعت ${_hm(r.at)}${r.phone.isEmpty ? '' : ' — ${r.phone}'}${r.note.isEmpty ? '' : ' — ${r.note}'}'),
            onTap: () => _edit(s, r),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: r.done ? 'باز کردن' : 'انجام شد',
                onPressed: () => setState(() {
                  r.done = !r.done;
                  s.updateSettings((_) {});
                }),
                icon: Icon(r.done ? Icons.undo_rounded : Icons.done_rounded),
              ),
              IconButton(
                onPressed: () => setState(() {
                  s.reservations.remove(r);
                  s.updateSettings((_) {});
                }),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ]),
          ),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('رزروی ثبت نشده')),
      ]),
    );
  }
}

// ---------------------------------------------------------------- تنظیمات

Future<void> showRestSettings(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final s = StoreScope.read(ctx);
        final c = s.restConfig;
        final service = TextEditingController(text: c.servicePct == 0 ? '' : fmtQty(c.servicePct));
        final fee = TextEditingController(text: c.deliveryFee == 0 ? '' : groupDigits(c.deliveryFee));
        var auto = c.autoAssemble;
        var acc = c.accountId;
        var copies = c.kitchenCopies;
        return StatefulBuilder(
          builder: (ctx, set) => FormDialog(
            title: 'تنظیمات رستوران',
            width: 480,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              FilledButton(
                onPressed: () {
                  s.restConfig = RestConfig(
                    autoAssemble: auto,
                    servicePct: double.tryParse(normalizeDigits(service.text)) ?? 0,
                    deliveryFee: parseMoney(fee.text),
                    accountId: acc,
                    kitchenCopies: copies,
                  );
                  s.updateSettings((_) {});
                  Navigator.pop(ctx);
                },
                child: const Text('تایید'),
              ),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: auto,
                onChanged: (v) => set(() => auto = v),
                title: const Text('ترکیب و مونتاژ رستورانی'),
                subtitle: const Text('با فروش غذایی که فرمول تولید دارد، مواد اولیه آن از انبار کم شود'),
              ),
              TextField(controller: service, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'درصد حق سرویس')),
              const SizedBox(height: 8),
              TextField(controller: fee, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'هزینه پیک')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: acc,
                decoration: const InputDecoration(labelText: 'صندوق پیش فرض'),
                items: [const DropdownMenuItem<String?>(value: null, child: Text('—')), for (final a in s.activeAccounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
                onChanged: (v) => set(() => acc = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Text('تعداد چاپ فیش آشپزخانه: '),
                IconButton(onPressed: copies > 1 ? () => set(() => copies--) : null, icon: const Icon(Icons.remove_rounded)),
                Text('$copies'),
                IconButton(onPressed: () => set(() => copies++), icon: const Icon(Icons.add_rounded)),
              ]),
            ]),
          ),
        );
      },
    );
