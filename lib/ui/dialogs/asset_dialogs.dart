import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'composite_dialogs.dart';
import 'simple_dialogs.dart';

class _Win extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? color;
  final Widget body;
  final Widget footer;
  final double width;
  const _Win({required this.title, required this.icon, required this.body, required this.footer, this.width = 1000, this.color});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final c = color;
    final header = Row(children: [
      Icon(icon, size: 22, color: Colors.white),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white))),
      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
    ]);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: (size.height * 0.9).clamp(420.0, 760.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (c == null)
            HeaderBand(padding: const EdgeInsets.fromLTRB(20, 10, 10, 10), child: header)
          else
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(c, Brand.of(context).partner, 0.55)!])),
              child: header,
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

// ================================================================ جدول اموال

const _cols = ['شناسه', 'نام اموال', 'محل', 'شماره اموال', 'تحویل گیرنده', 'بهای تمام شده', 'استهلاک', 'ارزش دفتری', 'تاریخ خرید', 'وضعیت'];

List<String> _cells(Asset a) => [
      '${a.code}',
      a.name,
      a.location,
      a.assetNo,
      a.receiver,
      groupDigits(a.cost),
      groupDigits(a.depreciation),
      groupDigits(a.bookValue),
      a.purchaseDate == null ? '' : jFormat(a.purchaseDate!),
      a.sold ? 'فروخته شده (${groupDigits(a.salePrice)})' : 'موجود',
    ];

Future<void> showAssetsTable(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _AssetsTable());

class _AssetsTable extends StatefulWidget {
  const _AssetsTable();

  @override
  State<_AssetsTable> createState() => _AssetsTableState();
}

class _AssetsTableState extends State<_AssetsTable> {
  int _col = 0;
  final _value = TextEditingController();
  String _filter = '';
  String? _sel;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  List<Asset> _list(AppStore s) {
    final q = normalizeDigits(_filter.trim()).toLowerCase();
    return ([...s.assets]..sort((a, b) => a.code.compareTo(b.code)))
        .where((a) => q.isEmpty || normalizeDigits(_cells(a)[_col]).toLowerCase().replaceAll(',', '').contains(q.replaceAll(',', '')))
        .toList();
  }

  Future<void> _edit({Asset? a}) async {
    await showDialog<void>(context: context, builder: (_) => _AssetForm(edit: a));
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final s = StoreScope.read(context);
    final a = s.asset(_sel);
    if (a == null) return toast(context, 'ردیفی انتخاب نشده', error: true);
    final ok = await confirm(context, 'حذف اموال', '«${a.name}» حذف شود؟');
    if (!ok || !mounted) return;
    if (s.removeAsset(a.id)) {
      setState(() => _sel = null);
    } else {
      toast(context, 'این مورد سند خرید یا فروش دارد؛ ابتدا آن سند را از لیست اسناد حذف کنید', error: true);
    }
  }

