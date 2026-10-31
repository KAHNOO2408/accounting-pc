/// More Sakan windows: «قفل اسناد»، «دفاتر تفصیلی در تفصیلی»، «لیست قرارداد»،
/// «دسترسی اسناد»، «دسترسی گزارشات»، «کپی دسترسی دفتر مالی»، «تنظیمات پشتیبان
/// گیری خودکار»، «فایل های موقت» و «بازیابی دفاتر گم شده».
library;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/books.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show pickPersonId;
import 'voucher_dialog.dart' show tafsiliOptions;

// ================================================================ قفل اسناد

Future<void> showDocLock(BuildContext context) async {
  final s = StoreScope.read(context);
  final from = TextEditingController(text: '${s.lastLockedNo + 1}');
  final nos = s.docKeys.map(s.docNumberOf).whereType<int>();
  final to = TextEditingController(text: '${nos.isEmpty ? 0 : nos.reduce((a, b) => a > b ? a : b)}');
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        void run(bool lock) {
          final a = int.tryParse(normalizeDigits(from.text.trim())), b = int.tryParse(normalizeDigits(to.text.trim()));
          if (a == null || b == null || b < a) return toast(ctx, 'محدوده شماره سند نامعتبر است', error: true);
          final n = s.lockDocRange(a, b, lock: lock);
          toast(ctx, lock ? '$n سند قفل شد' : 'قفل $n سند باز شد');
          set(() {});
        }

        return SakanWindow(
          title: 'قفل اسناد',
          width: 560,
          height: 480,
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: TextField(controller: from, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'از شماره سند:', isDense: true))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: to, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تا شماره سند:', isDense: true))),
              ]),
              const SizedBox(height: 6),
              const Text('اسناد قفل شده قابل ویرایش و حذف نیستند (فاکتورها، اسناد حسابداری و دریافت و پرداخت ها).', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('محدوده های قفل شده', style: TextStyle(fontWeight: FontWeight.w800)),
              Expanded(
                child: SakanGrid(
                  header: [sakanHead('از', 80), sakanHead('تا', 80), sakanHead('تاریخ', 110), sakanHead('کاربر', 0)],
                  count: s.lockRanges.length,
                  empty: 'سندی قفل نشده',
                  row: (_, i) {
                    final r = s.lockRanges[i];
                    return InkWell(
                      onTap: () => set(() {
                        from.text = '${r.$1}';
                        to.text = '${r.$2}';
                      }),
                      child: Row(children: [sakanCell(Text('${r.$1}'), 80), sakanCell(Text('${r.$2}'), 80), sakanCell(Text(jFormat(r.$3)), 110), sakanCell(Text(r.$4), 0)]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
                const SizedBox(width: 6),
                OutlinedButton(onPressed: () => run(false), child: const Text('باز کردن قفل')),
                const SizedBox(width: 6),
                FilledButton(onPressed: () => run(true), child: const Text('تایید F9')),
              ]),
            ]),
          ),
        );
      },
    ),
  );
}

// ================================================================ تفصیلی در تفصیلی

Future<void> showSubTafsilis(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Subs());

class _Subs extends StatefulWidget {
  const _Subs();
  @override
  State<_Subs> createState() => _SubsState();
}

class _SubsState extends State<_Subs> {
  String? _moeen;
  String? _taf;
  String? _sel;

