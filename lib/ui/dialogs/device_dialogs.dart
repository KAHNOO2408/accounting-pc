import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../core/xlsx.dart';
import '../../data/models.dart';
import '../../data/scale.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../../data/tax_report.dart';
import '../print.dart' show openFile, printTable, printTextTo, systemPrinters;
import '../widgets/common.dart';
import '../widgets/sakan.dart';

// ================================================================ ترازو

/// «مدیریت ساخت فایل ترازو» and weighted barcode settings.
Future<void> showScaleSettings(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Scale());

class _Scale extends StatefulWidget {
  const _Scale();

  @override
  State<_Scale> createState() => _ScaleState();
}

class _ScaleState extends State<_Scale> {
  late final AppStore _s = StoreScope.read(context);
  late final _pre = TextEditingController(text: _s.scale.prefixes.join(','));
  late int _code = _s.scale.codeDigits, _val = _s.scale.valueDigits;
  late bool _price = _s.scale.valueIsPrice;
  final _test = TextEditingController();

  @override
  void dispose() {
    _pre.dispose();
    _test.dispose();
    super.dispose();
  }

  void _save() {
    final old = _s.scale;
    _s.scale = ScaleConfig(
      prefixes: _pre.text.split(RegExp('[,،\\s]+')).map((x) => normalizeDigits(x.trim())).where((x) => x.isNotEmpty).toList(),
      codeDigits: _code,
      valueDigits: _val,
      valueIsPrice: _price,
    )
      ..keys = old.keys
      ..keyCount = old.keyCount
      ..memory = old.memory;
    _s.updateSettings((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _s.products.where((p) => !p.archived && p.info['scale'] == '1').toList();
    final hit = _test.text.trim().isEmpty ? null : _s.matchScan(_test.text);
    return FormDialog(
      title: 'ترازو و بارکد وزنی',
      width: 720,
      leading: TextButton.icon(
        onPressed: () async {
          _save();
          final loc = await fs.getSaveLocation(suggestedName: 'scale-plu.csv', acceptedTypeGroups: const [fs.XTypeGroup(label: 'CSV', extensions: ['csv'])]);
          if (loc == null) return;
          File(loc.path).writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(_s.scaleFile())], flush: true);
          if (mounted) toast(context, 'فایل ترازو با ${items.length} کالا ذخیره شد');
        },
        icon: const Icon(Icons.save_alt_rounded),
        label: const Text('ساخت فایل حافظه ترازو'),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            _save();
            Navigator.pop(context);
          },
          child: const Text('تایید'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ساختار بارکد وزنی (EAN-13): پیشوند + کد کالا (PLU) + وزن به گرم یا مبلغ + رقم کنترل', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _pre, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'پیشوندها (مثلا 20,21,22)', isDense: true))),
          const SizedBox(width: 8),
          DropdownButton<int>(value: _code, items: [for (final n in [4, 5, 6]) DropdownMenuItem(value: n, child: Text('$n رقم کد'))], onChanged: (v) => setState(() => _code = v ?? _code)),
          const SizedBox(width: 8),
          DropdownButton<int>(value: _val, items: [for (final n in [4, 5, 6]) DropdownMenuItem(value: n, child: Text('$n رقم مقدار'))], onChanged: (v) => setState(() => _val = v ?? _val)),
          const SizedBox(width: 8),
          FilterChip(label: const Text('مقدار = مبلغ'), selected: _price, onSelected: (v) => setState(() => _price = v)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _test,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'آزمایش: بارکد برچسب ترازو را اسکن کنید', isDense: true),
          onChanged: (_) {
            _save();
            setState(() {});
          },
        ),
        if (_test.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(hit == null ? 'کالایی پیدا نشد' : '${hit.$1.name}${hit.$2 == null ? '' : ' — مقدار ${hit.$2}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        const Divider(height: 24),
        Text('کالاهایی که به حافظه ترازو انتقال پیدا می‌کنند (${items.length}) — در تعریف کالا «انتقال به حافظه ترازو» و «کد ترازو» را تنظیم کنید:'),
        for (final p in items.take(50)) ListTile(dense: true, title: Text(p.name), leading: Text(pluOf(p)), trailing: Text(groupDigits(p.sellPrice))),
      ]),
    );
  }
}

// ================================================================ دفترچه تلفن و تماس ها

Future<void> showPhoneBook(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Phones());

class _Phones extends StatefulWidget {
  const _Phones();

  @override
  State<_Phones> createState() => _PhonesState();
}