  void _print() {
    final s = StoreScope.read(context);
    final list = _list(s);
    printTable(
      store: s,
      title: 'جدول اموال و تجهیزات',
      headers: ['ردیف', ..._cols],
      rows: [
        for (var i = 0; i < list.length; i++) ['${i + 1}', ..._cells(list[i])],
      ],
      numeric: const {6, 7, 8},
      footer: [
        '', '', 'جمع', '', '', '', //
        groupDigits(list.fold<int>(0, (x, a) => x + a.cost)),
        groupDigits(list.fold<int>(0, (x, a) => x + a.depreciation)),
        groupDigits(list.fold<int>(0, (x, a) => x + a.bookValue)),
        '', '',
      ],
      fileName: 'assets',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final list = _list(s);
    const widths = [60.0, 0.0, 110.0, 100.0, 120.0, 120.0, 100.0, 120.0, 95.0, 150.0];
    Widget cell(int i, Widget child) => i == 1 ? Expanded(child: child) : SizedBox(width: widths[i], child: child);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f12): _print,
        const SingleActivator(LogicalKeyboardKey.insert): () => _edit(),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: _Win(
          title: 'جدول اموال',
          icon: Icons.chair_outlined,
          width: 1240,
          footer: Row(children: [
            FilledButton.tonalIcon(
              onPressed: () {
                final a = s.asset(_sel);
                if (a == null) return toast(context, 'ردیفی انتخاب نشده', error: true);
                _edit(a: a);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('ویرایش'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('افزودن')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: th.colorScheme.error),
              label: const Text('حذف'),
            ),
            const Spacer(),
            Text('${list.length} مورد — ارزش دفتری ', style: th.textTheme.bodySmall),
            Money(list.where((a) => !a.sold).fold<int>(0, (x, a) => x + a.bookValue), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 16),
            FilledButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('چاپ F12')),
          ]),
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                SizedBox(
                  width: 220,
                  child: FieldDropdown<int>(
                    label: 'ستون',
                    value: _col,
                    items: [for (var i = 0; i < _cols.length; i++) DropdownMenuItem(value: i, child: Text(_cols[i]))],
                    onChanged: (v) => setState(() => _col = v ?? 0),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _value,
                    decoration: const InputDecoration(labelText: 'مقدار'),
                    onSubmitted: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(onPressed: () => setState(() => _filter = _value.text), child: const Text('محدود')),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _value.clear();
                    _filter = '';
                  }),
                  child: const Text('همه موارد'),
                ),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _head(context, [
                      const SizedBox(width: 44, child: Text('ردیف')),
                      for (var i = 0; i < _cols.length; i++) cell(i, Text(_cols[i])),
                    ]),
                    Expanded(
                      child: list.isEmpty
                          ? const EmptyState(icon: Icons.chair_outlined, text: 'اموالی ثبت نشده (افزودن یا خرید اموال و تجهیزات)')
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final a = list[i];
                                final c = _cells(a);
                                return Material(
                                  color: a.id == _sel
                                      ? th.colorScheme.primary.withValues(alpha: 0.14)
                                      : (i.isOdd ? th.colorScheme.surfaceContainerLowest : Colors.transparent),
                                  child: InkWell(
                                    onTap: () => setState(() => _sel = a.id),
                                    onDoubleTap: () => _edit(a: a),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: Row(children: [
                                        SizedBox(width: 44, child: Text('${i + 1}')),
                                        for (var k = 0; k < c.length; k++)
                                          cell(
                                            k,
                                            k == 9
                                                ? Align(
                                                    alignment: AlignmentDirectional.centerStart,
                                                    child: Pill(a.sold ? 'فروخته شده' : 'موجود', color: a.sold ? AppColors.expense : AppColors.income),
                                                  )
                                                : Text(c[k],
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(fontWeight: k == 1 ? FontWeight.w700 : null, color: a.sold ? th.hintColor : null)),
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

class _AssetForm extends StatefulWidget {
  final Asset? edit;
  const _AssetForm({this.edit});

  @override
  State<_AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<_AssetForm> {
  late final Asset? e = widget.edit;
  late final _name = TextEditingController(text: e?.name ?? '');
  late final _location = TextEditingController(text: e?.location ?? '');
  late final _no = TextEditingController(text: e?.assetNo ?? '');
  late final _receiver = TextEditingController(text: e?.receiver ?? '');
  late final _cost = TextEditingController(text: (e?.cost ?? 0) == 0 ? '' : groupDigits(e!.cost));
  late final _dep = TextEditingController(text: (e?.depreciation ?? 0) == 0 ? '' : groupDigits(e!.depreciation));
  late final _note = TextEditingController(text: e?.note ?? '');
  late DateTime? _date = e?.purchaseDate;
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _location, _no, _receiver, _cost, _dep, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final cost = parseMoney(_cost.text);
    final dep = parseMoney(_dep.text);
    if (_name.text.trim().isEmpty) return setState(() => _err = 'نام اموال را وارد کنید');
    if (dep > cost) return setState(() => _err = 'استهلاک از بهای تمام شده بیشتر است');
    final a = e ?? Asset(id: newId(), code: s.nextAssetCode(), name: '');
    a
      ..name = _name.text.trim()
      ..location = _location.text.trim()
      ..assetNo = _no.text.trim()
      ..receiver = _receiver.text.trim()
      ..note = _note.text.trim()
      ..purchaseDate = _date;
    if (a.buyVoucherId == null && !a.sold) a.cost = cost;
    if (!a.sold) a.depreciation = dep;
    s.saveAsset(a);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final locked = e != null && (e!.buyVoucherId != null || e!.sold);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: e == null ? 'افزودن اموال' : 'ویرایش اموال — شناسه ${e!.code}',
        width: 620,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'نام اموال')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _location, decoration: const InputDecoration(labelText: 'محل'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _no, decoration: const InputDecoration(labelText: 'شماره اموال'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _receiver, decoration: const InputDecoration(labelText: 'تحویل گیرنده'))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'تاریخ خرید', value: _date, clearable: true, onChanged: (d) => setState(() => _date = d))),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: locked
                  ? InputDecorator(
                      decoration: const InputDecoration(labelText: 'بهای تمام شده (از سند خرید)'),
                      child: Money(e!.cost),
                    )
                  : MoneyField(controller: _cost, label: 'بهای تمام شده'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: e?.sold == true
                  ? InputDecorator(decoration: const InputDecoration(labelText: 'استهلاک انباشته'), child: Money(e!.depreciation))
                  : MoneyField(controller: _dep, label: 'استهلاک انباشته'),
            ),
          ]),
          const SizedBox(height: 6),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظات')),
          const SizedBox(height: 8),
          Text('استهلاک به‌صورت سند «استهلاک اموال» (هزینه استهلاک / استهلاک انباشته) ثبت می‌شود.',
              style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}

// ================================================================ خرید / فروش اموال

class _BuyRow {
  final name = TextEditingController();
  final price = TextEditingController();
  final discount = TextEditingController();
  final note = TextEditingController();
  String? assetId; // sale rows

  int get net => parseMoney(price.text) - parseMoney(discount.text);

  void dispose() {
    for (final c in [name, price, discount, note]) {
      c.dispose();
    }
  }
}

Future<void> showAssetBuyDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _AssetDoc(sale: false));
Future<void> showAssetSellDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _AssetDoc(sale: true));

class _AssetDoc extends StatefulWidget {
  final bool sale;
  const _AssetDoc({required this.sale});

  @override
  State<_AssetDoc> createState() => _AssetDocState();
}

class _AssetDocState extends State<_AssetDoc> {
  late final TextEditingController _number;
  final _invoiceNo = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _date;
  String? _person;
  final List<_BuyRow> _rows = [];
  String? _err;

  bool get sale => widget.sale;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: '${StoreScope.read(context).nextVoucherNumber()}');
    final n = DateTime.now();
    _date = DateTime(n.year, n.month, n.day);
    _addRow();
  }

  @override
  void dispose() {
    for (final c in [_number, _invoiceNo, _desc]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final r = _BuyRow();
    for (final c in [r.price, r.discount]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    setState(() => _rows.add(r));
  }

  int get _total => _rows.fold(0, (a, r) => a + r.net);

  Future<void> _save() async {
    final s = StoreScope.read(context);
    final rows = sale ? _rows.where((r) => r.assetId != null).toList() : _rows.where((r) => r.name.text.trim().isNotEmpty).toList();
    String? err;
    if (rows.isEmpty) {
      err = sale ? 'اموال مورد فروش را انتخاب کنید' : 'نام اموال را وارد کنید';
    } else if (rows.any((r) => r.net < 0 || (!sale && r.net == 0))) {
      err = 'مبلغ هر ردیف را درست وارد کنید';
    } else if (sale && rows.map((r) => r.assetId).toSet().length != rows.length) {
      err = 'یک مورد اموال دوبار انتخاب شده است';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    final total = rows.fold<int>(0, (a, r) => a + r.net);
    final signed = sale ? total : -total;
    final before = _person == null ? 0 : s.personBalance(_person!);
    final items = await showPayMethodsDialog(
      context,
      personId: _person,
      items: const [],
      before: before,
      docAmount: signed,
      receiveSide: sale,
      title: sale ? 'نحوه دریافت — فروش اموال و تجهیزات' : 'نحوه پرداخت — خرید اموال و تجهیزات',
      skipLabel: _person == null ? null : 'ثبت سند بدون ${sale ? 'دریافت' : 'پرداخت'}',
    );
    if (items == null || !mounted) return;
    if (_person == null && signed + sumPayments(items) - sumReceipts(items) != 0) {
      setState(() => _err = 'سند کامل تسویه نشده؛ برای ثبت مانده، ${sale ? 'خریدار' : 'فروشنده'} را انتخاب کنید');
      return;
    }
    final title = sale ? 'فروش اموال و تجهیزات' : 'خرید اموال و تجهیزات';
    final desc = _desc.text.trim().isEmpty
        ? '$title${_invoiceNo.text.trim().isEmpty ? '' : ' — فاکتور ${_invoiceNo.text.trim()}'}${_person == null ? '' : ' — ${s.person(_person)?.name}'}'
        : _desc.text.trim();
    final pay = applyPayItems(s, _person, items, _date, desc);
    final number = int.tryParse(normalizeDigits(_number.text.trim()));
    final Voucher v;
    if (sale) {
      v = s.sellAssets(
        date: _date,
        number: number,
        desc: desc,
        personId: _person,
        sales: [for (final r in rows) (s.asset(r.assetId)!, r.net)],
        payLines: pay,
      );
    } else {
      v = s.buyAssets(
        date: _date,
        number: number,
        desc: desc,
        personId: _person,
        items: [
          for (final r in rows)
            Asset(id: newId(), code: 0, name: r.name.text.trim(), cost: r.net, note: r.note.text.trim(), purchaseDate: _date),
        ],
        payLines: pay,
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, '$title ثبت شد — سند ${v.number}');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final color = sale ? AppColors.income : AppColors.expense;
    final available = s.assets.where((a) => !a.sold).toList()..sort((a, b) => a.code.compareTo(b.code));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.insert): _addRow,
      },
      child: _Win(
        title: sale ? 'فروش اموال و تجهیزات' : 'خرید اموال و تجهیزات',
        icon: sale ? Icons.sell_outlined : Icons.add_business_outlined,
        color: color,
        width: 1100,
        footer: Row(children: [
          if (_err != null) Expanded(child: Text(_err!, style: TextStyle(color: th.colorScheme.error))) else const Spacer(),
          Text('جمع ${sale ? 'فروش' : 'فاکتور'}: ', style: th.textTheme.titleSmall),
          Money(_total, showUnit: true, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 16),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          const SizedBox(width: 8),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: _save, child: const Text('تایید و تسویه (F9)')),
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
              SizedBox(width: 170, child: DateField(label: 'تاریخ فاکتور', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: TextField(controller: _invoiceNo, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره فاکتور')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldDropdown<String?>(
                  label: sale ? 'خریدار' : 'حساب فروشنده',
                  value: _person,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('نقدی / متفرقه')),
                    for (final p in s.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _person = v),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'شخص جدید',
                onPressed: () async {
                  final id = await showPersonDialog(context);
                  if (id != null) setState(() => _person = id);
                },
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح سند (اختیاری)')),
            const SizedBox(height: 10),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _head(context, [
                    const SizedBox(width: 44, child: Text('ردیف')),
                    Expanded(flex: 3, child: Text(sale ? 'نام اموال' : 'عنوان حساب (نام اموال)')),
                    if (sale) const SizedBox(width: 130, child: Text('ارزش دفتری', textAlign: TextAlign.center)),
                    SizedBox(width: 150, child: Text(sale ? 'بهای فروش ریال' : 'بها به ریال', textAlign: TextAlign.center)),
                    if (!sale) const SizedBox(width: 130, child: Text('تخفیف به ریال', textAlign: TextAlign.center)),
                    if (!sale) const SizedBox(width: 130, child: Text('جمع کل', textAlign: TextAlign.center)),
                    const Expanded(flex: 2, child: Text('توضیحات')),
                    const SizedBox(width: 40),
                  ]),
                  Expanded(
                    child: ListView(children: [
                      for (var i = 0; i < _rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          child: Row(children: [
                            SizedBox(width: 44, child: Text('${i + 1}')),
                            Expanded(
                              flex: 3,
                              child: sale
                                  ? DropdownButtonFormField<String>(
                                      value: _rows[i].assetId,
                                      isExpanded: true,
                                      decoration: const InputDecoration(isDense: true, hintText: 'انتخاب اموال'),
                                      items: [
                                        for (final a in available)
                                          DropdownMenuItem(value: a.id, child: Text('${a.code} — ${a.name}', overflow: TextOverflow.ellipsis)),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _rows[i].assetId = v;
                                        final a = s.asset(v);
                                        if (a != null && _rows[i].price.text.isEmpty) _rows[i].price.text = groupDigits(a.bookValue);
                                      }),
                                    )
                                  : TextField(controller: _rows[i].name, decoration: const InputDecoration(isDense: true)),
                            ),
                            const SizedBox(width: 8),
                            if (sale)
                              SizedBox(
                                width: 130,
                                child: Center(child: s.asset(_rows[i].assetId) == null ? const Text('—') : Money(s.asset(_rows[i].assetId)!.bookValue)),
                              ),
                            SizedBox(
                              width: 150,
                              child: TextField(
                                controller: _rows[i].price,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.left,
                                inputFormatters: [MoneyInputFormatter()],
                                decoration: const InputDecoration(isDense: true),
                              ),
                            ),
                            if (!sale) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 122,
                                child: TextField(
                                  controller: _rows[i].discount,
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.left,
                                  inputFormatters: [MoneyInputFormatter()],
                                  decoration: const InputDecoration(isDense: true),
                                ),
                              ),
                              SizedBox(width: 130, child: Center(child: Money(_rows[i].net, style: const TextStyle(fontWeight: FontWeight.w700)))),
                            ],
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: TextField(controller: _rows[i].note, decoration: const InputDecoration(isDense: true))),
                            SizedBox(
                              width: 40,
                              child: IconButton(
                                tooltip: 'حذف ردیف',
                                onPressed: _rows.length == 1
                                    ? null
                                    : () => setState(() {
                                          _rows.removeAt(i).dispose();
                                        }),
                                icon: Icon(Icons.remove_circle_outline, size: 20, color: th.colorScheme.error),
                              ),
                            ),
                          ]),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add_rounded), label: const Text('افزودن ردیف (Insert)')),
                        ),
                      ),
                      if (sale && available.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('اموالی برای فروش وجود ندارد. از «جدول اموال» یا «خرید اموال و تجهیزات» اموال ثبت کنید.',
                              style: TextStyle(color: th.colorScheme.error)),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