  Future<void> _edit(AppStore s, [SubTafsili? x]) async {
    final name = TextEditingController(text: x?.name ?? '');
    final code = TextEditingController(text: '${x?.code ?? s.subsOf(_taf).fold<int>(0, (a, o) => o.code > a ? o.code : a) + 1}');
    final note = TextEditingController(text: x?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(x == null ? 'افزودن دفتر تفصیلی در تفصیلی' : 'ویرایش'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, decoration: const InputDecoration(labelText: 'کد', isDense: true)),
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام دفتر', isDense: true)),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظات', isDense: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = x ?? SubTafsili(id: newId(), tafsiliId: _taf!, code: 0, name: '');
    n
      ..code = int.tryParse(normalizeDigits(code.text.trim())) ?? n.code
      ..name = name.text
      ..note = note.text.trim();
    final e = s.saveSubTafsili(n);
    if (e != null) return toast(context, e, error: true);
    setState(() => _sel = n.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final moeens = [for (final m in allMoeens) if (m.hasEntity) m];
    final m = findMoeen(_moeen);
    final opts = m == null ? const <(String, String)>[] : tafsiliOptions(s, m);
    final rows = _taf == null ? const <(SubTafsili, int, int)>[] : s.subBalances(_taf!);
    final sel = rows.where((r) => r.$1.id == _sel).firstOrNull?.$1;
    return SakanWindow(
      title: 'دفاتر تفصیلی در تفصیلی',
      width: 860,
      height: 580,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _moeen,
                decoration: const InputDecoration(labelText: 'دفتر معین', isDense: true),
                items: [for (final x in moeens) DropdownMenuItem(value: x.code, child: Text('${x.code} - ${x.name}'))],
                onChanged: (v) => setState(() {
                  _moeen = v;
                  _taf = null;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: opts.any((o) => o.$1 == _taf) ? _taf : null,
                decoration: const InputDecoration(labelText: 'دفتر تفصیلی', isDense: true),
                items: [for (final o in opts) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _taf = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            sakanBtn('افزودن', _taf == null ? null : () => _edit(s), icon: Icons.add_rounded),
            const SizedBox(width: 6),
            sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            const SizedBox(width: 6),
            sakanBtn('حذف', sel == null
                ? null
                : () {
                    final e = s.removeSubTafsili(sel.id);
                    if (e != null) return toast(context, e, error: true);
                    setState(() => _sel = null);
                  }, icon: Icons.delete_outline),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 70), sakanHead('نام دفتر', 0), sakanHead('بدهکار', 140), sakanHead('بستانکار', 140), sakanHead('مانده', 150)],
              count: rows.length,
              empty: _taf == null ? 'دفتر معین و تفصیلی را انتخاب کنید' : 'دفتری تعریف نشده',
              row: (_, i) {
                final r = rows[i];
                final b = r.$2 - r.$3;
                return Material(
                  color: r.$1.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() => _sel = r.$1.id),
                    onDoubleTap: () => _edit(s, r.$1),
                    child: Row(children: [
                      sakanCell(Text('${r.$1.code}'), 70),
                      sakanCell(Text(r.$1.name), 0, align: Alignment.centerRight),
                      sakanCell(Text(groupDigits(r.$2)), 140),
                      sakanCell(Text(groupDigits(r.$3)), 140),
                      sakanCell(Text('${groupDigits(b.abs())} ${b > 0 ? 'بد' : (b < 0 ? 'بس' : '')}'), 150),
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

// ================================================================ لیست قرارداد

Future<void> showContracts(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Contracts());

class _Contracts extends StatefulWidget {
  const _Contracts();
  @override
  State<_Contracts> createState() => _ContractsState();
}

class _ContractsState extends State<_Contracts> {
  String? _sel;

  Future<void> _edit(AppStore s, [Contract? c]) async {
    final x = c == null ? Contract(id: newId(), code: s.nextContractCode(), title: '') : Contract.fromJson(c.toJson());
    final code = TextEditingController(text: '${x.code}');
    final title = TextEditingController(text: x.title);
    final amount = TextEditingController(text: x.amount == 0 ? '' : groupDigits(x.amount));
    final note = TextEditingController(text: x.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? 'ثبت قرارداد جدید' : 'ویرایش قرارداد'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'کد قرارداد', isDense: true)),
              TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان قرارداد / پیمان', isDense: true)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final id = await pickPersonId(ctx, title: 'کارفرما');
                  if (id != null) set(() => x.personId = id);
                },
                child: Text('کارفرما: ${s.person(x.personId)?.name ?? 'انتخاب کنید'}'),
              ),
              MoneyField(controller: amount, label: 'مبلغ قرارداد'),
              Row(children: [
                Expanded(child: DateField(label: 'تاریخ شروع', value: x.start, clearable: true, onChanged: (d) => set(() => x.start = d))),
                const SizedBox(width: 8),
                Expanded(child: DateField(label: 'تاریخ پایان', value: x.end, clearable: true, onChanged: (d) => set(() => x.end = d))),
              ]),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظات', isDense: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    x
      ..code = int.tryParse(normalizeDigits(code.text.trim())) ?? x.code
      ..title = title.text
      ..amount = parseMoney(amount.text)
      ..note = note.text.trim();
    final e = s.saveContract(x);
    if (e != null) return toast(context, e, error: true);
    setState(() => _sel = x.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = [...s.contracts]..sort((a, b) => a.code.compareTo(b.code));
    final sel = list.where((c) => c.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'لیست قرارداد',
      width: 900,
      height: 560,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            sakanBtn('ثبت قرارداد جدید', () => _edit(s), icon: Icons.add_rounded),
            const SizedBox(width: 6),
            sakanBtn('ویرایش قرارداد', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            const SizedBox(width: 6),
            sakanBtn('حذف قرارداد', sel == null
                ? null
                : () async {
                    if (!await confirm(context, 'حذف قرارداد', '«${sel.title}» حذف شود؟')) return;
                    final e = s.removeContract(sel.id);
                    if (!context.mounted) return;
                    if (e != null) return toast(context, e, error: true);
                    setState(() => _sel = null);
                  }, icon: Icons.delete_outline),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 60), sakanHead('عنوان', 0), sakanHead('کارفرما', 170), sakanHead('مبلغ قرارداد', 140), sakanHead('شروع', 95), sakanHead('پایان', 95)],
              count: list.length,
              empty: 'قراردادی ثبت نشده — قراردادها تفصیلی دفاتر «پیمان در دست اجرا» هستند',
              row: (_, i) {
                final c = list[i];
                return Material(
                  color: c.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() => _sel = c.id),
                    onDoubleTap: () => _edit(s, c),
                    child: Row(children: [
                      sakanCell(Text('${c.code}'), 60),
                      sakanCell(Text(c.title), 0, align: Alignment.centerRight),
                      sakanCell(Text(s.person(c.personId)?.name ?? ''), 170),
                      sakanCell(Text(groupDigits(c.amount)), 140),
                      sakanCell(Text(c.start == null ? '' : jFormat(c.start!)), 95),
                      sakanCell(Text(c.end == null ? '' : jFormat(c.end!)), 95),
                    ]),
                  ),
                );
              },
            ),
          ),
          Align(alignment: AlignmentDirectional.centerEnd, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت'))),
        ]),
      ),
    );
  }
}

