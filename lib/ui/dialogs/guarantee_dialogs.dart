import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../print_designer.dart' show showLayoutPicker;
import '../report/doc_reports.dart' show guaranteeReportData;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show pickPersonId;

/// «انتظامی ها» — list of received / issued guarantee documents.
Future<void> showGuarantees(BuildContext context, {bool? received}) => showDialog<void>(context: context, builder: (_) => _List(received: received));

class _List extends StatefulWidget {
  final bool? received;
  const _List({this.received});

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  late int _tab = widget.received == false ? 2 : (widget.received == true ? 1 : 0);
  bool _openOnly = false;
  String? _sel; // item id

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = <(GuaranteeDoc, GuaranteeItem)>[
      for (final g in [...s.guarantees]..sort((a, b) => b.number.compareTo(a.number)))
        if (_tab == 0 || (_tab == 1) == g.received)
          for (final it in g.items)
            if (!_openOnly || it.open) (g, it),
    ];
    final sel = rows.where((r) => r.$2.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'انتظامی ها',
      width: 1180,
      height: 660,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('دریافت انتظامی', () => showGuaranteeEditor(context, received: true), icon: Icons.move_to_inbox_outlined),
            sakanBtn('صدور انتظامی', () => showGuaranteeEditor(context, received: false), icon: Icons.outbox_outlined),
            sakanBtn('ویرایش', sel == null ? null : () => showGuaranteeEditor(context, edit: sel.$1), icon: Icons.edit_outlined),
            sakanBtn(sel?.$1.received == false ? 'پس گرفتن' : 'عودت', sel == null || !sel.$2.open ? null : () => _return(s, sel.$1, sel.$2), icon: Icons.assignment_return_outlined),
            sakanBtn('لغو عودت', sel == null || sel.$2.open
                ? null
                : () {
                    s.returnGuarantee(sel.$2, null);
                    setState(() {});
                  }, icon: Icons.undo_rounded),
            sakanBtn('حذف سند', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف سند انتظامی', '${sel.$1.label} ${sel.$1.number} حذف شود؟')) {
                      s.removeGuarantee(sel.$1.id);
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('گزارش اسناد انتظامی', () => _print(s, rows), icon: Icons.print_outlined),
            sakanBtn('چاپ سند با طرح', sel == null
                ? null
                : () => showLayoutPicker(context, type: PrintDocType.guarantee, data: (st) => guaranteeReportData(st, sel.$1), fileName: 'entezami-${sel.$1.number}'), icon: Icons.design_services_outlined),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 0, label: Text('همه')), ButtonSegment(value: 1, label: Text('دریافتی')), ButtonSegment(value: 2, label: Text('صادره'))],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            const SizedBox(width: 12),
            FilterChip(label: const Text('فقط عودت نشده‌ها'), selected: _openOnly, onSelected: (v) => setState(() => _openOnly = v)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('شماره سند', 75),
                sakanHead('تاریخ سند', 95),
                sakanHead('نوع', 110),
                sakanHead('طرف حساب', 0),
                sakanHead('نوع سند', 100),
                sakanHead('شماره سریال', 120),
                sakanHead('مبلغ', 120),
                sakanHead('تاریخ سررسید', 100),
                sakanHead('مکان نگهداری', 120),
                sakanHead('وضعیت', 110),
              ],
              count: rows.length,
              empty: 'سند انتظامی ثبت نشده',
              row: (ctx, i) {
                final (g, it) = rows[i];
                final on = it.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                return InkWell(
                  onTap: () => setState(() => _sel = it.id),
                  onDoubleTap: () => showGuaranteeEditor(context, edit: g),
                  child: Container(
                    color: on ? sakanSel : (!it.open ? const Color(0xFFEDEDED) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text('${g.number}', style: st), 75),
                      sakanCell(Text(jFormat(g.date), style: st), 95),
                      sakanCell(Text(g.label, style: st), 110),
                      sakanCell(Text(s.person(g.personId)?.name ?? '', style: st, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                      sakanCell(Text(it.kind.label, style: st), 100),
                      sakanCell(Text(it.serial, style: st), 120),
                      sakanCell(Text(groupDigits(it.amount), style: st.copyWith(fontWeight: FontWeight.w700)), 120),
                      sakanCell(Text(it.dueDate == null ? '' : jFormat(it.dueDate!), style: st), 100),
                      sakanCell(Text(it.place, style: st, overflow: TextOverflow.ellipsis), 120),
                      sakanCell(Text(it.open ? 'نزد ${g.received ? 'ما' : 'طرف حساب'}' : 'عودت ${jFormat(it.returnedOn!)}', style: st), 110),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'جمع ${groupDigits(rows.fold<int>(0, (a, r) => a + r.$2.amount))} — عودت نشده ${groupDigits(rows.where((r) => r.$2.open).fold<int>(0, (a, r) => a + r.$2.amount))}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }

  Future<void> _return(AppStore s, GuaranteeDoc g, GuaranteeItem it) async {
    var date = DateTime.now();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: g.received ? 'عودت انتظامی وارده' : 'پس گرفتن انتظامی صادره',
          width: 420,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${it.kind.label} ${it.serial} — ${groupDigits(it.amount)}'),
            const SizedBox(height: 8),
            DateField(label: 'تاریخ', value: date, onChanged: (d) => set(() => date = d ?? date)),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
          ]),
        ),
      ),
    );
    if (ok == true) {
      s.returnGuarantee(it, date, note.text.trim());
      setState(() {});
    }
    note.dispose();
  }

