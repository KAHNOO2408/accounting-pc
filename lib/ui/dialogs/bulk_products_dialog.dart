import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart' show normalizeDigits;
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// «تعریف لیستی کالا» — define many products at once in a grid.
Future<void> showBulkProducts(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Bulk());

class _Row {
  final name = TextEditingController();
  final code = TextEditingController();
  final unit = TextEditingController(text: 'عدد');
  final barcode = TextEditingController();
  final buy = TextEditingController();
  final sell = TextEditingController();
  List<TextEditingController> get all => [name, code, unit, barcode, buy, sell];
  bool get empty => name.text.trim().isEmpty;
}

class _Bulk extends StatefulWidget {
  const _Bulk();

  @override
  State<_Bulk> createState() => _BulkState();
}

class _BulkState extends State<_Bulk> {
  final List<_Row> _rows = [];
  String? _err;
  int _next = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows.isEmpty) {
      _next = StoreScope.read(context).nextTafsiliCode();
      for (var i = 0; i < 10; i++) {
        _add();
      }
    }
  }

  void _add() {
    final r = _Row()..code.text = '${_next++}';
    _rows.add(r);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      for (final c in r.all) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final rows = _rows.where((r) => !r.empty).toList();
    if (rows.isEmpty) return setState(() => _err = 'نام هیچ کالایی وارد نشده');
    final codes = <String>{};
    for (final r in rows) {
      final c = r.code.text.trim();
      if (c.isNotEmpty && (!codes.add(c) || s.products.any((p) => p.code == c) || s.people.any((p) => '${p.code}' == normalizeDigits(c)))) {
        return setState(() => _err = 'کد $c تکراری است');
      }
    }
    for (final r in rows) {
      s.upsertProduct(Product(
        id: newId(),
        name: r.name.text.trim(),
        code: r.code.text.trim(),
        unit: r.unit.text.trim().isEmpty ? 'عدد' : r.unit.text.trim(),
        buyPrice: parseMoney(r.buy.text),
        sellPrice: parseMoney(r.sell.text),
        info: {if (r.barcode.text.trim().isNotEmpty) 'barcode': r.barcode.text.trim()},
      ));
    }
    Navigator.pop(context);
    toast(context, '${rows.length} کالا تعریف شد');
  }

  @override
  Widget build(BuildContext context) {
    const w = [44.0, 0.0, 110.0, 90.0, 150.0, 130.0, 130.0];
    Widget cell(TextEditingController c, {bool money = false, bool ltr = false}) => TextField(
          controller: c,
          textDirection: money || ltr ? TextDirection.ltr : null,
          inputFormatters: money ? [MoneyInputFormatter()] : null,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.insert): () => setState(_add),
      },
      child: SakanWindow(
        title: 'تعریف لیستی کالا',
        width: 1000,
        height: 640,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              sakanBtn('افزودن ردیف', () => setState(_add), key: 'Ins', icon: Icons.add_rounded),
              const SizedBox(width: 10),
              const Text('ردیف‌هایی که نام ندارند ذخیره نمی‌شوند.'),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: SakanGrid(
                header: [
                  sakanHead('ردیف', w[0]),
                  sakanHead('نام کالا', w[1]),
                  sakanHead('کد', w[2]),
                  sakanHead('واحد', w[3]),
                  sakanHead('بارکد', w[4]),
                  sakanHead('بهای خرید', w[5]),
                  sakanHead('بهای فروش', w[6]),
                ],
                count: _rows.length,
                row: (ctx, i) {
                  final r = _rows[i];
                  return Container(
                    color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                    child: Row(children: [
                      sakanCell(Text('${i + 1}'), w[0]),
                      sakanCell(cell(r.name), w[1]),
                      sakanCell(cell(r.code, ltr: true), w[2]),
                      sakanCell(cell(r.unit), w[3]),
                      sakanCell(cell(r.barcode, ltr: true), w[4]),
                      sakanCell(cell(r.buy, money: true), w[5]),
                      sakanCell(cell(r.sell, money: true), w[6]),
                    ]),
                  );
                },
              ),
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 8),
            Row(children: [
              const Spacer(),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('تایید F9')),
            ]),
          ]),
        ),
      ),
    );
  }
}