class _PhonesState extends State<_Phones> {
  String _q = '';

  Future<void> _add(AppStore s, [Contact? c]) async {
    final name = TextEditingController(text: c?.name ?? ''), phone = TextEditingController(text: c?.phone ?? ''), note = TextEditingController(text: c?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'مخاطب',
        width: 400,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
        child: Column(children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام')),
          const SizedBox(height: 8),
          TextField(controller: phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تلفن')),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final x = c ?? Contact(id: newId(), name: '');
      x
        ..name = name.text.trim()
        ..phone = phone.text.trim()
        ..note = note.text.trim();
      if (c == null) s.contacts.add(x);
      s.updateSettings((_) {});
      setState(() {});
    }
    for (final t in [name, phone, note]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = <(String, String, String, Contact?)>[
      for (final p in s.peopleSorted.where((p) => p.phone.isNotEmpty)) (p.name, p.phone, 'طرف حساب — مانده ${groupDigits(s.personBalance(p.id))}', null),
      for (final c in s.contacts) (c.name, c.phone, c.note, c),
    ].where((r) => _q.isEmpty || r.$1.contains(_q) || normalizeDigits(r.$2).contains(_q)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return SakanWindow(
      title: 'دفترچه تلفن',
      width: 900,
      height: 620,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('مخاطب جدید', () => _add(s), icon: Icons.person_add_alt_rounded),
            sakanBtn('تماس جدید', () => showNewCall(context), icon: Icons.phone_callback_rounded),
            sakanBtn('لیست تماس های اخیر', () => showCallLog(context), icon: Icons.history_rounded),
            SizedBox(width: 240, child: TextField(decoration: const InputDecoration(hintText: 'نام یا شماره', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = normalizeDigits(v.trim())))),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('نام', 0), sakanHead('تلفن', 200), sakanHead('توضیحات', 300)],
              count: rows.length,
              row: (ctx, i) {
                final r = rows[i];
                return InkWell(
                  onDoubleTap: r.$4 == null ? null : () => _add(s, r.$4),
                  child: Container(
                    color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                    child: Row(children: [
                      sakanCell(Text(r.$1), 0, align: Alignment.centerRight),
                      sakanCell(SelectableText(r.$2, textDirection: TextDirection.ltr), 200),
                      sakanCell(Text(r.$3, overflow: TextOverflow.ellipsis), 300),
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

/// «تماس جدید»: who is calling, their balance and last invoices.
Future<void> showNewCall(BuildContext context, {String number = ''}) {
  final s = StoreScope.read(context);
  final c = TextEditingController(text: number);
  final note = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final (p, contact) = s.whoCalls(c.text);
      final invs = p == null ? <Invoice>[] : (s.realInvoices.where((i) => i.personId == p.id).toList()..sort((a, b) => b.date.compareTo(a.date)));
      return FormDialog(
        title: 'تماس جدید',
        width: 560,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          FilledButton(
            onPressed: c.text.trim().isEmpty
                ? null
                : () {
                    s.logCall(c.text, note: note.text.trim());
                    Navigator.pop(ctx);
                  },
            child: const Text('ثبت تماس'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: c, autofocus: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره تماس گیرنده'), onChanged: (_) => set(() {})),
          const SizedBox(height: 10),
          if (p != null) ...[
            Text('اطلاعات تماس گیرنده: ${p.name} (کد ${p.code})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('مانده حساب: ${groupDigits(s.personBalance(p.id))}'),
            if (invs.isNotEmpty) const Text('آخرین فاکتورها:'),
            for (final i in invs.take(5)) Text('• ${i.kind.label} ${i.number} — ${jFormat(i.date)} — ${groupDigits(i.total)}'),
          ] else if (contact != null)
            Text('${contact.name}${contact.note.isEmpty ? '' : ' — ${contact.note}'}', style: const TextStyle(fontWeight: FontWeight.w800))
          else if (c.text.trim().length >= 5)
            const Text('شماره در دفترچه تلفن نیست'),
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'یادداشت تماس')),
        ]),
      );
    }),
  ).whenComplete(() {
    c.dispose();
    note.dispose();
  });
}

Future<void> showCallLog(BuildContext context) {
  final s = StoreScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'لیست تماس های اخیر',
      width: 600,
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
      child: Column(children: [
        for (final c in s.calls.take(200))
          ListTile(
            dense: true,
            leading: const Icon(Icons.call_received_rounded),
            title: Text('${s.person(c.personId)?.name ?? s.whoCalls(c.number).$2?.name ?? 'ناشناس'} — ${c.number}'),
            subtitle: Text('${jFormat(c.date)} ${c.date.hour}:${c.date.minute.toString().padLeft(2, '0')}${c.note.isEmpty ? '' : ' — ${c.note}'}'),
          ),
        if (s.calls.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('تماسی ثبت نشده')),
      ]),
    ),
  );
}

// ================================================================ اطلاعات مالیاتی

/// «اطلاعات مورد نیاز حساب برای ساخت فایل TTMS».
Future<void> showPersonTaxInfo(BuildContext context, Person p) {
  final s = StoreScope.read(context);
  const keys = ['lastName', 'firstName', 'economicCode', 'nationalId', 'postalCode', 'cityCode', 'province', 'city', 'address'];
  final c = {for (final k in keys) k: TextEditingController(text: p.info[k] ?? (k == 'lastName' ? p.name : ''))};
  final phone = TextEditingController(text: p.phone);
  var legal = p.info['kind'] == 'legal';
  var finalConsumer = p.info['finalConsumer'] == '1';
  var refused = p.info['refused'] == '1';
  Widget f(String k, String label, {bool red = false, bool ltr = false}) => Expanded(
        child: TextField(
          controller: c[k],
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, isDense: true, labelStyle: red ? const TextStyle(color: Colors.red) : null),
        ),
      );
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => FormDialog(
        title: 'اطلاعات مورد نیاز حساب برای ساخت فایل TTMS — ${p.name}',
        width: 640,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
          FilledButton(
            onPressed: () {
              p.info['kind'] = legal ? 'legal' : 'real';
              for (final e in c.entries) {
                p.info[e.key] = e.key == 'address' || e.key == 'province' || e.key == 'city' || e.key.endsWith('Name') ? e.value.text.trim() : normalizeDigits(e.value.text.trim());
              }
              if (p.info['lastName'] == p.name) p.info.remove('lastName');
              p.info['finalConsumer'] = finalConsumer ? '1' : '';
              p.info['refused'] = refused ? '1' : '';
              p.info.removeWhere((_, v) => v.isEmpty);
              p.phone = phone.text.trim();
              s.upsertPerson(p);
              Navigator.pop(ctx);
            },
            child: const Text('تایید F9'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('در صورت استفاده از کیت «امور مالیاتی» اطلاعات مشخص شده به رنگ قرمز را به درستی وارد نمایید.', style: TextStyle(fontSize: 12, color: Colors.red)),
          const SizedBox(height: 8),
          Row(children: [
            const Text('نوع شخص: '),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('حقیقی')), ButtonSegment(value: true, label: Text('حقوقی'))],
              selected: {legal},
              onSelectionChanged: (v) => set(() => legal = v.first),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [f('lastName', legal ? 'نام شرکت' : 'نام خانوادگی فروشنده', red: true), const SizedBox(width: 8), if (!legal) f('firstName', 'نام')]),
          const SizedBox(height: 8),
          Row(children: [f('nationalId', legal ? 'شناسه ملی' : 'کد ملی', red: true, ltr: true), const SizedBox(width: 8), f('economicCode', 'شماره اقتصادی', ltr: true)]),
          const SizedBox(height: 8),
          Row(children: [f('postalCode', 'کد پستی', red: true, ltr: true), const SizedBox(width: 8), f('cityCode', 'پیش کد شهر', ltr: true), const SizedBox(width: 8),
            Expanded(child: TextField(controller: phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تلفن', isDense: true)))]),
          const SizedBox(height: 8),
          Row(children: [f('province', 'استان', red: true), const SizedBox(width: 8), f('city', 'شهر', red: true)]),
          const SizedBox(height: 8),
          Row(children: [f('address', 'آدرس', red: true)]),
          const SizedBox(height: 8),
          CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: finalConsumer, onChanged: (v) => set(() => finalConsumer = v ?? false), title: const Text('مصرف کننده نهایی (عرضه به مصرف کننده نهایی)')),
          CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: refused, onChanged: (v) => set(() => refused = v ?? false), title: const Text('امتناع از ارائه اطلاعات')),
        ]),
      ),
    ),
  ).whenComplete(() {
    for (final t in [...c.values, phone]) {
      t.dispose();
    }
  });
}

/// «ایجاد فایل مالیاتی ویژه نرم افزار TTMS»: 1 file, 2 year/season, 3 data.
Future<void> showTaxFile(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Ttms());

class _Ttms extends StatefulWidget {
  const _Ttms();

  @override
  State<_Ttms> createState() => _TtmsState();
}

class _TtmsState extends State<_Ttms> {
  int _step = 1;
  String? _path;
  late final TtmsOptions _o = () {
    final now = Jalali.fromDateTime(DateTime.now());
    return TtmsOptions(year: now.year, season: (now.month - 1) ~/ 3 + 1);
  }();
  final _threshold = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _write(AppStore s, {bool emtena = false}) async {
    _o.threshold = parseMoney(_threshold.text);
    final all = ttmsSheets(s, _o);
    final sheets = emtena ? all.where((x) => x.$1 == 'امتناع' || x.$1 == 'عرضه به مصرف کننده نهایی') : all.where((x) => x.$1 == 'خرید' || x.$1 == 'فروش');
    var path = _path;
    if (path == null) {
      final loc = await fs.getSaveLocation(suggestedName: 'TTMS-${_o.year}-${_o.season}${emtena ? '-emtena' : ''}.xlsx', acceptedTypeGroups: const [fs.XTypeGroup(label: 'Excel', extensions: ['xlsx'])]);
      if (loc == null) return;
      path = loc.path;
    }
    final (from, to) = seasonRange(_o.year, _o.season);
    final title = ['فصل ${_o.season} سال ${_o.year}${_o.month > 0 ? ' ماه ${_o.month}' : ''} (${jFormat(from)} تا ${jFormat(to)})'];
    File(path).writeAsBytesSync(buildXlsx([for (final (name, rows) in sheets) XlsxSheet(name, ttmsHeaders, rows, titleLines: title)]), flush: true);
    setState(() => _msg = 'فایل ذخیره شد: $path');
    openFile(path);
  }

  Future<void> _ops(AppStore s) => showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
          final ops = ttmsOps(s, _o);
          return FormDialog(
            title: 'مشاهده لیست عملیات',
            width: 980,
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
            child: Column(children: [
              for (final x in ops)
                ListTile(
                  dense: true,
                  leading: Checkbox(
                    value: usedInTaxFile(x.inv),
                    onChanged: (v) => set(() {
                      if (v == true) {
                        x.inv.info.remove('taxFile');
                      } else {
                        x.inv.info['taxFile'] = '0';
                      }
                      s.updateSettings((_) {});
                    }),
                  ),
                  title: Text('${x.inv.kind.label} ${x.inv.number} — ${s.person(x.inv.personId)?.name ?? 'متفرقه'} — ${groupDigits(x.inv.total)}'),
                  subtitle: Text('${jFormat(x.inv.date)}${x.excluded ? ' — ارسال نمی‌شود: ${x.reason}' : ''}${x.incomplete ? ' — ناقص: ${ttmsMissing(s.person(x.inv.personId)!).join('، ')}' : ''}',
                      style: TextStyle(color: x.excluded ? Colors.red : null)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButton<String>(
                      value: x.inv.info['taxGoodsType'] ?? 'goods',
                      items: const [DropdownMenuItem(value: 'goods', child: Text('کالا')), DropdownMenuItem(value: 'services', child: Text('خدمات'))],
                      onChanged: (v) => set(() {
                        x.inv.info['taxGoodsType'] = v ?? 'goods';
                        s.updateSettings((_) {});
                      }),
                    ),
                    if (x.inv.personId != null)
                      IconButton(
                        tooltip: 'اطلاعات مالیاتی طرف حساب',
                        onPressed: () => showPersonTaxInfo(ctx, s.person(x.inv.personId)!).then((_) => set(() {})),
                        icon: const Icon(Icons.badge_outlined),
                      ),
                  ]),
                ),
              if (ops.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('عملیاتی در این دوره نیست')),
            ]),
          );
        }),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final now = Jalali.fromDateTime(DateTime.now());
    Widget chapter(int n, String title, Widget body) => Card(
          color: _step == n ? null : const Color(0xFFF2F2F2),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (_step == n) ...[const SizedBox(height: 8), body],
            ]),
          ),
        );
    final ops = _step == 3 ? ttmsOps(s, _o) : const <TtmsOp>[];
    return FormDialog(
      title: 'ایجاد فایل مالیاتی ویژه نرم افزار TTMS',
      width: 720,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت F10'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        chapter(
          1,
          'مرحله اول : انتخاب فایل مالیات',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [
              FilledButton.tonal(
                onPressed: () async {
                  final loc = await fs.getSaveLocation(suggestedName: 'TTMS-${_o.year}-${_o.season}.xlsx', acceptedTypeGroups: const [fs.XTypeGroup(label: 'Excel', extensions: ['xlsx'])]);
                  if (loc != null) setState(() => _path = loc.path);
                },
                child: const Text('فایل جدید'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  final f = await fs.openFile(acceptedTypeGroups: const [fs.XTypeGroup(label: 'Excel', extensions: ['xlsx'])]);
                  if (f != null) setState(() => _path = f.path);
                },
                child: const Text('فراخوانی فایل'),
              ),
            ]),
            if (_path != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('مسیر فایل تولید شده: $_path', textDirection: TextDirection.ltr)),
            Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('مرحله بعد'))),
          ]),
        ),
        chapter(
          2,
          'مرحله دوم : تعیین سال و فصل',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('سال: '),
              DropdownButton<int>(value: _o.year, items: [for (var y = now.year - 3; y <= now.year; y++) DropdownMenuItem(value: y, child: Text('$y'))], onChanged: (v) => setState(() => _o.year = v ?? _o.year)),
              const SizedBox(width: 12),
              const Text('فصل: '),
              DropdownButton<int>(
                value: _o.season,
                items: const [DropdownMenuItem(value: 1, child: Text('بهار')), DropdownMenuItem(value: 2, child: Text('تابستان')), DropdownMenuItem(value: 3, child: Text('پاییز')), DropdownMenuItem(value: 4, child: Text('زمستان'))],
                onChanged: (v) => setState(() {
                  _o.season = v ?? _o.season;
                  _o.month = 0;
                }),
              ),
              const SizedBox(width: 12),
              const Text('ماه: '),
              DropdownButton<int>(
                value: _o.month,
                items: [const DropdownMenuItem(value: 0, child: Text('کل فصل')), for (var m = (_o.season - 1) * 3 + 1; m <= _o.season * 3; m++) DropdownMenuItem(value: m, child: Text(jalaliMonthNames[m - 1]))],
                onChanged: (v) => setState(() => _o.month = v ?? 0),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _threshold, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'تعیین مبلغ تشخیص معاملات کمتر از حد نصاب در قانون 169', isDense: true)),
            CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _o.skipIncomplete, onChanged: (v) => setState(() => _o.skipIncomplete = v ?? true), title: const Text('عملیاتی که تیک ارسال دارند ناقص هستند ارسال نگردد')),
            CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _o.skipNoDuty, onChanged: (v) => setState(() => _o.skipNoDuty = v ?? false), title: const Text('عملیاتی که تیک ارسال دارند ولی سر فصل عوارض ندارند ارسال نگردد')),
            CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _o.skipZeroDuty, onChanged: (v) => setState(() => _o.skipZeroDuty = v ?? false), title: const Text('عملیاتی که تیک ارسال دارند اما مبلغ عوارض آنها صفر است ارسال نگردد')),
            Row(children: [
              TextButton(onPressed: () => setState(() => _step = 1), child: const Text('مرحله قبل')),
              const Spacer(),
              FilledButton(onPressed: () => setState(() => _step = 3), child: const Text('مرحله بعد')),
            ]),
          ]),
        ),
        chapter(
          3,
          'مرحله سوم : ثبت اطلاعات',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${ops.length} عملیات — ارسال: ${ops.where((x) => !x.excluded).length} — ناقص: ${ops.where((x) => x.incomplete).length}'),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton(onPressed: () => _ops(s).then((_) => setState(() {})), child: const Text('مشاهده لیست عملیات')),
              FilledButton(onPressed: () => _write(s), child: const Text('ثبت اطلاعات')),
              FilledButton.tonal(onPressed: () => _write(s, emtena: true), child: const Text('ثبت اطلاعات امتناع / عرضه به مصرف کننده نهایی')),
              TextButton(onPressed: () => setState(() => _step = 2), child: const Text('مرحله قبل')),
            ]),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      ]),
    );
  }
}