  void _print(AppStore s, List<(GuaranteeDoc, GuaranteeItem)> rows) => printTable(
        store: s,
        title: 'گزارش اسناد انتظامی',
        headers: const ['شماره سند', 'تاریخ سند', 'نوع', 'طرف حساب', 'نوع سند', 'شماره سریال', 'مبلغ', 'تاریخ سررسید', 'نام بانک', 'مکان نگهداری', 'متعلق به', 'وضعیت'],
        rows: [
          for (final (g, it) in rows)
            [
              '${g.number}',
              jFormat(g.date),
              g.label,
              s.person(g.personId)?.name ?? '',
              it.kind.label,
              it.serial,
              groupDigits(it.amount),
              it.dueDate == null ? '' : jFormat(it.dueDate!),
              it.bank,
              it.place,
              it.owner,
              it.open ? 'عودت نشده' : 'عودت ${jFormat(it.returnedOn!)}',
            ],
        ],
        numeric: const {6},
        footer: ['', '', '', '', '', 'جمع', groupDigits(rows.fold<int>(0, (a, r) => a + r.$2.amount)), '', '', '', '', ''],
        fileName: 'entezami',
      );
}

// ---------------------------------------------------------------- editor

Future<void> showGuaranteeEditor(BuildContext context, {GuaranteeDoc? edit, bool received = true}) =>
    showDialog<void>(context: context, builder: (_) => _Editor(edit: edit, received: edit?.received ?? received));

class _Row {
  final String id;
  GuaranteeKind kind;
  DateTime? due;
  final serial = TextEditingController();
  final amount = TextEditingController();
  final bank = TextEditingController();
  final place = TextEditingController();
  final owner = TextEditingController();
  final GuaranteeItem? orig;
  _Row([this.orig])
      : id = orig?.id ?? newId(),
        kind = orig?.kind ?? GuaranteeKind.safte,
        due = orig?.dueDate {
    if (orig != null) {
      serial.text = orig!.serial;
      amount.text = orig!.amount == 0 ? '' : groupDigits(orig!.amount);
      bank.text = orig!.bank;
      place.text = orig!.place;
      owner.text = orig!.owner;
    }
  }
  void dispose() {
    for (final c in [serial, amount, bank, place, owner]) {
      c.dispose();
    }
  }
}

