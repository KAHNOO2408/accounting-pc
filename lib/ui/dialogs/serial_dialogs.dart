import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/serials.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty;

/// «تعیین سریال» and «مشخصه» of one invoice row. Returns (serials, variant).
Future<(List<String>, String)?> showRowSerials(
  BuildContext context, {
  required Product product,
  required List<String> serials,
  required String variant,
  required int qty,
  required bool outbound,
  String? excludeInvoiceId,
}) =>
    showDialog<(List<String>, String)>(
      context: context,
      builder: (_) => _RowSerials(product: product, serials: serials, variant: variant, qty: qty, outbound: outbound, excludeInvoiceId: excludeInvoiceId),
    );

class _RowSerials extends StatefulWidget {
  final Product product;
  final List<String> serials;
  final String variant;
  final int qty;
  final bool outbound;
  final String? excludeInvoiceId;
  const _RowSerials({required this.product, required this.serials, required this.variant, required this.qty, required this.outbound, this.excludeInvoiceId});

  @override
  State<_RowSerials> createState() => _RowSerialsState();
}

class _RowSerialsState extends State<_RowSerials> {
  late final List<String> _list = [...widget.serials];
  late String _variant = widget.variant;
  final _input = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _input.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _add(String sn) {
    final t = normalizeDigits(sn.trim());
    if (t.isEmpty) return;
    if (_list.contains(t)) {
      setState(() => _err = 'سریال $t تکراری است');
      return;
    }
    setState(() {
      _list.add(t);
      _err = null;
    });
  }

  /// «ساخت سریال پشت سر هم»: ABC100 … ABC120.
  void _range() {
    final a = normalizeDigits(_from.text.trim()), b = normalizeDigits(_to.text.trim());
    final ma = RegExp(r'^(.*?)(\d+)$').firstMatch(a), mb = RegExp(r'^(.*?)(\d+)$').firstMatch(b);
    if (ma == null || mb == null || ma[1] != mb[1]) return setState(() => _err = 'ابتدا و انتهای بازه باید پیشوند یکسان و عدد پایانی داشته باشند');
    final x = int.parse(ma[2]!), y = int.parse(mb[2]!);
    if (y < x || y - x > 5000) return setState(() => _err = 'بازه معتبر نیست');
    for (var n = x; n <= y; n++) {
      final sn = '${ma[1]}${n.toString().padLeft(ma[2]!.length, '0')}';
      if (!_list.contains(sn)) _list.add(sn);
    }
    setState(() => _err = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final p = widget.product;
    final variants = productVariants(p);
    final serial = tracksSerial(p);
    final available = widget.outbound && serial ? (s.serialsInStock(productId: p.id, excludeInvoiceId: widget.excludeInvoiceId).keys.where((k) => !_list.contains(k)).toList()..sort()) : <String>[];
    return FormDialog(
      title: 'سریال و مشخصه — ${p.name}',
      width: 640,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            if (variants.isNotEmpty && _variant.isEmpty) return setState(() => _err = 'مشخصه را انتخاب کنید');
            Navigator.pop(context, (_list, _variant));
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (variants.isNotEmpty) ...[
          const Text('مشخصه', style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final v in variants)
              ChoiceChip(
                label: Text('$v (${fmtQty(s.variantStock(p.id, v, excludeInvoiceId: widget.excludeInvoiceId))})'),
                selected: _variant == v,
                onSelected: (_) => setState(() => _variant = v),
              ),
          ]),
          const Divider(height: 20),
        ],
        if (!serial && variants.isEmpty) const Text('این کالا سریال یا مشخصه ندارد. در تعریف کالا «کالای سریال دار» یا «مشخصه‌ها» را تنظیم کنید.'),
        if (serial) ...[
          Text('سریال‌ها (${_list.length} از ${widget.qty})', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                autofocus: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'سریال (با بارکدخوان یا تایپ و Enter)', isDense: true),
                onSubmitted: (v) {
                  _add(v);
                  _input.clear();
                },
              ),
            ),
          ]),
          if (!widget.outbound) ...[
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(controller: _from, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'از سریال', isDense: true))),
              const SizedBox(width: 6),
              Expanded(child: TextField(controller: _to, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تا سریال', isDense: true))),
              TextButton(onPressed: _range, child: const Text('ساخت بازه')),
            ]),
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('سریال‌های موجود در انبار:'),
            Wrap(spacing: 4, runSpacing: 4, children: [for (final a in available.take(200)) ActionChip(label: Text(a), onPressed: () => _add(a))]),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final sn in _list) InputChip(label: Text(sn), onDeleted: () => setState(() => _list.remove(sn))),
          ]),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}

