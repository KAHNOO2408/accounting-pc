import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/scale.dart';
import '../../data/store.dart';
import '../../data/tools.dart';
import '../print.dart' show printInvoice, printSlip, printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, pickPersonId;

// ================================================================ فرمول های تغییر نرخ

Future<void> showPriceFormulas(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Prices());

class _Prices extends StatefulWidget {
  const _Prices();

  @override
  State<_Prices> createState() => _PricesState();
}

class _PricesState extends State<_Prices> {
  PriceField _f = PriceField.sell1;
  PriceMode _m = PriceMode.percent;
  final _v = TextEditingController(text: '10');
  int _round = 0;
  String _q = '';

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final value = double.tryParse(normalizeDigits(_v.text.replaceAll(',', ''))) ?? 0;
    final list = s.productsSorted.where((p) => !p.archived && (_q.isEmpty || p.name.contains(_q) || p.code.contains(_q))).toList();
    return SakanWindow(
      title: 'فرمول های تغییر نرخ',
      width: 1000,
      height: 660,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<PriceField>(value: _f, items: [for (final f in PriceField.values) DropdownMenuItem(value: f, child: Text(f.label))], onChanged: (v) => setState(() => _f = v ?? _f)),
            DropdownButton<PriceMode>(value: _m, items: [for (final m in PriceMode.values) DropdownMenuItem(value: m, child: Text(m.label))], onChanged: (v) => setState(() => _m = v ?? _m)),
            SizedBox(width: 120, child: TextField(controller: _v, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مقدار', isDense: true), onChanged: (_) => setState(() {}))),
            DropdownButton<int>(
              value: _round,
              items: const [
                DropdownMenuItem(value: 0, child: Text('بدون گرد کردن')),
                DropdownMenuItem(value: 100, child: Text('گرد به ۱۰۰')),
                DropdownMenuItem(value: 1000, child: Text('گرد به ۱٬۰۰۰')),
                DropdownMenuItem(value: 10000, child: Text('گرد به ۱۰٬۰۰۰')),
                DropdownMenuItem(value: 100000, child: Text('گرد به ۱۰۰٬۰۰۰')),
              ],
              onChanged: (v) => setState(() => _round = v ?? 0),
            ),
            SizedBox(width: 200, child: TextField(decoration: const InputDecoration(hintText: 'فیلتر نام یا کد', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            FilledButton.icon(
              onPressed: list.isEmpty
                  ? null
                  : () async {
                      if (!await confirm(context, 'اعمال فرمول', '${_f.label} ${list.length} کالا تغییر کند؟', ok: 'اعمال', danger: false)) return;
                      final n = s.applyPriceFormula(list, _f, _m, value, round: _round);
                      if (context.mounted) toast(context, 'قیمت $n کالا تغییر کرد');
                    },
              icon: const Icon(Icons.price_change_outlined),
              label: Text('اعمال به ${list.length} کالا'),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 90), sakanHead('نام کالا', 0), sakanHead('قیمت تمام شده', 120), sakanHead('${_f.label} فعلی', 130), sakanHead('قیمت جدید', 130)],
              count: list.length,
              row: (ctx, i) {
                final p = list[i];
                final nv = formulaPrice(s, p, _f, _m, value, round: _round);
                return Container(
                  color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                  child: Row(children: [
                    sakanCell(Text(p.code), 90),
                    sakanCell(Text(p.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                    sakanCell(Text(groupDigits(s.avgCost(p.id))), 120),
                    sakanCell(Text(groupDigits(_f.of(p))), 130),
                    sakanCell(Text(groupDigits(nv), style: TextStyle(fontWeight: FontWeight.w800, color: nv == _f.of(p) ? null : const Color(0xFF1F3BB3))), 130),
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

Future<void> showStandardBarcodes(BuildContext context) async {
  final s = StoreScope.read(context);
  final n = s.products.where((p) => (p.info['barcode'] ?? '').isEmpty).length;
  if (n == 0) return toast(context, 'همه کالاها بارکد دارند');
  if (!await confirm(context, 'ساخت بارکد استاندارد', 'برای $n کالای بدون بارکد، بارکد داخلی EAN-13 (شروع با 200) ساخته شود؟', ok: 'ساخت', danger: false)) return;
  final made = s.makeStandardBarcodes();
  if (context.mounted) toast(context, 'برای $made کالا بارکد ساخته شد');
}

// ================================================================ سند ترکیبی

Future<void> showCombinedVoucher(BuildContext context) {
  final s = StoreScope.read(context);
  var from = dateOnly(DateTime.now()), to = dateOnly(DateTime.now());
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final rows = combinedVoucher(s, from, to);
      final dr = rows.fold<int>(0, (a, r) => a + r.$3), cr = rows.fold<int>(0, (a, r) => a + r.$4);
      return FormDialog(
        title: 'سند ترکیبی عملیات یک روز یا یک ماه',
        width: 760,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 150, child: DateField(label: 'از تاریخ', value: from, onChanged: (v) => set(() => from = v ?? from))),
          const SizedBox(width: 6),
          SizedBox(width: 150, child: DateField(label: 'تا تاریخ', value: to, onChanged: (v) => set(() => to = v ?? to))),
          TextButton(
            onPressed: () => set(() {
              final j = Jalali.fromDateTime(from);
              from = Jalali(j.year, j.month, 1).toDateTime();
              to = Jalali(j.year, j.month, Jalali.monthLength(j.year, j.month)).toDateTime();
            }),
            child: const Text('کل ماه'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => printTable(
              store: s,
              title: 'سند ترکیبی',
              subtitle: 'از ${jFormat(from)} تا ${jFormat(to)}',
              headers: const ['کد', 'شرح حساب', 'بدهکار', 'بستانکار'],
              rows: [for (final r in rows) [r.$1, r.$2, groupDigits(r.$3), groupDigits(r.$4)]],
              numeric: const {2, 3},
              footer: ['', 'جمع', groupDigits(dr), groupDigits(cr)],
              fileName: 'sanad-tarkibi',
            ),
            child: const Text('چاپ'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rows)
            Row(children: [
              SizedBox(width: 70, child: Text(r.$1)),
              Expanded(child: Text(r.$2)),
              SizedBox(width: 130, child: Text(r.$3 == 0 ? '' : groupDigits(r.$3), textAlign: TextAlign.left)),
              SizedBox(width: 130, child: Text(r.$4 == 0 ? '' : groupDigits(r.$4), textAlign: TextAlign.left)),
            ]),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('عملیاتی در این بازه نیست')),
          const Divider(),
          Text('جمع بدهکار ${groupDigits(dr)} — جمع بستانکار ${groupDigits(cr)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );
    }),
  );
}

// ================================================================ فاکتور فروشگاهی

/// «فاکتور فروشگاهی»: quick counter sale with a barcode scanner.
Future<void> showShopInvoice(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Shop());

class _ShopLine {
  final Product p;
  double qty;
  int price;
  _ShopLine(this.p, this.qty, this.price);
  int get total => (qty * price).round();
}

class _Shop extends StatefulWidget {
  const _Shop();

  @override
  State<_Shop> createState() => _ShopState();
}

class _ShopState extends State<_Shop> {
  final _scan = TextEditingController();
  final _focus = FocusNode();
  final _disc = TextEditingController();
  final List<_ShopLine> _lines = [];
  final List<String> _log = []; // «ریز فعالیت های انجام شده در فاکتور فروشگاهی»
  String? _person;
  String? _acc;
  String? _err;

  @override
  void dispose() {
    _scan.dispose();
    _focus.dispose();
    _disc.dispose();
    super.dispose();
  }

  void _add(AppStore s, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    var hit = s.matchScan(t);
    if (hit == null) {
      final byName = s.products.where((p) => !p.archived && p.name.contains(t)).toList();
      if (byName.length == 1) hit = (byName.first, null);
    }
    setState(() {
      if (hit == null) {
        _err = 'کالایی با «$t» پیدا نشد';
      } else {
        _err = null;
        final (p, q) = hit;
        final l = _lines.where((x) => x.p.id == p.id && q == null).firstOrNull;
        if (l != null) {
          l.qty += 1;
        } else {
          _lines.add(_ShopLine(p, q ?? 1, p.sellPrice));
        }
        _log.add('${_hm()} افزودن ${p.name}${q == null ? '' : ' (${fmtQty(q)})'}');
      }
      _scan.clear();
    });
    _focus.requestFocus();
  }

  String _hm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    _acc ??= s.activeAccounts.firstOrNull?.id;
    final sub = _lines.fold<int>(0, (a, l) => a + l.total);
    final disc = parseMoney(_disc.text);
    final total = sub - disc;
    return SakanWindow(
      title: 'فاکتور فروشگاهی',
      width: 1100,
      height: 700,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _scan,
                focusNode: _focus,
                autofocus: true,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(labelText: 'بارکد / کد / نام کالا (Enter)', prefixIcon: Icon(Icons.qr_code_scanner_rounded)),
                onSubmitted: (v) => _add(s, v),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_err!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 8),
              Expanded(
                child: SakanGrid(
                  header: [sakanHead('ردیف', 50), sakanHead('کالا', 0), sakanHead('تعداد', 140), sakanHead('فی', 120), sakanHead('جمع', 130), sakanHead('', 50)],
                  count: _lines.length,
                  empty: 'کالا را اسکن کنید',
                  row: (ctx, i) {
                    final l = _lines[i];
                    return Container(
                      color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                      child: Row(children: [
                        sakanCell(Text('${i + 1}'), 50),
                        sakanCell(Text(l.p.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                        sakanCell(
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                l.qty -= 1;
                                _log.add('${_hm()} کاهش ${l.p.name}');
                                if (l.qty <= 0) _lines.remove(l);
                              }),
                              icon: const Icon(Icons.remove_rounded, size: 18),
                            ),
                            Text(fmtQty(l.qty)),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() {
                                l.qty += 1;
                                _log.add('${_hm()} افزایش ${l.p.name}');
                              }),
                              icon: const Icon(Icons.add_rounded, size: 18),
                            ),
                          ]),
                          140,
                        ),
                        sakanCell(Text(groupDigits(l.price)), 120),
                        sakanCell(Text(groupDigits(l.total), style: const TextStyle(fontWeight: FontWeight.w700)), 130),
                        sakanCell(
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() {
                              _lines.remove(l);
                              _log.add('${_hm()} حذف ${l.p.name}');
                            }),
                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                          ),
                          50,
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 320,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                color: const Color(0xFF1F3BB3),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    const Text('قابل پرداخت', style: TextStyle(color: Colors.white70)),
                    Text(groupDigits(total), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    Text('${_lines.length} قلم', style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: _disc, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'تخفیف', isDense: true), onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final id = await pickPersonId(context, title: 'خریدار');
                  if (id != null) setState(() => _person = id);
                },
                icon: const Icon(Icons.person_outline_rounded),
                label: Text(s.person(_person)?.name ?? 'خریدار: متفرقه'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _acc,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'دریافت به (صندوق / کارتخوان)', isDense: true),
                items: [for (final a in s.activeAccounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _acc = v),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                onPressed: _lines.isEmpty || _acc == null
                    ? null
                    : () {
                        final inv = Invoice(
                          id: newId(),
                          kind: InvoiceKind.sale,
                          number: s.nextInvoiceNumber(InvoiceKind.sale),
                          date: DateTime.now(),
                          personId: _person,
                          lines: [for (final l in _lines) InvoiceLine(productId: l.p.id, qty: l.qty, unitPrice: l.price)],
                          discount: disc,
                          accountId: _acc,
                          info: {'shop': '1', 'activity': _log.join('\n')},
                        );
                        inv.paid = inv.total;
                        s.saveInvoice(inv);
                        printSlip(
                          store: s,
                          title: 'فاکتور فروش ${inv.number}',
                          fields: [('تاریخ', '${jFormat(inv.date)} ${_hm()}'), if (_person != null) ('خریدار', s.person(_person)?.name ?? '')],
                          itemHeaders: const ['کالا', 'تعداد', 'جمع'],
                          items: [for (final l in _lines) [l.p.name, fmtQty(l.qty), groupDigits(l.total)]],
                          footer: 'جمع ${groupDigits(sub)}${disc == 0 ? '' : ' — تخفیف ${groupDigits(disc)}'} — پرداختی ${groupDigits(inv.total)}',
                          fileName: 'forooshgahi',
                        );
                        setState(() {
                          _lines.clear();
                          _log.clear();
                          _disc.clear();
                          _person = null;
                        });
                        toast(context, 'فاکتور ${inv.number} ثبت شد');
                        _focus.requestFocus();
                      },
                icon: const Icon(Icons.point_of_sale_rounded),
                label: const Text('ثبت و چاپ', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () {
                  final last = s.invoices.where((i) => i.info['shop'] == '1').toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  if (last.isNotEmpty) printInvoice(s, last.first);
                },
                child: const Text('چاپ A5 آخرین فاکتور'),
              ),
              const Divider(),
              const Text('ریز فعالیت‌ها', style: TextStyle(fontWeight: FontWeight.w700)),
              Expanded(child: ListView(children: [for (final e in _log.reversed) Text(e, style: const TextStyle(fontSize: 11.5))])),
            ]),
          ),
        ]),
      ),
    );
  }
}
