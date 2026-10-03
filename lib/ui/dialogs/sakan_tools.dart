import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart';
import '../../data/models.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../pages/vouchers_page.dart';
import '../print.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'ledger_dialogs.dart';
import 'users_dialogs.dart';

// ================================================================ مدیریت فایل های گزارش

String get _reportsFolder {
  final d = Directory('${Storage.userFolder.path}${Storage.sep}Reports');
  try {
    if (!d.existsSync()) d.createSync(recursive: true);
  } catch (_) {}
  return d.path;
}

Future<void> showReportFiles(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ReportFiles());

class _ReportFiles extends StatefulWidget {
  const _ReportFiles();

  @override
  State<_ReportFiles> createState() => _ReportFilesState();
}

class _ReportFilesState extends State<_ReportFiles> {
  String? _sel;

  Future<void> _edit(AppStore s, [ReportFile? r]) async {
    final res = await showReportFileDialog(context, r);
    if (res == null) return;
    if (res.selected) {
      for (final x in s.reportFiles) {
        x.selected = false;
      }
    }
    if (r == null) {
      s.reportFiles.add(res);
    } else {
      r
        ..folder = res.folder
        ..name = res.name
        ..file = res.file
        ..selected = res.selected;
    }
    s.saveNow();
    setState(() => _sel = res.id);
  }

  Future<void> _delete(AppStore s, ReportFile? r) async {
    if (r == null) return;
    final ok = await confirm(context, 'حذف گزارش', '«${r.name}» از لیست حذف شود؟');
    if (!ok) return;
    s.reportFiles.remove(r);
    s.saveNow();
    setState(() => _sel = null);
  }

  void _open(ReportFile? r) {
    if (r == null) return;
    final path = File(r.file).isAbsolute ? r.file : '${r.folder}${Storage.sep}${r.file}';
    if (!File(path).existsSync()) return toast(context, 'فایل گزارش پیدا نشد: $path', error: true);
    openFile(path);
  }

