import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'misc_dialogs.dart';

/// Large window frame used by the cheque tools (gradient header + body + footer).
class _Window extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget body;
  final Widget footer;
  final double width;
  const _Window({required this.title, required this.icon, required this.body, required this.footer, this.width = 1000});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: (size.height * 0.88).clamp(420.0, 720.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HeaderBand(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              child: Row(children: [
                Icon(icon, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                IconButton(
                  tooltip: 'بستن',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Expanded(child: body),
            const Divider(),
            Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 12), child: footer),
          ],
        ),
      ),
    );
  }
}

Widget _gridHeader(BuildContext context, List<Widget> cells) {
  final th = Theme.of(context);
  return Container(
    color: Brand.of(context).accent.withValues(alpha: 0.10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: DefaultTextStyle(
      style: th.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w800, color: th.colorScheme.onSurface),
      child: Row(children: cells),
    ),
  );
}

// ================================================================ معرفی دسته چک

Future<void> showChequeBooksWindow(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ChequeBooksWindow());

class _ChequeBooksWindow extends StatefulWidget {
  const _ChequeBooksWindow();

  @override
  State<_ChequeBooksWindow> createState() => _ChequeBooksWindowState();
}

class _ChequeBooksWindowState extends State<_ChequeBooksWindow> {
  String? _acc;
  String? _bookId;
  int? _number;
  String _q = '';

  List<Account> _banks(AppStore s) => s.activeAccounts.where((a) => a.type != AccountType.cash).toList();

  ChequeLeaf? _selected(AppStore s) {
    if (_acc == null || _bookId == null || _number == null) return null;
    return s.leavesOf(_acc!).where((l) => l.book.id == _bookId && l.number == _number).firstOrNull;
  }

  String _remarks(AppStore s, ChequeLeaf l) => switch (l.state) {
        LeafState.used => [
            if (l.cheque!.personId != null) 'در وجه ${s.person(l.cheque!.personId)?.name ?? ''}',
            'مبلغ ${groupDigits(l.cheque!.amount)}',
            'سررسید ${jFormat(l.cheque!.dueDate)}',
            l.cheque!.status.label,
          ].join(' — '),
        LeafState.voided => l.book.notes['${l.number}'] ?? '',
        LeafState.free => '',
      };

  Future<void> _define() async {
    final s = StoreScope.read(context);
    if (_banks(s).isEmpty) {
      toast(context, 'ابتدا یک حساب بانکی تعریف کنید', error: true);
      return;
    }
    final b = await showDialog<ChequeBook>(context: context, builder: (_) => _DefineBookDialog(accountId: _acc));
    if (b != null && mounted) {
      setState(() {
        _acc = b.accountId;
        _bookId = b.id;
        _number = b.start;
      });
      toast(context, 'دسته چک با ${b.count} برگه تعریف شد');
    }
  }

