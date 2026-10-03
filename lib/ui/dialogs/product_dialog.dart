import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;
import 'misc_dialogs.dart';

/// «اطلاعات دفتر تفصیلی موجودی کالا» — Sakan's product form.
Future<String?> showProductDialog(BuildContext context, {Product? edit}) =>
    showDialog<String>(context: context, builder: (_) => _ProductDialog(edit: edit));

const _sky = Color(0xFFDCEBFA);
const _skyDark = Color(0xFF9DC3EA);

class _ProductDialog extends StatefulWidget {
  final Product? edit;
  const _ProductDialog({this.edit});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _c = <String, TextEditingController>{};
  final _flags = <String, bool>{};
  bool _en = false; // نام کالا: Fa / En
  String _image = '';
  String? _err;

  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);

  static const _infoText = [
    'suffix', 'latin', 'techNo', 'unitLatin', 'barcode', 'barcodes', 'nationalBarcode', 'taxId', //
    'taxPct', 'dutyPct', 'returnPct', 'discountPct', 'marketingPct', 'consumerPrice', 'maxQty', 'orderPoint',
    'settleDays', 'giftRial', 'giftPct', 'unitDiscount',
  ];
  static const _flagKeys = ['defIn', 'defOut', 'countable', 'hidden', 'restaurant', 'autoPrice', 'noNegCheck'];

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    final s = StoreScope.read(context);
    c('code').text = e?.code ?? _nextCode(s);
    c('name').text = e?.name ?? '';
    c('unit').text = e?.unit ?? 'عدد';
    String money(int v) => v == 0 ? '0' : groupDigits(v);
    c('buy').text = money(e?.buyPrice ?? 0);
    c('sell').text = money(e?.sellPrice ?? 0);
    c('sell2').text = money(e?.sellPrice2 ?? 0);
    c('sell3').text = money(e?.sellPrice3 ?? 0);
    c('opening').text = e == null ? '0' : fmtQty(e.openingQty);
    c('min').text = e == null ? '0' : fmtQty(e.minQty);
    c('weight').text = e == null ? '0' : fmtQty(e.weight);
    c('note').text = e?.note ?? '';
    for (final k in _infoText) {
      c(k).text = e?.info[k] ?? '';
    }
    for (final k in _flagKeys) {
      _flags[k] = e?.info[k] == '1';
    }
    _en = e?.info['lang'] == 'en';
    _image = e?.info['image'] ?? '';
  }

  String _nextCode(AppStore s) {
    var n = 7001;
    for (final p in s.products) {
      final v = int.tryParse(normalizeDigits(p.code));
      if (v != null && v >= n) n = v + 1;
    }
    return '$n';
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    if (c('name').text.trim().isEmpty) {
      setState(() => _err = 'نام کالا را وارد کنید');
      return;
    }
    final code = c('code').text.trim();
    if (code.isNotEmpty && s.products.any((p) => p.id != widget.edit?.id && p.code == code)) {
      setState(() => _err = 'کد حساب تفصیلی $code تکراری است');
      return;
    }
    final p = widget.edit ?? Product(id: newId(), name: '');
    p
      ..name = c('name').text.trim()
      ..code = code
      ..unit = c('unit').text.trim().isEmpty ? 'عدد' : c('unit').text.trim()
      ..buyPrice = parseMoney(c('buy').text)
      ..sellPrice = parseMoney(c('sell').text)
      ..sellPrice2 = parseMoney(c('sell2').text)
      ..sellPrice3 = parseMoney(c('sell3').text)
      ..openingQty = parseQty(c('opening').text)
      ..minQty = parseQty(c('min').text)
      ..weight = parseQty(c('weight').text)
      ..note = c('note').text.trim();
    final info = <String, String>{...p.info};
    for (final k in _infoText) {
      info[k] = c(k).text.trim();
    }
    for (final k in _flagKeys) {
      info[k] = _flags[k] == true ? '1' : '';
    }
    info['lang'] = _en ? 'en' : '';
    info['image'] = _image;
    info.removeWhere((_, v) => v.isEmpty || v == '0');
    p.info = info;
    s.upsertProduct(p);
    Navigator.pop(context, p.id);
  }

  Future<void> _pickImage() async {
    final f = await fs.openFile(acceptedTypeGroups: const [
      fs.XTypeGroup(label: 'تصاویر', extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp']),
    ]);
    if (f != null) setState(() => _image = f.path);
  }

  /// ساخت نام و بارکد — builds a barcode from the code when empty.
  void _makeBarcode() {
    final base = normalizeDigits(c('code').text.trim()).replaceAll(RegExp(r'\D'), '');
    final r = Random();
    var code = '626${base.padLeft(5, '0')}';
    while (code.length < 12) {
      code += '${r.nextInt(10)}';
    }
    // EAN-13 check digit
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(code[i]) * (i.isOdd ? 3 : 1);
    }
    code += '${(10 - sum % 10) % 10}';
    setState(() => c('barcode').text = code);
  }

  Future<void> _subBarcodes() async {
    final t = TextEditingController(text: c('barcodes').text.split(',').where((e) => e.trim().isNotEmpty).join('\n'));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'بارکدهای فرعی',
        width: 420,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('تایید')),
        ],
        child: TextField(
          controller: t,
          minLines: 5,
          maxLines: 8,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(helperText: 'هر بارکد در یک خط'),
        ),
      ),
    );
    t.dispose();
    if (r != null) {
      setState(() => c('barcodes').text = r.split(RegExp(r'[\n,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).join(','));
    }
  }

  // ------------------------------------------------------------------ small widgets

  Widget _lbl(String t, {double? width}) {
    final w = Text(t, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis);
    return width == null
        ? Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w)
        : SizedBox(width: width, child: Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: w));
  }

  Widget _f(String k, {double? width, bool ltr = false, bool money = false, Color? fill, bool autofocus = false, String? hint}) {
    final f = SizedBox(
      height: 36,
      child: TextField(
        controller: c(k),
        autofocus: autofocus,
        textDirection: ltr || money ? TextDirection.ltr : null,
        textAlign: money ? TextAlign.left : TextAlign.start,
        inputFormatters: money ? [_ThousandsFormatter()] : null,
        decoration: InputDecoration(isDense: true, filled: true, fillColor: fill ?? Colors.white, hintText: hint),
        onSubmitted: (_) => _save(),
      ),
    );
    return width == null ? Expanded(child: f) : SizedBox(width: width, child: f);
  }

  /// Numeric field with the Sakan spin arrows.
  Widget _n(String k, {double width = 90, bool decimal = false}) => SizedBox(
        width: width,
        height: 36,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: c(k),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white),
              onSubmitted: (_) => _save(),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(onTap: () => _bump(k, 1, decimal), child: const Icon(Icons.arrow_drop_up, size: 18)),
            InkWell(onTap: () => _bump(k, -1, decimal), child: const Icon(Icons.arrow_drop_down, size: 18)),
          ]),
        ]),
      );

  void _bump(String k, int d, bool decimal) {
    final v = parseQty(c(k).text) + d;
    setState(() => c(k).text = fmtQty(v < 0 ? 0 : v));
  }

  Widget _chk(String k, String label) => InkWell(
        onTap: () => setState(() => _flags[k] = !(_flags[k] ?? false)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 28,
            height: 24,
            child: Checkbox(value: _flags[k] ?? false, visualDensity: VisualDensity.compact, onChanged: (v) => setState(() => _flags[k] = v ?? false)),
          ),
          Text(label),
        ]),
      );

  Widget _btn(String label, VoidCallback? on, {String key = '', IconData? icon, Color? color}) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: color ?? Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: const BorderSide(color: _skyDark),
        ),
        onPressed: on,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 4)],
          Text(label),
          if (key.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(key, style: const TextStyle(fontSize: 11, color: Color(0xFFD84315), fontWeight: FontWeight.w700)),
          ],
        ]),
      );

  Widget _section(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _sky, border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  static const _gap = SizedBox(height: 6);

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final img = _image.isNotEmpty && File(_image).existsSync() ? File(_image) : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1000,
          height: (size.height * 0.92).clamp(420.0, 760.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HeaderBand(
              padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('اطلاعات دفتر تفصیلی موجودی کالا',
                      style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // ------------------------------------------------ identity
                  _section([
                    Row(children: [
                      _lbl('کد حساب تفصیلی', width: 120),
                      _f('code', width: 110, ltr: true, fill: const Color(0xFFEFEFEF)),
                      const SizedBox(width: 14),
                      _lbl('نام کالا:'),
                      InkWell(onTap: () => setState(() => _en = false), child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(!_en ? Icons.radio_button_checked : Icons.radio_button_off, size: 18), const Text(' Fa'),
                      ])),
                      const SizedBox(width: 8),
                      InkWell(onTap: () => setState(() => _en = true), child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_en ? Icons.radio_button_checked : Icons.radio_button_off, size: 18), const Text(' En'),
                      ])),
                      const Spacer(),
                      _btn('ساخت نام و بارکد', _makeBarcode, icon: Icons.qr_code_rounded),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('نام کالا', width: 120),
                      _f('name', fill: const Color(0xFFFFF4B8), autofocus: widget.edit == null),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 44,
                        height: 36,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: Colors.white),
                          onPressed: () => setState(() => c('name').text = '${c('name').text.trim()} ${c('suffix').text.trim()}'.trim()),
                          child: const Text('•••'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _lbl('پسوند نام کالا:'),
                      _f('suffix', width: 180),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('نام کالا لاتین:', width: 120),
                      _f('latin', ltr: true),
                      const SizedBox(width: 10),
                      _lbl('شماره فنی:'),
                      _f('techNo', width: 180, ltr: true),
                    ]),
                    _gap,
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(children: [
                          Row(children: [
                            _lbl('درصد مالیات:', width: 120),
                            _n('taxPct'),
                            const SizedBox(width: 10),
                            _lbl('درصد عوارض:', width: 100),
                            _n('dutyPct'),
                            const SizedBox(width: 10),
                            _lbl('درصد مرجوعی:', width: 100),
                            _n('returnPct'),
                          ]),
                          _gap,
                          Row(children: [
                            _lbl('درصد بازاریابی:', width: 120),
                            _n('marketingPct'),
                            const SizedBox(width: 10),
                            _lbl('درصد تخفیف:', width: 100),
                            _n('discountPct'),
                            const SizedBox(width: 10),
                            _lbl('بهای مصرف کننده:', width: 100),
                            _f('consumerPrice', width: 130, money: true),
                          ]),
                          _gap,
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _lbl('مشخصات کالا:', width: 120),
                            Expanded(
                              child: TextField(
                                controller: c('note'),
                                minLines: 2,
                                maxLines: 3,
                                decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Column(children: [
                        Container(
                          width: 150,
                          height: 110,
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _skyDark), borderRadius: BorderRadius.circular(6)),
                          clipBehavior: Clip.antiAlias,
                          child: img == null
                              ? const Icon(Icons.image_outlined, size: 40, color: Colors.black26)
                              : Image.file(img, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          _btn('بارگذاری تصویر', _pickImage),
                          IconButton(
                            tooltip: 'حذف تصویر',
                            onPressed: _image.isEmpty ? null : () => setState(() => _image = ''),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935)),
                          ),
                        ]),
                      ]),
                    ]),
                  ]),
                  // ------------------------------------------------ units, prices, stock
                  _section([
                    Row(children: [
                      _lbl('واحد:', width: 120),
                      _f('unit', width: 170),
                      const SizedBox(width: 4),
                      Icon(Icons.star_rounded, color: Colors.amber.shade700),
                      const SizedBox(width: 14),
                      _lbl('واحد لاتین:', width: 100),
                      _f('unitLatin', width: 170, ltr: true, hint: 'Number'),
                      const Spacer(),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _chk('defIn', 'واحد پیش فرض در ورود'),
                        _chk('defOut', 'واحد پیش فرض در خروج'),
                        _chk('countable', 'کالای تعدادی'),
                      ]),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('فی ۱ فروش:', width: 120),
                      _f('sell', width: 200, money: true),
                      const SizedBox(width: 14),
                      _lbl('بهای خرید:', width: 100),
                      _f('buy', width: 200, money: true),
                      const SizedBox(width: 14),
                      _lbl('روز تسویه:', width: 90),
                      _n('settleDays', width: 80),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('فی ۲ فروش:', width: 120),
                      _f('sell2', width: 200, money: true),
                      const SizedBox(width: 14),
                      _lbl('فی ۳ فروش:', width: 100),
                      _f('sell3', width: 200, money: true),
                      const SizedBox(width: 14),
                      _lbl('ریال هدیه:', width: 90),
                      _f('giftRial', width: 110, money: true),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('حداقل موجودی:', width: 120),
                      _n('min'),
                      _lbl(c('unit').text),
                      const SizedBox(width: 8),
                      _lbl('حداکثر موجودی:'),
                      _n('maxQty'),
                      _lbl(c('unit').text),
                      const SizedBox(width: 8),
                      _lbl('نقطه سفارش:'),
                      _n('orderPoint'),
                      _lbl(c('unit').text),
                      const Spacer(),
                      _lbl('درصد هدیه:'),
                      _n('giftPct', width: 80),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('بارکد اصلی:', width: 120),
                      _f('barcode', width: 200, ltr: true),
                      const SizedBox(width: 6),
                      _btn('بارکدهای فرعی', _subBarcodes),
                      const SizedBox(width: 14),
                      _lbl('وزن کیلو گرم:'),
                      _n('weight', width: 100, decimal: true),
                      const Spacer(),
                      _lbl('ریال تخفیف به واحد اول:'),
                      _f('unitDiscount', width: 110, money: true),
                    ]),
                    _gap,
                    Row(children: [
                      _lbl('بارکد ملی:', width: 120),
                      _f('nationalBarcode', width: 200, ltr: true),
                      const SizedBox(width: 14),
                      _lbl('شناسه مالیاتی:'),
                      _f('taxId', width: 200, ltr: true),
                      const Spacer(),
                      _lbl('موجودی اول دوره:'),
                      _n('opening', width: 100, decimal: true),
                    ]),
                  ]),
                  // ------------------------------------------------ options
                  _section([
                    Wrap(spacing: 18, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _chk('hidden', 'مخفی کردن در کاردکس'),
                      _chk('restaurant', 'کالای رستورانی،فروشگاهی'),
                      _chk('autoPrice', 'محاسبه اتوماتیک فی'),
                      _chk('noNegCheck', 'عدم کنترل کاردکس منفی'),
                      _btn('تعیین گروه های یارانه', () => showComingSoon(context, 'تعیین گروه های یارانه')),
                      _btn('تعریف لیستی کالا', () => showComingSoon(context, 'تعریف لیستی کالا')),
                    ]),
                  ]),
                  if (_err != null) Text(_err!, style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            Container(
              color: _sky,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                _btn('انتخاب مرکز دفتر', () => showComingSoon(context, 'انتخاب مرکز دفتر'), icon: Icons.hub_outlined),
                const Spacer(),
                _btn('تایید', _save, key: 'F9', icon: Icons.check_circle_rounded, color: const Color(0xFFD7F2D7)),
                const SizedBox(width: 8),
                _btn('انصراف', () => Navigator.pop(context), key: 'F10', icon: Icons.cancel_rounded, color: const Color(0xFFFBE0E0)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Groups digits while typing money.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = normalizeDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final t = groupDigits(int.parse(digits));
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