// ================================================================ اتصال به سرور (شبکه)

/// «لیست سرورها» / «اتصال اولیه»: work on a shared folder from several computers.
Future<void> showServerSettings(BuildContext context) {
  final s = StoreScope.read(context);
  String? path = Storage.serverPath;
  String? msg;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => FormDialog(
        title: 'اتصال به سرور (کار شبکه‌ای)',
        width: 640,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          if (path != null)
            OutlinedButton(
              onPressed: () => set(() {
                Storage.serverPath = null;
                path = null;
                msg = 'اتصال قطع شد؛ برنامه را دوباره باز کنید تا اطلاعات همین کامپیوتر استفاده شود.';
              }),
              child: const Text('قطع اتصال'),
            ),
          FilledButton.icon(
            onPressed: () async {
              final dir = await fs.getDirectoryPath(confirmButtonText: 'انتخاب پوشه مشترک');
              if (dir == null) return;
              final target = File('$dir${Storage.sep}data.json');
              if (!target.existsSync()) {
                // first computer: copy this computer's data to the server folder
                s.storage.dataFile.copySync(target.path);
              }
              Storage.serverPath = dir;
              set(() {
                path = dir;
                msg = target.existsSync() ? 'متصل شد. برنامه را ببندید و دوباره باز کنید.' : 'متصل شد.';
              });
            },
            icon: const Icon(Icons.lan_outlined),
            label: const Text('انتخاب پوشه مشترک'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('محل فعلی اطلاعات: ${s.storage.dir.path}', textDirection: TextDirection.ltr),
          const SizedBox(height: 6),
          Text(path == null ? 'حالت: تک کاربره (اطلاعات روی همین کامپیوتر)' : 'حالت: شبکه — $path', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (Storage.networked) Text('آخرین ذخیره: ${s.storage.lastWriter}', textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          const Text(
            '۱. روی کامپیوتر اصلی (سرور) یک پوشه بسازید و آن را در شبکه به اشتراک بگذارید (دسترسی خواندن و نوشتن).\n'
            '۲. در کامپیوتر اصلی «انتخاب پوشه مشترک» را بزنید؛ اطلاعات فعلی به آن پوشه منتقل می‌شود.\n'
            '۳. در کامپیوترهای دیگر همان پوشه را از مسیر شبکه (مثلا \\\\PC1\\Taraz) انتخاب کنید.\n'
            'همه کامپیوترها همزمان ثبت می‌کنند؛ هر ثبت در لحظه ذخیره با تغییرات بقیه رکورد به رکورد ادغام می‌شود و هر چند ثانیه تغییرات دیگران روی صفحه می‌آید. اگر دو کامپیوتر همزمان یک شماره فاکتور یا سند بدهند، شماره دومی خودکار به شماره بعدی می‌رود.',
            style: TextStyle(fontSize: 12.5, height: 1.7),
          ),
          if (msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2E7D32)))),
        ]),
      ),
    ),
  );
}