class _Editor extends StatefulWidget {
  final GuaranteeDoc? edit;
  final bool received;
  const _Editor({this.edit, required this.received});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late DateTime _date = widget.edit?.date ?? DateTime.now();
  late String? _person = widget.edit?.personId;
  late final _babat = TextEditingController(text: widget.edit?.babat ?? '');
  late final List<_Row> _rows = widget.edit == null ? [_Row()] : [for (final i in widget.edit!.items) _Row(i)];
  String? _err;

  @override
  void dispose() {
    _babat.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final title = widget.received ? 'دریافت انتظامی' : 'صدور انتظامی';
    Widget f(TextEditingController c, String label, {double w = 120, bool money = false}) => SizedBox(
          width: w,
          child: TextField(
            controller: c,
            textDirection: money ? TextDirection.ltr : null,
            inputFormatters: money ? [MoneyInputFormatter()] : null,
            decoration: InputDecoration(labelText: label, isDense: true),
            onChanged: money ? (_) => setState(() {}) : null,
          ),
        );
    return FormDialog(
      title: widget.edit == null ? title : '$title شماره ${widget.edit!.number}',
      width: 1000,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final items = [
              for (final r in _rows)
                if (parseMoney(r.amount.text) > 0)
                  GuaranteeItem(
                    id: r.id,
                    kind: r.kind,
                    serial: r.serial.text.trim(),
                    amount: parseMoney(r.amount.text),
                    dueDate: r.due,
                    bank: r.bank.text.trim(),
                    place: r.place.text.trim(),
                    owner: r.owner.text.trim(),
                    returnedOn: r.orig?.returnedOn,
                    returnNote: r.orig?.returnNote ?? '',
                  ),
            ];
            if (_person == null) return setState(() => _err = 'طرف حساب را انتخاب کنید');
            if (items.isEmpty) return setState(() => _err = 'حداقل یک ردیف با مبلغ وارد کنید');
            s.saveGuarantee(GuaranteeDoc(
              id: widget.edit?.id ?? newId(),
              number: widget.edit?.number ?? s.nextGuaranteeNumber(),
              date: _date,
              received: widget.received,
              personId: _person,
              babat: _babat.text.trim(),
              items: items,
              createdAt: widget.edit?.createdAt,
            ));
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 180, child: DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final id = await pickPersonId(context, title: widget.received ? 'دریافت از' : 'صدور به');
                if (id != null) setState(() => _person = id);
              },
              icon: const Icon(Icons.person_search_rounded),
              label: Text(s.person(_person)?.name ?? (widget.received ? 'دریافت از' : 'صدور به')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _babat, decoration: const InputDecoration(labelText: 'بابت'))),
        ]),
        const SizedBox(height: 10),
        for (final r in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<GuaranteeKind>(
                  value: r.kind,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'نوع', isDense: true),
                  items: [for (final k in GuaranteeKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                  onChanged: (v) => setState(() => r.kind = v ?? r.kind),
                ),
              ),
              const SizedBox(width: 6),
              f(r.serial, 'شماره سریال'),
              const SizedBox(width: 6),
              f(r.amount, 'مبلغ', w: 130, money: true),
              const SizedBox(width: 6),
              SizedBox(width: 150, child: DateField(label: 'سررسید', value: r.due, clearable: true, onChanged: (d) => setState(() => r.due = d))),
              const SizedBox(width: 6),
              f(r.bank, 'بانک', w: 100),
              const SizedBox(width: 6),
              f(r.place, 'مکان نگهداری'),
              const SizedBox(width: 6),
              Expanded(child: f(r.owner, 'متعلق به')),
              IconButton(
                onPressed: _rows.length == 1 || r.orig?.returnedOn != null
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
        Text('جمع: ${groupDigits(_rows.fold<int>(0, (a, r) => a + parseMoney(r.amount.text)))}', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
