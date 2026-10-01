import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../print.dart';
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

Future<void> showInvoiceEditor(BuildContext context,
    {Invoice? edit, InvoiceKind kind = InvoiceKind.sale, bool proforma = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InvoiceEditor(edit: edit, kind: kind, proforma: proforma),
  );
}

class _Line {
  String? productId;
  final title = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  final discount = TextEditingController();
  final titleFocus = FocusNode();

  _Line();

  factory _Line.from(InvoiceLine l) {
    final x = _Line();
    x.productId = l.productId;
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
      InvoiceLine(productId: productId, title: title.text.trim(), qty: q, unitPrice: p, discount: d);

  void dispose() {
    title.dispose();
    qty.dispose();
    price.dispose();
    discount.dispose();
    titleFocus.dispose();
  }
}

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
  late DateTime _date;
  DateTime? _due;
  String? _person;
  String? _account;
  final _number = TextEditingController();
  final _discount = TextEditingController();
  final _extra = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  final List<_Line> _lines = [];
  String? _err;
  bool _inited = false;
  late bool _proforma;
  Invoice? _saved;

  bool get _isEdit => widget.edit != null;

  String get _title => _proforma ? 'پیش‌فاکتور فروش' : _kind.label;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    final e = widget.edit;
    _proforma = e?.proforma ?? widget.proforma;
    if (e != null) {
      _kind = e.kind;
      _date = e.date;
      _due = e.dueDate;
      _person = e.personId;
      _account = e.accountId;
      _number.text = '${e.number}';
      _discount.text = e.discount == 0 ? '' : groupDigits(e.discount);
      _extra.text = e.extra == 0 ? '' : groupDigits(e.extra);
      _paid.text = e.paid == 0 ? '' : groupDigits(e.paid);
      _note.text = e.note;
      _lines.addAll(e.lines.map(_Line.from));
    } else {
      _kind = _proforma ? InvoiceKind.sale : widget.kind;
      final n = DateTime.now();
      _date = DateTime(n.year, n.month, n.day);
      _number.text = '${store.nextInvoiceNumber(_kind, proforma: _proforma)}';
      _account = _defaultAccount(store);
    }
    if (_lines.isEmpty) _lines.add(_Line());
    for (final c in [_discount, _extra, _paid]) {
      c.addListener(_refresh);
    }
    for (final l in _lines) {
      _listen(l);
    }
  }

  String? _defaultAccount(AppStore store) {
    final acc = store.activeAccounts;
    for (final a in acc) {
      if (a.type == AccountType.cash) return a.id;
    }
    return acc.isEmpty ? null : acc.first.id;
  }

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
    for (final c in [_number, _discount, _extra, _paid, _note]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _subtotal => _lines.fold(0, (s, l) => s + l.total);
  int get _total => _subtotal - parseMoney(_discount.text) + parseMoney(_extra.text);
  int get _paidV => parseMoney(_paid.text);

  void _addLine() {
    final l = _Line();
    _listen(l);
    setState(() => _lines.add(l));
    WidgetsBinding.instance.addPostFrameCallback((_) => l.titleFocus.requestFocus());
  }

  void _removeLine(int i) {
    setState(() {
      final l = _lines.removeAt(i);
      l.dispose();
      if (_lines.isEmpty) {
        final n = _Line();
        _listen(n);
        _lines.add(n);
      }
    });
  }

  void _pickProduct(_Line l, Product p) {
    setState(() {
      l.productId = p.id;
      l.title.text = p.name;
      final price = _kind.buySide ? p.buyPrice : p.sellPrice;
      if (price > 0) l.price.text = groupDigits(price);
    });
  }

  void _setKind(InvoiceKind k) {
    final store = StoreScope.read(context);
    setState(() {
      final wasDefault = !_isEdit && _number.text == '${store.nextInvoiceNumber(_kind, proforma: _proforma)}';
      _kind = k;
      if (wasDefault) _number.text = '${store.nextInvoiceNumber(k)}';
    });
  }

  Invoice? _save({bool again = false, bool close = true}) {
    final store = StoreScope.read(context);
    final lines = _lines.where((l) => !l.isEmpty).toList();
    String? err;
    if (lines.isEmpty) {
      err = 'حداقل یک ردیف کالا یا خدمت وارد کنید';
    } else if (lines.any((l) => l.q <= 0)) {
      err = 'تعداد هر ردیف باید بیشتر از صفر باشد';
    } else if (lines.any((l) => l.title.text.trim().isEmpty && l.productId == null)) {
      err = 'شرح یا نام کالای هر ردیف را وارد کنید';
    } else if (_total < 0) {
      err = 'مبلغ نهایی منفی است؛ تخفیف را بررسی کنید';
    } else if (_proforma) {
      // no payment rules for a pro-forma
    } else if (_paidV > _total) {
      err = 'مبلغ پرداختی از مبلغ فاکتور بیشتر است';
    } else if (_paidV > 0 && _account == null) {
      err = 'حساب پرداخت/دریافت را انتخاب کنید';
    } else if (_paidV < _total && _person == null) {
      err = 'فاکتور کامل تسویه نشده؛ برای ثبت مانده (نسیه) طرف حساب را انتخاب کنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return null;
    }
    final paid = _proforma ? 0 : _paidV;
    final inv = _saved ?? widget.edit ?? Invoice(id: newId(), kind: _kind, number: 0, date: _date);
    inv
      ..kind = _kind
      ..proforma = _proforma
      ..number = int.tryParse(normalizeDigits(_number.text.trim())) ?? store.nextInvoiceNumber(_kind, proforma: _proforma)
      ..date = _date
      ..dueDate = paid < _total ? _due : null
      ..personId = _person
      ..lines = lines.map((l) => l.toLine()).toList()
      ..discount = parseMoney(_discount.text)
      ..extra = parseMoney(_extra.text)
      ..paid = paid
      ..accountId = paid > 0 ? _account : null
      ..note = _note.text.trim();
    store.saveInvoice(inv);
    if (again) {
      setState(() {
        for (final l in _lines) {
          l.dispose();
        }
        _lines
          ..clear()
          ..add(_Line());
        _listen(_lines.first);
        _discount.clear();
        _extra.clear();
        _paid.clear();
        _note.clear();
        _due = null;
        _err = null;
        _saved = null;
        _number.text = '${store.nextInvoiceNumber(_kind, proforma: _proforma)}';
      });
      toast(context, '$_title ثبت شد');
    } else if (close) {
      Navigator.pop(context);
      toast(context, '$_title شماره ${inv.number} ذخیره شد');
    } else {
      setState(() {
        _saved = inv;
        _err = null;
      });
    }
    return inv;
  }

  void _print() {
    final inv = _save(close: false);
    if (inv == null) return;
    try {
      printInvoice(StoreScope.read(context), inv);
    } catch (e) {
      toast(context, 'چاپ ناموفق: $e', error: true);
    }
  }

  void _convert() {
    final inv = _save(close: false);
    if (inv == null) return;
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
    final dirty = _lines.any((l) => !l.isEmpty) && !_isEdit;
    if (dirty) {
      final ok = await confirm(context, 'بستن فاکتور', 'اطلاعات واردشده ذخیره نشده. بسته شود؟', ok: 'بستن بدون ذخیره');
      if (!ok || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Color get _kindColor => switch (_kind) {
        InvoiceKind.sale => AppColors.income,
        InvoiceKind.purchase => AppColors.expense,
        _ => AppColors.loan,
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final remaining = _total - _paidV;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _save(again: !_isEdit),
        const SingleActivator(LogicalKeyboardKey.insert): _addLine,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _print,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: size.width > 1240 ? 1200 : size.width - 40,
          height: size.height * 0.92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------------------------------------------------------- header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: _kindColor.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: _kindColor, borderRadius: BorderRadius.circular(12)),
                      child: Icon(txnIcon(_kind.txnType), color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${_isEdit ? 'ویرایش ' : ''}$_title',
                        style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!_proforma)
                    SegmentedButton<InvoiceKind>(
                      showSelectedIcon: false,
                      segments: [
                        for (final k in InvoiceKind.values) ButtonSegment(value: k, label: Text(k.short)),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => _setKind(s.first),
                    ),
                    const SizedBox(width: 8),
                    IconButton(tooltip: 'بستن (Esc)', onPressed: _close, icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              const Divider(),
              // ---------------------------------------------------------- party
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: FieldDropdown<String?>(
                              label: _kind.personLabel,
                              value: _person,
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(_kind.buySide ? 'فروشنده متفرقه (نقدی)' : 'مشتری نقدی / متفرقه'),
                                ),
                                for (final p in store.peopleSorted)
                                  DropdownMenuItem<String?>(
                                    value: p.id,
                                    child: Row(children: [
                                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                                      Money(store.personBalance(p.id), colorBySign: true, style: th.textTheme.labelSmall),
                                    ]),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _person = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'طرف حساب جدید',
                            onPressed: () async {
                              final id = await showPersonDialog(context);
                              if (id != null) setState(() => _person = id);
                            },
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DateField(label: 'تاریخ فاکتور', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(labelText: 'شماره'),
                      ),
                    ),
                  ],
                ),
              ),
              // ---------------------------------------------------------- lines
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: th.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _linesHeader(th),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _lines.length + 1,
                            itemBuilder: (context, i) {
                              if (i == _lines.length) {
                                return Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton.icon(
                                      onPressed: _addLine,
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('افزودن ردیف (Insert)'),
                                    ),
                                  ),
                                );
                              }
                              return _lineRow(context, store, i);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ---------------------------------------------------------- footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _note,
                            maxLines: 2,
                            decoration: const InputDecoration(labelText: 'توضیحات فاکتور'),
                          ),
                          if (remaining > 0 && !_proforma) ...[
                            const SizedBox(height: 10),
                            DateField(
                              label: 'سررسید مانده (اختیاری)',
                              value: _due,
                              clearable: true,
                              onChanged: (d) => setState(() => _due = d),
                            ),
                          ],
                          if (_err != null) ...[
                            const SizedBox(height: 10),
                            Text(_err!, style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: _summary(context, store, th, _proforma ? 0 : remaining)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(
                  children: [
                    if (_isEdit)
                      TextButton.icon(
                        onPressed: _delete,
                        icon: Icon(Icons.delete_outline, color: th.colorScheme.error),
                        label: Text('حذف فاکتور', style: TextStyle(color: th.colorScheme.error)),
                      ),
                    const Spacer(),
                    TextButton(onPressed: _close, child: const Text('انصراف')),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _print,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('چاپ (Ctrl+P)'),
                    ),
                    const SizedBox(width: 8),
                    if (_proforma) ...[
                      OutlinedButton.icon(
                        onPressed: _convert,
                        icon: const Icon(Icons.transform_rounded, size: 18),
                        label: const Text('تبدیل به فاکتور فروش'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!_isEdit) ...[
                      OutlinedButton(onPressed: () => _save(again: true), child: const Text('ثبت و فاکتور بعدی (Ctrl+Enter)')),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _kindColor),
                      onPressed: () => _save(),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(_proforma ? 'ذخیره پیش‌فاکتور (Ctrl+S)' : 'ذخیره فاکتور (Ctrl+S)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _wIdx = 36.0;
  static const _wQty = 90.0;
  static const _wUnit = 60.0;
  static const _wPrice = 140.0;
  static const _wDisc = 120.0;
  static const _wTotal = 140.0;
  static const _wDel = 44.0;

  Widget _linesHeader(ThemeData th) {
    return Container(
      color: th.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: DefaultTextStyle(
        style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
        child: const Row(
          children: [
            SizedBox(width: _wIdx, child: Text('#', textAlign: TextAlign.center)),
            Expanded(child: Text('کالا / خدمت')),
            SizedBox(width: _wQty, child: Text('تعداد', textAlign: TextAlign.center)),
            SizedBox(width: _wUnit, child: Text('واحد', textAlign: TextAlign.center)),
            SizedBox(width: _wPrice, child: Text('فی (قیمت واحد)', textAlign: TextAlign.center)),
            SizedBox(width: _wDisc, child: Text('تخفیف ردیف', textAlign: TextAlign.center)),
            SizedBox(width: _wTotal, child: Text('مبلغ کل', textAlign: TextAlign.left)),
            SizedBox(width: _wDel),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(BuildContext context, AppStore store, int i) {
    final th = Theme.of(context);
    final l = _lines[i];
    final p = store.product(l.productId);
    String? stockInfo;
    var stockWarn = false;
    if (p != null) {
      final st = store.stock(p.id, excludeInvoiceId: widget.edit?.id);
      stockInfo = 'موجودی: ${fmtQty(st)} ${p.unit}';
      if (_kind.stockSign < 0 && l.q > st) stockWarn = true;
    }
    const dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _wIdx,
            child: Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(color: th.hintColor)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProductField(
                  key: ObjectKey(l),
                  line: l,
                  products: store.productsSorted.where((x) => !x.archived).toList(),
                  onPick: (p) => _pickProduct(l, p),
                  onTyped: () {
                    final cur = store.product(l.productId);
                    if (cur != null && cur.name != l.title.text) setState(() => l.productId = null);
                  },
                ),
                if (stockInfo != null || (l.productId == null && l.title.text.trim().isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 4, left: 4),
                    child: Row(
                      children: [
                        if (stockInfo != null)
                          Text(stockInfo,
                              style: th.textTheme.labelSmall?.copyWith(
                                  color: stockWarn ? th.colorScheme.error : th.hintColor,
                                  fontWeight: stockWarn ? FontWeight.w700 : null)),
                        if (stockWarn)
                          Text('  — بیشتر از موجودی', style: th.textTheme.labelSmall?.copyWith(color: th.colorScheme.error)),
                        if (l.productId == null && l.title.text.trim().isNotEmpty)
                          InkWell(
                            onTap: () async {
                              final np = Product(
                                id: newId(),
                                name: l.title.text.trim(),
                                buyPrice: _kind.buySide ? l.p : 0,
                                sellPrice: _kind.buySide ? 0 : l.p,
                              );
                              store.upsertProduct(np);
                              setState(() => l.productId = np.id);
                            },
                            child: Text('+ ثبت به‌عنوان کالای انبار',
                                style: th.textTheme.labelSmall?.copyWith(color: th.colorScheme.primary)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: _wQty,
            child: TextField(
              controller: l.qty,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              decoration: dense,
            ),
          ),
          SizedBox(
            width: _wUnit,
            child: Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Text(p?.unit ?? '—', textAlign: TextAlign.center, style: th.textTheme.bodySmall),
            ),
          ),
          SizedBox(
            width: _wPrice,
            child: TextField(
              controller: l.price,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              inputFormatters: [MoneyInputFormatter()],
              decoration: dense,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: _wDisc,
            child: TextField(
              controller: l.discount,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              inputFormatters: [MoneyInputFormatter()],
              decoration: dense,
            ),
          ),
          SizedBox(
            width: _wTotal,
            child: Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Money(l.total, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          SizedBox(
            width: _wDel,
            child: IconButton(
              tooltip: 'حذف ردیف',
              onPressed: () => _removeLine(i),
              icon: Icon(Icons.remove_circle_outline, size: 20, color: th.colorScheme.error.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, AppStore store, ThemeData th, int remaining) {
    Widget row(String label, Widget value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: bold
                        ? th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                        : th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
              ),
              value,
            ],
          ),
        );

    Widget moneyInput(TextEditingController c) => SizedBox(
          width: 170,
          child: TextField(
            controller: c,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            inputFormatters: [MoneyInputFormatter()],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
          ),
        );

    final paidLabel = _kind.moneyIn ? 'دریافت شده' : 'پرداخت شده';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: th.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: th.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          row('جمع ردیف‌ها', Money(_subtotal, style: const TextStyle(fontWeight: FontWeight.w600))),
          row('تخفیف کل فاکتور', moneyInput(_discount)),
          row('هزینه‌های جانبی (ارسال، بسته‌بندی…)', moneyInput(_extra)),
          const Divider(height: 14),
          row('مبلغ نهایی',
              Money(_total, showUnit: true, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: _kindColor)),
              bold: true),
          if (!_proforma) ...[
          const Divider(height: 14),
          Row(
            children: [
              Expanded(
                child: FieldDropdown<String?>(
                  label: _kind.moneyIn ? 'واریز به حساب' : 'برداشت از حساب',
                  value: _account,
                  items: [
                    for (final a in store.activeAccounts)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Row(children: [
                          ColorDot(a.color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                  onChanged: (v) => setState(() => _account = v),
                ),
              ),
              const SizedBox(width: 8),
              moneyInput(_paid),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(paidLabel, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
              const Spacer(),
              TextButton(
                onPressed: () => _paid.text = _total > 0 ? groupDigits(_total) : '',
                child: const Text('تسویه کامل'),
              ),
              TextButton(onPressed: () => _paid.clear(), child: const Text('نسیه')),
            ],
          ),
          row(
            remaining > 0 ? 'مانده (نسیه)' : 'مانده',
            Money(remaining,
                showUnit: true,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: remaining > 0 ? AppColors.debt : (remaining < 0 ? th.colorScheme.error : AppColors.income),
                )),
          ),
          ],
        ],
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
          return widget.products
              .where((p) => p.name.toLowerCase().contains(q) || p.code.toLowerCase().contains(q))
              .take(30);
        },
        onSelected: widget.onPick,
        fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
          controller: controller,
          focusNode: focus,
          onChanged: (_) => widget.onTyped(),
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'نام کالا را تایپ کنید یا شرح آزاد بنویسید',
            prefixIcon: Icon(Icons.inventory_2_outlined, size: 18),
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
                        child: Row(
                          children: [
                            Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                            Text('موجودی ${fmtQty(store.stock(p.id))}',
                                style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                            const SizedBox(width: 12),
                            Money(p.sellPrice, style: th.textTheme.labelMedium),
                          ],
                        ),
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

/// Quick label for invoice lists.
String invoiceTitle(Invoice i) => '${i.kind.label} ${i.number}  ·  ${jFormat(i.date)}';