  Future<void> _import(AppStore s) async {
    final f = await fs.openFile(acceptedTypeGroups: const [fs.XTypeGroup(label: 'دفتر', extensions: ['json'])]);
    if (f == null) return;
    try {
      final other = AppStore.open(Storage(File(f.path).parent));
      var n = 0;
      for (final r in other.reportFiles) {
        if (s.reportFiles.any((x) => x.name == r.name && x.file == r.file)) continue;
        s.reportFiles.add(ReportFile(id: newId(), folder: r.folder, name: r.name, file: r.file));
        n++;
      }
      s.saveNow();
      if (mounted) toast(context, '$n گزارش وارد شد');
    } catch (e) {
      if (mounted) toast(context, 'ورود ناموفق: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.reportFiles;
    final cur = list.where((r) => r.id == _sel).firstOrNull;
    const w = [50.0, 0.0, 0.0];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): () => cur == null ? Navigator.pop(context) : _open(cur),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: SakanWindow(
        title: 'مدیریت فایل های گزارش',
        width: 820,
        height: 560,
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('محل استقرار فایل گزارش:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 34,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
                  child: Text(cur?.folder.isNotEmpty == true ? cur!.folder : _reportsFolder, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: SakanGrid(
                header: [
                  sakanHead('ردیف', w[0], color: const Color(0xFFE53935), fg: Colors.white),
                  sakanHead('نام گزارش', w[1]),
                  sakanHead('نام فایل گزارش', w[2]),
                ],
                count: list.length,
                empty: 'گزارشی ثبت نشده؛ «افزودن» را بزنید',
                row: (_, i) {
                  final r = list[i];
                  final sel = r.id == _sel;
                  return Material(
                    color: sel ? sakanSel : (i.isOdd ? const Color(0xFFF6FAFE) : Colors.white),
                    child: InkWell(
                      onTap: () => setState(() => _sel = r.id),
                      onDoubleTap: () => _open(r),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: sel ? Colors.white : null, fontWeight: r.selected ? FontWeight.w800 : null),
                        child: Row(children: [
                          sakanCell(Text('${i + 1}'), w[0]),
                          sakanCell(Text(r.name + (r.selected ? '  ★' : ''), maxLines: 1, overflow: TextOverflow.ellipsis), w[1], align: Alignment.centerRight),
                          sakanCell(Text(r.file.split(Storage.sep).last, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr), w[2]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final (i, b) in [
                sakanBtn('افزودن', () => _edit(s), color: sakanGreen),
                sakanBtn('ویرایش', cur == null ? null : () => _edit(s, cur)),
                sakanBtn('حذف', cur == null ? null : () => _delete(s, cur)),
                sakanBtn('ورود گزارشات از دفاتر دیگر', () => _import(s)),
                sakanBtn('تایید', () => cur == null ? Navigator.pop(context) : _open(cur), key: 'F9'),
                sakanBtn('انصراف', () => Navigator.pop(context), key: 'F10', color: sakanPink),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(flex: i == 3 ? 2 : 1, child: b),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

/// «نمونه گزارش».
Future<ReportFile?> showReportFileDialog(BuildContext context, ReportFile? r) {
  final folder = TextEditingController(text: r?.folder ?? _reportsFolder);
  final name = TextEditingController(text: r?.name ?? '');
  final file = TextEditingController(text: r?.file ?? '');
  var selected = r?.selected ?? false;
  return showDialog<ReportFile>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      void ok() {
        if (name.text.trim().isEmpty || file.text.trim().isEmpty) return;
        Navigator.pop(ctx, ReportFile(id: r?.id ?? newId(), folder: folder.text.trim(), name: name.text.trim(), file: file.text.trim(), selected: selected));
      }

      Widget row(String label, Widget child) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))), Expanded(child: child)]),
          );
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f9): ok,
          const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(ctx),
        },
        child: SakanWindow(
          title: 'نمونه گزارش',
          width: 560,
          height: 330,
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              row('محل استقرار گزارش:', TextField(controller: folder, textDirection: TextDirection.ltr, decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white))),
              row('نام گزارش:', TextField(controller: name, autofocus: true, decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white))),
              row(
                'فایل گزارش:',
                Row(children: [
                  Expanded(child: TextField(controller: file, textDirection: TextDirection.ltr, decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white))),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 50,
                    child: sakanBtn('...', () async {
                      final f = await fs.openFile(initialDirectory: folder.text.isEmpty ? null : folder.text);
                      if (f == null) return;
                      set(() {
                        file.text = f.path;
                        folder.text = File(f.path).parent.path;
                        if (name.text.isEmpty) name.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
                      });
                    }, color: const Color(0xFFFFE082)),
                  ),
                ]),
              ),
              InkWell(
                onTap: () => set(() => selected = !selected),
                child: Row(children: [Checkbox(value: selected, onChanged: (v) => set(() => selected = v ?? false)), const Text('منتخب پیش فرض')]),
              ),
              const Spacer(),
              Row(children: [
                Expanded(child: sakanBtn('تایید', ok, key: 'F9', color: sakanGreen)),
                const SizedBox(width: 6),
                Expanded(child: sakanBtn('انصراف', () => Navigator.pop(ctx), key: 'F10')),
              ]),
            ]),
          ),
        ),
      );
    }),
  );
}

// ================================================================ تهیه گزارش از گروه مراکز دفتر

String _centerOf(AppStore s, String? key) {
  if (key == null) return '';
  if (key.startsWith('v:')) {
    final v = s.vouchers.where((v) => 'v:${v.id}' == key).firstOrNull;
    if (v != null && v.center.isNotEmpty) return v.center;
  }
  return s.docMeta[key]?.center ?? '';
}

Future<void> showCenterGroupReport(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _CenterReportFilter());

class _CenterReportFilter extends StatefulWidget {
  const _CenterReportFilter();

  @override
  State<_CenterReportFilter> createState() => _CenterReportFilterState();
}

class _CenterReportFilterState extends State<_CenterReportFilter> {
  bool _byDate = false, _byCenter = false, _onlyDr = false, _onlyCr = false;
  DateTime? _from, _to;
  final _centers = <String>{};

