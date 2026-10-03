import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/jalali.dart';
import '../../data/books.dart';
import '../../data/store.dart';
import '../widgets/common.dart';

const _sky = Color(0xFFDCEBFA);
const _skyDark = Color(0xFF9DC3EA);

/// Lets windows open another financial book (provided by the app root).
class BookSwitch extends InheritedWidget {
  final void Function(AppStore store) open;
  const BookSwitch({super.key, required this.open, required super.child});

  static BookSwitch? of(BuildContext context) => context.getInheritedWidgetOfExactType<BookSwitch>();

  @override
  bool updateShouldNotify(BookSwitch oldWidget) => false;
}

Widget _kb(String label, VoidCallback? onTap, {String key = '', IconData? icon, Color? color, double height = 38}) => SizedBox(
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: color ?? Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1))),
        ]),
      ),
    );

Widget _hcell(String t, double w) {
  final c = Container(
    height: 32,
    alignment: Alignment.center,
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black12))),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

Widget _cell(String t, double w, {bool bold = false, bool ltr = false}) {
  final c = Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black12))),
    child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: ltr ? TextDirection.ltr : null,
        style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

Widget _frame(BuildContext context, {required String title, required Widget body, double width = 900, double height = 600}) {
  final size = MediaQuery.of(context).size;
  return Dialog(
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    backgroundColor: _sky,
    child: SizedBox(
      width: width,
      height: height.clamp(200.0, size.height * 0.92),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HeaderBand(
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15))),
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Expanded(child: body),
      ]),
    ),
  );
}

String _date(DateTime? d) => d == null ? '' : jFormat(d);

// ================================================================ مدیریت دفاتر مالی

/// «مدیریت دفاتر مالی». With [pick] the chosen book is returned (ورود به دفتر).
Future<BookInfo?> showBooksManager(BuildContext context, {bool pick = false}) =>
    showDialog<BookInfo>(context: context, builder: (_) => _BooksManager(pick: pick));

class _BooksManager extends StatefulWidget {
  final bool pick;
  const _BooksManager({this.pick = false});

  @override
  State<_BooksManager> createState() => _BooksManagerState();
}

