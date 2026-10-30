import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

/// «تنظیمات فاکتور فروش / خرید» — Sakan's invoice options, in tabs like Sakan.
Future<void> showInvoiceOptionsDialog(BuildContext context, {required bool buy}) =>
    showDialog<void>(context: context, builder: (_) => _OptionsDialog(buy: buy));

class _OptionsDialog extends StatefulWidget {
  final bool buy;
  const _OptionsDialog({required this.buy});

  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  late InvoiceOptions _o;
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _inv = TextEditingController();
  final _slip = TextEditingController();
  int _tab = 0;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final st = StoreScope.read(context).settings;
    _o = InvoiceOptions.fromJson((widget.buy ? st.buyOptions : st.saleOptions).toJson());
    _min.text = fmtQty(_o.minPct);
    _max.text = fmtQty(_o.maxPct);
    _inv.text = '${_o.invoiceCopies}';
    _slip.text = '${_o.slipCopies}';
  }

  @override
  void dispose() {
    for (final c in [_min, _max, _inv, _slip]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    _o
      ..minPct = parseQty(_min.text)
      ..maxPct = parseQty(_max.text)
      ..invoiceCopies = (int.tryParse(_inv.text.trim()) ?? 1).clamp(1, 9)
      ..slipCopies = (int.tryParse(_slip.text.trim()) ?? 1).clamp(1, 9);
    StoreScope.read(context).updateSettings((s) {
      if (widget.buy) {
        s.buyOptions = _o;
      } else {
        s.saleOptions = _o;
      }
    });
    Navigator.pop(context);
  }

  Widget _yes(String label, bool v, ValueChanged<bool> on) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: v,
        title: Text(label),
        onChanged: (x) => setState(() => on(x ?? false)),
      );

  Widget _num(TextEditingController c, String label, {String suffix = ''}) => SizedBox(
        width: 260,
        child: TextField(controller: c, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true)),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final b = widget.buy;
    final tabs = b ? const ['فاکتور', 'پیغام ها', 'چاپ'] : const ['تنظیمات فروش', 'کنترل فی', 'فروش منفی', 'نمایش پیغام ها', 'ارزش افزوده', 'تنظیمات چاپ'];
    final o = _o;
    final unitNames = const ['واحد پیش فرض کالا', 'واحد 1', 'واحد 2', 'واحد 3'];
    Widget body;
    final page = b ? const [0, 3, 5][_tab] : _tab;
    switch (page) {
      case 0:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _yes('فراخوانی اتوماتیک آخرین فی ${b ? 'خرید' : 'فروش'}', o.lastFi, (v) => o.lastFi = v),
          _yes('آخرین فی بر اساس ${b ? 'فروشنده' : 'خریدار'}', o.lastFiByPerson, (v) => o.lastFiByPerson = v),
          _yes('اجازه ثبت کالای تکراری', o.allowDuplicate, (v) => o.allowDuplicate = v),
          _yes('زبان نام کالا: لاتین (در صورت تعریف)', o.latinNames, (v) => o.latinNames = v),
          if (!b) _yes('شماره درخواست بصورت خودکار پیشنهاد داده شود', o.autoRequestNo, (v) => o.autoRequestNo = v),
          _yes('باز کردن مجدد فرم ${b ? 'خرید' : 'فروش'} بعد از ثبت سند جدید', o.reopenAfterSave, (v) => o.reopenAfterSave = v),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 10, children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                value: o.defaultUnit,
                decoration: const InputDecoration(labelText: 'واحد پیش فرض', isDense: true),
                items: [for (var i = 0; i < 4; i++) DropdownMenuItem(value: i, child: Text(unitNames[i]))],
                onChanged: (v) => setState(() => o.defaultUnit = v ?? 0),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: s.warehouses.any((w) => w.id == o.defaultWarehouseId) ? o.defaultWarehouseId : null,
                decoration: const InputDecoration(labelText: 'انبار پیش فرض', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('انبار اصلی')),
                  for (final w in s.warehouses) DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => o.defaultWarehouseId = v),
              ),
            ),
          ]),
        ]);
      case 1:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _yes('کنترل حداقل و حداکثر فی فروش (فاکتور فروش)', o.priceRange, (v) => o.priceRange = v),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 10, children: [
            _num(_min, 'حداقل فی: درصد پایین‌تر از فی فروش کالا', suffix: '٪'),
            _num(_max, 'حداکثر فی: درصد بالاتر از فی فروش کالا (۰ = بدون سقف)', suffix: '٪'),
          ]),
          const SizedBox(height: 6),
          _yes('مجوز وارد کردن فی خارج از محدوده تعیین شده (با پیغام)', o.allowOutOfRange, (v) => o.allowOutOfRange = v),
        ]);
      case 2:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _yes('اجازه فروش منفی', o.allowNegative, (v) => o.allowNegative = v),
          Text('اگر خاموش باشد، فاکتوری که موجودی کالایی را منفی کند ثبت نمی‌شود.', style: Theme.of(context).textTheme.bodySmall),
        ]);
      case 3:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!b) ...[
            _yes('نمایش پیغام فروش منفی', o.msgNegative, (v) => o.msgNegative = v),
            _yes('نمایش پیغام حداقل موجودی', o.msgMinStock, (v) => o.msgMinStock = v),
            _yes('نمایش پیغام رسیدن به نقطه سفارش', o.msgOrderPoint, (v) => o.msgOrderPoint = v),
          ],
          if (b) _yes('نمایش پیغام خرید بیش از حداکثر موجودی', o.msgMaxStock, (v) => o.msgMaxStock = v),
          _yes('نمایش پیغام آخرین فی', o.msgLastFi, (v) => o.msgLastFi = v),
        ]);
      case 4:
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _yes('محاسبات ارزش افزوده از جمع بعد از تخفیف محاسبه گردد', o.vatAfterDiscount, (v) => o.vatAfterDiscount = v),
          Text('نرخ پیش فرض مالیات و عوارض در «تنظیمات» برنامه تعیین می‌شود.', style: Theme.of(context).textTheme.bodySmall),
        ]);
      default:
        body = Wrap(spacing: 12, runSpacing: 10, children: [
          _num(_inv, 'تعداد چاپ فاکتور'),
          _num(_slip, b ? 'تعداد چاپ رسید انبار' : 'تعداد چاپ حواله'),
        ]);
    }
    return FormDialog(
      title: b ? 'تنظیمات فاکتور خرید' : 'تنظیمات فاکتور فروش',
      width: 720,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(onPressed: _save, child: const Text('تایید F9')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var i = 0; i < tabs.length; i++) ChoiceChip(label: Text(tabs[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
        ]),
        const SizedBox(height: 12),
        body,
      ]),
    );
  }
}