  void _run() {
    final s = StoreScope.read(context);
    if (_byCenter && _centers.isEmpty) return toast(context, 'حداقل یک مرکز دفاتر را انتخاب کنید', error: true);
    final sums = <String, (int, int)>{};
    for (final p in buildJournal(s)) {
      if (_byDate && !DateFilter(from: _from, to: _to).hasDate(p.date)) continue;
      if (_byCenter) {
        final c = _centerOf(s, p.docKey);
        if (!_centers.contains(c.isEmpty ? 'اصلی' : c)) continue;
      }
      final k = '${p.moeen}|${p.tafsiliId ?? ''}';
      final o = sums[k] ?? (0, 0);
      sums[k] = (o.$1 + p.debit, o.$2 + p.credit);
    }
    final rows = <List<String>>[];
    final keys = sums.keys.toList()..sort();
    var td = 0, tc = 0;
    for (final k in keys) {
      final (d, c) = sums[k]!;
      final b = d - c;
      if (_onlyDr && b <= 0) continue;
      if (_onlyCr && b >= 0) continue;
      final m = findMoeen(k.split('|').first);
      td += d;
      tc += c;
      rows.add([accountCode(k), m?.kol.name ?? '', m?.name ?? '', accountName(s, k), groupDigits(d), groupDigits(c), groupDigits(b.abs()), b > 0 ? 'بد' : (b < 0 ? 'بس' : '-')]);
    }
    final title = 'گزارش از گروه مراکز دفتر${_byCenter ? ' — ${_centers.join('، ')}' : ''}';
    showDialog<void>(
      context: context,
      builder: (ctx) => _CenterReportResult(title: title, rows: rows, totalDr: td, totalCr: tc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    Widget check(String label, bool v, ValueChanged<bool> on) => InkWell(
          onTap: () => on(!v),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: v, onChanged: (x) => on(x ?? false)), Text(label, style: const TextStyle(fontWeight: FontWeight.w700))]),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _run,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: SakanWindow(
        title: 'تهیه گزارش از گروه مراکز دفتر',
        width: 620,
        height: 560,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: sakanSkyDark), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                check('محدودیت تاریخ:', _byDate, (v) => setState(() => _byDate = v)),
                if (_byDate)
                  Row(children: [
                    Expanded(child: DateField(label: 'از تاریخ', value: _from, clearable: true, onChanged: (d) => setState(() => _from = d))),
                    const SizedBox(width: 8),
                    Expanded(child: DateField(label: 'تا تاریخ', value: _to, clearable: true, onChanged: (d) => setState(() => _to = d))),
                  ]),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: sakanSkyDark), borderRadius: BorderRadius.circular(6)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  check('فیلتر گروه مرکز دفاتر', _byCenter, (v) => setState(() => _byCenter = v)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: _byCenter ? Colors.white : const Color(0xFFF7EEF0), border: Border.all(color: Colors.black26)),
                      child: ListView(children: [
                        for (final c in s.docCenters)
                          CheckboxListTile(
                            dense: true,
                            enabled: _byCenter,
                            value: _centers.contains(c),
                            title: Text(c),
                            onChanged: (v) => setState(() => v == true ? _centers.add(c) : _centers.remove(c)),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            check('فقط دفاتر با مانده بدهکار', _onlyDr, (v) => setState(() {
                  _onlyDr = v;
                  if (v) _onlyCr = false;
                })),
            check('فقط دفاتر با مانده بستانکار', _onlyCr, (v) => setState(() {
                  _onlyCr = v;
                  if (v) _onlyDr = false;
                })),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 170, child: sakanBtn('تهیه گزارش', _run, key: 'F9', icon: Icons.edit_note_rounded, color: sakanGreen)),
              const Spacer(),
              SizedBox(width: 140, child: sakanBtn('بازگشت', () => Navigator.pop(context), key: 'F10', icon: Icons.reply_rounded, color: const Color(0xFFFFE0B2))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _CenterReportResult extends StatelessWidget {
  final String title;
  final List<List<String>> rows;
  final int totalDr, totalCr;
  const _CenterReportResult({required this.title, required this.rows, required this.totalDr, required this.totalCr});

  static const _heads = ['کد', 'عنوان کل', 'عنوان معین', 'عنوان حساب', 'گردش بدهکار', 'گردش بستانکار', 'مانده', 'تشخیص'];
  static const _w = [80.0, 140.0, 160.0, 0.0, 130.0, 130.0, 130.0, 60.0];

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final b = totalDr - totalCr;
    return SakanWindow(
      title: 'گزارش پویا — $title',
      width: 1180,
      height: 700,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: SakanGrid(
              header: [for (var i = 0; i < _heads.length; i++) sakanHead(_heads[i], _w[i])],
              count: rows.length,
              empty: 'دفتری با این شرایط پیدا نشد',
              row: (_, i) {
                final r = rows[i];
                final sign = r[7] == 'بد' ? debtorBlue : (r[7] == 'بس' ? creditorRed : null);
                return Container(
                  color: i.isOdd ? const Color(0xFFF6FAFE) : Colors.white,
                  child: Row(children: [
                    for (var j = 0; j < r.length; j++)
                      sakanCell(
                        Text(r[j], maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: j >= 4 && j <= 6 ? TextDirection.ltr : null,
                            style: TextStyle(color: j >= 6 ? sign : null, fontWeight: j == 6 ? FontWeight.w800 : null)),
                        _w[j],
                        align: j == 3 ? Alignment.centerRight : Alignment.center,
                      ),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('جمع گردش بدهکار: ${groupDigits(totalDr)}    جمع گردش بستانکار: ${groupDigits(totalCr)}    مانده: ${groupDigits(b.abs())} ${b > 0 ? 'بد' : (b < 0 ? 'بس' : '')}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            SizedBox(
              width: 120,
              child: sakanBtn('چاپ', () => printTable(store: s, title: title, headers: _heads, rows: rows, numeric: const {4, 5, 6}, fileName: 'centers'), icon: Icons.print_outlined),
            ),
            const SizedBox(width: 6),
            SizedBox(width: 120, child: sakanBtn('بازگشت', () => Navigator.pop(context), key: 'F10')),
          ]),
        ]),
      ),
    );
  }
}

// ================================================================ سطل بازیافت

Future<void> showRecycleBin(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _RecycleBin());

class _RecycleBin extends StatefulWidget {
  const _RecycleBin();

  @override
  State<_RecycleBin> createState() => _RecycleBinState();
}

class _RecycleBinState extends State<_RecycleBin> {
  String? _sel;
  String _q = '';

  List<RecycleItem> _list(AppStore s) {
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final l = s.recycle.where((r) => q.isEmpty || normalizeDigits(r.desc).toLowerCase().contains(q) || '${r.number}' == q).toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return l;
  }

  void _restore(AppStore s, RecycleItem? r) {
    if (r == null) return toast(context, 'سندی انتخاب نشده', error: true);
    final err = s.restoreRecycled(r.id);
    if (err != null) return toast(context, err, error: true);
    setState(() => _sel = null);
    toast(context, 'سند ${r.number} بازیابی شد');
  }

  Future<void> _purge(AppStore s, RecycleItem? r) async {
    if (r == null) return;
    final ok = await confirm(context, 'حذف سند', 'سند ${r.number} برای همیشه حذف شود؟');
    if (!ok) return;
    s.purgeRecycled(r.id);
    setState(() => _sel = null);
  }

  Future<void> _clear(AppStore s) async {
    if (s.recycle.isEmpty) return;
    final ok = await confirm(context, 'پاک کردن سطل بازیافت', 'همه ${s.recycle.length} سند حذف شده برای همیشه پاک شوند؟');
    if (ok) s.clearRecycle();
  }

  Future<void> _search() async {
    final q = await showSearchBy(context, initial: _q);
    if (q != null) setState(() => _q = q);
  }

  /// Lines of the deleted document (shown on the side).
  List<(String, int, int)> _lines(AppStore s, RecycleItem r) {
    final doc = r.payload['doc'];
    if (doc is! Map<String, dynamic>) return const [];
    if (r.kind == 'v') {
      final v = Voucher.fromJson(doc);
      return [for (final l in v.lines) (accountName(s, '${l.moeen}|${l.tafsiliId ?? ''}'), l.debit, l.credit)];
    }
    if (r.kind == 'inv') {
      final inv = Invoice.fromJson(doc);
      return [for (final l in inv.lines) ('${s.product(l.productId)?.name ?? l.title}  × ${l.qty}', l.total, 0)];
    }
    final t = Txn.fromJson(doc);
    return [('${t.type.label} ${t.note}', t.amount, 0)];
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = _list(s);
    final cur = list.where((r) => r.id == _sel).firstOrNull ?? list.firstOrNull;
    const w = [130.0, 90.0, 100.0, 0.0];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => _restore(s, cur),
        const SingleActivator(LogicalKeyboardKey.f2): () => _purge(s, cur),
        const SingleActivator(LogicalKeyboardKey.f3): () => _clear(s),
        const SingleActivator(LogicalKeyboardKey.f4): () => showAuditReport(context),
        const SingleActivator(LogicalKeyboardKey.f5): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: SakanWindow(
          title: 'سطل بازیافت',
          width: 1200,
          height: 720,
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: sakanGroup(
                  'عملیات',
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final (label, key, fn, color) in [
                      ('بازیابی سند', 'F1', () => _restore(s, cur), const Color(0xFFFFE082)),
                      ('حذف سند', 'F2', () => _purge(s, cur), null),
                      ('پاک کردن سطل بازیافت', 'F3', () => _clear(s), null),
                      ('ردپای کاربر', 'F4', () => showAuditReport(context), null),
                      ('بازگشت', 'F5', () => Navigator.pop(context), null),
                      (_q.isEmpty ? 'جستجو' : 'جستجو ✓', '', _search, null),
                    ]) ...[
                      SizedBox(width: 140, child: sakanBtn(label, fn, key: key, color: color, height: 44)),
                      const SizedBox(width: 4),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    flex: 3,
                    child: SakanGrid(
                      header: [
                        sakanHead('تاریخ حذف', w[0]),
                        sakanHead('شماره سند', w[1]),
                        sakanHead('تاریخ سند', w[2]),
                        sakanHead('شرح سند', w[3]),
                      ],
                      count: list.length,
                      empty: 'سطل بازیافت خالی است',
                      row: (_, i) {
                        final r = list[i];
                        final sel = r.id == cur?.id;
                        return Material(
                          color: sel ? sakanSel : (i.isOdd ? const Color(0xFFF6FAFE) : Colors.white),
                          child: InkWell(
                            onTap: () => setState(() => _sel = r.id),
                            onDoubleTap: () => _restore(s, r),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(color: sel ? Colors.white : null, fontWeight: sel ? FontWeight.w700 : null),
                              child: Row(children: [
                                sakanCell(Text(jFormat(r.deletedAt)), w[0]),
                                sakanCell(Text('${r.number}/00', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)), w[1]),
                                sakanCell(Text(jFormat(r.date)), w[2]),
                                sakanCell(Text(r.desc, maxLines: 1, overflow: TextOverflow.ellipsis), w[3], align: Alignment.centerRight),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: SakanGrid(
                      header: [sakanHead('شرح', 0), sakanHead('مبلغ سند', 130), sakanHead('بستانکار', 110)],
                      count: cur == null ? 0 : _lines(s, cur).length,
                      empty: 'سندی انتخاب نشده',
                      row: (_, i) {
                        final l = _lines(s, cur!)[i];
                        return Row(children: [
                          sakanCell(Text(l.$1, maxLines: 1, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                          sakanCell(Text(l.$2 == 0 ? '' : groupDigits(l.$2), textDirection: TextDirection.ltr), 130),
                          sakanCell(Text(l.$3 == 0 ? '' : groupDigits(l.$3), textDirection: TextDirection.ltr), 110),
                        ]);
                      },
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text('${list.length} سند', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 20),
                if (cur != null) Text('مبلغ سند: ${groupDigits(cur.amount)}    کاربر حذف کننده: ${s.userName(cur.userId)}'),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ================================================================ کدبندی دفاتر کل و معین

Future<void> showChartCoding(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ChartCoding());

class _Tile {
  final String name;
  final String code;
  final String path;
  final int balance; // natural side
  final String kind;
  final VoidCallback open;
  final bool custom;
  _Tile(this.name, this.code, this.path, this.balance, this.kind, this.open, {this.custom = false});
}

class _ChartCoding extends StatefulWidget {
  const _ChartCoding();

  @override
  State<_ChartCoding> createState() => _ChartCodingState();
}

class _ChartCodingState extends State<_ChartCoding> {
  int _tab = 1; // 0 جستجو، 1 مسیر جاری دفاتر، 2 تنظیمات نمایشگر
  String? _kol; // level 2
  String? _moeen; // level 3
  final _filter = TextEditingController();
  String _applied = '';
  bool _showBalance = true, _showCode = true, _big = false;
  String? _sel;

  int get _level => _moeen != null ? 3 : (_kol != null ? 2 : 1);

  String get _path => [if (_kol != null) _kol!, if (_moeen != null) _moeen!].map((c) => '$c\\').join();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  static String _sideTitle(Side s) => switch (s) {
        Side.asset => 'دفاتر ترازنامه ای (دارایی)',
        Side.liability => 'دفاتر ترازنامه ای (بدهی)',
        Side.equity => 'دفاتر ترازنامه ای (سرمایه)',
        Side.income => 'دفاتر سود و زیانی (درآمد)',
        Side.expense => 'دفاتر سود و زیانی (هزینه)',
      };

  static String _kindOf(Side s) => s == Side.income || s == Side.expense ? 'سود و زیانی' : 'ترازنامه ای';

  void _up() => setState(() {
        _sel = null;
        if (_moeen != null) {
          _moeen = null;
        } else if (_kol != null) {
          _kol = null;
        } else {
          Navigator.pop(context);
        }
      });

  Map<String, List<_Tile>> _tiles(AppStore s) {
    final dr = <String, int>{};
    final journal = buildJournal(s);
    for (final p in journal) {
      dr[p.moeen] = (dr[p.moeen] ?? 0) + p.debit - p.credit;
      dr[p.kol] = (dr[p.kol] ?? 0) + p.debit - p.credit;
    }
    int nat(Side side, int d) => side == Side.asset || side == Side.expense ? d : -d;
    final q = normalizeDigits(_applied.trim()).toLowerCase();
    bool ok(String name, String code) => q.isEmpty || name.toLowerCase().contains(q) || code.contains(q);
    final out = <String, List<_Tile>>{};
    if (_level == 1) {
      for (final k in chart) {
        if (!ok(k.name, k.code)) continue;
        (out[_sideTitle(k.side)] ??= []).add(_Tile(k.name, k.code, '${k.code}\\', nat(k.side, dr[k.code] ?? 0), _kindOf(k.side), () => setState(() {
              _kol = k.code;
              _sel = null;
            })));
      }
    } else if (_level == 2) {
      final k = chart.firstWhere((k) => k.code == _kol);
      for (final m in k.ledgers) {
        if (s.hiddenMoeens.contains(m.code) || !ok(m.name, m.code)) continue;
        (out['${k.name} (${_kindOf(k.side)})'] ??= []).add(_Tile(m.name, m.code, '${k.code}\\${m.code}\\', nat(k.side, dr[m.code] ?? 0), _kindOf(k.side), () {
          if (m.hasEntity) {
            setState(() {
              _moeen = m.code;
              _sel = null;
            });
          } else {
            showAccountLedger(context, AccRow(key: m.code, code: m.code, kol: k.name, moeen: m.name, name: m.name, balance: dr[m.code] ?? 0, moeens: {m.code}));
          }
        }, custom: s.customMoeens.containsKey(m.code)));
      }
    } else {
      final m = findMoeen(_moeen)!;
      final bal = <String, int>{};
      for (final p in journal) {
        final key = '${p.moeen}|${p.tafsiliId ?? ''}';
        bal[key] = (bal[key] ?? 0) + p.debit - p.credit;
        bal[p.moeen] = (bal[p.moeen] ?? 0) + p.debit - p.credit;
      }
      for (final r in accountRows(s, AccCat(m.name, [m.code]), bal)) {
        if (!ok(r.name, r.code)) continue;
        (out['${m.name} (${_kindOf(m.side)})'] ??= [])
            .add(_Tile(r.name, r.code, '${m.kolCode}\\${m.code}\\${r.code}', nat(m.side, r.balance), 'تفصیلی', () => showAccountLedger(context, r)));
      }
    }
    return out;
  }

  Future<void> _create(AppStore s) async {
    final kols = chart.map((k) => k.code).toList();
    var kol = _kol ?? kols.first;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'ساخت دفتر',
          width: 480,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              value: kol,
              decoration: const InputDecoration(labelText: 'دفتر کل'),
              items: [for (final k in chart) DropdownMenuItem(value: k.code, child: Text('${k.code}  ${k.name}'))],
              onChanged: (v) => set(() => kol = v ?? kol),
            ),
            const SizedBox(height: 10),
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان دفتر معین')),
          ]),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final code = s.addMoeen(kol, name.text);
    setState(() {
      _kol = kol;
      _moeen = null;
      _sel = code;
    });
    if (mounted) toast(context, 'دفتر $code — ${name.text.trim()} ساخته شد');
  }

  Future<void> _editCustom(AppStore s, _Tile t) async {
    final c = TextEditingController(text: t.name);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'دفتر ${t.code}',
        width: 440,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, '#delete'), child: const Text('حذف دفتر', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('تایید')),
        ],
        child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان دفتر')),
      ),
    );
    if (r == null) return;
    final err = r == '#delete' ? s.editMoeen(t.code, remove: true) : s.editMoeen(t.code, name: r);
    if (err != null && mounted) toast(context, err, error: true);
  }

  void _print(AppStore s, Map<String, List<_Tile>> groups) {
    final rows = <List<String>>[
      for (final e in groups.entries)
        for (final t in e.value) [t.code, t.name, t.path, groupDigits(t.balance.abs()) + (t.balance < 0 ? '-' : ''), e.key],
    ];
    printTable(store: s, title: 'کدبندی دفاتر کل و معین', subtitle: 'مسیر جاری: ${_path.isEmpty ? 'ریشه' : _path}', headers: const ['کد', 'عنوان دفتر', 'مسیر', 'مانده', 'گروه'], rows: rows, numeric: const {3}, fileName: 'chart');
  }

  Widget _tabButton(String label, int i, {VoidCallback? onTap}) => InkWell(
        onTap: onTap ?? () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _tab == i ? Colors.white : Colors.transparent,
            border: Border.all(color: _tab == i ? sakanSkyDark : Colors.transparent),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Text(label, style: TextStyle(fontWeight: _tab == i ? FontWeight.w800 : FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final groups = _tiles(s);
    final all = allMoeens.toList();
    final tileW = _big ? 230.0 : 190.0;

    Widget tabBody() => switch (_tab) {
          0 => Row(children: [
              const Text('فیلتر', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _filter,
                    decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, hintText: 'فیلتر با نام دفتر'),
                    onSubmitted: (v) => setState(() => _applied = v),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(width: 90, child: sakanBtn('دفاتر', () => setState(() => _applied = _filter.text), icon: Icons.folder_open_rounded)),
              const SizedBox(width: 4),
              SizedBox(
                width: 90,
                child: sakanBtn('اسناد', () {
                  final nav = Nav.of(context);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  nav.go(AppPage.vouchers);
                }, icon: Icons.list_alt_rounded),
              ),
            ]),
          2 => Wrap(spacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final (label, v, fn) in [
                ('نمایش مانده', _showBalance, (bool x) => setState(() => _showBalance = x)),
                ('نمایش کد و مسیر', _showCode, (bool x) => setState(() => _showCode = x)),
                ('آیکون بزرگ', _big, (bool x) => setState(() => _big = x)),
              ])
                InkWell(onTap: () => fn(!v), child: Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: v, onChanged: (x) => fn(x ?? false)), Text(label)])),
            ]),
          _ => Row(children: [
              const Text('مسیر جاری دفاتر:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 32,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
                  child: Text(_path, textDirection: TextDirection.ltr),
                ),
              ),
              const SizedBox(width: 10),
              Text('شماره سطح: $_level', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              const Text('شماره آخرین سطح نسخه نرم افزار: 3'),
              const SizedBox(width: 10),
              SizedBox(width: 70, child: sakanBtn('چاپ', () => _print(s, groups), icon: Icons.print_outlined)),
              const SizedBox(width: 4),
              SizedBox(
                width: 80,
                child: sakanBtn('ن.ن.چاپ', () => _print(s, groups), icon: Icons.preview_outlined),
              ),
            ]),
        };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _up,
        const SingleActivator(LogicalKeyboardKey.backspace): _up,
      },
      child: Focus(
        autofocus: true,
        child: SakanWindow(
          title: 'کدبندی دفاتر کل و معین',
          width: 1240,
          height: 760,
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _tabButton('جستجو', 0),
                _tabButton('مسیر جاری دفاتر', 1),
                _tabButton('تنظیمات نمایشگر', 2),
                _tabButton('ساخت دفتر', 3, onTap: () => _create(s)),
                InkWell(
                  onTap: _up,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(children: [Icon(Icons.arrow_circle_right_rounded, color: Color(0xFF2E9E4F), size: 20), SizedBox(width: 4), Text('برگشت', style: TextStyle(fontWeight: FontWeight.w600))]),
                  ),
                ),
              ]),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), border: Border.all(color: sakanSkyDark)),
                child: tabBody(),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // ledger list with visibility checks
                  Container(
                    width: 300,
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: sakanSkyDark)),
                    child: ListView(children: [
                      for (final m in all)
                        InkWell(
                          onTap: () => setState(() {
                            _kol = m.kolCode;
                            _moeen = null;
                            _sel = m.code;
                          }),
                          child: Container(
                            height: 28,
                            color: _sel == m.code ? sakanSel : null,
                            child: Row(children: [
                              Checkbox(
                                value: !s.hiddenMoeens.contains(m.code),
                                visualDensity: VisualDensity.compact,
                                activeColor: const Color(0xFF2E9E4F),
                                onChanged: (_) => s.toggleMoeenHidden(m.code),
                              ),
                              Expanded(
                                child: Text(m.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: _sel == m.code ? Colors.white : null, fontSize: 13)),
                              ),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  // tiles
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: sakanSkyDark)),
                      child: groups.isEmpty
                          ? const Center(child: Text('دفتری وجود ندارد', style: TextStyle(color: Colors.black45)))
                          : ListView(padding: const EdgeInsets.all(10), children: [
                              for (final e in groups.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(children: [
                                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF345))),
                                    const SizedBox(width: 8),
                                    const Expanded(child: Divider()),
                                  ]),
                                ),
                                Wrap(spacing: 10, runSpacing: 10, children: [
                                  for (final t in e.value)
                                    InkWell(
                                      onTap: () => setState(() => _sel = t.code),
                                      onDoubleTap: t.open,
                                      onLongPress: t.custom ? () => _editCustom(s, t) : null,
                                      onSecondaryTap: t.custom ? () => _editCustom(s, t) : null,
                                      child: Container(
                                        width: tileW,
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: _sel == t.code ? const Color(0xFFE3EEFC) : null,
                                          border: Border.all(color: _sel == t.code ? sakanSel : Colors.transparent),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Icon(t.kind == 'تفصیلی' ? Icons.description_outlined : Icons.table_chart_outlined,
                                              size: _big ? 48 : 38, color: t.custom ? const Color(0xFF2E9E4F) : const Color(0xFF7A8BA3)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                                              if (_showCode) Text(t.code, style: const TextStyle(fontSize: 11)),
                                              if (_showCode) Text(t.path, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                                              if (_showBalance)
                                                Text(groupDigits(t.balance.abs()) + (t.balance < 0 ? '-' : ''),
                                                    textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: balanceColor(t.balance))),
                                              Text(t.kind, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
                                            ]),
                                          ),
                                        ]),
                                      ),
                                    ),
                                ]),
                              ],
                            ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