// ================================================================ دسترسی اسناد / گزارشات

/// «دسترسی اسناد» of [user]: per document type ثبت / ویرایش / حذف.
Future<void> showDocAccess(BuildContext context, AppUser user) async {
  final s = StoreScope.read(context);
  final m = {for (final (t, _) in docAccessTypes) t: user.docAccess[t] ?? 'ned'};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SakanWindow(
        title: 'دسترسی اسناد — ${user.name}',
        width: 620,
        height: 460,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: SakanGrid(
                header: [sakanHead('نوع سند', 0), sakanHead('ثبت', 80), sakanHead('ویرایش', 80), sakanHead('حذف', 80)],
                count: docAccessTypes.length,
                row: (_, i) {
                  final (t, name) = docAccessTypes[i];
                  Widget c(String op) => sakanCell(
                        Checkbox(
                          value: m[t]!.contains(op),
                          onChanged: (v) => set(() => m[t] = v == true ? '${m[t]}$op' : m[t]!.replaceAll(op, '')),
                        ),
                        80,
                      );
                  return Row(children: [sakanCell(Text(name), 0, align: Alignment.centerRight), c('n'), c('e'), c('d')]);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
              const SizedBox(width: 6),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return;
  s.setDocAccess(user.id, {
    for (final e in m.entries)
      if (!(e.value.contains('n') && e.value.contains('e') && e.value.contains('d'))) e.key: e.value,
  });
}

/// «دسترسی گزارشات» of [user]: report buttons ([reportItems]) and print /
/// report layouts.
Future<void> showReportAccess(BuildContext context, AppUser user, List<String> reportItems) async {
  final s = StoreScope.read(context);
  final denied = {...user.denied};
  final deniedLayouts = {...user.deniedReports};
  final layouts = [for (final t in PrintDocType.values) for (final l in s.reportLayouts.where((l) => l.type == t)) l];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SakanWindow(
        title: 'دسترسی گزارشات — ${user.name}',
        width: 760,
        height: 620,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: ListView(children: [
                const Text('گزارشات', style: TextStyle(fontWeight: FontWeight.w800)),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final i in reportItems)
                    FilterChip(label: Text(i), selected: !denied.contains(i), onSelected: (v) => set(() => v ? denied.remove(i) : denied.add(i))),
                ]),
                const Divider(height: 22),
                const Text('طرح های گزارش و چاپ ساخته شده', style: TextStyle(fontWeight: FontWeight.w800)),
                if (layouts.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('طرحی ساخته نشده')),
                for (final l in layouts)
                  CheckboxListTile(
                    dense: true,
                    value: !deniedLayouts.contains(l.id),
                    title: Text(l.name),
                    subtitle: Text(l.type.label),
                    onChanged: (v) => set(() => v == true ? deniedLayouts.remove(l.id) : deniedLayouts.add(l.id)),
                  ),
              ]),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
              const SizedBox(width: 6),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return;
  user
    ..denied = denied
    ..deniedReports = deniedLayouts;
  s.saveUser(user);
}

/// «کپی دسترسی دفتر مالی»: permissions of the same users in another book.
Future<void> showCopyBookAccess(BuildContext context) async {
  final s = StoreScope.read(context);
  final reg = BookRegistry.of(s);
  final cur = BookRegistry.idOf(s.storage.dir);
  final books = reg.active.where((b) => b.id != cur).toList();
  if (books.isEmpty) return toast(context, 'دفتر مالی دیگری وجود ندارد', error: true);
  final id = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('کپی دسترسی از دفتر مالی'),
      children: [for (final b in books) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, b.id), child: Text(b.title))],
    ),
  );
  if (id == null || !context.mounted) return;
  final n = s.copyAccessFrom(reg.open(id));
  toast(context, n == 0 ? 'کاربر هم نامی در آن دفتر پیدا نشد' : 'دسترسی $n کاربر کپی شد');
}