class _BooksManagerState extends State<_BooksManager> {
  late BookRegistry _reg;
  late String _currentId;
  String? _sel;

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    _reg = BookRegistry.of(s);
    _currentId = BookRegistry.idOf(s.storage.dir);
    _sel = _currentId;
  }

  BookInfo? get _cur => _reg.active.where((b) => b.id == _sel).firstOrNull;

  Future<void> _edit(BookInfo? b) async {
    if (b == null) return toast(context, 'دفتری انتخاب نشده', error: true);
    final r = await showBookInfoDialog(context, b, title: 'ویرایش مشخصات دفتر');
    if (r == null) return;
    setState(() {
      b
        ..title = r.title
        ..latin = r.latin
        ..start = r.start
        ..end = r.end
        ..group = r.group;
      _reg.save();
    });
  }

  Future<void> _create({bool fromSelected = false}) async {
    final s = StoreScope.read(context);
    final src = fromSelected ? _cur : null;
    if (fromSelected && src == null) return toast(context, 'ابتدا دفتر منتخب را انتخاب کنید', error: true);
    final last = _reg.active.map((b) => b.end).whereType<DateTime>().fold<DateTime?>(null, (a, d) => a == null || d.isAfter(a) ? d : a);
    final y = last == null ? Jalali.now().year : Jalali.fromDateTime(last).year + 1;
    final draft = BookInfo(
      id: '',
      title: 'دفتر مالی $y',
      latin: 'mali$y',
      start: Jalali(y, 1, 1).toDateTime(),
      end: Jalali(y, 12, Jalali.monthLength(y, 12)).toDateTime(),
      group: src?.group ?? '',
    );
    final info = await showBookInfoDialog(context, draft, title: fromSelected ? 'ساخت دفتر مالی از روی «${src!.title}»' : 'ساخت دفتر مالی');
    if (info == null || !mounted) return;
    final copy = src == null ? null : (src.id == _currentId ? s : _reg.open(src.id));
    final b = _reg.create(info, s, copyOf: copy);
    setState(() => _sel = b.id);
    toast(context, '«${b.title}» ساخته شد');
  }

  Future<void> _delete() async {
    final b = _cur;
    if (b == null) return;
    if (b.id == _currentId) return toast(context, 'دفتر جاری حذف نمی‌شود', error: true);
    final ok = await confirm(context, 'حذف دفتر', '«${b.title}» حذف شود؟ (از «بازیابی دفاتر حذف شده» برمی‌گردد)');
    if (!ok) return;
    setState(() {
      b.deleted = true;
      _reg.save();
      _sel = _currentId;
    });
  }

  Future<void> _restore() async {
    final list = _reg.deleted;
    if (list.isEmpty) return toast(context, 'دفتر حذف شده ای وجود ندارد');
    final r = await showDialog<BookInfo>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'بازیابی دفاتر حذف شده',
        width: 480,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
        child: Column(children: [
          for (final b in list)
            ListTile(
              dense: true,
              leading: const Icon(Icons.restore_rounded),
              title: Text(b.title),
              subtitle: Text('${_date(b.start)} تا ${_date(b.end)}'),
              onTap: () => Navigator.pop(ctx, b),
            ),
        ]),
      ),
    );
    if (r == null) return;
    setState(() {
      r.deleted = false;
      _reg.save();
      _sel = r.id;
    });
  }

  void _move(int d) {
    final b = _cur;
    if (b == null) return;
    final i = _reg.books.indexOf(b);
    final j = i + d;
    if (j < 0 || j >= _reg.books.length) return;
    setState(() {
      _reg.books
        ..removeAt(i)
        ..insert(j, b);
      _reg.save();
    });
  }

  void _ok() {
    final b = _cur;
    if (b == null) return;
    Navigator.pop(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final list = _reg.active;
    const w = [0.0, 130.0, 150.0, 150.0, 150.0];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: _frame(
          context,
          title: 'مدیریت دفاتر مالی',
          width: 960,
          height: 560,
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Container(
                          color: const Color(0xFFEFF5FC),
                          child: Row(children: [
                            _hcell('عنوان دفتر مالی', w[0]),
                            _hcell('نام لاتین', w[1]),
                            _hcell('تاریخ شروع سال مالی', w[2]),
                            _hcell('تاریخ پایان سال مالی', w[3]),
                            _hcell('عنوان گروه', w[4]),
                          ]),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(children: [
                            for (final b in list)
                              Material(
                                color: b.id == _sel ? const Color(0xFF2F6FDE) : Colors.white,
                                child: InkWell(
                                  onTap: () => setState(() => _sel = b.id),
                                  onDoubleTap: () {
                                    setState(() => _sel = b.id);
                                    widget.pick ? _ok() : _edit(b);
                                  },
                                  child: DefaultTextStyle.merge(
                                    style: TextStyle(color: b.id == _sel ? Colors.white : null),
                                    child: SizedBox(
                                      height: 32,
                                      child: Row(children: [
                                        _cell(b.id == _currentId ? '${b.title}  (جاری)' : b.title, w[0], bold: b.id == _currentId),
                                        _cell(b.latin, w[1], ltr: true),
                                        _cell(_date(b.start), w[2]),
                                        _cell(_date(b.end), w[3]),
                                        _cell(b.group, w[4]),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(children: [
                    for (final (icon, tip, fn) in [
                      (Icons.apps_rounded, 'ورود به دفتر', _ok),
                      (Icons.arrow_upward_rounded, 'بالا', () => _move(-1)),
                      (Icons.arrow_downward_rounded, 'پایین', () => _move(1)),
                      (Icons.bookmark_rounded, 'ویرایش مشخصات دفتر', () => _edit(_cur)),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: IconButton.outlined(tooltip: tip, onPressed: fn, icon: Icon(icon, size: 20)),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                for (final (i, b) in [
                  _kb('ویرایش مشخصات دفتر', () => _edit(_cur), color: const Color(0xFFD7F2D7)),
                  _kb('ساخت دفتر مالی', () => _create()),
                  _kb('مشخصات شرکت', () => showCompanyInfo(context)),
                  _kb('ساخت دفتر مالی از روی دفتر منتخب', () => _create(fromSelected: true)),
                  _kb('بازیابی دفاتر حذف شده', _restore),
                  _kb('حذف دفتر', _delete),
                  if (widget.pick) _kb('تایید', _ok, key: 'F9', color: const Color(0xFFD7F2D7)),
                  _kb('انصراف', () => Navigator.pop(context), key: 'F10', color: const Color(0xFFFBE0E0)),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: b),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Fields of a book (ساخت / ویرایش دفتر).
Future<BookInfo?> showBookInfoDialog(BuildContext context, BookInfo b, {required String title}) {
  final t = TextEditingController(text: b.title);
  final l = TextEditingController(text: b.latin);
  final g = TextEditingController(text: b.group);
  DateTime? start = b.start, end = b.end;
  return showDialog<BookInfo>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      void ok() {
        if (t.text.trim().isEmpty) return;
        Navigator.pop(ctx, BookInfo(id: b.id, title: t.text.trim(), latin: l.text.trim(), start: start, end: end, group: g.text.trim()));
      }

      return FormDialog(
        title: title,
        width: 520,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
          FilledButton(onPressed: ok, child: const Text('تایید F9')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: t, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان دفتر مالی')),
          const SizedBox(height: 10),
          TextField(controller: l, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'نام لاتین')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DateField(label: 'تاریخ شروع سال مالی', value: start, onChanged: (d) => set(() => start = d))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'تاریخ پایان سال مالی', value: end, onChanged: (d) => set(() => end = d))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: g, decoration: const InputDecoration(labelText: 'عنوان گروه')),
        ]),
      );
    }),
  );
}

/// «مشخصات شرکت».
Future<void> showCompanyInfo(BuildContext context) async {
  final s = StoreScope.read(context);
  final n = TextEditingController(text: s.settings.businessName);
  final o = TextEditingController(text: s.settings.ownerName);
  final p = TextEditingController(text: s.settings.businessPhone);
  final a = TextEditingController(text: s.settings.businessAddress);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'مشخصات شرکت',
      width: 520,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: n, autofocus: true, decoration: const InputDecoration(labelText: 'نام شرکت / فروشگاه')),
        const SizedBox(height: 10),
        TextField(controller: o, decoration: const InputDecoration(labelText: 'نام مدیر')),
        const SizedBox(height: 10),
        TextField(controller: p, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تلفن')),
        const SizedBox(height: 10),
        TextField(controller: a, maxLines: 2, decoration: const InputDecoration(labelText: 'آدرس')),
      ]),
    ),
  );
  if (ok == true) {
    s.settings
      ..businessName = n.text.trim()
      ..ownerName = o.text.trim()
      ..businessPhone = p.text.trim()
      ..businessAddress = a.text.trim();
    s.saveNow();
  }
}

// ================================================================ انتقال حسابهای دفتر به دفتر جدید

Future<void> showTransferToBook(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _TransferToBook());

class _TransferToBook extends StatefulWidget {
  const _TransferToBook();

  @override
  State<_TransferToBook> createState() => _TransferToBookState();
}

class _TransferToBookState extends State<_TransferToBook> {
  String? _target;

  Future<void> _ok() async {
    final s = StoreScope.read(context);
    final reg = BookRegistry.of(s);
    final cur = BookRegistry.idOf(s.storage.dir);
    if (_target == null) return toast(context, 'دفتر مقصد را انتخاب کنید', error: true);
    if (_target == cur) return toast(context, 'دفتر مقصد نمی‌تواند دفتر جاری باشد', error: true);
    final b = reg.byId(_target!);
    final ok = await confirm(context, 'انتقال حسابها', 'مانده همه حسابها به عنوان مانده اول دوره به «${b?.title}» منتقل شود؟', ok: 'انتقال', danger: false);
    if (!ok || !mounted) return;
    try {
      reg.transferBalances(s, _target!);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'مانده حسابها به «${b?.title}» منتقل شد');
    } catch (e) {
      toast(context, 'انتقال ناموفق: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final reg = BookRegistry.of(s);
    final cur = BookRegistry.idOf(s.storage.dir);
    final books = reg.active.where((b) => b.id != cur).toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: _frame(
        context,
        title: 'انتقال حسابهای دفتر به دفتر جدید',
        width: 560,
        height: 230,
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Text('دفتر', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: books.any((b) => b.id == _target) ? _target : null,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white),
                    items: [for (final b in books) DropdownMenuItem(value: b.id, child: Text(b.title))],
                    onChanged: (v) => setState(() => _target = v),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 50,
                  child: _kb('...', () async {
                    final b = await showBooksManager(context, pick: true);
                    if (b != null) setState(() => _target = b.id);
                  }),
                ),
              ]),
            ),
            const Spacer(),
            Row(children: [
              Expanded(child: _kb('تایید', _ok, key: 'F9', color: const Color(0xFFD7F2D7))),
              const SizedBox(width: 6),
              Expanded(child: _kb('انصراف', () => Navigator.pop(context), key: 'F10')),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ================================================================ ورود به دفاتر دیگر

/// F12 — picks another book and opens it.
Future<void> openOtherBook(BuildContext context) async {
  final s = StoreScope.read(context);
  final b = await showBooksManager(context, pick: true);
  if (b == null || !context.mounted) return;
  final reg = BookRegistry.of(s);
  if (b.id == BookRegistry.idOf(s.storage.dir)) return toast(context, 'این دفتر هم اکنون باز است');
  reg.current = b.id;
  reg.save();
  final sw = BookSwitch.of(context);
  if (sw == null) {
    toast(context, 'دفتر «${b.title}» در اجرای بعدی برنامه باز می‌شود');
    return;
  }
  sw.open(reg.open(b.id));
}
