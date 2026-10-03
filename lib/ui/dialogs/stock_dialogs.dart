import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/kardex.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../pages/vouchers_page.dart';
import '../print.dart';
import '../print_designer.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty, showInvoiceEditor;
import 'product_dialog.dart';

// ================================================================ shared bits

const _sky = Color(0xFFDCEBFA);
const _skyDark = Color(0xFF9DC3EA);
const _orange = Color(0xFFFFC98B);
const _red = Color(0xFFE53935);

class _Win extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget body;
  final Widget footer;
  final double width;
  final double maxHeight;
  const _Win({required this.title, required this.icon, required this.body, required this.footer, this.width = 1000, this.maxHeight = 780});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: (size.height * 0.92).clamp(420.0, maxHeight),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HeaderBand(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Row(children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.white))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(child: body),
          Container(
            color: _sky,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: footer,
          ),
        ]),
      ),
    );
  }
}

/// Sakan-style button: caption with its shortcut key in a separate red text.
Widget _kb(String label, VoidCallback? onTap, {String key = '', IconData? icon, Color? color, double? width}) {
  final b = OutlinedButton(
    style: OutlinedButton.styleFrom(
      backgroundColor: color ?? Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: const BorderSide(color: _skyDark),
    ),
    onPressed: onTap,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 4)],
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      if (key.isNotEmpty) ...[
        const SizedBox(width: 6),
        Text(key, style: TextStyle(fontSize: 11, color: AppColors.expense.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
      ],
    ]),
  );
  return width == null ? b : SizedBox(width: width, child: b);
}

Widget _check(String label, bool v, ValueChanged<bool> on) => InkWell(
      onTap: () => on(!v),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 28, height: 24, child: Checkbox(value: v, visualDensity: VisualDensity.compact, onChanged: (x) => on(x ?? false))),
        Text(label),
      ]),
    );

Widget _radio(String label, bool sel, VoidCallback on) => InkWell(
      onTap: on,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: sel ? const Color(0xFF1F3BB3) : Colors.black45),
        const SizedBox(width: 4),
        Text(label),
      ]),
    );

Widget _spin(int v, ValueChanged<int> on, {int min = 0, int max = 20}) => Container(
      height: 34,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 30, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        Column(mainAxisSize: MainAxisSize.min, children: [
          InkWell(onTap: v < max ? () => on(v + 1) : null, child: const Icon(Icons.arrow_drop_up, size: 16)),
          InkWell(onTap: v > min ? () => on(v - 1) : null, child: const Icon(Icons.arrow_drop_down, size: 16)),
        ]),
      ]),
    );

Widget _box(String text, {double? width, bool ltr = false, Color color = Colors.white}) {
  final c = Container(
    height: 34,
    alignment: AlignmentDirectional.centerStart,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: ltr ? TextDirection.ltr : null),
  );
  return width == null ? Expanded(child: c) : SizedBox(width: width, child: c);
}

Widget _lbl(String t) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

String _qty(double v, int dec) => dec == 0 ? fmtQty(v) : v.toStringAsFixed(dec);

/// Header cell of a grid.
Widget _hcell(String t, double w, {Color? color, Color? fg}) {
  final c = Container(
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, border: const Border(left: BorderSide(color: Colors.black12))),
    child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

Widget _cell(Widget child, double w, {Alignment align = Alignment.center}) {
  final c = Container(
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black12))),
    child: child,
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

// ================================================================ لیست اقلام موجودی (جدول کالا)

/// جدول کالا — «لیست اقلام موجودی». With [pick] the selected product is returned on تایید.
Future<Product?> showStockList(BuildContext context, {bool pick = false}) =>
    showDialog<Product>(context: context, builder: (_) => _StockList(pick: pick));

class _StockList extends StatefulWidget {
  final bool pick;
  const _StockList({this.pick = false});

  @override
  State<_StockList> createState() => _StockListState();
}

class _StockListState extends State<_StockList> {
  final _f1 = TextEditingController();
  final _f2 = TextEditingController();
  final _f1Focus = FocusNode();
  final _f2Focus = FocusNode();
  final _scroll = ScrollController();
  bool _bc9 = true, _bc7 = false, _hideZero = false, _fromStart = true, _onlyMoved = false;
  int _bc9n = 9, _bc7n = 7;
  int _mode = 0; // 0 دو کادری، 1 کلمه به کلمه
  int _defBox = 0;
  int _dec = 0;
  String? _sel;
  final _marks = <String>{};

