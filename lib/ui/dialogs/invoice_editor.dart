import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../print_designer.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'composite_dialogs.dart';
import 'misc_dialogs.dart';
import 'price_dialog.dart';
import 'simple_dialogs.dart';

String fmtQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  var s = q.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

double parseQty(String s) {
  final t = normalizeDigits(s).replaceAll('٫', '.').replaceAll('/', '.').replaceAll(',', '').trim();
  return double.tryParse(t) ?? 0;
}

/// Quick label for invoice lists.
String invoiceTitle(Invoice i) => '${i.kind.label} ${i.number}  ·  ${jFormat(i.date)}';

Future<void> showInvoiceEditor(BuildContext context, {Invoice? edit, InvoiceKind kind = InvoiceKind.sale, bool proforma = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InvoiceEditor(edit: edit, kind: kind, proforma: proforma),
  );
}

class _Line {
  String? productId;
  String? warehouseId;
  final title = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  final discount = TextEditingController();
  final titleFocus = FocusNode();

  _Line();

  factory _Line.from(InvoiceLine l) {
    final x = _Line();
    x.productId = l.productId;
    x.warehouseId = l.warehouseId;
    x.title.text = l.title;
    x.qty.text = fmtQty(l.qty);
    x.price.text = l.unitPrice == 0 ? '' : groupDigits(l.unitPrice);
    x.discount.text = l.discount == 0 ? '' : groupDigits(l.discount);
    return x;
  }

  double get q => parseQty(qty.text);
  int get p => parseMoney(price.text);
  int get d => parseMoney(discount.text);
  int get total => (q * p).round() - d;
  bool get isEmpty => title.text.trim().isEmpty && productId == null && p == 0;

  InvoiceLine toLine() =>
      InvoiceLine(productId: productId, title: title.text.trim(), qty: q, unitPrice: p, discount: d, warehouseId: warehouseId);

  Map<String, dynamic> toJson() => toLine().toJson();

  void dispose() {
    title.dispose();
    qty.dispose();
    price.dispose();
    discount.dispose();
    titleFocus.dispose();
  }
}

/// فاکتور فروش / خرید / برگشتی — laid out like Sakan's invoice form.
class InvoiceEditor extends StatefulWidget {
  final Invoice? edit;
  final InvoiceKind kind;
  final bool proforma;
  const InvoiceEditor({super.key, this.edit, this.kind = InvoiceKind.sale, this.proforma = false});

  @override
  State<InvoiceEditor> createState() => _InvoiceEditorState();
}

class _InvoiceEditorState extends State<InvoiceEditor> {
  late InvoiceKind _kind;
  late bool _proforma;
  late DateTime _date;
  late DateTime _saleDate;
  DateTime? _due;
  String? _person;
  final _number = TextEditingController();
  final _warehouseNo = TextEditingController();
  final _requestNo = TextEditingController();
  final _babat = TextEditingController();
  final _address = TextEditingController();
  final _region = TextEditingController();
  final _buyerName = TextEditingController();
  String _receiver = '';
  String _note = '';
  int _discount = 0;
  int _extra = 0;
  int _decimals = 0;
  bool _fromBig = false;
  bool _fromSmall = true;
  bool _zebra = true;
  int _tab = 0;
  int? _selRow;
  final List<_Line> _lines = [];
  final List<_Line> _services = [];
  List<PayItem>? _preItems;
  String? _err;
  bool _inited = false;
  Invoice? _saved;

  bool get _isEdit => widget.edit != null;
  bool get _legacy => (widget.edit?.paid ?? 0) > 0;
  bool get _buy => _kind.buySide;
  String get _title => _proforma ? 'پیش فاکتور فروش' : _kind.label;
  String get _partyLabel => _buy ? 'فروشنده' : 'خریدار';
  Color get _kindColor => switch (_kind) {
        InvoiceKind.sale => AppColors.income,
        InvoiceKind.purchase => AppColors.expense,
        _ => AppColors.loan,
      };