/// «لیست سریال ها» — every serial, where it is now, and its history.
Future<void> showSerialList(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _SerialList());

class _SerialList extends StatefulWidget {
  const _SerialList();

  @override
  State<_SerialList> createState() => _SerialListState();
}

class _SerialListState extends State<_SerialList> {
  String _q = '';
  bool _inStockOnly = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = <(Product, String, SerialMove?, bool)>[];
    for (final p in s.products.where(tracksSerial)) {
      final stock = s.serialsInStock(productId: p.id);
      final all = <String, SerialMove?>{for (final sn in openingSerials(p)) sn: null};
      for (final m in s.serialMoves(productId: p.id)) {
        all[m.serial] = m;
      }
      for (final e in all.entries) {
        final here = stock.containsKey(e.key);
        if (_inStockOnly && !here) continue;
        if (_q.isNotEmpty && !e.key.contains(_q) && !p.name.contains(_q)) continue;
        rows.add((p, e.key, e.value, here));
      }
    }
    rows.sort((a, b) => a.$2.compareTo(b.$2));
    String where(SerialMove? m) => m == null ? 'موجودی اول دوره' : '${m.invoice.kind.label} ${m.invoice.number} — ${s.person(m.invoice.personId)?.name ?? 'متفرقه'}';
    return SakanWindow(
      title: 'لیست سریال ها',
      width: 1100,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 260, child: TextField(decoration: const InputDecoration(hintText: 'سریال یا نام کالا', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = normalizeDigits(v.trim())))),
            FilterChip(label: const Text('فقط موجود در انبار'), selected: _inStockOnly, onSelected: (v) => setState(() => _inStockOnly = v)),
            sakanBtn('انتقال بین سریال', () => showSerialSwap(context), icon: Icons.swap_horiz_rounded),
            sakanBtn('چاپ', () => printTable(
                  store: s,
                  title: 'لیست سریال ها',
                  headers: const ['سریال', 'کالا', 'وضعیت', 'آخرین سند', 'تاریخ'],
                  rows: [for (final r in rows) [r.$2, r.$1.name, r.$4 ? 'در انبار' : 'خارج شده', where(r.$3), r.$3 == null ? '' : jFormat(r.$3!.invoice.date)]],
                  fileName: 'serial-ha',
                ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('سریال', 180), sakanHead('کالا', 0), sakanHead('وضعیت', 100), sakanHead('آخرین سند', 320), sakanHead('تاریخ', 100)],
              count: rows.length,
              empty: 'سریالی ثبت نشده (کالای سریال دار را در تعریف کالا مشخص کنید)',
              row: (ctx, i) {
                final r = rows[i];
                return InkWell(
                  onDoubleTap: () => _history(s, r.$1, r.$2),
                  child: Container(
                    color: r.$4 ? const Color(0xFFE6F6E6) : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text(r.$2, textDirection: TextDirection.ltr), 180),
                      sakanCell(Text(r.$1.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                      sakanCell(Text(r.$4 ? 'در انبار' : 'خارج شده'), 100),
                      sakanCell(Text(where(r.$3), overflow: TextOverflow.ellipsis), 320),
                      sakanCell(Text(r.$3 == null ? '' : jFormat(r.$3!.invoice.date)), 100),
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

  void _history(AppStore s, Product p, String sn) => showDialog<void>(
        context: context,
        builder: (ctx) => FormDialog(
          title: 'گردش سریال $sn — ${p.name}',
          width: 560,
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
          child: Column(children: [
            if (openingSerials(p).contains(sn)) const ListTile(dense: true, title: Text('موجودی اول دوره')),
            for (final m in s.serialMoves(productId: p.id, serial: sn))
              ListTile(
                dense: true,
                leading: Icon(m.inbound ? Icons.call_received_rounded : Icons.call_made_rounded),
                title: Text('${m.invoice.kind.label} ${m.invoice.number}'),
                subtitle: Text('${jFormat(m.invoice.date)} — ${s.person(m.invoice.personId)?.name ?? 'متفرقه'}'),
              ),
          ]),
        ),
      );
}

/// «انتقال بین سریال»: replaces a serial on a sale (e.g. a swapped device).
Future<void> showSerialSwap(BuildContext context) async {
  final s = StoreScope.read(context);
  final from = TextEditingController(), to = TextEditingController();
  String? msg;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => FormDialog(
        title: 'انتقال بین سریال',
        width: 460,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          FilledButton(
            onPressed: () {
              final a = normalizeDigits(from.text.trim()), b = normalizeDigits(to.text.trim());
              final moves = s.serialMoves(serial: a);
              if (moves.isEmpty) return set(() => msg = 'سریال $a در هیچ فاکتوری نیست');
              final last = moves.last;
              if (s.serialsInStock(productId: last.line.productId).containsKey(b)) {
                // the new serial leaves the stock instead of the old one
              } else if (!last.inbound) {
                return set(() => msg = 'سریال $b در انبار نیست');
              }
              s.swapSerial(last.invoice.id, a, b);
              set(() => msg = 'در ${last.invoice.kind.label} ${last.invoice.number} سریال $a به $b تغییر کرد');
            },
            child: const Text('انتقال'),
          ),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('سریال ثبت شده در آخرین فاکتور با سریال جدید جایگزین می‌شود.'),
          const SizedBox(height: 8),
          TextField(controller: from, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سریال فعلی')),
          const SizedBox(height: 8),
          TextField(controller: to, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سریال جدید')),
          if (msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
    ),
  );
  from.dispose();
  to.dispose();
}

/// «تعریف کالا با مشخصه» and serial settings of a product.
Future<void> showProductAttrs(BuildContext context, Product p) => showDialog<void>(context: context, builder: (_) => _Attrs(product: p));

class _Attrs extends StatefulWidget {
  final Product product;
  const _Attrs({required this.product});

  @override
  State<_Attrs> createState() => _AttrsState();
}

class _AttrsState extends State<_Attrs> {
  late final List<(TextEditingController, TextEditingController)> _rows = [
    for (final (n, v) in productAttrs(widget.product)) (TextEditingController(text: n), TextEditingController(text: v.join('، '))),
  ];
  late bool _serial = tracksSerial(widget.product);
  late final _open = TextEditingController(text: openingSerials(widget.product).join('، '));

  @override
  void dispose() {
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.read(context);
    final p = widget.product;
    return FormDialog(
      title: 'سریال و مشخصه — ${p.name}',
      width: 620,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final attrs = <(String, List<String>)>[
              for (final (a, b) in _rows)
                if (a.text.trim().isNotEmpty) (a.text.trim(), b.text.split(RegExp('[,،]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList()),
            ];
            p.info['attrs'] = encodeAttrs(attrs.where((a) => a.$2.isNotEmpty).toList());
            p.info['serial'] = _serial ? '1' : '';
            p.info['openSerials'] = _open.text.split(RegExp('[,،\\n]')).map((x) => normalizeDigits(x.trim())).where((x) => x.isNotEmpty).join(',');
            p.info.removeWhere((_, v) => v.isEmpty);
            s.upsertProduct(p);
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _serial, onChanged: (v) => setState(() => _serial = v), title: const Text('کالای سریال دار'), subtitle: const Text('در هر خرید و فروش سریال تک تک کالاها ثبت شود')),
        if (_serial) TextField(controller: _open, maxLines: 2, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سریال‌های موجودی اول دوره (با ویرگول جدا کنید)')),
        const Divider(height: 24),
        Row(children: [
          const Text('مشخصه‌ها (تعریف کالا با مشخصه)', style: TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton.icon(onPressed: () => setState(() => _rows.add((TextEditingController(), TextEditingController()))), icon: const Icon(Icons.add_rounded), label: const Text('مشخصه')),
        ]),
        for (final (a, b) in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 140, child: TextField(controller: a, decoration: const InputDecoration(labelText: 'نام مشخصه (مثلا رنگ)', isDense: true))),
              const SizedBox(width: 6),
              Expanded(child: TextField(controller: b, decoration: const InputDecoration(labelText: 'مقادیر (قرمز، آبی، مشکی)', isDense: true), onChanged: (_) => setState(() {}))),
            ]),
          ),
        const SizedBox(height: 6),
        Builder(builder: (_) {
          final probe = Product(id: '', name: '', info: {
            'attrs': encodeAttrs([
              for (final (a, b) in _rows)
                if (a.text.trim().isNotEmpty) (a.text.trim(), b.text.split(RegExp('[,،]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList()),
            ]),
          });
          final v = productVariants(probe);
          return Text(v.isEmpty ? 'بدون مشخصه' : '${v.length} حالت: ${v.take(12).join('، ')}${v.length > 12 ? '…' : ''}');
        }),
      ]),
    );
  }
}