// ================================================================ پشتیبان گیری خودکار

Future<void> showAutoBackupSettings(BuildContext context) async {
  final s = StoreScope.read(context);
  final t = [for (final b in s.backupSlots) TextEditingController(text: b.$1)];
  final p = [for (final b in s.backupSlots) TextEditingController(text: b.$2)];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تنظیمات پشتیبان گیری خودکار'),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: t[i],
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: 'زمان پشتیبان گیری ${i == 0 ? 'اول' : 'دوم'}:', hintText: '13:30', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: p[i],
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: 'مسیر پشتیبان گیری ${i == 0 ? 'اول' : 'دوم'}:', isDense: true),
                  ),
                ),
                IconButton(
                  tooltip: '...',
                  onPressed: () async {
                    final d = await fs.getDirectoryPath();
                    if (d != null) p[i].text = d;
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ]),
            ),
          const Text('در زمان تعیین شده (وقتی برنامه باز است) یک فایل پشتیبان فشرده در مسیر ذخیره می شود. مسیر دوم را روی درایو یا فلش دیگری بگذارید.', style: TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  for (final c in t) {
    final v = normalizeDigits(c.text.trim());
    if (v.isNotEmpty && !RegExp(r'^\d{1,2}:\d{2}$').hasMatch(v)) return toast(context, 'زمان را به شکل 13:30 وارد کنید', error: true);
  }
  s.setBackupSlots([for (var i = 0; i < 2; i++) (normalizeDigits(t[i].text.trim()), p[i].text.trim())]);
  toast(context, 'تنظیمات پشتیبان گیری خودکار ذخیره شد');
}

// ================================================================ فایل های موقت

Future<void> showTempDocs(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Temps());

class _Temps extends StatefulWidget {
  const _Temps();
  @override
  State<_Temps> createState() => _TempsState();
}