  List<_Line> get _rows => _tab == 0 ? _lines : _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    final e = widget.edit;
    _proforma = e?.proforma ?? widget.proforma;
    final now = DateTime.now();
    if (e != null) {
      _kind = e.kind;
      _date = e.date;
      _due = e.dueDate;
      _person = e.personId;
      _number.text = '${e.number}';
      _discount = e.discount;
      _extra = e.extra;
      _note = e.note;
      _warehouseNo.text = e.info['warehouseNo'] ?? '';
      _requestNo.text = e.info['requestNo'] ?? '';
      _babat.text = e.info['babat'] ?? '';
      _address.text = e.info['address'] ?? '';
      _region.text = e.info['region'] ?? '';
      _buyerName.text = e.info['buyerName'] ?? '';
      _receiver = e.info['receiver'] ?? '';
      _saleDate = DateTime.tryParse(e.info['saleDate'] ?? '') ?? e.date;
      for (final l in e.lines) {
        (l.productId == null ? _services : _lines).add(_Line.from(l));
      }
    } else {
      _kind = _proforma ? InvoiceKind.sale : widget.kind;
      _date = DateTime(now.year, now.month, now.day);
      _saleDate = _date;
      _number.text = '${store.nextInvoiceNumber(_kind, proforma: _proforma)}';
      _warehouseNo.text = '${_nextWarehouseNo(store)}';
    }
    if (_lines.isEmpty) _lines.add(_Line());
    if (_services.isEmpty) _services.add(_Line());
    for (final l in [..._lines, ..._services]) {
      _listen(l);
    }
  }

  int _nextWarehouseNo(AppStore s) => s.invoices.fold<int>(1, (n, i) => i.warehouseNo >= n ? i.warehouseNo + 1 : n);

  void _listen(_Line l) {
    for (final c in [l.qty, l.price, l.discount, l.title]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_number, _warehouseNo, _requestNo, _babat, _address, _region, _buyerName]) {
      c.dispose();
    }
    for (final l in [..._lines, ..._services]) {
      l.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ totals

  int get _goodsTotal => _lines.fold(0, (s, l) => s + l.total);
  int get _servicesTotal => _services.fold(0, (s, l) => s + l.total);
  int get _lineDiscounts => [..._lines, ..._services].fold(0, (s, l) => s + l.d);
  int get _subtotal => _goodsTotal + _servicesTotal;
  int get _total => _subtotal - _discount + _extra;
  int get _itemCount => [..._lines, ..._services].where((l) => !l.isEmpty).length;

  double _weight(AppStore s) => _lines.fold(0.0, (a, l) => a + l.q * (s.product(l.productId)?.weight ?? 0));

  // ------------------------------------------------------------------ rows

  void _addLine() {
    final l = _Line();
    _listen(l);
    setState(() {
      _rows.add(l);
      _selRow = _rows.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => l.titleFocus.requestFocus());
  }

  void _removeRow() {
    final i = _selRow;
    if (i == null || i >= _rows.length) return toast(context, 'ردیفی انتخاب نشده', error: true);
    setState(() {
      _rows.removeAt(i).dispose();
      if (_rows.isEmpty) {
        final n = _Line();
        _listen(n);
        _rows.add(n);
      }
      _selRow = null;
    });
  }

  Future<void> _pickProduct(_Line l, Product p) async {
    setState(() {
      l.productId = p.id;
      l.title.text = p.name;
      final price = _buy ? p.buyPrice : p.sellPrice;
      if (price > 0) l.price.text = groupDigits(price);
      _selRow = _lines.indexOf(l);
    });
    // Sakan asks for the quantity and the unit price right away
    final q = await showQtyDialog(context, product: p, personId: _person, warehouseId: l.warehouseId, initial: l.q, buy: _buy);
    if (q != null && mounted) setState(() => l.qty.text = fmtQty(q));
    if (!_buy && mounted) await _pickPrice(l, p);
    if (mounted && identical(l, _lines.last)) _addLine();
  }

  Future<void> _pickPrice(_Line l, Product p) async {
    final v = await showUnitPriceDialog(context, product: p, personId: _person, current: l.p);
    if (v != null && mounted) setState(() => l.price.text = groupDigits(v));
  }

  Future<void> _editQty(_Line l) async {
    final p = StoreScope.read(context).product(l.productId);
    if (p == null) return;
    final q = await showQtyDialog(context, product: p, personId: _person, warehouseId: l.warehouseId, initial: l.q, buy: _buy);
    if (q != null && mounted) setState(() => l.qty.text = fmtQty(q));
  }

  // ------------------------------------------------------------------ header actions

  Future<String?> _ask(String title, String label, {String initial = '', bool number = false}) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => FormDialog(
        title: title,
        width: 440,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('تایید')),
        ],
        child: TextField(
          controller: c,
          autofocus: true,
          textDirection: number ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => Navigator.pop(ctx, c.text),
        ),
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _docDetails() async {
    final r = await _ask('مشخصات سند', 'توضیحات / شرح سند', initial: _note);
    if (r != null) setState(() => _note = r.trim());
  }

  Future<void> _pickPerson() async {
    final s = StoreScope.read(context);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => _PersonPicker(people: s.peopleSorted, title: 'انتخاب $_partyLabel'),
    );
    if (id == null || !mounted) return;
    if (id == '+') {
      final n = await showPersonDialog(context);
      if (n != null) setState(() => _person = n);
      return;
    }
    setState(() => _person = id);
  }

  Future<void> _priceIncrease() async {
    final r = await _ask('% افزایش فی', 'درصد افزایش (برای کاهش عدد منفی وارد کنید)', number: true);
    final pct = double.tryParse(normalizeDigits(r ?? '').replaceAll('٫', '.'));
    if (pct == null) return;
    setState(() {
      for (final l in [..._lines, ..._services]) {
        if (l.p > 0) l.price.text = groupDigits((l.p * (1 + pct / 100)).round());
      }
    });
  }

  Future<void> _applyDiscount({required bool percent}) async {
    final r = await _ask(percent ? 'تخفیف درصدی' : 'تخفیف مبلغی', percent ? 'درصد تخفیف کل فاکتور' : 'مبلغ تخفیف کل فاکتور',
        initial: percent ? '' : (_discount == 0 ? '' : groupDigits(_discount)), number: true);
    if (r == null) return;
    setState(() {
      if (percent) {
        final pct = double.tryParse(normalizeDigits(r).replaceAll('٫', '.')) ?? 0;
        _discount = (_subtotal * pct / 100).round();
      } else {
        _discount = parseMoney(r);
      }
    });
  }

  Future<void> _costs() async {
    final r = await _ask('هزینه ها', 'هزینه حمل و سایر هزینه‌های فاکتور', initial: _extra == 0 ? '' : groupDigits(_extra), number: true);
    if (r != null) setState(() => _extra = parseMoney(r));
  }

  Future<void> _fromProforma() async {
    final s = StoreScope.read(context);
    final list = s.invoices.where((i) => i.proforma && (_person == null || i.personId == _person)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) return toast(context, 'پیش فاکتوری برای این طرف حساب نیست', error: true);
    final pf = await showDialog<Invoice>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'اطلاعات پیش فاکتور',
        width: 560,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
        child: Column(children: [
          for (final i in list)
            ListTile(
              title: Text('پیش فاکتور ${i.number} — ${s.person(i.personId)?.name ?? 'متفرقه'}'),
              subtitle: Text('${jFormat(i.date)} — ${i.lines.length} ردیف'),
              trailing: Money(i.total),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (pf == null || !mounted) return;
    setState(() {
      _person ??= pf.personId;
      for (final l in pf.lines) {
        final n = _Line.from(l);
        _listen(n);
        (l.productId == null ? _services : _lines).insert((l.productId == null ? _services : _lines).length - 1, n);
      }
    });
  }

  void _search() async {
    final q = await _ask('جستجو', 'نام یا کد کالا');
    if (q == null || q.trim().isEmpty || !mounted) return;
    final s = StoreScope.read(context);
    final t = normalizeDigits(q.trim()).toLowerCase();
    final i = _rows.indexWhere((l) =>
        l.title.text.toLowerCase().contains(t) || (s.product(l.productId)?.code.toLowerCase().contains(t) ?? false));
    if (i < 0) return toast(context, 'کالایی با این عبارت در فاکتور نیست', error: true);
    setState(() => _selRow = i);
  }

  void _rowsSummary() {
    final s = StoreScope.read(context);
    final rows = [..._lines, ..._services].where((l) => !l.isEmpty).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'ردیف کالاها',
        width: 600,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        child: Column(children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 30, child: Text('${i + 1}')),
                Expanded(child: Text(rows[i].title.text)),
                SizedBox(width: 80, child: Text('${fmtQty(rows[i].q)} ${s.product(rows[i].productId)?.unit ?? ''}')),
                SizedBox(width: 120, child: Align(alignment: Alignment.centerLeft, child: Money(rows[i].total))),
              ]),
            ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ temp file

  File _tempFile(AppStore s) => File('${s.storage.dir.path}${Storage.sep}draft_${_proforma ? 'proforma' : _kind.name}.json');

  void _saveTemp() {
    final s = StoreScope.read(context);
    _tempFile(s).writeAsStringSync(jsonEncode({
      'person': _person,
      'lines': [..._lines, ..._services].where((l) => !l.isEmpty).map((l) => l.toJson()).toList(),
      'discount': _discount,
      'extra': _extra,
      'note': _note,
      'babat': _babat.text,
      'address': _address.text,
    }));
    toast(context, 'در فایل موقت ثبت شد');
  }

  void _loadTemp() {
    final s = StoreScope.read(context);
    final f = _tempFile(s);
    if (!f.existsSync()) return toast(context, 'فایل موقتی وجود ندارد', error: true);
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    setState(() {
      _person = j['person'] as String?;
      _discount = (j['discount'] as num?)?.toInt() ?? 0;
      _extra = (j['extra'] as num?)?.toInt() ?? 0;
      _note = '${j['note'] ?? ''}';
      _babat.text = '${j['babat'] ?? ''}';
      _address.text = '${j['address'] ?? ''}';
      for (final l in [..._lines, ..._services]) {
        l.dispose();
      }
      _lines.clear();
      _services.clear();
      for (final x in (j['lines'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
        final il = InvoiceLine.fromJson(x);
        final n = _Line.from(il);
        _listen(n);
        (il.productId == null ? _services : _lines).add(n);
      }
      for (final list in [_lines, _services]) {
        final n = _Line();
        _listen(n);
        list.add(n);
      }
    });
  }

  // ------------------------------------------------------------------ save

  Future<Invoice?> _save({bool close = true, bool settle = true, bool draft = false}) async {
    final store = StoreScope.read(context);
    final lines = [..._lines, ..._services].where((l) => !l.isEmpty).toList();
    String? err;
    if (lines.isEmpty) {
      err = 'حداقل یک ردیف کالا یا خدمت وارد کنید';
    } else if (lines.any((l) => l.q <= 0)) {
      err = 'تعداد هر ردیف باید بیشتر از صفر باشد';
    } else if (lines.any((l) => l.title.text.trim().isEmpty && l.productId == null)) {
      err = 'شرح یا نام کالای هر ردیف را وارد کنید';
    } else if (_total < 0) {
      err = 'مبلغ نهایی منفی است؛ تخفیف را بررسی کنید';
    } else if (!_proforma && !_legacy && !settle && !draft && _person == null) {
      err = 'فاکتور متفرقه بدون تسویه ثبت نمی‌شود؛ $_partyLabel را انتخاب کنید یا «تایید F9» را بزنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return null;
    }
    List<PayItem> items = const [];
    if (!_proforma && !_legacy && settle) {
      final signed = _kind.txnType.personSign * _total;
      final before = _person == null ? 0 : store.personBalance(_person!, excludeInvoiceId: (_saved ?? widget.edit)?.id);
      final r = await showPayMethodsDialog(
        context,
        personId: _person,
        items: _preItems ?? const [],
        before: before,
        docAmount: signed,
        receiveSide: _kind.moneyIn,
        title: '${_kind.moneyIn ? 'نحوه دریافت' : 'نحوه پرداخت'} — $_title',
        skipLabel: _person == null ? null : 'ثبت فاکتور بدون ${_kind.moneyIn ? 'دریافت' : 'پرداخت'}',
      );
      if (r == null || !mounted) return null;
      if (_person == null && signed + sumPayments(r) - sumReceipts(r) != 0) {
        setState(() => _err = 'فاکتور کامل تسویه نشده؛ برای ثبت مانده (نسیه) $_partyLabel را انتخاب کنید');
        return null;
      }
      items = r;
    }
    final inv = _saved ?? widget.edit ?? Invoice(id: newId(), kind: _kind, number: 0, date: _date);
    inv
      ..kind = _kind
      ..proforma = _proforma
      ..number = int.tryParse(normalizeDigits(_number.text.trim())) ?? store.nextInvoiceNumber(_kind, proforma: _proforma)
      ..date = _date
      ..dueDate = _due
      ..personId = _person
      ..lines = lines.map((l) => l.toLine()).toList()
      ..discount = _discount
      ..extra = _extra
      ..note = _note
      ..info = ({
        ...inv.info,
        'warehouseNo': normalizeDigits(_warehouseNo.text.trim()),
        'requestNo': _requestNo.text.trim(),
        'babat': _babat.text.trim(),
        'address': _address.text.trim(),
        'region': _region.text.trim(),
        'receiver': _receiver,
        'buyerName': _person == null ? _buyerName.text.trim() : '',
        'saleDate': _saleDate.toIso8601String(),
      }..removeWhere((_, v) => v.isEmpty));
    if (!_legacy) {
      inv
        ..paid = 0
        ..accountId = null;
    }
    store.saveInvoice(inv);
    if (items.isNotEmpty) saveInvoiceSettlement(store, inv, items);
    _preItems = null;
    if (close) {
      if (mounted) {
        Navigator.pop(context);
        toast(context, '$_title شماره ${inv.number} ذخیره شد');
      }
    } else if (mounted) {
      setState(() {
        _saved = inv;
        _err = null;
      });
    }
    return inv;
  }

  /// تایید و چاپ — save, then show the printout.
  Future<void> _saveAndPrint(List<PrintDocType> types) async {
    final nav = Navigator.of(context);
    final inv = await _save(close: false);
    if (inv == null || !mounted) return;
    nav.pop();
    for (final t in types) {
      if (!nav.context.mounted) return;
      await previewInvoice(nav.context, inv, t);
    }
  }

  Future<void> _financial() async {
    final signed = _kind.txnType.personSign * _total;
    final s = StoreScope.read(context);
    final before = _person == null ? 0 : s.personBalance(_person!, excludeInvoiceId: (_saved ?? widget.edit)?.id);
    final r = await showPayMethodsDialog(
      context,
      personId: _person,
      items: _preItems ?? const [],
      before: before,
      docAmount: signed,
      receiveSide: _kind.moneyIn,
      title: 'عملیات مالی — $_title',
    );
    if (r != null) setState(() => _preItems = r);
  }

  Future<void> _navigate(int dir) async {
    final s = StoreScope.read(context);
    final list = s.invoices.where((i) => i.kind == _kind && i.proforma == _proforma).toList()..sort((a, b) => a.number.compareTo(b.number));
    if (list.isEmpty) return;
    final cur = int.tryParse(normalizeDigits(_number.text)) ?? 0;
    final target = dir < 0 ? list.where((i) => i.number < cur).lastOrNull : list.where((i) => i.number > cur).firstOrNull;
    if (target == null) return toast(context, dir < 0 ? 'فاکتور قبلی وجود ندارد' : 'فاکتور بعدی وجود ندارد');
    final nav = Navigator.of(context);
    nav.pop();
    await showInvoiceEditor(nav.context, edit: target);
  }

  Future<void> _convert() async {
    final inv = await _save(close: false);
    if (inv == null || !mounted) return;
    final sale = StoreScope.read(context).convertProforma(inv);
    final nav = Navigator.of(context);
    nav.pop();
    showInvoiceEditor(nav.context, edit: sale);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'حذف فاکتور', 'این فاکتور و ثبت‌های مالی و انبار آن حذف شود؟');
    if (!ok || !mounted) return;
    StoreScope.read(context).removeInvoice(widget.edit!.id);
    Navigator.pop(context);
  }

  Future<void> _close() async {
    final dirty = [..._lines, ..._services].any((l) => !l.isEmpty) && !_isEdit && _saved == null;
    if (dirty) {
      final ok = await confirm(context, 'بستن فاکتور', 'اطلاعات واردشده ذخیره نشده. بسته شود؟', ok: 'بستن بدون ذخیره');
      if (!ok || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  // ------------------------------------------------------------------ UI helpers

  Widget _btn(String label, VoidCallback? onTap, {String key = '', double? width, Color? color, IconData? icon, bool dropdown = false}) {
    final b = Material(
      color: color ?? const Color(0xFFDCE8F7),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF9DB7DA))),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: const Color(0xFF1F3B63)), const SizedBox(width: 4)],
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: onTap == null ? Colors.black38 : const Color(0xFF1F3B63))),
            ),
            if (key.isNotEmpty) ...[const SizedBox(width: 6), Text(key, style: const TextStyle(fontSize: 11, color: Color(0xFFC62828), fontWeight: FontWeight.w700))],
            if (dropdown) const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ]),
        ),
      ),
    );
    return width == null ? b : SizedBox(width: width, child: b);
  }

  Widget _field(TextEditingController c, {double? width, bool ltr = false, bool readOnly = false}) {
    final f = SizedBox(
      height: 34,
      child: TextField(
        controller: c,
        readOnly: readOnly,
        textDirection: ltr ? TextDirection.ltr : null,
        textAlign: ltr ? TextAlign.center : TextAlign.start,
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      ),
    );
    return width == null ? Expanded(child: f) : SizedBox(width: width, child: f);
  }

  Widget _valueBox(String text, {double? width, Color? color, bool bold = true, TextDirection? dir}) {
    final b = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(color: color ?? Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)),
      child: Text(text, textDirection: dir, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
    );
    return width == null ? Expanded(child: b) : SizedBox(width: width, child: b);
  }

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)));

  Widget _dateBox(DateTime v, ValueChanged<DateTime> on, {double width = 160}) => SizedBox(
        width: width,
        height: 40,
        child: DateField(label: '', value: v, onChanged: (d) => on(d ?? v)),
      );

  Widget _sum(String label, String value, {double width = 150, Widget? trailing}) => Row(mainAxisSize: MainAxisSize.min, children: [
        _lbl(label),
        _valueBox(value, width: width, dir: TextDirection.ltr),
        if (trailing != null) trailing,
      ]);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final person = store.person(_person);

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f1): _docDetails,
      const SingleActivator(LogicalKeyboardKey.f2): _pickPerson,
      const SingleActivator(LogicalKeyboardKey.f3): () => showComingSoon(context, 'انتخاب تیم بازاریابی'),
      const SingleActivator(LogicalKeyboardKey.f7): () => setState(() => _person = null),
      const SingleActivator(LogicalKeyboardKey.f5): () => _saveAndPrint([PrintDocType.invoice]),
      const SingleActivator(LogicalKeyboardKey.f8): () => _saveAndPrint([PrintDocType.invoice, PrintDocType.warehouse]),
      const SingleActivator(LogicalKeyboardKey.f9): () => _save(),
      const SingleActivator(LogicalKeyboardKey.f10): _close,
      const SingleActivator(LogicalKeyboardKey.f11): _financial,
      const SingleActivator(LogicalKeyboardKey.f12): () async {
        final inv = await _save(close: false, settle: false, draft: true);
        if (inv != null && mounted) await showReportBuilder(context, inv, PrintDocType.invoice);
      },
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(settle: false),
      const SingleActivator(LogicalKeyboardKey.insert): _addLine,
      const SingleActivator(LogicalKeyboardKey.escape): _close,
    };

    final headerBg = const Color(0xFFC9DCF2);
    return CallbackShortcuts(
      bindings: bindings,
      child: Dialog(
        insetPadding: const EdgeInsets.all(10),
        clipBehavior: Clip.antiAlias,
        backgroundColor: const Color(0xFFE6EEF8),
        child: SizedBox(
          width: size.width - 20,
          height: size.height - 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ---------------------------------------------------------- title bar
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [_kindColor, Color.lerp(_kindColor, Brand.of(context).partner, 0.55)!])),
              child: Row(children: [
                Icon(txnIcon(_kind.txnType), color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('${_isEdit ? 'ویرایش ' : ''}$_title', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                if (_isEdit)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                    label: const Text('حذف فاکتور', style: TextStyle(color: Colors.white)),
                  ),
                if (_proforma)
                  TextButton.icon(
                    onPressed: _convert,
                    icon: const Icon(Icons.transform_rounded, color: Colors.white, size: 18),
                    label: const Text('تبدیل به فاکتور فروش', style: TextStyle(color: Colors.white)),
                  ),
                IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded, color: Colors.white)),
              ]),
            ),
            // ---------------------------------------------------------- header rows
            Container(
              color: headerBg,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(children: [
                Row(children: [
                  _btn('مشخصات سند', _docDetails, key: 'F1', width: 160),
                  _lbl('شماره سند'),
                  _valueBox(_isEdit ? '${store.docNumberOf('inv:${widget.edit!.id}') ?? ''}' : '${store.nextVoucherNumber()}', width: 110, dir: TextDirection.ltr),
                  _lbl('شماره درخواست'),
                  _field(_requestNo, width: 110, ltr: true),
                  const SizedBox(width: 6),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    _orangeCheck('از بزرگترین', _fromBig, (v) => setState(() => _fromBig = v)),
                    const SizedBox(height: 2),
                    _orangeCheck('از کوچکترین', _fromSmall, (v) => setState(() => _fromSmall = v)),
                  ]),
                  const SizedBox(width: 10),
                  _btn('% افزایش فی', _priceIncrease, dropdown: true),
                  _lbl('شماره حواله انبار'),
                  _field(_warehouseNo, width: 110, ltr: true),
                  const Spacer(),
                  _btn('بخش تنظیمات فاکتور', () => showComingSoon(context, 'بخش تنظیمات فاکتور')),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _btn(_receiver.isEmpty ? 'تحویل گیرنده' : 'تحویل گیرنده: $_receiver', () async {
                    final r = await _ask('تحویل گیرنده', 'نام تحویل گیرنده', initial: _receiver);
                    if (r != null) setState(() => _receiver = r.trim());
                  }, width: 160, color: const Color(0xFFE8F0FB)),
                  _lbl('تاریخ فاکتور'),
                  _dateBox(_date, (d) => setState(() => _date = d)),
                  _lbl('شماره فاکتور'),
                  _field(_number, width: 110, ltr: true),
                  _lbl('بابت:'),
                  _field(_babat),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _btn(_partyLabel, _pickPerson, key: 'F2', width: 160),
                  const SizedBox(width: 6),
                  if (_person == null)
                    _field(_buyerName, width: 260)
                  else
                    _valueBox(person?.name ?? '', width: 260),
                  _lbl('منطقه:'),
                  _field(_region, width: 140),
                  _lbl('آدرس:'),
                  _field(_address),
                  _lbl('با رقم اعشار'),
                  SizedBox(
                    width: 70,
                    child: DropdownButtonFormField<int>(
                      value: _decimals,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      items: [for (var i = 0; i <= 3; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                      onChanged: (v) => setState(() => _decimals = v ?? 0),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _btn('متفرقه', () => setState(() => _person = null), key: 'F7', width: 160, color: _person == null ? const Color(0xFFFFE0B2) : null),
                  _lbl('عنوان حساب'),
                  _valueBox(person?.name ?? (_buyerName.text.isEmpty ? _partyLabel : _buyerName.text), width: 220, color: const Color(0xFFFFFFFF)),
                  _lbl('معین حساب:'),
                  _valueBox(_person == null ? 'متفرقه' : (_buy ? 'بستانکاران تجاری' : 'بدهکاران تجاری'), width: 170, bold: false),
                  _lbl(_buy ? 'تاریخ خرید:' : 'تاریخ فروش:'),
                  _dateBox(_saleDate, (d) => setState(() => _saleDate = d)),
                  const SizedBox(width: 8),
                  _btn('اعمال مدل های تخفیفات و جوایز', () => showComingSoon(context, 'اعمال مدل های تخفیفات و جوایز')),
                  const SizedBox(width: 6),
                  _btn('انتخاب تیم بازاریابی', () => showComingSoon(context, 'انتخاب تیم بازاریابی'), key: 'F3'),
                  if (person != null) ...[
                    const Spacer(),
                    Text('مانده: ', style: th.textTheme.bodySmall),
                    Money(store.personBalance(person.id), colorBySign: true, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ]),
              ]),
            ),
            // ---------------------------------------------------------- tabs
            Container(
              color: const Color(0xFFDDE7F3),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(children: [
                _tabChip('اقلام کالا', '1', 0, const Color(0xFFFFC857)),
                _tabChip('فروش خدمات', '3', 1, const Color(0xFF7CCB7C)),
                const Spacer(),
                _lbl('تعداد اقلام:'),
                _valueBox('$_itemCount', width: 70, dir: TextDirection.ltr),
                const SizedBox(width: 8),
                _btn('جستجو', _search),
                const SizedBox(width: 4),
                _btn('اطلاعات پیش فاکتور', _fromProforma),
                const SizedBox(width: 4),
                _btn('ردیف کالاها', _rowsSummary),
                const SizedBox(width: 4),
                _btn('رنگ ردیف ها جدول', () => setState(() => _zebra = !_zebra)),
              ]),
            ),
            // ---------------------------------------------------------- grid
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF9DB7DA))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _gridHeader(th),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _rows.length,
                      itemBuilder: (context, i) => _gridRow(context, store, i),
                    ),
                  ),
                ]),
              ),
            ),
            // ---------------------------------------------------------- green bar
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFB9DFA0), borderRadius: BorderRadius.circular(6)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _btn('چاپ بارکد', () async {
                    final inv = await _save(close: false, settle: false, draft: true);
                    if (inv != null && mounted) await showReportBuilder(context, inv, PrintDocType.barcode);
                  }, dropdown: true, icon: Icons.qr_code_2_rounded),
                  const SizedBox(width: 6),
                  _btn('تسویه امانی', () => showComingSoon(context, 'تسویه امانی')),
                  const SizedBox(width: 6),
                  PopupMenuButton<bool>(
                    tooltip: 'اعمال تخفیف',
                    onSelected: (p) => _applyDiscount(percent: p),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('تخفیف درصدی')),
                      PopupMenuItem(value: false, child: Text('تخفیف مبلغی')),
                    ],
                    child: IgnorePointer(child: _btn('اعمال تخفیف', () {}, dropdown: true)),
                  ),
                  _sum('جمع تخفیف', groupDigits(_discount + _lineDiscounts),
                      width: 130,
                      trailing: IconButton(
                        tooltip: 'تخفیف درصدی',
                        onPressed: () => _applyDiscount(percent: true),
                        icon: const Icon(Icons.percent_rounded, size: 18),
                      )),
                  _sum('جمع عوارض', '0', width: 100),
                  _sum('جمع مالیات', '0', width: 100),
                  _sum('جمع وزن اقلام', fmtQty(_weight(store)), width: 90),
                  const SizedBox(width: 10),
                  _btn('حذف ردیف', _removeRow, icon: Icons.close_rounded, color: const Color(0xFFFFE5E5)),
                ]),
              ),
            ),
            // ---------------------------------------------------------- blue bar
            Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFB7CDEA), borderRadius: BorderRadius.circular(6)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _btn('قبلی', () => _navigate(-1), width: 80),
                  const SizedBox(width: 4),
                  _btn('بعدی', () => _navigate(1), width: 80),
                  _sum('جمع اقلام کالا', groupDigits(_goodsTotal)),
                  _sum('جمع اقلام خدماتی', groupDigits(_servicesTotal)),
                  _sum('هزینه حمل', groupDigits(_extra), width: 110),
                  _sum('جمع تخفیف', groupDigits(_discount + _lineDiscounts), width: 120),
                  _lbl('جمع فاکتور'),
                  Container(
                    height: 38,
                    width: 190,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: _kindColor, width: 2)),
                    child: Text(groupDigits(_total), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _kindColor)),
                  ),
                  _lbl(store.settings.currency),
                ]),
              ),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Text(_err!, style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w700)),
              ),
            if (_preItems != null && _preItems!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: Text('عملیات مالی تعیین شده: دریافت ${groupDigits(sumReceipts(_preItems!))} — پرداخت ${groupDigits(sumPayments(_preItems!))}',
                    style: th.textTheme.bodySmall?.copyWith(color: AppColors.income)),
              ),
            // ---------------------------------------------------------- bottom buttons
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFD3E2F4), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  _btn('خواندن از فایل موقت', _loadTemp, width: 170),
                  const SizedBox(height: 4),
                  _btn('ثبت در فایل موقت', _saveTemp, width: 170),
                ]),
                const SizedBox(width: 8),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Builder(
                    builder: (bctx) => _btn('تعیین نوع چاپ', () => showPrintTypeMenu(bctx, () => _save(close: false, settle: false, draft: true)),
                        key: 'F12', width: 220, dropdown: true, icon: Icons.print_outlined),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _btn('هزینه ها', _costs, width: 104),
                    const SizedBox(width: 4),
                    _btn('عملیات مالی', _proforma ? null : _financial, key: 'F11', width: 112),
                  ]),
                ]),
                const Spacer(),
                const Text('تایید و چاپ', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  _btn('فاکتور و حواله انبار', () => _saveAndPrint([PrintDocType.invoice, PrintDocType.warehouse]), key: 'F8', width: 230),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _btn('فاکتور', () => _saveAndPrint([PrintDocType.invoice]), key: 'F5', width: 113),
                    const SizedBox(width: 4),
                    _btn('حواله انبار', () => _saveAndPrint([PrintDocType.warehouse]), width: 113),
                  ]),
                ]),
                const SizedBox(width: 12),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  _btn(_proforma ? 'ذخیره پیش فاکتور' : 'تایید', () => _save(settle: !_proforma),
                      key: 'F9', width: 150, icon: Icons.check_circle_rounded, color: const Color(0xFFD7F2D7)),
                  const SizedBox(height: 4),
                  _btn('انصراف', _close, key: 'F10', width: 150, icon: Icons.cancel_rounded, color: const Color(0xFFFBE0E0)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _orangeCheck(String label, bool v, ValueChanged<bool> on) => InkWell(
        onTap: () => on(!v),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFFFC98B), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFD08A3C))),
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          SizedBox(width: 26, height: 20, child: Checkbox(value: v, visualDensity: VisualDensity.compact, onChanged: (x) => on(x ?? false))),
        ]),
      );

  Widget _tabChip(String label, String n, int index, Color color) {
    final sel = _tab == index;
    return InkWell(
      onTap: () => setState(() {
        _tab = index;
        _selRow = null;
      }),
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 2),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? color : color.withValues(alpha: 0.45),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          border: Border.all(color: color.withValues(alpha: 0.9)),
        ),
        child: Text('$label $n', style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
      ),
    );
  }

  static const _wPrint = 44.0;
  static const _wIdx = 50.0;
  static const _wWh = 120.0;
  static const _wQty = 90.0;
  static const _wUnit = 70.0;
  static const _wPrice = 160.0;
  static const _wDisc = 110.0;
  static const _wTotal = 160.0;

  Widget _gridHeader(ThemeData th) {
    final goods = _tab == 0;
    return Container(
      color: const Color(0xFFF6C66A),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DefaultTextStyle(
        style: th.textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w800),
        child: Row(children: [
          Container(
            width: _wPrint,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 2),
            color: const Color(0xFFE53935),
            child: const Text('چاپ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: _wIdx, child: Text('ردیف', textAlign: TextAlign.center)),
          Expanded(child: Text(goods ? 'نام کالا' : 'شرح خدمات')),
          if (goods) const SizedBox(width: _wWh, child: Text('نام انبار', textAlign: TextAlign.center)),
          const SizedBox(width: _wQty, child: Text('تعداد', textAlign: TextAlign.center)),
          if (goods) const SizedBox(width: _wUnit, child: Text('واحد', textAlign: TextAlign.center)),
          const SizedBox(width: _wPrice, child: Text('بهای واحد ریال', textAlign: TextAlign.center)),
          const SizedBox(width: _wDisc, child: Text('تخفیف', textAlign: TextAlign.center)),
          const SizedBox(width: _wTotal, child: Text('جمع', textAlign: TextAlign.center)),
        ]),
      ),
    );
  }

  Widget _gridRow(BuildContext context, AppStore store, int i) {
    final th = Theme.of(context);
    final goods = _tab == 0;
    final l = _rows[i];
    final p = store.product(l.productId);
    final sel = _selRow == i;
    final multiWh = store.warehouses.length > 1;
    String? stockInfo;
    var warn = false;
    if (p != null) {
      final st = store.stock(p.id, excludeInvoiceId: widget.edit?.id, warehouseId: multiWh ? store.whId(l.warehouseId) : null);
      stockInfo = 'موجودی ${fmtQty(st)}';
      if (_kind.stockSign < 0 && l.q > st) warn = true;
    }
    const dense = InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10));
    final cellBorder = BoxDecoration(border: Border(left: BorderSide(color: Colors.black.withValues(alpha: 0.08))));
    return GestureDetector(
      onTap: () => setState(() => _selRow = i),
      child: Container(
        color: sel
            ? const Color(0xFF2F6FED).withValues(alpha: 0.18)
            : (_zebra && i.isOdd ? const Color(0xFFF3F7FC) : Colors.white),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(width: _wPrint + 4, height: 40, color: sel ? const Color(0xFFF6C66A) : null, child: sel ? const Icon(Icons.arrow_left_rounded) : null),
          SizedBox(width: _wIdx, child: Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: Container(
              decoration: cellBorder,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                if (goods)
                  _ProductField(
                    key: ObjectKey(l),
                    line: l,
                    products: store.productsSorted.where((x) => !x.archived).toList(),
                    onPick: (p) => _pickProduct(l, p),
                    onTyped: () {
                      final cur = store.product(l.productId);
                      if (cur != null && cur.name != l.title.text) setState(() => l.productId = null);
                    },
                  )
                else
                  TextField(controller: l.title, focusNode: l.titleFocus, decoration: dense.copyWith(hintText: 'شرح خدمت')),
                if (stockInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 2),
                    child: Text(warn ? '$stockInfo — بیشتر از موجودی' : stockInfo,
                        style: th.textTheme.labelSmall?.copyWith(color: warn ? th.colorScheme.error : th.hintColor)),
                  ),
              ]),
            ),
          ),
          if (goods)
            Container(
              width: _wWh,
              decoration: cellBorder,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: multiWh
                  ? DropdownButtonFormField<String>(
                      value: store.whId(l.warehouseId),
                      isExpanded: true,
                      isDense: true,
                      decoration: dense,
                      items: [for (final w in store.warehouses) DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => l.warehouseId = v),
                    )
                  : Text(store.warehouse(l.warehouseId)?.name ?? '', textAlign: TextAlign.center),
            ),
          Container(
            width: _wQty,
            decoration: cellBorder,
            child: TextField(
              controller: l.qty,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: dense.copyWith(
                suffixIcon: p == null
                    ? null
                    : InkWell(onTap: () => _editQty(l), child: const Icon(Icons.more_horiz_rounded, size: 16)),
                suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              ),
            ),
          ),
          if (goods)
            Container(width: _wUnit, decoration: cellBorder, child: Text(p?.unit ?? '', textAlign: TextAlign.center)),
          Container(
            width: _wPrice,
            decoration: cellBorder,
            child: TextField(
              controller: l.price,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              inputFormatters: [MoneyInputFormatter()],
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: dense.copyWith(
                prefixIcon: p == null
                    ? null
                    : InkWell(
                        onTap: () => _pickPrice(l, p),
                        child: Tooltip(message: 'تعیین فی', child: Icon(Icons.price_change_outlined, size: 18, color: th.colorScheme.primary)),
                      ),
                prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ),
          ),
          Container(
            width: _wDisc,
            decoration: cellBorder,
            child: TextField(
              controller: l.discount,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              inputFormatters: [MoneyInputFormatter()],
              decoration: dense,
            ),
          ),
          Container(
            width: _wTotal,
            decoration: cellBorder,
            alignment: Alignment.center,
            child: Text(groupDigits(l.total), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

class _PersonPicker extends StatefulWidget {
  final List<Person> people;
  final String title;
  const _PersonPicker({required this.people, required this.title});

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final list = widget.people.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.phone.contains(q)).toList();
    return FormDialog(
      title: widget.title,
      width: 560,
      leading: TextButton.icon(onPressed: () => Navigator.pop(context, '+'), icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('شخص جدید')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'جستجوی نام یا تلفن', prefixIcon: Icon(Icons.search_rounded)),
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
            subtitle: p.phone.isEmpty ? null : Text(p.phone),
            trailing: Money(s.personBalance(p.id), colorBySign: true),
            onTap: () => Navigator.pop(context, p.id),
          ),
      ]),
    );
  }
}