// ================================================================ پرینترها

/// «پرینتر های آشپزخانه» / «پرینتر های حواله انبار»: slips go straight to these printers.
Future<void> showPrinterSettings(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Printers());

class _Printers extends StatefulWidget {
  const _Printers();

  @override
  State<_Printers> createState() => _PrintersState();
}

class _PrintersState extends State<_Printers> {
  List<String>? _list;

  @override
  void initState() {
    super.initState();
    systemPrinters().then((v) {
      if (mounted) setState(() => _list = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    Widget row(String role, String label) {
      final cur = s.printers[role] ?? '';
      final items = {...?_list, if (cur.isNotEmpty) cur}.toList();
      return Row(children: [
        SizedBox(width: 170, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: cur,
            items: [const DropdownMenuItem(value: '', child: Text('— چاپ معمولی با پنجره چاپ —')), for (final p in items) DropdownMenuItem(value: p, child: Text(p))],
            onChanged: (v) => setState(() {
              if (v == null || v.isEmpty) {
                s.printers.remove(role);
              } else {
                s.printers[role] = v;
              }
              s.updateSettings((_) {});
            }),
          ),
        ),
        TextButton(
          onPressed: cur.isEmpty
              ? null
              : () async {
                  final ok = await printTextTo(cur, textSlip('چاپ آزمایشی $label', [('تاریخ', jFormat(DateTime.now()))], const []), fileName: 'test');
                  if (context.mounted) toast(context, ok ? 'ارسال شد' : 'چاپ نشد', error: !ok);
                },
          child: const Text('چاپ آزمایشی'),
        ),
      ]);
    }

    return FormDialog(
      title: 'تنظیم پرینترها',
      width: 640,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_list == null) const LinearProgressIndicator(),
        if (_list != null && _list!.isEmpty) const Text('پرینتری پیدا نشد (فقط در ویندوز).'),
        row('kitchen', 'پرینتر آشپزخانه'),
        row('warehouse', 'پرینتر حواله انبار'),
        const SizedBox(height: 8),
        const Text('فیش آشپزخانه و حواله انبار بدون باز شدن پنجره چاپ مستقیم به این پرینترها فرستاده می‌شوند.', style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