  Future<void> _void() async {
    final s = StoreScope.read(context);
    final l = _selected(s);
    if (l == null) return toast(context, 'برگه چک را انتخاب کنید', error: true);
    if (l.state == LeafState.used) return toast(context, 'این برگه برای چک صادر شده استفاده شده است', error: true);
    if (l.state == LeafState.voided) return toast(context, 'این برگه قبلا ابطال شده است', error: true);
    final note = TextEditingController(text: 'ابطال شده');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'ابطال برگه چک ${l.serial}',
        width: 440,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابطال')),
        ],
        child: TextField(controller: note, autofocus: true, decoration: const InputDecoration(labelText: 'ملاحظات')),
      ),
    );
    if (ok == true) s.setLeafVoid(l.book, l.number, true, note: note.text.trim());
    note.dispose();
  }

  void _unvoid() {
    final s = StoreScope.read(context);
    final l = _selected(s);
    if (l == null) return toast(context, 'برگه چک را انتخاب کنید', error: true);
    if (l.state != LeafState.voided) return toast(context, 'این برگه باطل نشده است', error: true);
    s.setLeafVoid(l.book, l.number, false);
  }

  Future<void> _delete() async {
    final s = StoreScope.read(context);
    final l = _selected(s);
    if (l == null) return toast(context, 'یک برگه از دسته چک مورد نظر را انتخاب کنید', error: true);
    final b = l.book;
    final ok = await confirm(context, 'حذف دسته چک', 'دسته چک ${b.serialOf(b.start)} تا ${b.serialOf(b.start + b.count - 1)} حذف شود؟');
    if (!ok || !mounted) return;
    if (s.removeChequeBook(b.id)) {
      setState(() => _bookId = _number = null);
      toast(context, 'دسته چک حذف شد');
    } else {
      toast(context, 'از این دسته چک، چک صادر شده و قابل حذف نیست', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final banks = _banks(s);
    if (_acc == null || !banks.any((a) => a.id == _acc)) _acc = banks.isEmpty ? null : banks.first.id;
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final leaves = _acc == null
        ? <ChequeLeaf>[]
        : s.leavesOf(_acc!).where((l) => q.isEmpty || '${l.serial} ${_remarks(s, l)}'.toLowerCase().contains(q)).toList();
    final all = _acc == null ? <ChequeLeaf>[] : s.leavesOf(_acc!);
    int count(LeafState st) => all.where((l) => l.state == st).length;

    Widget tool(String label, String key, IconData icon, Color color, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(backgroundColor: color.withValues(alpha: 0.12), foregroundColor: color),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text('$label ($key)'),
          ),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _define,
        const SingleActivator(LogicalKeyboardKey.f3): _void,
        const SingleActivator(LogicalKeyboardKey.f4): _unvoid,
        const SingleActivator(LogicalKeyboardKey.f5): _delete,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: _Window(
          title: 'معرفی دسته چک',
          icon: Icons.menu_book_outlined,
          footer: Row(children: [
            Pill('سفید: ${count(LeafState.free)}', color: AppColors.income),
            const SizedBox(width: 6),
            Pill('صادر شده: ${count(LeafState.used)}', color: th.colorScheme.primary),
            const SizedBox(width: 6),
            Pill('باطل: ${count(LeafState.voided)}', color: AppColors.expense),
            const Spacer(),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت (F10)')),
          ]),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(children: [
                  tool('تعریف', 'F2', Icons.add_box_outlined, AppColors.income, _define),
                  tool('ابطال', 'F3', Icons.block_rounded, AppColors.expense, _void),
                  tool('برگشت از ابطال', 'F4', Icons.undo_rounded, AppColors.debt, _unvoid),
                  tool('حذف', 'F5', Icons.delete_outline_rounded, const Color(0xFF64748B), _delete),
                  const Spacer(),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'عبارت مورد جستجو', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // leaves grid
                      Expanded(
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _gridHeader(context, const [
                              SizedBox(width: 50, child: Text('ردیف')),
                              SizedBox(width: 150, child: Text('شماره چک')),
                              SizedBox(width: 100, child: Text('وضعیت')),
                              Expanded(child: Text('ملاحظات')),
                            ]),
                            Expanded(
                              child: leaves.isEmpty
                                  ? EmptyState(
                                      icon: Icons.menu_book_outlined,
                                      text: banks.isEmpty ? 'حساب بانکی تعریف نشده' : 'برای این بانک دسته چکی تعریف نشده (F2)',
                                    )
                                  : ListView.builder(
                                      itemCount: leaves.length,
                                      itemExtent: 40,
                                      itemBuilder: (context, i) {
                                        final l = leaves[i];
                                        final sel = l.book.id == _bookId && l.number == _number;
                                        final newBook = i == 0 || leaves[i - 1].book.id != l.book.id;
                                        final (txt, color) = switch (l.state) {
                                          LeafState.free => ('سفید', AppColors.income),
                                          LeafState.used => ('صادر شده', th.colorScheme.primary),
                                          LeafState.voided => ('باطل', AppColors.expense),
                                        };
                                        return Material(
                                          color: sel
                                              ? th.colorScheme.primary.withValues(alpha: 0.14)
                                              : (i.isOdd ? th.colorScheme.surfaceContainerLowest : th.colorScheme.surface),
                                          child: InkWell(
                                            onTap: () => setState(() {
                                              _bookId = l.book.id;
                                              _number = l.number;
                                            }),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              decoration: newBook && i > 0
                                                  ? BoxDecoration(border: Border(top: BorderSide(color: th.colorScheme.primary.withValues(alpha: 0.5), width: 2)))
                                                  : null,
                                              child: Row(children: [
                                                SizedBox(width: 50, child: Text('${i + 1}')),
                                                SizedBox(
                                                  width: 150,
                                                  child: Text(l.serial,
                                                      textDirection: TextDirection.ltr,
                                                      textAlign: TextAlign.right,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        decoration: l.state == LeafState.voided ? TextDecoration.lineThrough : null,
                                                      )),
                                                ),
                                                SizedBox(width: 100, child: Align(alignment: AlignmentDirectional.centerStart, child: Pill(txt, color: color))),
                                                Expanded(child: Text(_remarks(s, l), overflow: TextOverflow.ellipsis)),
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
                      const SizedBox(width: 12),
                      // bank list
                      SizedBox(
                        width: 250,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _gridHeader(context, const [Expanded(child: Text('نام بانک'))]),
                            Expanded(
                              child: ListView(children: [
                                for (final a in banks)
                                  ListTile(
                                    dense: true,
                                    selected: a.id == _acc,
                                    selectedTileColor: th.colorScheme.primary.withValues(alpha: 0.12),
                                    leading: Icon(Icons.account_balance_rounded, color: Color(a.color), size: 20),
                                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    trailing: Text('${s.chequeBooks.where((b) => b.accountId == a.id).length} دسته',
                                        style: th.textTheme.labelSmall),
                                    onTap: () => setState(() {
                                      _acc = a.id;
                                      _bookId = _number = null;
                                    }),
                                  ),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DefineBookDialog extends StatefulWidget {
  final String? accountId;
  const _DefineBookDialog({this.accountId});

  @override
  State<_DefineBookDialog> createState() => _DefineBookDialogState();
}

class _DefineBookDialogState extends State<_DefineBookDialog> {
  String? _acc;
  final _prefix = TextEditingController();
  final _start = TextEditingController();
  final _suffix = TextEditingController();
  final _count = TextEditingController(text: '50');
  String? _err;

  @override
  void initState() {
    super.initState();
    _acc = widget.accountId;
  }

  @override
  void dispose() {
    for (final c in [_prefix, _start, _suffix, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final start = int.tryParse(normalizeDigits(_start.text.trim()));
    final count = int.tryParse(normalizeDigits(_count.text.trim()));
    String? err;
    if (_acc == null) {
      err = 'عنوان حساب را انتخاب کنید';
    } else if (start == null || start <= 0) {
      err = 'شماره چک را وارد کنید';
    } else if (count == null || count <= 0 || count > 1000) {
      err = 'تعداد برگه باید بین ۱ تا ۱۰۰۰ باشد';
    }
    if (err == null) {
      final b = ChequeBook(id: newId(), accountId: _acc!, prefix: _prefix.text.trim(), start: start!, suffix: _suffix.text.trim(), count: count!);
      final existing = s.leavesOf(_acc!).map((l) => l.serial).toSet();
      final dup = b.numbers.map(b.serialOf).where(existing.contains).firstOrNull;
      if (dup != null) {
        err = 'برگه $dup قبلا در دسته چک دیگری تعریف شده است';
      } else {
        s.saveChequeBook(b);
        Navigator.pop(context, b);
        return;
      }
    }
    setState(() => _err = err);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final banks = s.activeAccounts.where((a) => a.type != AccountType.cash).toList();
    if (_acc == null && banks.isNotEmpty) _acc = banks.first.id;
    final start = int.tryParse(normalizeDigits(_start.text.trim()));
    final count = int.tryParse(normalizeDigits(_count.text.trim()));
    final preview = start != null && count != null && count > 0
        ? 'از ${_prefix.text.trim()}$start${_suffix.text.trim()} تا ${_prefix.text.trim()}${start + count - 1}${_suffix.text.trim()}'
        : '';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'تعریف دسته چک',
        width: 520,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldDropdown<String?>(
              label: 'عنوان حساب',
              value: _acc,
              items: [for (final a in banks) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _acc = v),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _suffix,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'پسوند شماره'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _start,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'شماره چک'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _prefix,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'پیشوند شماره'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _count,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'تعداد برگه'),
              onChanged: (_) => setState(() {}),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(preview, style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
            ],
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!, style: TextStyle(color: th.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

// ================================================================ جا به جایی چک

Future<void> showChequeMoveDialog(BuildContext context, {Voucher? edit}) =>
    showDialog<void>(context: context, builder: (_) => _ChequeMoveDialog(edit: edit));

class _ChequeMoveDialog extends StatefulWidget {
  final Voucher? edit;
  const _ChequeMoveDialog({this.edit});

  @override
  State<_ChequeMoveDialog> createState() => _ChequeMoveDialogState();
}

class _ChequeMoveDialogState extends State<_ChequeMoveDialog> {
  late final TextEditingController _number;
  final _desc = TextEditingController();
  final _copies = TextEditingController(text: '1');
  late DateTime _date;
  String? _from;
  String? _to;
  List<String> _ids = [];
  int? _sel;
  String? _err;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    final s = StoreScope.read(context);
    final now = DateTime.now();
    _number = TextEditingController(text: '${e?.number ?? s.nextVoucherNumber()}');
    _date = e?.date ?? DateTime(now.year, now.month, now.day);
    if (e != null) {
      _from = e.meta['from'] as String?;
      _to = e.meta['to'] as String?;
      _ids = [for (final x in (e.meta['cheques'] as List? ?? const [])) '$x'];
      _desc.text = e.desc;
    }
  }

  @override
  void dispose() {
    for (final c in [_number, _desc, _copies]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Cheque> _rows(AppStore s) => [for (final id in _ids) if (s.cheque(id) != null) s.cheque(id)!];

  Future<void> _details() async {
    final s = StoreScope.read(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'مشخصات سند',
        width: 480,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InputDecorator(
            decoration: const InputDecoration(labelText: 'شماره ثابت'),
            child: Text('${widget.edit?.fixedNumber ?? s.nextFixedNumber()}'),
          ),
          const SizedBox(height: 14),
          TextField(controller: _desc, autofocus: true, maxLines: 3, decoration: const InputDecoration(labelText: 'شرح سند')),
        ]),
      ),
    );
  }

  Future<void> _add() async {
    final s = StoreScope.read(context);
    if (_from == null) {
      setState(() => _err = 'صندوق پرداخت کننده چک را انتخاب کنید');
      return;
    }
    final avail = s.chequesInBox(_from!).where((c) => !_ids.contains(c.id)).toList();
    if (avail.isEmpty) {
      toast(context, 'چک دریافتی در جریانی در این صندوق نیست', error: true);
      return;
    }
    final picked = await showDialog<List<String>>(context: context, builder: (_) => _PickChequesDialog(cheques: avail));
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        _ids = [..._ids, ...picked];
        _err = null;
      });
    }
  }

  void _remove() {
    if (_sel == null || _sel! >= _ids.length) return;
    setState(() {
      _ids.removeAt(_sel!);
      _sel = null;
    });
  }

  bool _save({bool print = false}) {
    final s = StoreScope.read(context);
    String? err;
    if (_from == null || _to == null) {
      err = 'صندوق پرداخت کننده و دریافت کننده را انتخاب کنید';
    } else if (_from == _to) {
      err = 'صندوق مبدا و مقصد نباید یکی باشد';
    } else if (_ids.isEmpty) {
      err = 'حداقل یک چک اضافه کنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return false;
    }
    final rows = _rows(s);
    final v = s.moveCheques(
      edit: widget.edit,
      fromId: _from!,
      toId: _to!,
      chequeIds: _ids,
      date: _date,
      number: int.tryParse(normalizeDigits(_number.text.trim())),
      desc: _desc.text.trim(),
    );
    if (print) {
      final copies = (int.tryParse(normalizeDigits(_copies.text.trim())) ?? 1).clamp(1, 5);
      for (var k = 0; k < copies; k++) {
        printTable(
          store: s,
          title: 'سند جا به جایی چک شماره ${v.number}',
          subtitle: '${jFormat(v.date)} — از ${s.account(_from)?.name ?? ''} به ${s.account(_to)?.name ?? ''}',
          headers: const ['ردیف', 'شماره چک', 'نام بانک', 'تاریخ سررسید', 'مبلغ', 'ملاحظات'],
          rows: [
            for (var i = 0; i < rows.length; i++)
              ['${i + 1}', rows[i].serial, rows[i].bank, jFormat(rows[i].dueDate), groupDigits(rows[i].amount), s.person(rows[i].personId)?.name ?? ''],
          ],
          numeric: const {4},
          footer: ['', '', '', 'جمع', groupDigits(rows.fold<int>(0, (a, c) => a + c.amount)), ''],
          fileName: 'cheque_move_${v.number}${copies > 1 ? '_${k + 1}' : ''}',
        );
      }
    }
    Navigator.pop(context);
    toast(context, 'سند جا به جایی چک شماره ${v.number} ثبت شد');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final boxes = s.activeAccounts.where((a) => a.type == AccountType.cash).toList();
    final rows = _rows(s);
    final total = rows.fold<int>(0, (a, c) => a + c.amount);

    Widget boxPicker(String label, String? value, ValueChanged<String?> onChanged, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(label, style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 8),
              FieldDropdown<String?>(
                label: 'عنوان حساب',
                value: value,
                items: [
                  for (final a in boxes)
                    DropdownMenuItem<String?>(
                      value: a.id,
                      child: Row(children: [
                        Expanded(child: Text(a.name)),
                        Text('${s.chequesInBox(a.id).length} چک', style: th.textTheme.labelSmall),
                      ]),
                    ),
                ],
                onChanged: onChanged,
              ),
            ]),
          ),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): _details,
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f12): () => showComingSoon(context, 'تعیین نوع چاپ'),
        const SingleActivator(LogicalKeyboardKey.insert): _add,
        const SingleActivator(LogicalKeyboardKey.delete): _remove,
      },
      child: Focus(
        autofocus: true,
        child: _Window(
          title: 'جا به جایی چک',
          icon: Icons.swap_horiz_rounded,
          width: 980,
          footer: Row(children: [
            OutlinedButton.icon(
              onPressed: () => showComingSoon(context, 'تعیین نوع چاپ'),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('تعیین نوع چاپ (F12)'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _copies,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'تعداد نسخه', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _save(print: true), child: const Text('تایید و چاپ')),
            if (_err != null) ...[
              const SizedBox(width: 12),
              Expanded(child: Text(_err!, style: TextStyle(color: th.colorScheme.error), overflow: TextOverflow.ellipsis)),
            ] else
              const Spacer(),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
          ]),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: _details,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('مشخصات سند (F1)'),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند')),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  boxPicker('صندوق دریافت کننده چک', _to, (v) => setState(() => _to = v), AppColors.income),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_back_rounded, size: 28)),
                  boxPicker('صندوق پرداخت کننده چک', _from, (v) {
                    setState(() {
                      if (v != _from && widget.edit == null) _ids = [];
                      _from = v;
                    });
                  }, AppColors.expense),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('افزودن چک (Insert)')),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _sel == null ? null : _remove,
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                    label: const Text('حذف چک (Delete)'),
                  ),
                  const Spacer(),
                  Text('جمع مبلغ: ', style: th.textTheme.titleSmall),
                  Money(total, style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _gridHeader(context, const [
                        SizedBox(width: 50, child: Text('ردیف')),
                        SizedBox(width: 140, child: Text('شماره چک')),
                        SizedBox(width: 150, child: Text('نام بانک')),
                        SizedBox(width: 120, child: Text('تاریخ سررسید')),
                        SizedBox(width: 150, child: Text('مبلغ', textAlign: TextAlign.left)),
                        SizedBox(width: 16),
                        Expanded(child: Text('ملاحظات')),
                      ]),
                      Expanded(
                        child: rows.isEmpty
                            ? const EmptyState(icon: Icons.swap_horiz_rounded, text: 'چکی برای جا به جایی اضافه نشده (Insert)')
                            : ListView.builder(
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final c = rows[i];
                                  return Material(
                                    color: _sel == i ? th.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
                                    child: InkWell(
                                      onTap: () => setState(() => _sel = i),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        child: Row(children: [
                                          SizedBox(width: 50, child: Text('${i + 1}')),
                                          SizedBox(width: 140, child: Text(c.serial, style: const TextStyle(fontWeight: FontWeight.w700))),
                                          SizedBox(width: 150, child: Text(c.bank, overflow: TextOverflow.ellipsis)),
                                          SizedBox(width: 120, child: Text(jFormat(c.dueDate))),
                                          SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Money(c.amount))),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              [s.person(c.personId)?.name ?? '', c.note].where((x) => x.isNotEmpty).join(' — '),
                                              overflow: TextOverflow.ellipsis,
                                            ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickChequesDialog extends StatefulWidget {
  final List<Cheque> cheques;
  const _PickChequesDialog({required this.cheques});

  @override
  State<_PickChequesDialog> createState() => _PickChequesDialogState();
}

class _PickChequesDialogState extends State<_PickChequesDialog> {
  final Set<String> _sel = {};

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final all = _sel.length == widget.cheques.length;
    return FormDialog(
      title: 'انتخاب چک',
      width: 640,
      leading: TextButton(
        onPressed: () => setState(() => all ? _sel.clear() : _sel.addAll(widget.cheques.map((c) => c.id))),
        child: Text(all ? 'لغو انتخاب همه' : 'انتخاب همه'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel.toList()), child: Text('افزودن (${_sel.length})')),
      ],
      child: Column(
        children: [
          for (final c in widget.cheques)
            CheckboxListTile(
              dense: true,
              value: _sel.contains(c.id),
              onChanged: (v) => setState(() => v == true ? _sel.add(c.id) : _sel.remove(c.id)),
              title: Row(children: [
                Expanded(child: Text('${c.serial.isEmpty ? 'بدون شماره' : c.serial} — ${c.bank}')),
                Money(c.amount, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              subtitle: Text('سررسید ${jFormat(c.dueDate)} — ${s.person(c.personId)?.name ?? ''}',
                  style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
            ),
        ],
      ),
    );
  }
}