// ================================================================ تعیین تعداد

/// «تعیین تعداد» — quantity with the stock of the warehouse before and after.
Future<double?> showQtyDialog(BuildContext context,
        {required Product product, String? personId, String? warehouseId, double initial = 1, bool buy = false}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _QtyDialog(product: product, personId: personId, warehouseId: warehouseId, initial: initial, buy: buy),
    );

class _QtyDialog extends StatefulWidget {
  final Product product;
  final String? personId;
  final String? warehouseId;
  final double initial;
  final bool buy;
  const _QtyDialog({required this.product, this.personId, this.warehouseId, this.initial = 1, this.buy = false});

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _qty = TextEditingController(text: fmtQty(widget.initial <= 0 ? 1 : widget.initial));

  @override
  void initState() {
    super.initState();
    _qty.addListener(() {
      if (mounted) setState(() {});
    });
    _qty.selection = TextSelection(baseOffset: 0, extentOffset: _qty.text.length);
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _ok() {
    final q = parseQty(_qty.text);
    if (q <= 0) return;
    Navigator.pop(context, q);
  }

  Widget _num(String v) => Container(
        width: 130,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)),
        child: Text(v, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final p = widget.product;
    final multi = s.warehouses.length > 1;
    final wh = s.warehouse(widget.warehouseId);
    final stock = s.stock(p.id, warehouseId: multi ? s.whId(widget.warehouseId) : null);
    final pfQty = s.invoices.where((i) => i.proforma).expand((i) => i.lines).where((l) => l.productId == p.id).fold<double>(0, (a, l) => a + l.qty);
    final q = parseQty(_qty.text);
    final after = widget.buy ? stock + q : stock - q;
    Widget row(String label, String now, String afterOrders) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [SizedBox(width: 150, child: Text(label)), _num(now), const SizedBox(width: 10), _num(afterOrders)]),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => showProductHistory(context, p, mode: 0),
        const SingleActivator(LogicalKeyboardKey.f3): () => showProductHistory(context, p, personId: widget.personId, mode: 1),
        const SingleActivator(LogicalKeyboardKey.f4): () => showProductHistory(context, p, mode: 2),
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'تعیین تعداد — ${p.name}',
        width: 640,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
          FilledButton(onPressed: _ok, child: const Text('تایید F9')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton(onPressed: () => showComingSoon(context, 'وضعیت سفارش'), child: const Text('وضعیت سفارش')),
          OutlinedButton(onPressed: () => showProductHistory(context, p, mode: 0), child: const Text('کل فروش ها F2')),
          OutlinedButton(onPressed: () => showProductHistory(context, p, personId: widget.personId, mode: 1), child: const Text('کل فروش های طرف حساب F3')),
          OutlinedButton(onPressed: () => showProductHistory(context, p, mode: 2), child: const Text('کل خرید ها F4')),
        ]),
          const SizedBox(height: 12),
          Row(children: [const SizedBox(width: 150, child: Text('نام انبار:')), Text(wh?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 150),
            SizedBox(width: 130, child: Text('موجودی فعلی', textAlign: TextAlign.center, style: th.textTheme.labelSmall)),
            const SizedBox(width: 10),
            SizedBox(width: 130, child: Text('بعد از اعمال وضعیت سفارشات', textAlign: TextAlign.center, style: th.textTheme.labelSmall)),
          ]),
          row('موجودی واحد ${p.unit}:', fmtQty(stock), fmtQty(stock - pfQty)),
          row('موجودی واحد:', '0', '0'),
          row('موجودی امانی:', '0', '0'),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 150, child: Text('تعداد:', style: TextStyle(fontWeight: FontWeight.w800))),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _qty,
                autofocus: true,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _ok(),
              ),
            ),
            const SizedBox(width: 10),
            Text('واحد: ${p.unit}'),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 150, child: Text('مانده:')),
            _num(fmtQty(after)),
            const SizedBox(width: 10),
            Text('مانده پیش فاکتور: ${fmtQty(pfQty)} ${p.unit}', style: th.textTheme.bodySmall),
          ]),
          if (!widget.buy && after < 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('تعداد بیشتر از موجودی است', style: TextStyle(color: th.colorScheme.error)),
            ),
        ]),
      ),
    );
  }
}