  @override
  void initState() {
    super.initState();
    for (final c in [_f1, _f2]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _f1.dispose();
    _f2.dispose();
    _f1Focus.dispose();
    _f2Focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _match(String hay, String q) {
    if (q.isEmpty) return true;
    return _fromStart ? hay.startsWith(q) : hay.contains(q);
  }

  bool _barcodeMatch(Product p, String q) {
    final digits = normalizeDigits(q);
    if (!RegExp(r'^\d+$').hasMatch(digits)) return false;
    final codes = [p.info['barcode'] ?? '', ...(p.info['barcodes'] ?? '').split(',')].map((e) => e.trim()).where((e) => e.isNotEmpty);
    for (final c in codes) {
      if (_bc9 && digits.length >= _bc9n && c.length >= _bc9n && c.substring(0, _bc9n) == digits.substring(0, _bc9n)) return true;
      if (_bc7 && digits.length >= _bc7n && c.length >= _bc7n && c.substring(0, _bc7n) == digits.substring(0, _bc7n)) return true;
      if (c == digits) return true;
    }
    return false;
  }

  List<Product> _list(AppStore s) {
    final q1 = normalizeDigits(_f1.text.trim()).toLowerCase();
    final q2 = normalizeDigits(_f2.text.trim()).toLowerCase();
    return s.productsSorted.where((p) {
      if (p.archived || p.info['hidden'] == '1') return false;
      if (_hideZero && s.stock(p.id).abs() < 1e-9) return false;
      if (_onlyMoved && !s.productInUse(p.id)) return false;
      final name = p.name.toLowerCase();
      final code = p.code.toLowerCase();
      bool one(String q) {
        if (q.isEmpty) return true;
        if (_barcodeMatch(p, q)) return true;
        if (_mode == 1) {
          return q.split(RegExp(r'\s+')).every((w) => name.contains(w) || code.contains(w));
        }
        return _match(name, q) || _match(code, q);
      }

      return one(q1) && (_mode == 1 || one(q2));
    }).toList();
  }

  Product? _current(AppStore s) => s.product(_sel);

  Future<void> _add() async {
    final id = await showProductDialog(context);
    if (id != null) setState(() => _sel = id);
  }

  Future<void> _edit() async {
    final p = _current(StoreScope.read(context));
    if (p == null) return toast(context, 'ابتدا یک کالا را انتخاب کنید', error: true);
    await showProductDialog(context, edit: p);
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final s = StoreScope.read(context);
    final p = _current(s);
    if (p == null) return;
    final used = s.productInUse(p.id);
    final ok = await confirm(context, 'حذف کالا', used ? 'این کالا در اسناد استفاده شده و بایگانی می‌شود. ادامه؟' : '«${p.name}» حذف شود؟');
    if (ok) {
      s.removeProduct(p.id);
      setState(() => _sel = null);
    }
  }

  void _kardex() {
    final p = _current(StoreScope.read(context));
    if (p == null) return toast(context, 'ابتدا یک کالا را انتخاب کنید', error: true);
    showKardex(context, p);
  }

  void _ok() {
    final p = _current(StoreScope.read(context));
    if (widget.pick) {
      if (p == null) return toast(context, 'ابتدا یک کالا را انتخاب کنید', error: true);
      Navigator.pop(context, p);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _printBarcodes(List<Product> list) async {
    final ids = _marks.isNotEmpty ? _marks.toList() : [if (_sel != null) _sel!];
    if (ids.isEmpty) return toast(context, 'کالاهای مورد نظر را در ستون «چاپ» علامت بزنید', error: true);
    final inv = Invoice(
      id: newId(),
      kind: InvoiceKind.sale,
      number: 0,
      date: DateTime.now(),
      lines: [for (final id in ids) InvoiceLine(productId: id, qty: 1, title: StoreScope.read(context).product(id)?.name ?? '')],
    );
    await showReportBuilder(context, inv, PrintDocType.barcode);
  }

  void _sumKardex(AppStore s, List<Product> list) {
    var q = 0.0;
    var v = 0;
    for (final p in list) {
      final st = s.stock(p.id);
      q += st;
      if (st > 0) v += (st * s.avgCost(p.id)).round();
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'تنظیم جمع تعداد کاردکس',
        width: 420,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const SizedBox(width: 150, child: Text('تعداد اقلام:')), Text('${list.length}')]),
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 150, child: Text('جمع تعداد:')), Text(_qty(q, _dec), textDirection: TextDirection.ltr)]),
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 150, child: Text('جمع مبلغ موجودی:')), Text(groupDigits(v), textDirection: TextDirection.ltr)]),
        ]),
      ),
    );
  }

  void _related(AppStore s) {
    final p = _current(s);
    if (p == null) return toast(context, 'ابتدا یک کالا را انتخاب کنید', error: true);
    final docs = s.realInvoices.where((i) => i.lines.any((l) => l.productId == p.id)).toList();
    final centers = <String, int>{};
    for (final i in docs) {
      final c = s.meta('inv:${i.id}').center;
      centers[c.isEmpty ? 'بدون مرکز' : c] = (centers[c.isEmpty ? 'بدون مرکز' : c] ?? 0) + 1;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'مراکز دفاتر مربوطه — ${p.name}',
        width: 460,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: centers.isEmpty
            ? const Text('این کالا در هیچ سندی استفاده نشده است')
            : Column(children: [
                for (final e in centers.entries)
                  ListTile(dense: true, leading: const Icon(Icons.hub_outlined), title: Text(e.key), trailing: Text('${e.value} سند')),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final list = _list(s);
    if (_sel != null && !list.any((p) => p.id == _sel)) _sel = null;
    _sel ??= list.firstOrNull?.id;
    final selIndex = list.indexWhere((p) => p.id == _sel);

    void move(int d) {
      final i = (selIndex + d).clamp(0, list.length - 1);
      if (list.isEmpty) return;
      setState(() => _sel = list[i].id);
      if (_scroll.hasClients) {
        final t = (i * 34.0 - 140).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(t);
      }
    }

    const w = [44.0, 80.0, 0.0, 100.0, 80.0, 80.0, 70.0, 130.0];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f12): () => _printBarcodes(list),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => move(-1),
      },
      child: _Win(
        title: 'لیست اقلام موجودی',
        icon: Icons.grid_on_rounded,
        width: 1060,
        footer: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _kb('چاپ بارکد', () => _printBarcodes(list), key: 'F12', icon: Icons.qr_code_2_rounded),
          Row(mainAxisSize: MainAxisSize.min, children: [const Text('با رقم اعشار '), _spin(_dec, (v) => setState(() => _dec = v), max: 4)]),
          _kb('تنظیم جمع تعداد کاردکس', () => _sumKardex(s, list)),
          _kb('اطلاعات کالا', _edit, color: _orange, icon: Icons.info_outline_rounded),
          _kb('رویت کاردکس', _kardex, icon: Icons.inventory_outlined),
          _kb('تایید', _ok, key: 'F9', icon: Icons.check_circle_rounded, color: const Color(0xFFD7F2D7)),
          _kb('انصراف', () => Navigator.pop(context), key: 'F10', icon: Icons.cancel_rounded, color: const Color(0xFFFBE0E0)),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: _sky,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _check('جستجو در بارکد با', _bc9, (v) => setState(() => _bc9 = v)),
                  const SizedBox(width: 4),
                  _spin(_bc9n, (v) => setState(() => _bc9n = v), min: 1, max: 20),
                  const Text(' رقم ابتدایی'),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _check('جستجو در بارکد با', _bc7, (v) => setState(() => _bc7 = v)),
                  const SizedBox(width: 4),
                  _spin(_bc7n, (v) => setState(() => _bc7n = v), min: 1, max: 20),
                  const Text(' رقم ابتدایی'),
                ]),
                _check('عدم نمایش کالاهای با موجودی صفر', _hideZero, (v) => setState(() => _hideZero = v)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _lbl('فیلتر:'),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _f1,
                      focusNode: _f1Focus,
                      autofocus: _defBox == 0,
                      decoration: const InputDecoration(isDense: true, hintText: 'متن مورد نظر را جهت فیلتر شدن وارد نمایید', fillColor: Color(0xFFFFF7D6), filled: true),
                      onSubmitted: (_) => _ok(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _f2,
                      focusNode: _f2Focus,
                      autofocus: _defBox == 1,
                      enabled: _mode == 0,
                      decoration: const InputDecoration(isDense: true, hintText: 'مرحله دوم فیلتر'),
                      onSubmitted: (_) => _ok(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _kb('افزودن', _add, icon: Icons.star_rounded, color: const Color(0xFFFFF3C4)),
                const SizedBox(width: 6),
                _kb('حذف', _delete, icon: Icons.remove_rounded, color: const Color(0xFFFFE5E5)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _check('جستجو از ابتدای عبارت', _fromStart, (v) => setState(() => _fromStart = v)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _lbl('نحوه جستجو:'),
                  _radio('جستجوی دو کادری', _mode == 0, () => setState(() => _mode = 0)),
                  const SizedBox(width: 10),
                  _radio('جستجوی کلمه به کلمه', _mode == 1, () => setState(() => _mode = 1)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _lbl('کادر پیش فرض:'),
                  _radio('کادر اول', _defBox == 0, () {
                    setState(() => _defBox = 0);
                    _f1Focus.requestFocus();
                  }),
                  const SizedBox(width: 10),
                  _radio('کادر دوم', _defBox == 1, () {
                    setState(() => _defBox = 1);
                    _f2Focus.requestFocus();
                  }),
                ]),
                _kb('رویت مراکز دفاتر مربوطه', () => _related(s)),
                _kb(_onlyMoved ? 'فیلتر دفاتر کالا ✓' : 'فیلتر دفاتر کالا', () => setState(() => _onlyMoved = !_onlyMoved)),
                _kb('تمام اقلام', () {
                  _f1.clear();
                  _f2.clear();
                  setState(() {
                    _onlyMoved = false;
                    _hideZero = false;
                  });
                }),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _lbl('انتخاب:'),
                  _kb('همه', () => setState(() => _marks.addAll(list.map((p) => p.id)))),
                  const SizedBox(width: 4),
                  _kb('هیچ', () => setState(_marks.clear)),
                  const SizedBox(width: 4),
                  _kb('معکوس', () => setState(() {
                        for (final p in list) {
                          if (!_marks.remove(p.id)) _marks.add(p.id);
                        }
                      })),
                ]),
              ]),
            ]),
          ),
          Container(
            color: th.colorScheme.surfaceContainerLow,
            child: Row(children: [
              _hcell('چاپ', w[0], color: _red, fg: Colors.white),
              _hcell('کد کالا', w[1], color: _orange),
              _hcell('نام کالا', w[2]),
              _hcell('تعداد ۱', w[3]),
              _hcell('تعداد ۲', w[4]),
              _hcell('تعداد ۳', w[5]),
              _hcell('واحد', w[6]),
              _hcell('بهای فروش', w[7]),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(icon: Icons.inventory_2_outlined, text: 'کالایی پیدا نشد')
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: 34,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      final sel = p.id == _sel;
                      final st = s.stock(p.id);
                      final fg = sel ? Colors.white : null;
                      return Material(
                        color: sel ? const Color(0xFF2F6FDE) : (i.isOdd ? const Color(0xFFF4F8FD) : Colors.white),
                        child: InkWell(
                          onTap: () => setState(() => _sel = p.id),
                          onDoubleTap: () {
                            setState(() => _sel = p.id);
                            widget.pick ? _ok() : showKardex(context, p);
                          },
                          child: DefaultTextStyle.merge(
                            style: TextStyle(color: fg, fontWeight: sel ? FontWeight.w700 : null),
                            child: Row(children: [
                              _cell(
                                  Checkbox(
                                    value: _marks.contains(p.id),
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (v) => setState(() => v == true ? _marks.add(p.id) : _marks.remove(p.id)),
                                  ),
                                  w[0]),
                              _cell(Text(p.code, style: const TextStyle(fontWeight: FontWeight.w700)), w[1]),
                              _cell(Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis), w[2], align: Alignment.centerRight),
                              _cell(
                                  Text(_qty(st, _dec),
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(fontWeight: FontWeight.w800, color: st < 0 && !sel ? th.colorScheme.error : null)),
                                  w[3]),
                              _cell(const Text('0'), w[4]),
                              _cell(const Text('0'), w[5]),
                              _cell(Text(p.unit), w[6]),
                              _cell(Text(groupDigits(p.sellPrice), textDirection: TextDirection.ltr), w[7]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            color: th.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text('${list.length} قلم کالا${_marks.isEmpty ? '' : ' — ${_marks.length} مورد برای چاپ علامت خورده'}', style: th.textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ کاردکس کالا

Future<void> showKardex(BuildContext context, Product product) =>
    showDialog<void>(context: context, builder: (_) => _KardexWin(product: product));

class _KardexWin extends StatefulWidget {
  final Product product;
  const _KardexWin({required this.product});

  @override
  State<_KardexWin> createState() => _KardexWinState();
}

class _KardexWinState extends State<_KardexWin> {
  late String _pid = widget.product.id;
  String? _wh; // null = تمام انبارها
  int _col = 0; // 0 شرح، 1 شماره، 2 تاریخ، 3 نام انبار
  final _value = TextEditingController();
  String _applied = '';
  int _dec = 0;
  int? _sel;
  final _scroll = ScrollController();

  static const _cols = ['شرح', 'شماره', 'تاریخ', 'نام انبار'];

  @override
  void dispose() {
    _value.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<KardexRow> _rows(AppStore s) {
    final all = buildKardex(s, _pid, warehouseId: _wh);
    final q = normalizeDigits(_applied.trim()).toLowerCase();
    if (q.isEmpty) return all;
    return all.where((r) {
      final v = switch (_col) {
        0 => r.desc,
        1 => '${r.number ?? ''}',
        2 => jFormat(r.date),
        _ => r.warehouse,
      };
      return normalizeDigits(v).toLowerCase().contains(q);
    }).toList();
  }

  void _goTo(int i) {
    setState(() => _sel = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo((i * 34.0 - 120).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  void _negRow(List<KardexRow> rows) {
    final start = (_sel ?? -1) + 1;
    var i = rows.indexWhere((r) => r.balance < -1e-9, start);
    if (i < 0) i = rows.indexWhere((r) => r.balance < -1e-9);
    if (i < 0) return toast(context, 'ردیف منفی در کاردکس وجود ندارد');
    _goTo(i);
  }

  void _showInDocs(KardexRow? r) {
    if (r == null || !r.docKey.startsWith('inv:')) return toast(context, 'این ردیف سند قابل رویت ندارد', error: true);
    VouchersPage.focusKey = r.docKey;
    final nav = Nav.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    nav.go(AppPage.vouchers);
  }

  void _edit(KardexRow? r) {
    if (r?.invoice == null) return toast(context, 'این ردیف قابل ویرایش نیست', error: true);
    showInvoiceEditor(context, edit: r!.invoice);
  }

  void _stockReport(AppStore s, Product p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'گزارش موجودی — ${p.name}',
        width: 460,
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
        child: Column(children: [
          for (final w in s.warehouses)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warehouse_outlined),
              title: Text(w.name),
              trailing: Text('${fmtQty(s.stock(p.id, warehouseId: w.id))} ${p.unit}', textDirection: TextDirection.ltr),
            ),
          const Divider(),
          ListTile(
            dense: true,
            title: const Text('جمع کل', style: TextStyle(fontWeight: FontWeight.w800)),
            trailing: Text('${fmtQty(s.stock(p.id))} ${p.unit}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final p = s.product(_pid) ?? widget.product;
    final rows = _rows(s);
    if (_sel != null && _sel! >= rows.length) _sel = null;
    final cur = _sel == null ? null : rows[_sel!];
    final last = rows.lastOrNull;
    final balance = last?.balance ?? 0;
    final value = last?.value ?? 0;
    final avg = last?.avg ?? 0;
    const w = [50.0, 80.0, 96.0, 0.0, 80.0, 110.0, 130.0, 90.0, 100.0];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (rows.isNotEmpty) _goTo(((_sel ?? -1) + 1).clamp(0, rows.length - 1));
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (rows.isNotEmpty) _goTo(((_sel ?? rows.length) - 1).clamp(0, rows.length - 1));
        },
      },
      child: Focus(
        autofocus: true,
        child: _Win(
          title: 'کاردکس کالا — ${p.name}',
          icon: Icons.inventory_outlined,
          width: 1100,
          footer: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [const Text('با رقم اعشار '), _spin(_dec, (v) => setState(() => _dec = v), max: 4)]),
            _kb('ردیف منفی', () => _negRow(rows), icon: Icons.south_rounded),
            _kb('محاسبه مجدد', () {
              setState(() {});
              toast(context, 'کاردکس دوباره محاسبه شد');
            }, icon: Icons.refresh_rounded),
            _kb('رویت در لیست اسناد', () => _showInDocs(cur), icon: Icons.list_alt_rounded),
            _kb('ویرایش', () => _edit(cur), icon: Icons.edit_outlined, color: const Color(0xFFFFF3C4)),
            _kb('بازگشت', () => Navigator.pop(context), key: 'F10', icon: Icons.reply_rounded, color: const Color(0xFFFFE0B2)),
          ]),
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: _sky,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(6)),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(4)),
                        child: const Text('اطلاعات کالا', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      SizedBox(width: 90, child: _lbl('نام کالا:')),
                      _box(p.name, color: const Color(0xFFFFF7D6)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 44,
                        height: 34,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: Colors.white),
                          onPressed: () async {
                            final np = await showStockList(context, pick: true);
                            if (np != null) {
                              setState(() {
                                _pid = np.id;
                                _sel = null;
                              });
                            }
                          },
                          child: const Text('...'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      _lbl('گزارش موجودی:'),
                      _kb('${fmtQty(s.stock(p.id))} ${p.unit}', () => _stockReport(s, p), width: 150),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      SizedBox(width: 90, child: _lbl('مشخصات:')),
                      _box(p.note),
                      const SizedBox(width: 10),
                      _lbl('شماره فنی:'),
                      _box(p.info['techNo'] ?? '', width: 150),
                      const SizedBox(width: 10),
                      _lbl('رویت بر اساس انبار:'),
                      SizedBox(
                        width: 170,
                        height: 34,
                        child: DropdownButtonFormField<String>(
                          value: _wh ?? '*',
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                          items: [
                            const DropdownMenuItem(value: '*', child: Text('تمام انبارها')),
                            for (final w in s.warehouses) DropdownMenuItem(value: w.id, child: Text(w.name)),
                          ],
                          onChanged: (v) => setState(() {
                            _wh = v == '*' ? null : v;
                            _sel = null;
                          }),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      SizedBox(width: 90, child: _lbl('بارکد:')),
                      _box(p.info['barcode'] ?? '', ltr: true),
                      const SizedBox(width: 10),
                      _lbl('روش محاسبه کاردکس:'),
                      _box('میانگین_متحرک', width: 150),
                      const Spacer(),
                    ]),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _lbl('ستون:'),
                  SizedBox(
                    width: 150,
                    height: 34,
                    child: DropdownButtonFormField<int>(
                      value: _col,
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      items: [for (var i = 0; i < _cols.length; i++) DropdownMenuItem(value: i, child: Text(_cols[i]))],
                      onChanged: (v) => setState(() => _col = v ?? 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _lbl('مقدار:'),
                  SizedBox(
                    width: 200,
                    height: 36,
                    child: TextField(
                      controller: _value,
                      decoration: const InputDecoration(isDense: true),
                      onSubmitted: (v) => setState(() {
                        _applied = v;
                        _sel = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _kb('محدود', () => setState(() {
                        _applied = _value.text;
                        _sel = null;
                      })),
                  const SizedBox(width: 6),
                  _kb('همه موارد', () {
                    _value.clear();
                    setState(() {
                      _applied = '';
                      _sel = null;
                    });
                  }),
                ]),
              ]),
            ),
            Container(
              color: th.colorScheme.surfaceContainerLow,
              child: Row(children: [
                _hcell('ردیف', w[0], color: _red, fg: Colors.white),
                _hcell('شماره', w[1]),
                _hcell('تاریخ', w[2]),
                _hcell('شرح', w[3]),
                _hcell('عدد', w[4]),
                _hcell('فی', w[5]),
                _hcell('جمع کل', w[6]),
                _hcell('مانده', w[7]),
                _hcell('نام انبار', w[8]),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(icon: Icons.swap_vert_rounded, text: 'گردشی برای این کالا ثبت نشده')
                  : ListView.builder(
                      controller: _scroll,
                      itemExtent: 34,
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final sel = i == _sel;
                        final neg = r.balance < -1e-9;
                        return Material(
                          color: sel ? const Color(0xFF2F6FDE) : (neg ? const Color(0xFFFFE3E3) : (i.isOdd ? const Color(0xFFF4F8FD) : Colors.white)),
                          child: InkWell(
                            onTap: () => setState(() => _sel = i),
                            onDoubleTap: () => _edit(r),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(color: sel ? Colors.white : null, fontWeight: sel ? FontWeight.w700 : null),
                              child: Row(children: [
                                _cell(Text('${i + 1}'), w[0]),
                                _cell(Text(r.number == null ? '' : groupDigits(r.number!), style: const TextStyle(fontWeight: FontWeight.w700)), w[1]),
                                _cell(Text(r.docKey == 'open' ? '' : jFormat(r.date)), w[2]),
                                _cell(Text(r.desc, maxLines: 1, overflow: TextOverflow.ellipsis), w[3], align: Alignment.centerRight),
                                _cell(Text(_qty(r.qty, _dec), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)), w[4]),
                                _cell(Text(groupDigits(r.fi), textDirection: TextDirection.ltr), w[5]),
                                _cell(Text(groupDigits(r.total), textDirection: TextDirection.ltr), w[6]),
                                _cell(Text(_qty(r.balance, _dec), textDirection: TextDirection.ltr), w[7]),
                                _cell(Text(r.warehouse, maxLines: 1, overflow: TextOverflow.ellipsis), w[8]),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              color: _sky,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Column(children: [
                Row(children: [
                  _lbl('تعداد:'),
                  _box('${rows.length}', width: 90, ltr: true),
                  const SizedBox(width: 14),
                  _lbl('موجودی:'),
                  _box('${_qty(balance, _dec)} ${p.unit}', width: 140, ltr: true),
                  const SizedBox(width: 6),
                  _box(groupDigits(value), width: 170, ltr: true),
                  const SizedBox(width: 14),
                  _lbl('ملاحظات:'),
                  _box('${_qty(balance, _dec)} ${p.unit} فی ${groupDigits(avg)} ریال'),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ================================================================ کنترل اسناد

Future<bool?> _ask(BuildContext context, String title, String msg, {bool cancel = false}) => showDialog<bool>(
      context: context,
      builder: (ctx) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(ctx)},
        child: AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            if (cancel) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله')),
          ],
        ),
      ),
    );

/// کنترل کاردکس — finds کاردکس‌های منفی.
Future<void> runKardexControl(BuildContext context) async {
  final yes = await _ask(context, 'کنترل کاردکس', 'مایل به کنترل کاردکس های منفی هستید؟');
  if (yes != true || !context.mounted) return;
  final s = StoreScope.read(context);
  final list = negativeKardexes(s);
  if (list.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('کنترل کاردکس'),
        content: const Text('کاردکس منفی وجود ندارد'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => _Win(
      title: 'لیست کاردکس های منفی',
      icon: Icons.rule_rounded,
      width: 860,
      maxHeight: 600,
      footer: Row(children: [
        Text('${list.length} کالا', style: Theme.of(ctx).textTheme.bodySmall),
        const Spacer(),
        _kb('بازگشت', () => Navigator.pop(ctx), key: 'F10', icon: Icons.reply_rounded),
      ]),
      body: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final (p, r) = list[i];
          return ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFFFFE3E3), child: Text('${i + 1}')),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${jFormat(r.date)} — ${r.desc}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('مانده ${fmtQty(r.balance)}', textDirection: TextDirection.rtl, style: const TextStyle(color: _red, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              _kb('رویت کاردکس', () => showKardex(ctx, p)),
            ]),
            onTap: () => showKardex(ctx, p),
          );
        },
      ),
    ),
  );
}

/// چک کاردکس — differences between the vouchers and the کاردکس.
Future<void> showKardexCheck(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _KardexCheck());

class _KardexCheck extends StatefulWidget {
  const _KardexCheck();

  @override
  State<_KardexCheck> createState() => _KardexCheckState();
}

class _KardexCheckState extends State<_KardexCheck> {
  bool _all = false;
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final rows = checkKardex(s, all: _all);
    if (_sel != null && _sel! >= rows.length) _sel = null;
    const w = [50.0, 0.0, 120.0, 150.0, 130.0, 150.0];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context)},
      child: _Win(
        title: 'چک کاردکس',
        icon: Icons.playlist_add_check_rounded,
        width: 960,
        maxHeight: 640,
        footer: Row(children: [
          _check('نمایش همه ردیف ها', _all, (v) => setState(() => _all = v)),
          const SizedBox(width: 12),
          Text(rows.isEmpty ? 'مغایرتی بین اسناد و کاردکس وجود ندارد' : '${rows.length} ردیف', style: th.textTheme.bodySmall),
          const Spacer(),
          _kb('ویرایش', _sel == null ? null : () => showInvoiceEditor(context, edit: rows[_sel!].invoice), icon: Icons.edit_outlined, color: const Color(0xFFFFF3C4)),
          const SizedBox(width: 8),
          _kb('برگشت', () => Navigator.pop(context), key: 'F10', icon: Icons.reply_rounded, color: const Color(0xFFFFE0B2)),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: th.colorScheme.surfaceContainerLow,
            child: Row(children: [
              _hcell('ردیف', w[0], color: _red, fg: Colors.white),
              _hcell('نام کالا', w[1]),
              _hcell('شماره مبنا در سند', w[2]),
              _hcell('مبلغ در سند', w[3]),
              _hcell('شماره مبنا در کاردکس', w[4]),
              _hcell('مبلغ در کاردکس', w[5]),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.verified_outlined, text: 'مغایرتی بین اسناد و کاردکس وجود ندارد')
                : ListView.builder(
                    itemExtent: 34,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final sel = i == _sel;
                      final diff = r.docAmount != r.kardexAmount;
                      return Material(
                        color: sel ? const Color(0xFF2F6FDE) : (diff ? const Color(0xFFFFF0E0) : Colors.white),
                        child: InkWell(
                          onTap: () => setState(() => _sel = i),
                          onDoubleTap: () => showInvoiceEditor(context, edit: r.invoice),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(color: sel ? Colors.white : null),
                            child: Row(children: [
                              _cell(Text('${i + 1}'), w[0]),
                              _cell(Text(r.product.name, maxLines: 1, overflow: TextOverflow.ellipsis), w[1], align: Alignment.centerRight),
                              _cell(Text(groupDigits(r.docNo)), w[2]),
                              _cell(Text(groupDigits(r.docAmount), textDirection: TextDirection.ltr), w[3]),
                              _cell(Text(groupDigits(r.kardexNo)), w[4]),
                              _cell(Text(groupDigits(r.kardexAmount), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: diff ? FontWeight.w800 : null)), w[5]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// گزارش خلاف ماهیت.
Future<void> runNatureReport(BuildContext context) async {
  final stock = await _ask(context, 'گزارش خلاف ماهیت', 'آیا میخواهید در کنترل مانده حسابها مانده موجودی کالا نیز کنترل شود؟', cancel: true);
  if (stock == null || !context.mounted) return;
  // short progress step, like Sakan's «در حال کنترل مانده حسابها»
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(width: 16),
        Text('در حال کنترل مانده حسابها ...'),
      ]),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!context.mounted) return;
  Navigator.of(context).pop();
  await showDialog<void>(context: context, builder: (_) => _NatureWin(includeStock: stock));
}

class _NatureWin extends StatefulWidget {
  final bool includeStock;
  const _NatureWin({required this.includeStock});

  @override
  State<_NatureWin> createState() => _NatureWinState();
}

class _NatureWinState extends State<_NatureWin> {
  int? _sel;
  bool _byCenter = false;

  void _print(AppStore s, List<NatureRow> rows) {
    printTable(
      store: s,
      title: 'لیست دفاتری که ماهیت غیر مجاز دارند',
      headers: const ['ردیف', 'عنوان دفتر', 'شناسه', 'نام مشخصه', 'شناسه مشخصه', 'محل استقرار', 'مانده', 'شماره سند بر هم زننده ماهیت'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            rows[i].moeen.name,
            rows[i].moeen.code,
            rows[i].tafsiliName,
            rows[i].tafsiliCode,
            rows[i].moeen.kol.name,
            groupDigits(rows[i].balance.abs()),
            rows[i].breakingDoc,
          ],
      ],
      numeric: const {6},
      fileName: 'contra-nature',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final rows = contraNature(s, includeStock: widget.includeStock);
    if (_sel != null && _sel! >= rows.length) _sel = null;
    const w = [46.0, 0.0, 80.0, 170.0, 110.0, 150.0, 130.0, 150.0];
    void ok() => Navigator.pop(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): ok,
        const SingleActivator(LogicalKeyboardKey.f10): ok,
      },
      child: _Win(
        title: 'لیست دفاتری که ماهیت غیر مجاز دارند',
        icon: Icons.report_gmailerrorred_outlined,
        width: 1120,
        maxHeight: 680,
        footer: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _kb('مشاهده سند', () {
            final nav = Nav.of(context);
            Navigator.of(context).popUntil((r) => r.isFirst);
            nav.go(AppPage.vouchers);
          }, icon: Icons.visibility_outlined),
          _kb('تنظیم جمع مبالغ اسناد', () {
            setState(() {});
            toast(context, 'جمع مبالغ اسناد دوباره محاسبه شد');
          }),
          _kb('محاسبه مانده نهایی بدون مرکز هزینه', () => setState(() => _byCenter = false), color: !_byCenter ? const Color(0xFFFFF3C4) : null),
          _kb('محاسبه مانده نهایی بر اساس مرکز هزینه', () => setState(() => _byCenter = true), color: _byCenter ? const Color(0xFFFFF3C4) : null),
          _kb('گزارش خلاف ماهیت', () => _print(s, rows), icon: Icons.print_outlined),
          _kb('تایید', ok, key: 'F9', icon: Icons.check_circle_rounded, color: const Color(0xFFD7F2D7)),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: th.colorScheme.surfaceContainerLow,
            child: Row(children: [
              _hcell('ردیف', w[0], color: _red, fg: Colors.white),
              _hcell('عنوان دفتر', w[1]),
              _hcell('شناسه', w[2]),
              _hcell('نام مشخصه', w[3]),
              _hcell('شناسه مشخصه', w[4]),
              _hcell('محل استقرار', w[5]),
              _hcell('مانده', w[6]),
              _hcell('شماره سند بر هم زننده ماهیت', w[7]),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.verified_outlined, text: 'دفتری با ماهیت غیر مجاز وجود ندارد')
                : ListView.builder(
                    itemExtent: 34,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final sel = i == _sel;
                      return Material(
                        color: sel ? const Color(0xFF2F6FDE) : (i.isOdd ? const Color(0xFFF4F8FD) : Colors.white),
                        child: InkWell(
                          onTap: () => setState(() => _sel = i),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(color: sel ? Colors.white : null),
                            child: Row(children: [
                              _cell(Text('${i + 1}'), w[0]),
                              _cell(Text(r.moeen.name, maxLines: 1, overflow: TextOverflow.ellipsis), w[1], align: Alignment.centerRight),
                              _cell(Text(r.moeen.code), w[2]),
                              _cell(Text(r.tafsiliName, maxLines: 1, overflow: TextOverflow.ellipsis), w[3]),
                              _cell(Text(r.tafsiliCode), w[4]),
                              _cell(Text(r.moeen.kol.name, maxLines: 1, overflow: TextOverflow.ellipsis), w[5]),
                              _cell(Text(groupDigits(r.balance.abs()), textDirection: TextDirection.ltr, style: TextStyle(color: sel ? null : _red, fontWeight: FontWeight.w800)), w[6]),
                              _cell(Text(r.breakingDoc), w[7]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// نمایش اخطارهای ورودی — «گزارش پویا» of cheques due soon or overdue.
Future<void> showIncomingWarnings(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _Warnings());

class _Warnings extends StatefulWidget {
  const _Warnings();

  @override
  State<_Warnings> createState() => _WarningsState();
}

class _WarningsState extends State<_Warnings> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final limit = t0.add(Duration(days: _days));
    final list = s.cheques
        .where((c) => (c.status == ChequeStatus.pending || c.status == ChequeStatus.deposited) && !c.dueDate.isAfter(limit))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    const headers = ['ردیف', 'نوع اخطار', 'شماره چک', 'بانک', 'طرف حساب', 'تاریخ سررسید', 'روز مانده', 'مبلغ', 'وضعیت'];
    List<String> cells(Cheque c, int i) {
      final d = DateTime(c.dueDate.year, c.dueDate.month, c.dueDate.day).difference(t0).inDays;
      return [
        '${i + 1}',
        c.direction == ChequeDirection.received ? 'چک دریافتی' : 'چک پرداختی',
        c.serial,
        c.bank,
        s.person(c.personId)?.name ?? '',
        jFormat(c.dueDate),
        d < 0 ? '${-d} روز گذشته' : (d == 0 ? 'امروز' : '$d روز'),
        groupDigits(c.amount),
        c.status.label,
      ];
    }

    final rows = [for (var i = 0; i < list.length; i++) cells(list[i], i)];
    const w = [46.0, 100.0, 110.0, 120.0, 0.0, 100.0, 110.0, 130.0, 150.0];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context)},
      child: _Win(
        title: 'گزارش پویا — اخطارهای ورودی',
        icon: Icons.warning_amber_rounded,
        width: 1120,
        maxHeight: 660,
        footer: Row(children: [
          const Text('سررسید تا '),
          _spin(_days, (v) => setState(() => _days = v), max: 90),
          const Text(' روز آینده'),
          const SizedBox(width: 12),
          Text('${list.length} اخطار', style: th.textTheme.bodySmall),
          const Spacer(),
          _kb('چاپ', () => printTable(store: s, title: 'اخطارهای ورودی', headers: headers, rows: rows, numeric: const {7}, fileName: 'warnings'),
              icon: Icons.print_outlined),
          const SizedBox(width: 8),
          _kb('بستن', () => Navigator.pop(context), key: 'F10'),
        ]),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: th.colorScheme.surfaceContainerLow,
            child: Row(children: [for (var i = 0; i < headers.length; i++) _hcell(headers[i], w[i], color: i == 0 ? _red : null, fg: i == 0 ? Colors.white : null)]),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.notifications_off_outlined, text: 'اخطاری وجود ندارد')
                : ListView.builder(
                    itemExtent: 34,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final over = list[i].dueDate.isBefore(t0);
                      return Container(
                        color: over ? const Color(0xFFFFE3E3) : (i.isOdd ? const Color(0xFFF4F8FD) : Colors.white),
                        child: Row(children: [
                          for (var j = 0; j < headers.length; j++)
                            _cell(
                                Text(rows[i][j],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: j == 7 ? TextDirection.ltr : null,
                                    style: TextStyle(fontWeight: j == 7 || j == 6 ? FontWeight.w700 : null, color: j == 6 && over ? _red : null)),
                                w[j]),
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

/// Used by the ribbon: opens the کاردکس of a product chosen from the list.
Future<void> pickAndShowKardex(BuildContext context) async {
  final p = await showStockList(context, pick: true);
  if (p != null && context.mounted) await showKardex(context, p);
}
