import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printSlip, printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show pickPersonId, showInvoiceEditor;

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Widget _personButton(BuildContext context, AppStore s, String? id, String label, ValueChanged<String> onPick) => OutlinedButton.icon(
      onPressed: () async {
        final r = await pickPersonId(context, title: label);
        if (r != null) onPick(r);
      },
      icon: const Icon(Icons.person_search_rounded),
      label: Text(s.person(id)?.name ?? label, overflow: TextOverflow.ellipsis),
    );

Widget _productDrop(AppStore s, String? value, ValueChanged<String?> onChanged) => DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'کالا'),
      items: [const DropdownMenuItem<String?>(value: null, child: Text('— نام دستی —')), for (final p in s.productsSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name))],
      onChanged: onChanged,
    );

// ================================================================ لیست گارانتی

Future<void> showWarranties(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Warranties());

class _Warranties extends StatefulWidget {
  const _Warranties();

  @override
  State<_Warranties> createState() => _WarrantiesState();
}

class _WarrantiesState extends State<_Warranties> {
  String? _sel;
  String _q = '';
  bool _activeOnly = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final now = DateTime.now();
    final list = s.warranties.where((w) {
      if (_activeOnly && !w.activeAt(now)) return false;
      if (_q.isEmpty) return true;
      return '${w.code}' == _q || w.serial.contains(_q) || w.currentSerial.contains(_q) || w.productName.contains(_q) || (s.person(w.personId)?.name.contains(_q) ?? false);
    }).toList()
      ..sort((a, b) => b.code.compareTo(a.code));
    final sel = list.where((w) => w.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'لیست گارانتی',
      width: 1150,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('صدور گارانتی', () => showWarrantyEditor(context), key: 'Ins', icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => showWarrantyEditor(context, edit: sel), icon: Icons.edit_outlined),
            sakanBtn('اعمال گارانتی', sel == null ? null : () => showWarrantyEvent(context, sel), icon: Icons.build_circle_outlined),
            sakanBtn('پذیرش', sel == null ? null : () => showReceptionEditor(context, warranty: sel), icon: Icons.handyman_outlined),
            sakanBtn('چاپ برگ گارانتی', sel == null ? null : () => _printCard(s, sel), icon: Icons.print_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف گارانتی', 'گارانتی ${sel.code} حذف شود؟')) {
                      s.warranties.removeWhere((w) => w.id == sel.id);
                      s.updateSettings((_) {});
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            SizedBox(width: 220, child: TextField(decoration: const InputDecoration(hintText: 'کد، سریال، کالا یا مشتری', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            FilterChip(label: const Text('فقط گارانتی‌های فعال'), selected: _activeOnly, onSelected: (v) => setState(() => _activeOnly = v)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('کد گارانتی', 80),
                sakanHead('نام کالا', 0),
                sakanHead('سریال کالا', 140),
                sakanHead('مشتری', 170),
                sakanHead('شروع', 95),
                sakanHead('اتمام', 95),
                sakanHead('شماره فاکتور', 90),
                sakanHead('اعمال', 60),
                sakanHead('وضعیت', 80),
              ],
              count: list.length,
              empty: 'گارانتی ثبت نشده',
              row: (ctx, i) {
                final w = list[i];
                final on = w.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                final active = w.activeAt(now);
                return InkWell(
                  onTap: () => setState(() => _sel = w.id),
                  onDoubleTap: () => showWarrantyEditor(context, edit: w),
                  child: Container(
                    color: on ? sakanSel : (!active ? const Color(0xFFF6E7E7) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text('${w.code}', style: st), 80),
                      sakanCell(Text(w.productName, style: st, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                      sakanCell(Text(w.currentSerial, style: st), 140),
                      sakanCell(Text(s.person(w.personId)?.name ?? w.receiver, style: st, overflow: TextOverflow.ellipsis), 170),
                      sakanCell(Text(jFormat(w.start), style: st), 95),
                      sakanCell(Text(jFormat(w.end), style: st), 95),
                      sakanCell(Text(w.invoiceNo == 0 ? '' : '${w.invoiceNo}', style: st), 90),
                      sakanCell(Text('${w.events.length}', style: st), 60),
                      sakanCell(Text(active ? 'فعال' : 'منقضی', style: st), 80),
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

  void _printCard(AppStore s, Warranty w) => printSlip(
        store: s,
        title: 'برگ گارانتی',
        narrow: false,
        fields: [
          ('کد گارانتی', '${w.code}'),
          ('نام کالا', w.productName),
          ('سریال کالا', w.currentSerial),
          ('مشتری', s.person(w.personId)?.name ?? w.receiver),
          ('تاریخ شروع گارانتی', jFormat(w.start)),
          ('تاریخ اتمام گارانتی', jFormat(w.end)),
          if (w.invoiceNo != 0) ('شماره فاکتور', '${w.invoiceNo}'),
          if (w.contractNo.isNotEmpty) ('شماره قرارداد', w.contractNo),
          if (w.note.isNotEmpty) ('شرایط', w.note),
        ],
        itemHeaders: const ['تاریخ', 'نوع', 'سریال جدید', 'توضیحات'],
        items: [for (final e in w.events) [jFormat(e.date), e.kind, e.newSerial, e.note]],
        footer: 'مهر و امضای فروشنده',
        fileName: 'garanti-${w.code}',
      );
}

Future<void> showWarrantyEditor(BuildContext context, {Warranty? edit, Invoice? fromInvoice}) =>
    showDialog<void>(context: context, builder: (_) => _WarrantyEditor(edit: edit, fromInvoice: fromInvoice));

class _WarrantyEditor extends StatefulWidget {
  final Warranty? edit;
  final Invoice? fromInvoice;
  const _WarrantyEditor({this.edit, this.fromInvoice});

  @override
  State<_WarrantyEditor> createState() => _WarrantyEditorState();
}

class _WarrantyEditorState extends State<_WarrantyEditor> {
  late final Warranty? _e = widget.edit;
  late String? _product = _e?.productId;
  late String? _person = _e?.personId ?? widget.fromInvoice?.personId;
  late DateTime _start = _e?.start ?? widget.fromInvoice?.date ?? DateTime.now();
  late DateTime _end = _e?.end ?? DateTime(_start.year + 1, _start.month, _start.day);
  late final _name = TextEditingController(text: _e?.productName ?? '');
  late final _serial = TextEditingController(text: _e?.serial ?? '');
  late final _receiver = TextEditingController(text: _e?.receiver ?? '');
  late final _invoice = TextEditingController(text: _e == null ? (widget.fromInvoice == null ? '' : '${widget.fromInvoice!.number}') : (_e!.invoiceNo == 0 ? '' : '${_e!.invoiceNo}'));
  late final _contract = TextEditingController(text: _e?.contractNo ?? '');
  late final _note = TextEditingController(text: _e?.note ?? '');
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _serial, _receiver, _invoice, _contract, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return FormDialog(
      title: _e == null ? 'صدور گارانتی' : 'ویرایش گارانتی ${_e!.code}',
      width: 720,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final name = s.product(_product)?.name ?? _name.text.trim();
            if (name.isEmpty) return setState(() => _err = 'کالا را انتخاب یا نام آن را وارد کنید');
            if (_end.isBefore(_start)) return setState(() => _err = 'تاریخ اتمام قبل از تاریخ شروع است');
            final serial = _serial.text.trim();
            if (serial.isNotEmpty && s.warranties.any((w) => w.id != _e?.id && w.serial == serial && w.productName == name)) {
              return setState(() => _err = 'برای این سریال قبلا گارانتی صادر شده');
            }
            s.saveWarranty((_e ?? Warranty(id: newId(), code: s.nextWarrantyCode(), start: _start, end: _end))
              ..productId = _product
              ..productName = name
              ..serial = serial
              ..start = _start
              ..end = _end
              ..personId = _person
              ..receiver = _receiver.text.trim()
              ..invoiceNo = int.tryParse(normalizeDigits(_invoice.text.trim())) ?? 0
              ..contractNo = _contract.text.trim()
              ..note = _note.text.trim());
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _productDrop(s, _product, (v) => setState(() => _product = v))),
          if (_product == null) ...[const SizedBox(width: 8), Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام کالا')))],
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _serial, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سریال کالا'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _personButton(context, s, _person, 'مشتری', (v) => setState(() => _person = v))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _receiver, decoration: const InputDecoration(labelText: 'نام دریافت کننده'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: DateField(label: 'تاریخ شروع گارانتی / قرارداد', value: _start, onChanged: (d) => setState(() => _start = d ?? _start))),
          const SizedBox(width: 8),
          Expanded(child: DateField(label: 'تاریخ اتمام گارانتی / قرارداد', value: _end, onChanged: (d) => setState(() => _end = d ?? _end))),
          const SizedBox(width: 8),
          for (final m in [6, 12, 18, 24])
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ActionChip(label: Text('$m ماه'), onPressed: () => setState(() => _end = DateTime(_start.year, _start.month + m, _start.day))),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _invoice, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره فاکتور'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _contract, decoration: const InputDecoration(labelText: 'شماره قرارداد'))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'شرایط و توضیحات')),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}

/// «اعمال گارانتی»: replacement / substitution / repair under warranty.
Future<void> showWarrantyEvent(BuildContext context, Warranty w) async {
  final s = StoreScope.read(context);
  var date = DateTime.now();
  var kind = 'تعمیر';
  final serial = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => FormDialog(
        title: 'اعمال گارانتی ${w.code} — ${w.productName}',
        width: 480,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!w.activeAt(date)) const Text('توجه: گارانتی در این تاریخ منقضی شده است', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'تعمیر', label: Text('تعمیر')), ButtonSegment(value: 'تعویض', label: Text('تعویض')), ButtonSegment(value: 'جایگزین', label: Text('جایگزین'))],
            selected: {kind},
            onSelectionChanged: (v) => set(() => kind = v.first),
          ),
          const SizedBox(height: 8),
          DateField(label: 'تاریخ تعویض یا جایگزین', value: date, onChanged: (d) => set(() => date = d ?? date)),
          if (kind != 'تعمیر') ...[
            const SizedBox(height: 8),
            TextField(controller: serial, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'سریال کالای جدید')),
          ],
          const SizedBox(height: 8),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
      ),
    ),
  );
  if (ok == true) {
    w.events.add(WarrantyEvent(date: date, kind: kind, newSerial: kind == 'تعمیر' ? '' : serial.text.trim(), note: note.text.trim()));
    s.saveWarranty(w);
  }
  serial.dispose();
  note.dispose();
}

// ================================================================ پذیرش

Future<void> showReceptions(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Receptions());

class _Receptions extends StatefulWidget {
  const _Receptions();

  @override
  State<_Receptions> createState() => _ReceptionsState();
}

class _ReceptionsState extends State<_Receptions> {
  String? _sel;
  String? _status;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.receptions.where((r) {
      if (_status != null && r.status != _status) return false;
      if (_q.isEmpty) return true;
      return '${r.number}' == _q || r.serial.contains(_q) || r.productName.contains(_q) || (s.person(r.personId)?.name.contains(_q) ?? false);
    }).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final sel = list.where((r) => r.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'پذیرش و تعمیرات',
      width: 1180,
      height: 660,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('پذیرش جدید', () => showReceptionEditor(context), key: 'Ins', icon: Icons.add_rounded),
            sakanBtn('ویرایش / تعمیر', sel == null ? null : () => showReceptionEditor(context, edit: sel), icon: Icons.handyman_outlined),
            sakanBtn('رسید مشتری', sel == null ? null : () => printReceptionReceipt(s, sel), icon: Icons.receipt_outlined),
            sakanBtn('برچسب تعمیر', sel == null ? null : () => printRepairLabel(s, sel), icon: Icons.label_outline_rounded),
            sakanBtn('صدور فاکتور', sel == null || sel.cost <= 0
                ? null
                : () {
                    final inv = s.receptionInvoice(sel);
                    showInvoiceEditor(context, edit: inv);
                  }, icon: Icons.request_quote_outlined),
            sakanBtn('تحویل به مشتری', sel == null || sel.deliveredOn != null
                ? null
                : () {
                    sel
                      ..deliveredOn = DateTime.now()
                      ..status = 'تحویل شده';
                    s.saveReception(sel);
                  }, icon: Icons.assignment_turned_in_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف پذیرش', 'پذیرش ${sel.number} حذف شود؟')) {
                      s.receptions.removeWhere((r) => r.id == sel.id);
                      s.updateSettings((_) {});
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('چاپ لیست', () => printTable(
                  store: s,
                  title: 'لیست پذیرش',
                  headers: const ['شماره', 'تاریخ', 'مشتری', 'کالا', 'سریال', 'ایراد', 'وضعیت', 'هزینه'],
                  rows: [
                    for (final r in list) ['${r.number}', jFormat(r.date), s.person(r.personId)?.name ?? '', r.productName, r.serial, r.problem, r.status, groupDigits(r.cost)],
                  ],
                  numeric: const {7},
                  fileName: 'paziresh',
                ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 240, child: TextField(decoration: const InputDecoration(hintText: 'شماره، سریال، کالا یا مشتری', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(spacing: 4, children: [
                ChoiceChip(label: const Text('همه'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                for (final st in receptionStatuses)
                  ChoiceChip(label: Text('$st (${s.receptions.where((r) => r.status == st).length})'), selected: _status == st, onSelected: (_) => setState(() => _status = st)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('شماره پذیرش', 85),
                sakanHead('تاریخ', 120),
                sakanHead('مشتری', 160),
                sakanHead('کالا', 0),
                sakanHead('سریال', 120),
                sakanHead('گارانتی', 70),
                sakanHead('ایراد', 170),
                sakanHead('وضعیت', 105),
                sakanHead('هزینه', 105),
              ],
              count: list.length,
              empty: 'پذیرشی ثبت نشده',
              row: (ctx, i) {
                final r = list[i];
                final on = r.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                return InkWell(
                  onTap: () => setState(() => _sel = r.id),
                  onDoubleTap: () => showReceptionEditor(context, edit: r),
                  child: Container(
                    color: on ? sakanSel : (r.status == 'آماده تحویل' ? const Color(0xFFE6F6E6) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text('${r.number}', style: st), 85),
                      sakanCell(Text('${jFormat(r.date)} ${_hm(r.date)}', style: st), 120),
                      sakanCell(Text(s.person(r.personId)?.name ?? '', style: st, overflow: TextOverflow.ellipsis), 160),
                      sakanCell(Text(r.productName, style: st, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                      sakanCell(Text(r.serial, style: st), 120),
                      sakanCell(Text(r.warrantyCode == 0 ? '' : '${r.warrantyCode}', style: st), 70),
                      sakanCell(Text(r.problem, style: st, overflow: TextOverflow.ellipsis), 170),
                      sakanCell(Text(r.status, style: st), 105),
                      sakanCell(Text(groupDigits(r.cost == 0 ? r.estimate : r.cost), style: st), 105),
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
}

/// «رسید مشتری».
void printReceptionReceipt(AppStore s, Reception r) => printSlip(
      store: s,
      title: 'رسید پذیرش کالا',
      copies: 2,
      fields: [
        ('شماره پذیرش', '${r.number}'),
        ('تاریخ تحویل از مشتری', '${jFormat(r.date)} ساعت ${_hm(r.date)}'),
        ('نام مشتری', s.person(r.personId)?.name ?? ''),
        if ((s.person(r.personId)?.phone ?? '').isNotEmpty) ('تلفن', s.person(r.personId)!.phone),
        ('نام کالا', r.productName),
        if (r.serial.isNotEmpty) ('شماره سریال', r.serial),
        if (r.warrantyCode != 0) ('شماره گارانتی', '${r.warrantyCode}'),
        ('ایراد اعلام شده', r.problem),
        if (r.accessories.isNotEmpty) ('لوازم همراه', r.accessories),
        if (r.estimate != 0) ('هزینه تقریبی', groupDigits(r.estimate)),
        if (r.promised != null) ('تاریخ تحویل احتمالی', jFormat(r.promised!)),
        if (r.location.isNotEmpty) ('مکان پذیرش', r.location),
        ('پذیرش کننده', r.user),
      ],
      footer: 'ارائه این رسید هنگام تحویل کالا الزامی است',
      fileName: 'resid-paziresh-${r.number}',
    );

/// «برچسب تعمیر» stuck on the device.
void printRepairLabel(AppStore s, Reception r) => printSlip(
      store: s,
      title: 'پذیرش ${r.number}',
      fields: [
        ('مشتری', s.person(r.personId)?.name ?? ''),
        ('کالا', r.productName),
        if (r.serial.isNotEmpty) ('سریال', r.serial),
        ('ایراد', r.problem),
        ('تاریخ', jFormat(r.date)),
        if (r.promised != null) ('تحویل', jFormat(r.promised!)),
      ],
      fileName: 'barchasb-tamir-${r.number}',
    );

Future<void> showReceptionEditor(BuildContext context, {Reception? edit, Warranty? warranty}) =>
    showDialog<void>(context: context, builder: (_) => _ReceptionEditor(edit: edit, warranty: warranty));

class _ReceptionEditor extends StatefulWidget {
  final Reception? edit;
  final Warranty? warranty;
  const _ReceptionEditor({this.edit, this.warranty});

  @override
  State<_ReceptionEditor> createState() => _ReceptionEditorState();
}

class _ReceptionEditorState extends State<_ReceptionEditor> {
  late final Reception? _e = widget.edit;
  late String? _person = _e?.personId ?? widget.warranty?.personId;
  late String? _product = _e?.productId ?? widget.warranty?.productId;
  late int _warranty = _e?.warrantyCode ?? widget.warranty?.code ?? 0;
  late String _status = _e?.status ?? receptionStatuses.first;
  late DateTime _date = _e?.date ?? DateTime.now();
  late DateTime? _promised = _e?.promised;
  late final _name = TextEditingController(text: _e?.productName ?? widget.warranty?.productName ?? '');
  late final _serial = TextEditingController(text: _e?.serial ?? widget.warranty?.currentSerial ?? '');
  late final _location = TextEditingController(text: _e?.location ?? '');
  late final _problem = TextEditingController(text: _e?.problem ?? '');
  late final _acc = TextEditingController(text: _e?.accessories ?? '');
  late final _estimate = TextEditingController(text: _e == null || _e!.estimate == 0 ? '' : groupDigits(_e!.estimate));
  late final _repair = TextEditingController(text: _e?.repairNote ?? '');
  late final _cost = TextEditingController(text: _e == null || _e!.cost == 0 ? '' : groupDigits(_e!.cost));
  String? _err;
  bool _print = true;

  @override
  void dispose() {
    for (final c in [_name, _serial, _location, _problem, _acc, _estimate, _repair, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  void _lookup(AppStore s) {
    final w = s.findWarranty(_serial.text);
    setState(() {
      if (w == null) {
        _warranty = 0;
        _err = 'گارانتی با این سریال پیدا نشد';
        return;
      }
      _err = null;
      _warranty = w.code;
      _person ??= w.personId;
      _product ??= w.productId;
      if (_name.text.isEmpty) _name.text = w.productName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final w = s.warranties.where((x) => x.code == _warranty && _warranty != 0).firstOrNull;
    return FormDialog(
      title: _e == null ? 'پذیرش کالا' : 'پذیرش ${_e!.number}',
      width: 820,
      leading: _e == null ? Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: _print, onChanged: (v) => setState(() => _print = v ?? true)), const Text('چاپ رسید مشتری')]) : null,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final name = s.product(_product)?.name ?? _name.text.trim();
            if (_person == null) return setState(() => _err = 'مشتری را انتخاب کنید');
            if (name.isEmpty) return setState(() => _err = 'کالا را انتخاب یا نام آن را وارد کنید');
            if (_problem.text.trim().isEmpty) return setState(() => _err = 'ایراد اعلام شده را وارد کنید');
            final r = (_e ?? Reception(id: newId(), number: s.nextReceptionNumber(), date: _date))
              ..date = _date
              ..personId = _person
              ..productId = _product
              ..productName = name
              ..serial = _serial.text.trim()
              ..warrantyCode = _warranty
              ..location = _location.text.trim()
              ..problem = _problem.text.trim()
              ..accessories = _acc.text.trim()
              ..estimate = parseMoney(_estimate.text)
              ..promised = _promised
              ..status = _status
              ..repairNote = _repair.text.trim()
              ..cost = parseMoney(_cost.text);
            if (_status == 'تحویل شده') r.deliveredOn ??= DateTime.now();
            s.saveReception(r);
            Navigator.pop(context);
            if (_e == null && _print) printReceptionReceipt(s, r);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _personButton(context, s, _person, 'مشتری', (v) => setState(() => _person = v))),
          const SizedBox(width: 8),
          SizedBox(width: 160, child: DateField(label: 'تاریخ تحویل از مشتری', value: _date, onChanged: (d) => setState(() => _date = d == null ? _date : DateTime(d.year, d.month, d.day, _date.hour, _date.minute)))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _location, decoration: const InputDecoration(labelText: 'مکان پذیرش'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _productDrop(s, _product, (v) => setState(() => _product = v))),
          if (_product == null) ...[const SizedBox(width: 8), Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام کالا')))],
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _serial,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'شماره سریال',
                suffixIcon: IconButton(tooltip: 'جستجوی گارانتی', onPressed: () => _lookup(s), icon: const Icon(Icons.verified_outlined)),
              ),
              onSubmitted: (_) => _lookup(s),
            ),
          ),
        ]),
        if (w != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'گارانتی ${w.code}: ${jFormat(w.start)} تا ${jFormat(w.end)} — ${w.activeAt(_date) ? 'فعال' : 'منقضی شده'}',
              style: TextStyle(color: w.activeAt(_date) ? Colors.green.shade800 : Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 8),
        TextField(controller: _problem, maxLines: 2, decoration: const InputDecoration(labelText: 'ایراد اعلام شده')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _acc, decoration: const InputDecoration(labelText: 'لوازم همراه'))),
          const SizedBox(width: 8),
          SizedBox(width: 150, child: TextField(controller: _estimate, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'هزینه تقریبی'))),
          const SizedBox(width: 8),
          SizedBox(width: 160, child: DateField(label: 'تحویل احتمالی', value: _promised, clearable: true, onChanged: (d) => setState(() => _promised = d))),
        ]),
        const Divider(height: 24),
        Row(children: [
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'وضعیت'),
              items: [for (final st in receptionStatuses) DropdownMenuItem(value: st, child: Text(st))],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 160, child: TextField(controller: _cost, textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'هزینه نهایی تعمیر'))),
          if (w != null && w.activeAt(_date)) const Padding(padding: EdgeInsets.only(right: 8), child: Text('در گارانتی')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _repair, maxLines: 2, decoration: const InputDecoration(labelText: 'شرح تعمیرات انجام شده')),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