/// Product search field with free-text fallback.
class _ProductField extends StatefulWidget {
  final _Line line;
  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onTyped;

  const _ProductField({
    super.key,
    required this.line,
    required this.products,
    required this.onPick,
    required this.onTyped,
  });

  @override
  State<_ProductField> createState() => _ProductFieldState();
}

class _ProductFieldState extends State<_ProductField> {
  double _width = 300;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      _width = c.maxWidth;
      return RawAutocomplete<Product>(
        textEditingController: widget.line.title,
        focusNode: widget.line.titleFocus,
        displayStringForOption: (p) => p.name,
        optionsBuilder: (v) {
          final q = normalizeDigits(v.text.trim()).toLowerCase();
          if (q.isEmpty) return widget.products.take(30);
          return widget.products.where((p) => p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q)).take(30);
        },
        onSelected: widget.onPick,
        fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
          controller: controller,
          focusNode: focus,
          onChanged: (_) => widget.onTyped(),
          onSubmitted: (_) => onSubmit(),
          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1F3BB3)),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: 'نام کالا یا کد را تایپ کنید',
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) {
          final store = StoreScope.of(context);
          final list = options.toList();
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 280, maxWidth: _width, minWidth: _width),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final highlighted = AutocompleteHighlightedOption.of(context) == i;
                    return InkWell(
                      onTap: () => onSelected(p),
                      child: Container(
                        color: highlighted ? th.colorScheme.primary.withValues(alpha: 0.08) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        child: Row(children: [
                          if (p.code.isNotEmpty) SizedBox(width: 60, child: Text(p.code, style: th.textTheme.labelSmall)),
                          Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                          Text('موجودی ${fmtQty(store.stock(p.id))}', style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                          const SizedBox(width: 12),
                          Money(p.sellPrice, style: th.textTheme.labelMedium),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
