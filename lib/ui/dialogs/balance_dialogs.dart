import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printSlip, printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty, pickPersonId;

/// «لیست خرید بالانس».
Future<void> showBalanceDeals(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _List());

class _List extends StatefulWidget {
  const _List();

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = [...s.balanceDeals]..sort((a, b) => b.date.compareTo(a.date));
    final sel = list.where((d) => d.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'لیست خرید بالانس',
      width: 1150,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            sakanBtn('خرید بالانس', () => showBalanceEditor(context), icon: Icons.add_rounded),
            sakanBtn('برگشت از خرید بالانس', () => showBalanceEditor(context, isReturn: true), icon: Icons.assignment_return_outlined),
            sakanBtn('ویرایش', sel == null ? null : () => showBalanceEditor(context, edit: sel), icon: Icons.edit_outlined),
            sakanBtn('چاپ', sel == null ? null : () => _print(s, sel), icon: Icons.print_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف', '${sel.label} ${sel.number} و سند آن حذف شود؟')) {
                      s.removeBalanceDeal(sel.id);
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('چاپ لیست', () => printTable(
                  store: s,
                  title: 'لیست خرید بالانس',
                  headers: const ['نوع', 'شماره', 'تاریخ', 'فروشنده', 'خریدار', 'مبلغ خرید', 'مبلغ فروش', 'درآمد واسطه گری'],
                  rows: [
                    for (final d in list)
                      [d.label, '${d.number}', jFormat(d.date), s.person(d.sellerId)?.name ?? '', s.person(d.buyerId)?.name ?? '', groupDigits(d.buyTotal), groupDigits(d.sellTotal), groupDigits(d.margin)],
                  ],
                  numeric: const {5, 6, 7},
                  fileName: 'kharid-balans',
                ), icon: Icons.list_alt_rounded),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('نوع', 150), sakanHead('شماره', 70), sakanHead('تاریخ', 95), sakanHead('فروشنده', 0), sakanHead('خریدار', 180), sakanHead('مبلغ خرید', 120), sakanHead('مبلغ فروش', 120), sakanHead('واسطه گری', 110)],
              count: list.length,
              empty: 'خرید بالانسی ثبت نشده',
              row: (ctx, i) {
                final d = list[i];
                final on = d.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                return InkWell(
                  onTap: () => setState(() => _sel = d.id),
                  onDoubleTap: () => showBalanceEditor(context, edit: d),
                  child: Container(
                    color: on ? sakanSel : (d.isReturn ? const Color(0xFFFDF0E6) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text(d.label, style: st), 150),
                      sakanCell(Text('${d.number}', style: st), 70),
                      sakanCell(Text(jFormat(d.date), style: st), 95),
                      sakanCell(Text(s.person(d.sellerId)?.name ?? '', style: st), 0, align: Alignment.centerRight),
                      sakanCell(Text(s.person(d.buyerId)?.name ?? '', style: st, overflow: TextOverflow.ellipsis), 180),
                      sakanCell(Text(groupDigits(d.buyTotal), style: st), 120),
                      sakanCell(Text(groupDigits(d.sellTotal), style: st), 120),
                      sakanCell(Text(groupDigits(d.margin), style: st.copyWith(fontWeight: FontWeight.w700)), 110),
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

  void _print(AppStore s, BalanceDeal d) => printSlip(
        store: s,
        title: '${d.label} شماره ${d.number}',
        narrow: false,
        fields: [
          ('تاریخ', jFormat(d.date)),
          ('فروشنده', s.person(d.sellerId)?.name ?? ''),
          ('خریدار', s.person(d.buyerId)?.name ?? ''),
          if (d.vehicle.isNotEmpty || d.plate.isNotEmpty) ('وسیله نقلیه', '${d.vehicle} ${d.plate}'.trim()),
          if (d.waybill.isNotEmpty) ('شماره بارنامه', d.waybill),
          if (d.carrier.isNotEmpty) ('شرکت باربری', d.carrier),
          if (d.origin.isNotEmpty || d.destination.isNotEmpty) ('مبدا / مقصد', '${d.origin} ← ${d.destination}'),
          ('جمع خرید', groupDigits(d.buyTotal)),
          ('جمع فروش', groupDigits(d.sellTotal)),
          if (d.note.isNotEmpty) ('شرح', d.note),
        ],
        itemHeaders: const ['شرح کالا', 'تعداد', 'فی خرید', 'فی فروش', 'جمع فروش'],
        items: [
          for (final l in d.lines) [s.product(l.productId)?.name ?? l.title, fmtQty(l.qty), groupDigits(l.buyPrice), groupDigits(l.sellPrice), groupDigits(l.sellTotal)],
        ],
        fileName: 'balans-${d.number}',
      );
}

class _Row {
  String? productId;
  final title = TextEditingController();
  final qty = TextEditingController(text: '1');
  final buy = TextEditingController();
  final sell = TextEditingController();
  _Row([BalanceLine? l]) {
    if (l != null) {
      productId = l.productId;
      title.text = l.title;
      qty.text = fmtQty(l.qty);
      buy.text = l.buyPrice == 0 ? '' : groupDigits(l.buyPrice);
      sell.text = l.sellPrice == 0 ? '' : groupDigits(l.sellPrice);
    }
  }
  BalanceLine get line => BalanceLine(productId: productId, title: title.text.trim(), qty: parseQty(qty.text), buyPrice: parseMoney(buy.text), sellPrice: parseMoney(sell.text));
  void dispose() {
    for (final c in [title, qty, buy, sell]) {
      c.dispose();
    }
  }
}

Future<void> showBalanceEditor(BuildContext context, {BalanceDeal? edit, bool isReturn = false}) =>
    showDialog<void>(context: context, builder: (_) => _Editor(edit: edit, isReturn: edit?.isReturn ?? isReturn));

class _Editor extends StatefulWidget {
  final BalanceDeal? edit;
  final bool isReturn;
  const _Editor({this.edit, required this.isReturn});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final BalanceDeal? _e = widget.edit;
  late DateTime _date = _e?.date ?? DateTime.now();
  late String? _seller = _e?.sellerId;
  late String? _buyer = _e?.buyerId;
  late String _income = _e?.incomeAcc ?? mOtherIncome;
  late final List<_Row> _rows = _e == null ? [_Row()] : [for (final l in _e!.lines) _Row(l)];
  late final _sDisc = TextEditingController(text: (_e?.sellerDiscount ?? 0) == 0 ? '' : groupDigits(_e!.sellerDiscount));
  late final _bDisc = TextEditingController(text: (_e?.buyerDiscount ?? 0) == 0 ? '' : groupDigits(_e!.buyerDiscount));
  late final Map<String, TextEditingController> _t = {
    for (final k in ['vehicle', 'plate', 'waybill', 'carrier', 'origin', 'destination', 'note']) k: TextEditingController(text: _field(k)),
  };
  String? _err;

  String _field(String k) => switch (k) {
        'vehicle' => _e?.vehicle ?? '',
        'plate' => _e?.plate ?? '',
        'waybill' => _e?.waybill ?? '',
        'carrier' => _e?.carrier ?? '',
        'origin' => _e?.origin ?? '',
        'destination' => _e?.destination ?? '',
        _ => _e?.note ?? '',
      };

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _sDisc.dispose();
    _bDisc.dispose();
    for (final c in _t.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final title = widget.isReturn ? 'برگشت از خرید بالانس' : 'خرید بالانس';
    final probe = BalanceDeal(id: '', number: 0, date: _date, lines: [for (final r in _rows) r.line], sellerDiscount: parseMoney(_sDisc.text), buyerDiscount: parseMoney(_bDisc.text));
    Widget tf(String k, String label) => Expanded(child: TextField(controller: _t[k], decoration: InputDecoration(labelText: label, isDense: true)));
    return FormDialog(
      title: _e == null ? title : '$title شماره ${_e!.number}',
      width: 1000,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final lines = [for (final r in _rows) if (r.line.qty > 0 && (r.productId != null || r.line.title.isNotEmpty)) r.line];
            if (_seller == null || _buyer == null) return setState(() => _err = 'فروشنده و خریدار را انتخاب کنید');
            if (_seller == _buyer) return setState(() => _err = 'فروشنده و خریدار نمی‌توانند یکی باشند');
            if (lines.isEmpty) return setState(() => _err = 'حداقل یک ردیف کالا وارد کنید');
            s.saveBalanceDeal(BalanceDeal(
              id: _e?.id ?? newId(),
              number: _e?.number ?? s.nextBalanceNumber(widget.isReturn),
              date: _date,
              isReturn: widget.isReturn,
              sellerId: _seller,
              buyerId: _buyer,
              lines: lines,
              sellerDiscount: parseMoney(_sDisc.text),
              buyerDiscount: parseMoney(_bDisc.text),
              incomeAcc: _income,
              vehicle: _t['vehicle']!.text.trim(),
              plate: _t['plate']!.text.trim(),
              waybill: _t['waybill']!.text.trim(),
              carrier: _t['carrier']!.text.trim(),
              origin: _t['origin']!.text.trim(),
              destination: _t['destination']!.text.trim(),
              note: _t['note']!.text.trim(),
              voucherId: _e?.voucherId,
              createdAt: _e?.createdAt,
            ));
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 170, child: DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final id = await pickPersonId(context, title: 'فروشنده');
                if (id != null) setState(() => _seller = id);
              },
              icon: const Icon(Icons.storefront_outlined),
              label: Text('فروشنده: ${s.person(_seller)?.name ?? '—'}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final id = await pickPersonId(context, title: 'خریدار');
                if (id != null) setState(() => _buyer = id);
              },
              icon: const Icon(Icons.person_outline_rounded),
              label: Text('خریدار: ${s.person(_buyer)?.name ?? '—'}'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        for (final r in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  value: r.productId,
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'کالا', isDense: true),
                  items: [const DropdownMenuItem<String?>(value: null, child: Text('— شرح دستی —')), for (final p in s.productsSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name))],
                  onChanged: (v) => setState(() => r.productId = v),
                ),
              ),
              if (r.productId == null) ...[const SizedBox(width: 6), Expanded(flex: 2, child: TextField(controller: r.title, decoration: const InputDecoration(labelText: 'شرح', isDense: true)))],
              const SizedBox(width: 6),
              SizedBox(width: 80, child: TextField(controller: r.qty, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تعداد', isDense: true), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 6),
              SizedBox(
                width: 130,
                child: TextField(controller: r.buy, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'فی خرید', isDense: true), onChanged: (_) => setState(() {})),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 130,
                child: TextField(controller: r.sell, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'فی فروش', isDense: true), onChanged: (_) => setState(() {})),
              ),
              IconButton(
                onPressed: _rows.length == 1
                    ? null
                    : () => setState(() {
                          _rows.remove(r);
                          r.dispose();
                        }),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ]),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(onPressed: () => setState(() => _rows.add(_Row())), icon: const Icon(Icons.add_rounded), label: const Text('افزودن ردیف')),
        ),
        Row(children: [
          SizedBox(width: 160, child: TextField(controller: _sDisc, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'تخفیف فروشنده', isDense: true), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          SizedBox(width: 160, child: TextField(controller: _bDisc, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'تخفیف به خریدار', isDense: true), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _income,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'حساب درآمد واسطه گری', isDense: true),
              items: [for (final m in allMoeens) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _income = v ?? _income),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [tf('vehicle', 'نام وسیله نقلیه'), const SizedBox(width: 6), tf('plate', 'شماره وسیله نقلیه'), const SizedBox(width: 6), tf('waybill', 'شماره بارنامه'), const SizedBox(width: 6), tf('carrier', 'نام شرکت باربری')]),
        const SizedBox(height: 8),
        Row(children: [tf('origin', 'مبدا حرکت'), const SizedBox(width: 6), tf('destination', 'مقصد حرکت'), const SizedBox(width: 6), tf('note', 'شرح')]),
        const SizedBox(height: 10),
        Text('جمع خرید (بدهی به فروشنده): ${groupDigits(probe.buyTotal)}    جمع فروش (طلب از خریدار): ${groupDigits(probe.sellTotal)}    درآمد واسطه گری: ${groupDigits(probe.margin)}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