class _TempsState extends State<_Temps> {
  final Set<String> _sel = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.tempDocs.where((t) => _q.isEmpty || t.name.contains(_q) || t.voucher.desc.contains(_q)).toList();
    return SakanWindow(
      title: 'لیست فایل های موقت',
      width: 900,
      height: 560,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 200, child: TextField(decoration: const InputDecoration(labelText: 'جستجو', isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            sakanBtn('همه', () => setState(() => _sel.addAll(list.map((t) => t.id)))),
            sakanBtn('هیچ', () => setState(_sel.clear)),
            sakanBtn('معکوس', () => setState(() {
                  for (final t in list) {
                    if (!_sel.remove(t.id)) _sel.add(t.id);
                  }
                })),
            sakanBtn('تایید و ثبت سند ردیف های منتخب', _sel.isEmpty
                ? null
                : () {
                    final bad = s.postTempDocs({..._sel});
                    setState(_sel.clear);
                    toast(context, bad.isEmpty ? 'اسناد ثبت شد' : 'ثبت نشد (تراز نیست): ${bad.join('، ')}', error: bad.isNotEmpty);
                  }, color: const Color(0xFFE8F5E9), icon: Icons.check_rounded),
            sakanBtn('حذف', _sel.isEmpty
                ? null
                : () async {
                    if (!await confirm(context, 'حذف فایل های موقت', '${_sel.length} فایل حذف شود؟')) return;
                    s.removeTempDocs({..._sel});
                    setState(_sel.clear);
                  }, icon: Icons.delete_outline),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('', 40), sakanHead('نام فایل موقت', 0), sakanHead('تاریخ سند', 100), sakanHead('شرح سند', 220), sakanHead('مبلغ', 130), sakanHead('کاربر', 110)],
              count: list.length,
              empty: 'فایل موقتی نیست — در «سند حسابداری» دکمه «ذخیره در فایل موقت» را بزنید',
              row: (_, i) {
                final t = list[i];
                final dr = t.voucher.lines.fold<int>(0, (a, l) => a + l.debit);
                return InkWell(
                  onTap: () => setState(() => _sel.contains(t.id) ? _sel.remove(t.id) : _sel.add(t.id)),
                  child: Row(children: [
                    sakanCell(Checkbox(value: _sel.contains(t.id), onChanged: (v) => setState(() => v == true ? _sel.add(t.id) : _sel.remove(t.id))), 40),
                    sakanCell(Text(t.name), 0, align: Alignment.centerRight),
                    sakanCell(Text(jFormat(t.voucher.date)), 100),
                    sakanCell(Text(t.voucher.desc, overflow: TextOverflow.ellipsis), 220),
                    sakanCell(Text(groupDigits(dr)), 130),
                    sakanCell(Text(t.user), 110),
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

// ================================================================ بازیابی دفاتر گم شده

Future<void> showRecoverBooks(BuildContext context) async {
  final s = StoreScope.read(context);
  final reg = BookRegistry.of(s);
  final lost = reg.lostBookIds();
  if (lost.isEmpty) return toast(context, 'دفتر گم شده ای پیدا نشد');
  final sel = <String>{...lost};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('بازیابی دفاتر گم شده'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('این دفاتر روی دیسک هست ولی در لیست دفاتر مالی نیست:'),
            for (final id in lost)
              CheckboxListTile(
                dense: true,
                value: sel.contains(id),
                title: Text(id),
                subtitle: Text(reg.open(id).settings.businessName),
                onChanged: (v) => set(() => v == true ? sel.add(id) : sel.remove(id)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('جایگزین شود')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  for (final id in sel) {
    reg.recoverBook(id);
  }
  toast(context, '${sel.length} دفتر به لیست دفاتر مالی برگشت');
}

// ================================================================ گزارش شعب

/// «گزارش فروش به تفکیک شعبه».
Future<void> showBranchSales(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _BranchSales());

class _BranchSales extends StatefulWidget {
  const _BranchSales();
  @override
  State<_BranchSales> createState() => _BranchSalesState();
}

class _BranchSalesState extends State<_BranchSales> {
  late DateTime _from = Jalali(Jalali.now().year, 1, 1).toDateTime(), _to = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = s.salesByBranch(_from, DateTime(_to.year, _to.month, _to.day, 23, 59));
    final tot = rows.fold<(int, int, int)>((0, 0, 0), (a, r) => (a.$1 + r.$2, a.$2 + r.$3, a.$3 + r.$4));
    return SakanWindow(
      title: 'گزارش فروش به تفکیک شعبه',
      width: 820,
      height: 520,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 180, child: DateField(label: 'از تاریخ', value: _from, onChanged: (d) => setState(() => _from = d ?? _from))),
            const SizedBox(width: 10),
            SizedBox(width: 180, child: DateField(label: 'تا تاریخ', value: _to, onChanged: (d) => setState(() => _to = d ?? _to))),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('شعبه', 0), sakanHead('تعداد فاکتور', 100), sakanHead('فروش', 150), sakanHead('برگشت از فروش', 150), sakanHead('فروش خالص', 150)],
              count: rows.length + (rows.isEmpty ? 0 : 1),
              empty: 'فروشی در این بازه نیست',
              row: (_, i) {
                final last = i == rows.length;
                final r = last ? ('جمع', tot.$1, tot.$2, tot.$3) : rows[i];
                final st = TextStyle(fontWeight: last ? FontWeight.w800 : null);
                return Row(children: [
                  sakanCell(Text(r.$1, style: st), 0, align: Alignment.centerRight),
                  sakanCell(Text('${r.$4}', style: st), 100),
                  sakanCell(Text(groupDigits(r.$2), style: st), 150),
                  sakanCell(Text(groupDigits(r.$3), style: st), 150),
                  sakanCell(Text(groupDigits(r.$2 - r.$3), style: st), 150),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
