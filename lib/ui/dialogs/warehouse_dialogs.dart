import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

/// Big window frame shared by the warehouse tools.
class _Win extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget body;
  final Widget footer;
  final double width;
  final double maxHeight;
  const _Win({required this.title, required this.icon, required this.body, required this.footer, this.width = 900, this.maxHeight = 680});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: (size.height * 0.88).clamp(380.0, maxHeight),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HeaderBand(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
            child: Row(children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(child: body),
          const Divider(),
          Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 12), child: footer),
        ]),
      ),
    );
  }
}

Widget _head(BuildContext context, List<Widget> cells) {
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

// ================================================================ لیست انبارها

/// «لیست انبار های سیستم». With [pick] the chosen warehouse id is returned.
Future<String?> showWarehousesWindow(BuildContext context, {bool pick = false, String? selected}) =>
    showDialog<String>(context: context, builder: (_) => _WarehousesWindow(pick: pick, selected: selected));

class _WarehousesWindow extends StatefulWidget {
  final bool pick;
  final String? selected;
  const _WarehousesWindow({this.pick = false, this.selected});

  @override
  State<_WarehousesWindow> createState() => _WarehousesWindowState();
}

class _WarehousesWindowState extends State<_WarehousesWindow> {
  late String? _sel = widget.selected;

  Future<void> _edit({Warehouse? w}) async {
    final r = await showDialog<Warehouse>(context: context, builder: (_) => _WarehouseForm(edit: w));
    if (r != null) setState(() => _sel = r.id);
  }

  Future<void> _delete() async {
    final s = StoreScope.read(context);
    final w = s.warehouses.where((x) => x.id == _sel).firstOrNull;
    if (w == null) return toast(context, 'انبار را انتخاب کنید', error: true);
    final ok = await confirm(context, 'حذف انبار', 'انبار «${w.name}» حذف شود؟');
    if (!ok || !mounted) return;
    if (s.removeWarehouse(w.id)) {
      setState(() => _sel = null);
    } else {
      toast(context, w.id == s.mainWarehouseId ? 'انبار اصلی قابل حذف نیست' : 'این انبار در اسناد استفاده شده و قابل حذف نیست', error: true);
    }
  }

  void _ok() {
    if (widget.pick && _sel == null) return toast(context, 'انبار را انتخاب کنید', error: true);
    Navigator.pop(context, _sel);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: _Win(
          title: 'لیست انبار های سیستم',
          icon: Icons.warehouse_outlined,
          width: 820,
          maxHeight: 600,
          footer: Row(children: [
            FilledButton.tonalIcon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('معرفی انبار')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: th.colorScheme.error),
              label: const Text('حذف انبار'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                final w = s.warehouses.where((x) => x.id == _sel).firstOrNull;
                if (w == null) return toast(context, 'انبار را انتخاب کنید', error: true);
                _edit(w: w);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('ویرایش انبار'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                final w = s.warehouses.where((x) => x.id == _sel).firstOrNull;
                if (w == null) return toast(context, 'انبار را انتخاب کنید', error: true);
                showDialog<void>(context: context, builder: (_) => _WarehouseStock(w: w));
              },
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('موجودی انبار'),
            ),
            const Spacer(),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت (F10)')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _ok, child: const Text('تایید (F9)')),
          ]),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _head(context, const [
                  Expanded(flex: 3, child: Text('نام انبار')),
                  SizedBox(width: 70, child: Text('شناسه')),
                  Expanded(flex: 2, child: Text('انباردار')),
                  Expanded(flex: 3, child: Text('مشخصات')),
                  Expanded(flex: 3, child: Text('ملاحظات')),
                ]),
                Expanded(
                  child: ListView(children: [
                    for (final w in [...s.warehouses]..sort((a, b) => a.code.compareTo(b.code)))
                      Material(
                        color: w.id == _sel ? th.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _sel = w.id),
                          onDoubleTap: () {
                            setState(() => _sel = w.id);
                            if (widget.pick) {
                              _ok();
                            } else {
                              _edit(w: w);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            child: Row(children: [
                              Expanded(
                                flex: 3,
                                child: Row(children: [
                                  Icon(Icons.warehouse_rounded, size: 18, color: th.colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  if (w.id == s.mainWarehouseId) ...[
                                    const SizedBox(width: 6),
                                    Pill('اصلی', color: AppColors.income),
                                  ],
                                ]),
                              ),
                              SizedBox(width: 70, child: Text('${w.code}')),
                              Expanded(flex: 2, child: Text(w.keeper)),
                              Expanded(flex: 3, child: Text(w.specs, overflow: TextOverflow.ellipsis)),
                              Expanded(flex: 3, child: Text(w.note, overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarehouseForm extends StatefulWidget {
  final Warehouse? edit;
  const _WarehouseForm({this.edit});

  @override
  State<_WarehouseForm> createState() => _WarehouseFormState();
}

class _WarehouseFormState extends State<_WarehouseForm> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _keeper = TextEditingController(text: widget.edit?.keeper ?? '');
  late final _specs = TextEditingController(text: widget.edit?.specs ?? '');
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _keeper, _specs, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _err = 'نام انبار را وارد کنید');
      return;
    }
    if (s.warehouses.any((w) => w.name == name && w.id != widget.edit?.id)) {
      setState(() => _err = 'انباری با این نام وجود دارد');
      return;
    }
    final w = widget.edit ?? Warehouse(id: newId(), code: s.nextWarehouseCode(), name: name);
    w
      ..name = name
      ..keeper = _keeper.text.trim()
      ..specs = _specs.text.trim()
      ..note = _note.text.trim();
    s.saveWarehouse(w);
    Navigator.pop(context, w);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'اطلاعات انبار',
        width: 480,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'نام انبار')),
          const SizedBox(height: 12),
          TextField(controller: _keeper, decoration: const InputDecoration(labelText: 'نام انباردار')),
          const SizedBox(height: 12),
          TextField(controller: _specs, decoration: const InputDecoration(labelText: 'مشخصات انبار')),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظات')),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}

class _WarehouseStock extends StatelessWidget {
  final Warehouse w;
  const _WarehouseStock({required this.w});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = [
      for (final p in s.productsSorted)
        if (s.stock(p.id, warehouseId: w.id) != 0) (p, s.stock(p.id, warehouseId: w.id)),
    ];
    return FormDialog(
      title: 'موجودی ${w.name}',
      width: 620,
      actions: [
        OutlinedButton.icon(
          onPressed: () => printTable(
            store: s,
            title: 'موجودی ${w.name}',
            headers: const ['ردیف', 'کد کالا', 'نام کالا', 'موجودی', 'واحد'],
            rows: [
              for (var i = 0; i < rows.length; i++) ['${i + 1}', rows[i].$1.code, rows[i].$1.name, fmtQty(rows[i].$2), rows[i].$1.unit],
            ],
            fileName: 'warehouse_${w.code}',
          ),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('چاپ'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
      child: rows.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('کالایی در این انبار موجود نیست')))
          : Column(children: [
              for (final (p, q) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 80, child: Text(p.code)),
                    Expanded(child: Text(p.name)),
                    Text('${fmtQty(q)} ${p.unit}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: q < 0 ? Theme.of(context).colorScheme.error : null)),
                  ]),
                ),
            ]),
    );
  }
}

// ================================================================ لیست اقلام موجودی

Future<String?> showStockItemsPicker(BuildContext context, {String? warehouseId, String? excludeTransferId}) => showDialog<String>(
    context: context, builder: (_) => _ItemsPicker(warehouseId: warehouseId, excludeTransferId: excludeTransferId));

class _ItemsPicker extends StatefulWidget {
  final String? warehouseId;
  final String? excludeTransferId;
  const _ItemsPicker({this.warehouseId, this.excludeTransferId});

  @override
  State<_ItemsPicker> createState() => _ItemsPickerState();
}

class _ItemsPickerState extends State<_ItemsPicker> {
  String _q = '';
  bool _hideZero = true;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final list = [
      for (final p in s.productsSorted.where((p) => !p.archived))
        (p, s.stock(p.id, warehouseId: widget.warehouseId, excludeTransferId: widget.excludeTransferId)),
    ].where((x) => (!_hideZero || x.$2 != 0) && (q.isEmpty || '${x.$1.code} ${x.$1.name}'.toLowerCase().contains(q))).toList();
    return _Win(
      title: 'لیست اقلام موجودی',
      icon: Icons.inventory_2_outlined,
      width: 760,
      maxHeight: 620,
      footer: Row(children: [
        Text('${list.length} قلم', style: th.textTheme.bodySmall),
        const Spacer(),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'جستجو در نام یا کد کالا', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (_) {
                  if (list.length == 1) Navigator.pop(context, list.first.$1.id);
                },
              ),
            ),
            const SizedBox(width: 10),
            Checkbox(value: _hideZero, onChanged: (v) => setState(() => _hideZero = v ?? true)),
            const Text('عدم نمایش کالاهای با موجودی صفر'),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _head(context, const [
                  SizedBox(width: 90, child: Text('کد کالا')),
                  Expanded(child: Text('نام کالا')),
                  SizedBox(width: 110, child: Text('موجودی', textAlign: TextAlign.center)),
                  SizedBox(width: 70, child: Text('واحد', textAlign: TextAlign.center)),
                ]),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final (p, st) = list[i];
                      return InkWell(
                        onTap: () => Navigator.pop(context, p.id),
                        child: Container(
                          color: i.isOdd ? th.colorScheme.surfaceContainerLowest : null,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            SizedBox(width: 90, child: Text(p.code)),
                            Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            SizedBox(
                              width: 110,
                              child: Text(fmtQty(st),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w700, color: st <= 0 ? th.colorScheme.error : null)),
                            ),
                            SizedBox(width: 70, child: Text(p.unit, textAlign: TextAlign.center)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ انتقال بین انبارها

Future<void> showTransferDialog(BuildContext context, {WarehouseTransfer? edit}) =>
    showDialog<void>(context: context, builder: (_) => _TransferDialog(edit: edit));

class _Row {
  String productId;
  String? toId;
  final qty = TextEditingController(text: '1');
  final note = TextEditingController();
  _Row(this.productId, {this.toId});
}

class _TransferDialog extends StatefulWidget {
  final WarehouseTransfer? edit;
  const _TransferDialog({this.edit});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late final TextEditingController _number;
  late final TextEditingController _receipt;
  final _copies = TextEditingController(text: '1');
  late DateTime _date;
  late String _from;
  final List<_Row> _rows = [];
  int? _sel;
  String? _err;

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    final e = widget.edit;
    _number = TextEditingController(text: '${e?.number ?? s.nextTransferNumber()}');
    _receipt = TextEditingController(text: '${e?.receiptNo ?? s.nextReceiptNumber()}');
    final n = DateTime.now();
    _date = e?.date ?? DateTime(n.year, n.month, n.day);
    _from = s.whId(e?.fromId);
    if (e != null) {
      for (final l in e.lines) {
        final r = _Row(l.productId, toId: l.toId);
        r.qty.text = fmtQty(l.qty);
        r.note.text = l.note;
        r.qty.addListener(_onQty);
        _rows.add(r);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_number, _receipt, _copies]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.qty.dispose();
      r.note.dispose();
    }
    super.dispose();
  }

  void _onQty() {
    if (mounted) setState(() {});
  }

  double get _totalQty => _rows.fold(0.0, (a, r) => a + parseQty(r.qty.text));

  String? _defaultTo(AppStore s) => s.warehouses.where((w) => w.id != _from).map((w) => w.id).firstOrNull;

  Future<void> _add() async {
    final s = StoreScope.read(context);
    final id = await showStockItemsPicker(context, warehouseId: _from, excludeTransferId: widget.edit?.id);
    if (id == null || !mounted) return;
    setState(() {
      final r = _Row(id, toId: _rows.isNotEmpty ? _rows.last.toId : _defaultTo(s));
      r.qty.addListener(_onQty);
      _rows.add(r);
      _sel = _rows.length - 1;
      _err = null;
    });
  }

  void _remove() {
    if (_sel == null || _sel! >= _rows.length) return;
    setState(() {
      final r = _rows.removeAt(_sel!);
      r.qty.dispose();
      r.note.dispose();
      _sel = null;
    });
  }

  Future<void> _pickFrom() async {
    final id = await showWarehousesWindow(context, pick: true, selected: _from);
    if (id != null && mounted) {
      setState(() {
        _from = id;
        for (final r in _rows) {
          if (r.toId == id) r.toId = null;
        }
      });
    }
  }

  WarehouseTransfer? _save({bool print = false}) {
    final s = StoreScope.read(context);
    String? err;
    if (s.warehouses.length < 2) {
      err = 'برای انتقال حداقل دو انبار لازم است. از «لیست انبارها» انبار جدید معرفی کنید';
    } else if (_rows.isEmpty) {
      err = 'حداقل یک کالا اضافه کنید';
    } else if (_rows.any((r) => parseQty(r.qty.text) <= 0)) {
      err = 'تعداد هر ردیف باید بیشتر از صفر باشد';
    } else if (_rows.any((r) => r.toId == null || s.whId(r.toId) == _from)) {
      err = 'انبار وارده هر ردیف را انتخاب کنید (غیر از انبار صادره)';
    } else {
      final need = <String, double>{};
      for (final r in _rows) {
        need[r.productId] = (need[r.productId] ?? 0) + parseQty(r.qty.text);
      }
      for (final e in need.entries) {
        final have = s.stock(e.key, warehouseId: _from, excludeTransferId: widget.edit?.id);
        if (e.value > have) {
          err = 'موجودی «${s.product(e.key)?.name}» در ${s.warehouse(_from)?.name} کافی نیست (${fmtQty(have)})';
          break;
        }
      }
    }
    if (err != null) {
      setState(() => _err = err);
      return null;
    }
    final t = widget.edit ?? WarehouseTransfer(id: newId(), number: 0, date: _date, fromId: _from);
    t
      ..number = int.tryParse(normalizeDigits(_number.text.trim())) ?? s.nextTransferNumber()
      ..receiptNo = int.tryParse(normalizeDigits(_receipt.text.trim())) ?? 0
      ..date = _date
      ..fromId = _from
      ..lines = [
        for (final r in _rows) TransferLine(productId: r.productId, toId: r.toId!, qty: parseQty(r.qty.text), note: r.note.text.trim()),
      ];
    s.saveTransfer(t);
    if (print) _print(s, t);
    Navigator.pop(context);
    toast(context, 'انتقال بین انبارها شماره ${t.number} ثبت شد');
    return t;
  }

  void _print(AppStore s, WarehouseTransfer t) {
    final copies = (int.tryParse(normalizeDigits(_copies.text.trim())) ?? 1).clamp(1, 5);
    for (var k = 0; k < copies; k++) {
      printTable(
        store: s,
        title: 'انتقال بین انبارها — شماره ${t.number}',
        subtitle: '${jFormat(t.date)} — انبار صادره: ${s.warehouse(t.fromId)?.name ?? ''} — رسید انبار ${t.receiptNo}',
        headers: const ['ردیف', 'کد کالا', 'نام کالا', 'انبار وارده', 'تعداد', 'واحد', 'توضیحات'],
        rows: [
          for (var i = 0; i < t.lines.length; i++)
            [
              '${i + 1}',
              s.product(t.lines[i].productId)?.code ?? '',
              s.product(t.lines[i].productId)?.name ?? '',
              s.warehouse(t.lines[i].toId)?.name ?? '',
              fmtQty(t.lines[i].qty),
              s.product(t.lines[i].productId)?.unit ?? '',
              t.lines[i].note,
            ],
        ],
        footer: ['', '', '', 'جمع', fmtQty(t.totalQty), '', ''],
        fileName: 'transfer_${t.number}${copies > 1 ? '_${k + 1}' : ''}',
      );
    }
  }

  Future<void> _history() async {
    final s = StoreScope.read(context);
    final t = await showDialog<WarehouseTransfer>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'انتقال‌های ثبت شده',
        width: 640,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        child: s.transfers.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('انتقالی ثبت نشده')))
            : Column(children: [
                for (final t in [...s.transfers]..sort((a, b) => b.number.compareTo(a.number)))
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 16, child: Text('${t.number}', style: const TextStyle(fontSize: 11))),
                    title: Text('از ${s.warehouse(t.fromId)?.name ?? ''} — ${t.lines.length} ردیف — جمع تعداد ${fmtQty(t.totalQty)}'),
                    subtitle: Text(jFormat(t.date)),
                    onTap: () => Navigator.pop(ctx, t),
                  ),
              ]),
      ),
    );
    if (t == null || !mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    await showTransferDialog(nav.context, edit: t);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'حذف انتقال', 'سند انتقال شماره ${widget.edit!.number} حذف شود؟');
    if (!ok || !mounted) return;
    StoreScope.read(context).removeTransfer(widget.edit!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    for (final r in _rows) {
      r.toId ??= _defaultTo(s);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f12): () => _save(print: true),
        const SingleActivator(LogicalKeyboardKey.insert): _add,
      },
      child: Focus(
        autofocus: true,
        child: _Win(
          title: widget.edit == null ? 'انتقال بین انبار' : 'ویرایش انتقال بین انبار',
          icon: Icons.move_up_rounded,
          width: 1000,
          maxHeight: 720,
          footer: Row(children: [
            if (widget.edit != null) ...[
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline_rounded, color: th.colorScheme.error),
                label: Text('حذف سند', style: TextStyle(color: th.colorScheme.error)),
              ),
              const SizedBox(width: 8),
            ] else ...[
              TextButton.icon(onPressed: _history, icon: const Icon(Icons.history_rounded), label: const Text('انتقال‌های قبلی')),
              const SizedBox(width: 8),
            ],
            if (_err != null) Expanded(child: Text(_err!, style: TextStyle(color: th.colorScheme.error))) else const Spacer(),
            SizedBox(
              width: 86,
              child: TextField(
                controller: _copies,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'تعداد چاپ', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _save(print: true),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('تایید و چاپ (F12)'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
          ]),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                SizedBox(
                  width: 130,
                  child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند')),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: TextField(controller: _receipt, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره رسید انبار')),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 170, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'جمع تعداد'),
                    child: Text(fmtQty(_totalQty), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const Spacer(),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.tonalIcon(
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.warehouse_outlined, size: 18),
                  label: const Text('نام انبار صادره'),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.expense.withValues(alpha: 0.3)),
                  ),
                  child: Text(s.warehouse(_from)?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                const Spacer(),
                FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('افزودن کالا (Insert)')),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _sel == null ? null : _remove,
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                  label: const Text('حذف ردیف'),
                ),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _head(context, const [
                      SizedBox(width: 44, child: Text('ردیف')),
                      Expanded(flex: 3, child: Text('نام کالا')),
                      SizedBox(width: 170, child: Text('انبار وارده')),
                      SizedBox(width: 10),
                      SizedBox(width: 90, child: Text('تعداد', textAlign: TextAlign.center)),
                      SizedBox(width: 60, child: Text('واحد', textAlign: TextAlign.center)),
                      Expanded(flex: 2, child: Text('توضیحات')),
                    ]),
                    Expanded(
                      child: _rows.isEmpty
                          ? const EmptyState(icon: Icons.move_up_rounded, text: 'کالایی اضافه نشده (Insert)')
                          : ListView.builder(
                              itemCount: _rows.length,
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                final p = s.product(r.productId);
                                return Material(
                                  color: _sel == i ? th.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setState(() => _sel = i),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      child: Row(children: [
                                        SizedBox(width: 44, child: Text('${i + 1}')),
                                        Expanded(
                                          flex: 3,
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(p?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                                            Text(
                                              'موجودی ${s.warehouse(_from)?.name}: ${fmtQty(s.stock(r.productId, warehouseId: _from, excludeTransferId: widget.edit?.id))}',
                                              style: th.textTheme.labelSmall?.copyWith(color: th.hintColor),
                                            ),
                                          ]),
                                        ),
                                        SizedBox(
                                          width: 170,
                                          child: DropdownButtonFormField<String>(
                                            value: r.toId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(isDense: true),
                                            items: [
                                              for (final w in s.warehouses.where((w) => w.id != _from))
                                                DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                                            ],
                                            onChanged: (v) => setState(() => r.toId = v),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 90,
                                          child: TextField(
                                            controller: r.qty,
                                            textAlign: TextAlign.center,
                                            textDirection: TextDirection.ltr,
                                            decoration: const InputDecoration(isDense: true),
                                          ),
                                        ),
                                        SizedBox(width: 60, child: Text(p?.unit ?? '', textAlign: TextAlign.center)),
                                        Expanded(
                                          flex: 2,
                                          child: TextField(controller: r.note, decoration: const InputDecoration(isDense: true)),
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
            ]),
          ),
        ),
      ),
    );
  }
}
