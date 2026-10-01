import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

Future<String?> showProductDialog(BuildContext context, {Product? edit}) =>
    showDialog<String>(context: context, builder: (_) => _ProductDialog(edit: edit));

class _ProductDialog extends StatefulWidget {
  final Product? edit;
  const _ProductDialog({this.edit});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name, _code, _unit, _buy, _sell, _sell2, _sell3, _opening, _min, _note;
  String? _err;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _unit = TextEditingController(text: e?.unit ?? 'عدد');
    _buy = TextEditingController(text: (e?.buyPrice ?? 0) == 0 ? '' : groupDigits(e!.buyPrice));
    _sell = TextEditingController(text: (e?.sellPrice ?? 0) == 0 ? '' : groupDigits(e!.sellPrice));
    _sell2 = TextEditingController(text: (e?.sellPrice2 ?? 0) == 0 ? '' : groupDigits(e!.sellPrice2));
    _sell3 = TextEditingController(text: (e?.sellPrice3 ?? 0) == 0 ? '' : groupDigits(e!.sellPrice3));
    _opening = TextEditingController(text: e == null ? '0' : fmtQty(e.openingQty));
    _min = TextEditingController(text: e == null ? '0' : fmtQty(e.minQty));
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _unit, _buy, _sell, _sell2, _sell3, _opening, _min, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'نام کالا را وارد کنید');
      return;
    }
    final p = widget.edit ?? Product(id: newId(), name: '');
    p
      ..name = _name.text.trim()
      ..code = _code.text.trim()
      ..unit = _unit.text.trim().isEmpty ? 'عدد' : _unit.text.trim()
      ..buyPrice = parseMoney(_buy.text)
      ..sellPrice = parseMoney(_sell.text)
      ..sellPrice2 = parseMoney(_sell2.text)
      ..sellPrice3 = parseMoney(_sell3.text)
      ..openingQty = parseQty(_opening.text)
      ..minQty = parseQty(_min.text)
      ..note = _note.text.trim();
    StoreScope.read(context).upsertProduct(p);
    Navigator.pop(context, p.id);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return FormDialog(
      title: widget.edit == null ? 'کالای جدید' : 'ویرایش کالا',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'نام کالا / خدمت'),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _code,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'کد / بارکد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MoneyField(controller: _buy, label: 'قیمت خرید')),
              const SizedBox(width: 12),
              Expanded(child: MoneyField(controller: _sell, label: 'بهای فروش ۱')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MoneyField(controller: _sell2, label: 'بهای فروش ۲')),
              const SizedBox(width: 12),
              Expanded(child: MoneyField(controller: _sell3, label: 'بهای فروش ۳')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'واحد (عدد، کیلو، متر…)'))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _opening,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'موجودی اول دوره'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _min,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'حداقل موجودی (هشدار)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'توضیحات')),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
