import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty, pickPersonId;

// ================================================================ سند امانی

/// «دریافت امانی» / «پرداخت امانی» — Sakan's consignment document.
Future<void> showConsignEditor(BuildContext context, ConsignDir dir, {Consignment? edit, bool loan = false}) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _ConsignEditor(dir: edit?.dir ?? dir, edit: edit, loan: edit?.loan ?? loan));

class _Row {
  final String id;
  String? productId;
  String? warehouseId;
  int unit = 1;
  final qty = TextEditingController(text: '1');
  final fi = TextEditingController();
  _Row(this.id);

  double get q => parseQty(qty.text);
  int get f => parseMoney(fi.text);

  void dispose() {
    qty.dispose();
    fi.dispose();
  }
}

class _ConsignEditor extends StatefulWidget {
  final ConsignDir dir;
  final Consignment? edit;
  final bool loan;
  const _ConsignEditor({required this.dir, this.edit, this.loan = false});

  String get title => loan ? (dir == ConsignDir.received ? 'ورود قرضی' : 'خروج قرضی') : dir.label;

  @override
  State<_ConsignEditor> createState() => _ConsignEditorState();
}

class _ConsignEditorState extends State<_ConsignEditor> {
  late DateTime _date;
  DateTime? _follow;
  String? _person;
  final _number = TextEditingController();
  final _followNote = TextEditingController();
  final _note = TextEditingController();
  final List<_Row> _rows = [];
  String? _err;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    final e = widget.edit;
    _date = e?.date ?? DateTime.now();
    _follow = e?.followDate;
    _person = e?.personId;
    _number.text = '${e?.number ?? s.nextConsignNumber(widget.dir, loan: widget.loan)}';
    _followNote.text = e?.followNote ?? '';
    _note.text = e?.note ?? '';
    for (final l in e?.lines ?? const <ConsignLine>[]) {
      final r = _Row(l.id)
        ..productId = l.productId
        ..warehouseId = l.warehouseId
        ..unit = l.unitNo;
      final other = l.unitNo != 1 && l.unitQty != 0;
      r.qty.text = fmtQty(other ? l.unitQty : l.qty);
      r.fi.text = groupDigits(other ? l.unitFi : l.fi);
      _rows.add(r);
    }
  }

  @override
  void dispose() {
    for (final c in [_number, _followNote, _note]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _addProduct() async {
    final id = await pickProductId(context);
    if (id == null || !mounted) return;
    final p = StoreScope.read(context).product(id)!;
    setState(() {
      final r = _Row(newId())
        ..productId = id
        ..unit = p.hasUnit(p.defaultUnit) ? p.defaultUnit : 1
        ..warehouseId = widget.loan ? StoreScope.read(context).allowedWarehouse(null) : null;
      // «امانی قرضی» is valued at cost (the stock's average price)
      final avg = StoreScope.read(context).avgCost(p.id);
      final base = widget.loan ? (avg > 0 ? avg : p.buyPrice) : (widget.dir == ConsignDir.received ? p.buyPrice : p.sellPrice);
      r.fi.text = groupDigits((base * p.unitFactor(r.unit)).round());
      _rows.add(r);
    });
  }

  void _save() {
    final s = StoreScope.read(context);
    final number = int.tryParse(normalizeDigits(_number.text.trim())) ?? 0;
    if (number <= 0) return setState(() => _err = 'شماره سند را وارد کنید');
    if (s.consignments.any((c) => c.id != widget.edit?.id && c.dir == widget.dir && c.loan == widget.loan && c.number == number)) {
      return setState(() => _err = 'شماره $number قبلاً ثبت شده است');
    }
    final lines = <ConsignLine>[];
    for (final r in _rows) {
      final p = s.product(r.productId);
      if (p == null) continue;
      final f = p.unitFactor(r.unit);
      final other = r.unit != 1 && f != 1;
      lines.add(ConsignLine(
        id: r.id,
        productId: p.id,
        warehouseId: r.warehouseId,
        qty: r.q * f,
        fi: other ? (r.f / f).round() : r.f,
        unitNo: other ? r.unit : 1,
        unitQty: other ? r.q : 0,
        unitFi: other ? r.f : 0,
      ));
    }
    final c = Consignment(
      loan: widget.loan,
      id: widget.edit?.id ?? newId(),
      dir: widget.dir,
      number: number,
      date: _date,
      personId: _person,
      followDate: _follow,
      followNote: _followNote.text.trim(),
      note: _note.text.trim(),
      lines: lines,
      createdAt: widget.edit?.createdAt,
    );
    final e = s.saveConsignment(c);
    if (e != null) return setState(() => _err = e);
    Navigator.pop(context);
    toast(context, '${widget.title} شماره $number ذخیره شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final total = _rows.fold<int>(0, (a, r) => a + (r.q * r.f).round());
    const wIdx = 44.0, wWh = 140.0, wUnit = 90.0, wQty = 90.0, wFi = 130.0, wTot = 140.0, wRem = 90.0, wDel = 40.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.insert): _addProduct,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: SakanWindow(
          title: widget.loan ? 'امانی قرضی — ${widget.title}' : widget.dir.label,
          width: 1100,
          height: 700,
          body: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(width: 120, child: TextField(controller: _number, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: 'شماره', isDense: true))),
                SizedBox(width: 200, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
                SizedBox(
                  width: 260,
                  child: sakanBtn(
                    '${widget.dir.personLabel}: ${s.person(_person)?.name ?? 'انتخاب کنید'}',
                    () async {
                      final id = await pickPersonId(context, title: 'انتخاب ${widget.dir.personLabel}');
                      if (id != null) setState(() => _person = id);
                    },
                    key: 'F2',
                  ),
                ),
                SizedBox(width: 200, child: DateField(label: 'تاریخ پیگرد', value: _follow, clearable: true, onChanged: (d) => setState(() => _follow = d))),
                SizedBox(width: 280, child: TextField(controller: _followNote, decoration: const InputDecoration(labelText: 'شرح پیگرد', isDense: true))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'شرح سند', isDense: true)),
              const SizedBox(height: 8),
              Row(children: [
                sakanBtn('افزودن کالا', _addProduct, key: 'Ins', icon: Icons.add_rounded),
                const Spacer(),
                Text('جمع کل: ', style: th.textTheme.titleSmall),
                Money(total, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Expanded(
                child: SakanGrid(
                  header: [
                    sakanHead('ردیف', wIdx),
                    sakanHead('نام کالا', 0),
                    sakanHead('انبار', wWh),
                    sakanHead('واحد', wUnit),
                    sakanHead('تعداد', wQty),
                    sakanHead('فی', wFi),
                    sakanHead('جمع', wTot),
                    sakanHead('مانده', wRem),
                    sakanHead('', wDel),
                  ],
                  count: _rows.length,
                  empty: 'کالایی اضافه نشده (Insert)',
                  row: (ctx, i) {
                    final r = _rows[i];
                    final p = s.product(r.productId);
                    final old = widget.edit == null ? null : widget.edit!.lines.where((x) => x.id == r.id).firstOrNull;
                    final rem = old == null ? null : s.consignRemaining(widget.edit!, old);
                    final dense = const InputDecoration(isDense: true, border: InputBorder.none);
                    return Container(
                      color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                      child: Row(children: [
                        sakanCell(Text('${i + 1}'), wIdx),
                        sakanCell(Text(p?.name ?? '', overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                        sakanCell(
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: s.whId(r.warehouseId),
                              isExpanded: true,
                              isDense: true,
                              items: [for (final w in s.warehousesFor(r.warehouseId)) DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))],
                              onChanged: (v) => setState(() => r.warehouseId = v),
                            ),
                          ),
                          wWh,
                        ),
                        sakanCell(
                          p != null && (p.hasUnit(2) || p.hasUnit(3))
                              ? DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: r.unit,
                                    isExpanded: true,
                                    isDense: true,
                                    items: [for (final n in [1, 2, 3]) if (p.hasUnit(n)) DropdownMenuItem(value: n, child: Text(p.unitName(n)))],
                                    onChanged: (n) => setState(() {
                                      final from = p.unitFactor(r.unit), to = p.unitFactor(n ?? 1);
                                      r.qty.text = fmtQty(r.q * from / to);
                                      if (r.f != 0) r.fi.text = groupDigits((r.f / from * to).round());
                                      r.unit = n ?? 1;
                                    }),
                                  ),
                                )
                              : Text(p?.unit ?? ''),
                          wUnit,
                        ),
                        sakanCell(
                          TextField(
                            controller: r.qty,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            decoration: dense,
                            onChanged: (_) => setState(() {}),
                          ),
                          wQty,
                        ),
                        sakanCell(
                          TextField(
                            controller: r.fi,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            inputFormatters: [MoneyInputFormatter()],
                            decoration: dense,
                            onChanged: (_) => setState(() {}),
                          ),
                          wFi,
                        ),
                        sakanCell(Text(groupDigits((r.q * r.f).round()), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)), wTot),
                        sakanCell(Text(rem == null ? '' : fmtQty(rem / (p?.unitFactor(r.unit) ?? 1))), wRem),
                        sakanCell(
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            tooltip: 'حذف ردیف',
                            onPressed: () => setState(() {
                              _rows.removeAt(i).dispose();
                            }),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935)),
                          ),
                          wDel,
                        ),
                      ]),
                    );
                  },
                ),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: TextStyle(color: th.colorScheme.error))),
              const SizedBox(height: 8),
              Row(children: [
                Text('کالای ${widget.dir == ConsignDir.received ? 'دریافت شده' : 'تحویل داده شده'} جزو موجودی مالی ${widget.dir == ConsignDir.received ? 'نمی‌شود' : 'باقی می‌ماند'}؛ '
                    'تسویه با «تسویه امانی» در فاکتور ${widget.dir.invoiceKind == InvoiceKind.purchase ? 'خرید' : 'فروش'} یا «تسویه انبار» انجام می‌شود.',
                    style: th.textTheme.bodySmall),
                const Spacer(),
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('تایید F9')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Simple product search («انتخاب کالا»).
Future<String?> pickProductId(BuildContext context) => showDialog<String>(context: context, builder: (_) => const _ProductPick());

class _ProductPick extends StatefulWidget {
  const _ProductPick();

  @override
  State<_ProductPick> createState() => _ProductPickState();
}

class _ProductPickState extends State<_ProductPick> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final list = s.productsSorted.where((p) => !p.archived && (q.isEmpty || '${p.code} ${p.name} ${p.info['barcode'] ?? ''}'.toLowerCase().contains(q))).toList();
    return FormDialog(
      title: 'انتخاب کالا',
      width: 560,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'جستجوی نام، کد یا بارکد', prefixIcon: Icon(Icons.search_rounded)),
          onChanged: (v) => setState(() => _q = v),
          onSubmitted: (_) {
            if (list.length == 1) Navigator.pop(context, list.first.id);
          },
        ),
        const SizedBox(height: 8),
        for (final p in list.take(60))
          ListTile(
            dense: true,
            title: Text(p.name),
            subtitle: Text(p.code),
            trailing: Text('${fmtQty(s.stock(p.id))} ${p.unit}'),
            onTap: () => Navigator.pop(context, p.id),
          ),
      ]),
    );
  }
}

// ================================================================ لیست امانی‌ها

/// «امانی دریافتنی / پرداختنی» and «مانده امانی»: every consignment row with
/// its returned, invoiced and remaining quantity. With [personId] it is
/// «صورت امانی های طرف حساب».
Future<void> showConsignList(BuildContext context, {ConsignDir? dir, String? personId, bool openOnly = false, bool loan = false}) =>
    showDialog<void>(context: context, builder: (_) => _ConsignList(dir: dir, personId: personId, openOnly: openOnly, loan: loan));

class _ConsignList extends StatefulWidget {
  final ConsignDir? dir;
  final String? personId;
  final bool openOnly;
  final bool loan;
  const _ConsignList({this.dir, this.personId, this.openOnly = false, this.loan = false});

  @override
  State<_ConsignList> createState() => _ConsignListState();
}

typedef _CRow = (Consignment, ConsignLine, double returned, double invoiced, double remaining);

class _ConsignListState extends State<_ConsignList> {
  late ConsignDir? _dir = widget.dir;
  late bool _open = widget.openOnly;
  String _q = '';
  String? _sel; // line id

  List<_CRow> _rows(AppStore s) {
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final out = <_CRow>[];
    final list = s.consignments.where((c) => c.loan == widget.loan && (_dir == null || c.dir == _dir) && (widget.personId == null || c.personId == widget.personId)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final c in list) {
      for (final l in c.lines) {
        final ret = c.returnedQty(l.id);
        final inv = s.consignInvoiced(l.id);
        final rem = l.qty - ret - inv;
        if (_open && rem <= 1e-9) continue;
        final text = '${c.number} ${s.person(c.personId)?.name ?? ''} ${s.product(l.productId)?.name ?? ''} ${c.followNote} ${c.note}'.toLowerCase();
        if (q.isNotEmpty && !text.contains(q)) continue;
        out.add((c, l, ret, inv, rem));
      }
    }
    return out;
  }

  Future<void> _return(AppStore s, _CRow r) async {
    final p = s.product(r.$2.productId);
    final qty = TextEditingController(text: fmtQty(r.$5));
    final note = TextEditingController();
    var date = DateTime.now();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: '${r.$1.loan ? 'عودت' : 'تسویه انبار'} — ${r.$1.title} ${r.$1.number}',
          width: 460,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                final e = s.addConsignReturn(r.$2.id, parseQty(qty.text), date, note: note.text.trim());
                if (e != null) {
                  set(() => err = e);
                } else {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('ثبت برگشت'),
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p?.name ?? ''} — مانده ${fmtQty(r.$5)} ${p?.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(r.$1.dir == ConsignDir.received ? 'کالای امانی به ${s.person(r.$1.personId)?.name ?? 'تحویل دهنده'} پس داده می‌شود.' : 'کالای امانی از ${s.person(r.$1.personId)?.name ?? 'تحویل گیرنده'} پس گرفته می‌شود.'),
            const SizedBox(height: 10),
            TextField(controller: qty, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: 'تعداد (${p?.unit ?? ''})')),
            const SizedBox(height: 10),
            DateField(label: 'تاریخ', value: date, onChanged: (d) => set(() => date = d ?? date)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
        ),
      ),
    );
    qty.dispose();
    note.dispose();
  }

  Future<void> _delete(AppStore s, Consignment c) async {
    if (!await confirm(context, 'حذف سند امانی', '${c.title} شماره ${c.number} حذف شود؟')) return;
    final e = s.removeConsignment(c.id);
    if (e != null && mounted) toast(context, e, error: true);
  }

  void _print(AppStore s, List<_CRow> rows) {
    final title = widget.personId != null
        ? 'صورت امانی های ${s.person(widget.personId)?.name ?? ''}'
        : (_open ? 'مانده ${_dir?.listLabel ?? 'امانی'}' : (_dir?.listLabel ?? 'امانی ها'));
    printTable(
      store: s,
      title: title,
      headers: const ['نوع', 'شماره', 'تاریخ', 'طرف حساب', 'کالا', 'انبار', 'تعداد', 'برگشتی', 'فاکتور شده', 'مانده', 'فی', 'جمع', 'تاریخ پیگرد'],
      rows: [
        for (final r in rows)
          [
            r.$1.title,
            '${r.$1.number}',
            jFormat(r.$1.date),
            s.person(r.$1.personId)?.name ?? '',
            s.product(r.$2.productId)?.name ?? '',
            s.warehouse(r.$2.warehouseId)?.name ?? '',
            fmtQty(r.$2.qty),
            fmtQty(r.$3),
            fmtQty(r.$4),
            fmtQty(r.$5),
            groupDigits(r.$2.fi),
            groupDigits(r.$2.total),
            r.$1.followDate == null ? '' : jFormat(r.$1.followDate!),
          ],
      ],
      numeric: const {6, 7, 8, 9, 10, 11},
      fileName: 'amani',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final rows = _rows(s);
    final sel = rows.where((r) => r.$2.id == _sel).firstOrNull;
    final title = widget.loan
        ? 'لیست امانی قرضی'
        : (widget.personId != null ? 'صورت امانی های طرف حساب — ${s.person(widget.personId)?.name ?? ''}' : 'امانی ها');
    const w = [90.0, 60.0, 100.0, 150.0, 0.0, 70.0, 70.0, 80.0, 70.0, 110.0, 100.0];
    final remValue = rows.fold<int>(0, (a, r) => a + (r.$2.qty == 0 ? 0 : (r.$2.total * r.$5 / r.$2.qty).round()));
    return SakanWindow(
      title: title,
      width: 1200,
      height: 720,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn(widget.loan ? 'ورود قرضی' : 'دریافت امانی', () => showConsignEditor(context, ConsignDir.received, loan: widget.loan), icon: Icons.move_to_inbox_outlined),
            sakanBtn(widget.loan ? 'خروج قرضی' : 'پرداخت امانی', () => showConsignEditor(context, ConsignDir.given, loan: widget.loan), icon: Icons.outbox_outlined),
            sakanBtn('ویرایش', sel == null ? null : () => showConsignEditor(context, sel.$1.dir, edit: sel.$1, loan: sel.$1.loan), icon: Icons.edit_outlined),
            sakanBtn('حذف سند', sel == null ? null : () => _delete(s, sel.$1), icon: Icons.delete_outline_rounded),
            sakanBtn(widget.loan ? 'عودت کالا' : 'تسویه انبار', sel == null || sel.$5 <= 1e-9 ? null : () => _return(s, sel), icon: Icons.assignment_return_outlined),
            sakanBtn('چاپ', () => _print(s, rows), icon: Icons.print_outlined),
            const SizedBox(width: 12),
            SegmentedButton<ConsignDir?>(
              segments: const [
                ButtonSegment(value: null, label: Text('همه')),
                ButtonSegment(value: ConsignDir.received, label: Text('دریافتنی')),
                ButtonSegment(value: ConsignDir.given, label: Text('پرداختنی')),
              ],
              selected: {_dir},
              onSelectionChanged: (v) => setState(() => _dir = v.first),
            ),
            FilterChip(label: const Text('فقط مانده دار'), selected: _open, onSelected: (v) => setState(() => _open = v)),
            SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(hintText: 'جستجو', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('نوع', w[0]),
                sakanHead('شماره', w[1]),
                sakanHead('تاریخ', w[2]),
                sakanHead('طرف حساب', w[3]),
                sakanHead('کالا', w[4]),
                sakanHead('تعداد', w[5]),
                sakanHead('برگشتی', w[6]),
                sakanHead('فاکتور شده', w[7]),
                sakanHead('مانده', w[8], color: sakanGreen),
                sakanHead('جمع', w[9]),
                sakanHead('تاریخ پیگرد', w[10]),
              ],
              count: rows.length,
              empty: 'سند امانی وجود ندارد',
              row: (ctx, i) {
                final r = rows[i];
                final on = r.$2.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                final due = r.$1.followDate != null && r.$5 > 1e-9 && !r.$1.followDate!.isAfter(DateTime.now());
                return InkWell(
                  onTap: () => setState(() => _sel = r.$2.id),
                  onDoubleTap: () => showConsignEditor(context, r.$1.dir, edit: r.$1, loan: r.$1.loan),
                  child: Container(
                    color: on ? sakanSel : (due ? sakanPink : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text(r.$1.title, style: st), w[0]),
                      sakanCell(Text('${r.$1.number}', style: st), w[1]),
                      sakanCell(Text(jFormat(r.$1.date), style: st), w[2]),
                      sakanCell(Text(s.person(r.$1.personId)?.name ?? '', style: st, overflow: TextOverflow.ellipsis), w[3]),
                      sakanCell(Text(s.product(r.$2.productId)?.name ?? '', style: st, overflow: TextOverflow.ellipsis), w[4], align: Alignment.centerRight),
                      sakanCell(Text(fmtQty(r.$2.qty), style: st), w[5]),
                      sakanCell(Text(fmtQty(r.$3), style: st), w[6]),
                      sakanCell(Text(fmtQty(r.$4), style: st), w[7]),
                      sakanCell(Text(fmtQty(r.$5), style: st.copyWith(fontWeight: FontWeight.w800)), w[8]),
                      sakanCell(Text(groupDigits(r.$2.total), style: st, textDirection: TextDirection.ltr), w[9]),
                      sakanCell(Text(r.$1.followDate == null ? '' : jFormat(r.$1.followDate!), style: st), w[10]),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${rows.length} ردیف', style: th.textTheme.bodySmall),
            const SizedBox(width: 12),
            Text('ردیف‌های صورتی: تاریخ پیگرد رسیده', style: th.textTheme.bodySmall),
            const Spacer(),
            const Text('ارزش مانده امانی: '),
            Money(remValue, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}

// ================================================================ تسویه امانی در فاکتور

/// A consignment row picked for «تسویه امانی» and the quantity (unit 1) to settle.
class ConsignPick {
  final Consignment doc;
  final ConsignLine line;
  final double qty;
  const ConsignPick(this.doc, this.line, this.qty);
}

/// «تسویه امانی» from the invoice editor: open rows of [dir] for [personId]
/// (all people when null), with the quantity to bring into the invoice.
Future<List<ConsignPick>?> pickConsignRows(BuildContext context, ConsignDir dir, {String? personId, String? excludeInvoiceId, Set<String> taken = const {}}) =>
    showDialog<List<ConsignPick>>(
      context: context,
      builder: (_) => _ConsignPicker(dir: dir, personId: personId, excludeInvoiceId: excludeInvoiceId, taken: taken),
    );

class _ConsignPicker extends StatefulWidget {
  final ConsignDir dir;
  final String? personId;
  final String? excludeInvoiceId;
  final Set<String> taken;
  const _ConsignPicker({required this.dir, this.personId, this.excludeInvoiceId, this.taken = const {}});

  @override
  State<_ConsignPicker> createState() => _ConsignPickerState();
}

class _ConsignPickerState extends State<_ConsignPicker> {
  final Map<String, TextEditingController> _qty = {};

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final open = <(Consignment, ConsignLine, double)>[];
    for (final c in s.consignments.where((c) => !c.loan && c.dir == widget.dir && (widget.personId == null || c.personId == widget.personId))) {
      for (final l in c.lines) {
        if (widget.taken.contains(l.id)) continue;
        final rem = s.consignRemaining(c, l, excludeInvoiceId: widget.excludeInvoiceId);
        if (rem > 1e-9) open.add((c, l, rem));
      }
    }
    return FormDialog(
      title: 'تسویه امانی — ${widget.dir.listLabel}${widget.personId == null ? '' : ' ${s.person(widget.personId)?.name ?? ''}'}',
      width: 820,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: () {
            final out = <ConsignPick>[];
            for (final (c, l, rem) in open) {
              final q = parseQty(_qty[l.id]?.text ?? '');
              if (q > 0) out.add(ConsignPick(c, l, q > rem ? rem : q));
            }
            Navigator.pop(context, out);
          },
          child: const Text('افزودن به فاکتور'),
        ),
      ],
      child: open.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('امانی تسویه نشده‌ای وجود ندارد')))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('تعداد هر ردیف را که در این فاکتور تسویه می‌شود وارد کنید (به واحد اول کالا).', style: th.textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final (c, l, rem) in open)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 120, child: Text('${c.title} ${c.number}')),
                    SizedBox(width: 90, child: Text(jFormat(c.date))),
                    SizedBox(width: 130, child: Text(s.person(c.personId)?.name ?? '', overflow: TextOverflow.ellipsis)),
                    Expanded(child: Text(s.product(l.productId)?.name ?? '', overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 110, child: Text('مانده ${fmtQty(rem)}')),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _qty.putIfAbsent(l.id, () => TextEditingController()),
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(isDense: true, hintText: fmtQty(rem)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'همه مانده',
                      onPressed: () => setState(() => _qty[l.id]!.text = fmtQty(rem)),
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                    ),
                  ]),
                ),
            ]),
    );
  }
}
