import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/discounts.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

const _weekNames = {6: 'شنبه', 7: 'یکشنبه', 1: 'دوشنبه', 2: 'سه شنبه', 3: 'چهار شنبه', 4: 'پنج شنبه', 5: 'جمعه'};

String _hm(int? m) => m == null ? '' : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
int? _parseHm(String s) {
  final p = normalizeDigits(s.trim()).split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null || h > 23 || m > 59) return null;
  return h * 60 + m;
}

// ================================================================ مدل های تخفیفات

Future<void> showDiscountModels(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Models());

class _Models extends StatefulWidget {
  const _Models();

  @override
  State<_Models> createState() => _ModelsState();
}

class _ModelsState extends State<_Models> {
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.discountModels;
    final sel = list.where((m) => m.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'مدل های تخفیفات و اشانتیون',
      width: 1100,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            sakanBtn('افزودن', () => showDiscountModelEditor(context), icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => showDiscountModelEditor(context, edit: sel), icon: Icons.edit_outlined),
            sakanBtn('حذف', sel == null ? null : () => setState(() => s.removeDiscountModel(sel.id)), icon: Icons.delete_outline_rounded),
            sakanBtn(sel?.active == false ? 'فعال کردن' : 'غیر فعال کردن', sel == null ? null : () => s.saveDiscountModel(sel..active = !sel.active), icon: Icons.toggle_on_outlined),
            sakanBtn('تخفیف های عمومی', () => showAmountDiscounts(context), icon: Icons.percent_rounded),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('ردیف', 50),
                sakanHead('نام مدل', 0),
                sakanHead('نام کالا', 180),
                sakanHead('نوع مدل', 190),
                sakanHead('معیار محاسبه', 120),
                sakanHead('محاسبه', 90),
                sakanHead('محدوده تاریخی', 180),
                sakanHead('وضعیت', 70),
              ],
              count: list.length,
              empty: 'مدل تخفیفی تعریف نشده',
              row: (ctx, i) {
                final m = list[i];
                final on = m.id == _sel;
                final st = TextStyle(color: on ? Colors.white : (m.active ? null : Colors.black38), fontSize: 12.5);
                return InkWell(
                  onTap: () => setState(() => _sel = m.id),
                  onDoubleTap: () => showDiscountModelEditor(context, edit: m),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text('${i + 1}', style: st), 50),
                      sakanCell(Text(m.name, style: st.copyWith(fontWeight: FontWeight.w700)), 0, align: Alignment.centerRight),
                      sakanCell(Text(s.product(m.productId)?.name ?? 'همه کالاها', style: st, overflow: TextOverflow.ellipsis), 180),
                      sakanCell(Text(m.typeLabel, style: st, overflow: TextOverflow.ellipsis), 190),
                      sakanCell(Text(m.base.label, style: st), 120),
                      sakanCell(Text(m.progressive ? 'تصاعدی' : 'ویژه', style: st), 90),
                      sakanCell(Text(m.fromDate == null && m.toDate == null ? '—' : '${m.fromDate == null ? '' : jFormat(m.fromDate!)} تا ${m.toDate == null ? '' : jFormat(m.toDate!)}', style: st), 180),
                      sakanCell(Text(m.active ? 'فعال' : 'غیر فعال', style: st), 70),
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

Future<void> showDiscountModelEditor(BuildContext context, {DiscountModel? edit}) =>
    showDialog<void>(context: context, builder: (_) => _ModelEditor(edit: edit));

class _ModelEditor extends StatefulWidget {
  final DiscountModel? edit;
  const _ModelEditor({this.edit});

  @override
  State<_ModelEditor> createState() => _ModelEditorState();
}

class _ModelEditorState extends State<_ModelEditor> {
  late DiscountModel _m;
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _fromT = TextEditingController();
  final _toT = TextEditingController();
  final _monthDay = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
    _m = widget.edit == null ? DiscountModel(id: newId(), name: '') : DiscountModel.fromJson(widget.edit!.toJson());
    _name.text = _m.name;
    _note.text = _m.note;
    _fromT.text = _hm(_m.fromMinute);
    _toT.text = _hm(_m.toMinute);
    _monthDay.text = _m.monthDay == null ? '' : '${_m.monthDay}';
  }

  @override
  void dispose() {
    for (final c in [_name, _note, _fromT, _toT, _monthDay]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final m = _m
      ..name = _name.text.trim()
      ..note = _note.text.trim()
      ..fromMinute = _parseHm(_fromT.text)
      ..toMinute = _parseHm(_toT.text)
      ..monthDay = int.tryParse(normalizeDigits(_monthDay.text.trim()));
    if (m.name.isEmpty) return setState(() => _err = 'نام مدل را وارد کنید');
    if (!m.retail && !m.wholesale && !m.special) return setState(() => _err = 'حداقل یک نوع مدل (خرده، عمده یا ویژه) را انتخاب کنید');
    m.tiers.removeWhere((t) => t.pct == 0 && t.amount == 0 && t.freeQty == 0 && t.giftProductId == null);
    if (m.tiers.isEmpty) return setState(() => _err = 'جدول اشانتیون‌ها و تخفیفات خالی است');
    StoreScope.read(context).saveDiscountModel(m);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final m = _m;
    final products = s.productsSorted.where((p) => !p.archived).toList();
    Widget chk(String t, bool v, ValueChanged<bool> on) => FilterChip(label: Text(t), selected: v, onSelected: (x) => setState(() => on(x)));
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f9): _save},
      child: FormDialog(
        title: 'مدل تخفیفات و اشانتیون',
        width: 1040,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: _save, child: const Text('تایید')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('اطلاعات مدل', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 260, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام مدل', isDense: true))),
            const Text('نوع مدل:'),
            chk('خرده فروشی', m.retail, (v) => m.retail = v),
            chk('عمده فروشی', m.wholesale, (v) => m.wholesale = v),
            chk('ویژه', m.special, (v) => m.special = v),
            const Text('وضعیت مدل:'),
            chk('فعال', m.active, (v) => m.active = v),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String?>(
                value: m.productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'نام کالا', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('همه کالاها')),
                  for (final p in products) DropdownMenuItem<String?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => m.productId = v),
              ),
            ),
            SizedBox(width: 420, child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'توضیحات', isDense: true))),
          ]),
          const Divider(height: 22),
          const Text('محدوده تاریخی و زمانی اعمال', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 190, child: DateField(label: 'از تاریخ', value: m.fromDate, clearable: true, onChanged: (d) => setState(() => m.fromDate = d))),
            SizedBox(width: 190, child: DateField(label: 'تا تاریخ', value: m.toDate, clearable: true, onChanged: (d) => setState(() => m.toDate = d))),
            SizedBox(width: 190, child: DateField(label: 'تاریخ مشخص', value: m.specialDate, clearable: true, onChanged: (d) => setState(() => m.specialDate = d))),
            SizedBox(width: 110, child: TextField(controller: _fromT, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'از ساعت', hintText: '08:00', isDense: true))),
            SizedBox(width: 110, child: TextField(controller: _toT, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تا ساعت', hintText: '14:00', isDense: true))),
            SizedBox(width: 130, child: TextField(controller: _monthDay, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'ماهانه (روز)', isDense: true))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            const Padding(padding: EdgeInsets.only(top: 8, left: 6), child: Text('هفتگی:')),
            for (final e in _weekNames.entries) chk(e.value, m.weekdays.contains(e.key), (v) => v ? m.weekdays.add(e.key) : m.weekdays.remove(e.key)),
          ]),
          const Divider(height: 22),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('مبنای محاسبه:', style: TextStyle(fontWeight: FontWeight.w800)),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('محاسبه تصاعدی')), ButtonSegment(value: false, label: Text('محاسبه ویژه'))],
              selected: {m.progressive},
              onSelectionChanged: (v) => setState(() => m.progressive = v.first),
            ),
            const Text('معیار محاسبه:', style: TextStyle(fontWeight: FontWeight.w800)),
            DropdownButton<DiscountBase>(
              value: m.base,
              items: [for (final b in DiscountBase.values) DropdownMenuItem(value: b, child: Text(b.label))],
              onChanged: (v) => setState(() => m.base = v ?? m.base),
            ),
            chk('اعمال خودکار تخفیف در فروش', m.autoApply, (v) => m.autoApply = v),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Text('جدول اشانتیون ها و تخفیفات', style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(onPressed: () => setState(() => m.tiers.add(DiscountTier())), icon: const Icon(Icons.add_rounded), label: const Text('افزودن ردیف')),
          ]),
          for (final t in m.tiers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _n('از', fmtQty(t.from), (v) => t.from = parseQty(v)),
                _n('تا (۰=بی‌سقف)', fmtQty(t.to), (v) => t.to = parseQty(v)),
                _n('تخفیف ٪', fmtQty(t.pct), (v) => t.pct = parseQty(v)),
                _n('تخفیف هر واحد', groupDigits(t.amount), (v) => t.amount = parseMoney(v), money: true),
                _n('تخفیف تعدادی', fmtQty(t.freeQty), (v) => t.freeQty = parseQty(v)),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    value: t.giftProductId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'اشانتیون', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      for (final p in products) DropdownMenuItem<String?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => t.giftProductId = v),
                  ),
                ),
                _n('تعداد اشانتیون', fmtQty(t.giftQty), (v) => t.giftQty = parseQty(v)),
                IconButton(onPressed: () => setState(() => m.tiers.remove(t)), icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935))),
              ]),
            ),
          if (m.tiers.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('ردیفی اضافه نشده')),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
    );
  }

  Widget _n(String label, String init, ValueChanged<String> on, {bool money = false}) => SizedBox(
        width: 120,
        child: TextFormField(
          initialValue: init == '0' ? '' : init,
          textDirection: TextDirection.ltr,
          inputFormatters: money ? [MoneyInputFormatter()] : null,
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: on,
        ),
      );
}

// ================================================================ تخفیف های عمومی / فردی

/// «تخفیف های عمومی» ([personId] null) or «تخصیص تخفیفات فردی».
Future<void> showAmountDiscounts(BuildContext context, {String? personId}) =>
    showDialog<void>(context: context, builder: (_) => _AmountDiscounts(personId: personId));

class _AmountDiscounts extends StatefulWidget {
  final String? personId;
  const _AmountDiscounts({this.personId});

  @override
  State<_AmountDiscounts> createState() => _AmountDiscountsState();
}

class _AmountDiscountsState extends State<_AmountDiscounts> {
  late List<AmountDiscount> _list;
  int _type = 0;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    _list = [for (final d in s.amountDiscounts.where((d) => d.personId == widget.personId)) AmountDiscount.fromJson(d.toJson())];
    _type = s.person(widget.personId)?.priceType ?? 0;
  }

  Widget _f(String label, String init, ValueChanged<String> on, {double w = 150, bool money = false}) => SizedBox(
        width: w,
        child: TextFormField(
          initialValue: init,
          textDirection: money ? TextDirection.ltr : null,
          inputFormatters: money ? [MoneyInputFormatter()] : null,
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: on,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final person = s.person(widget.personId);
    return FormDialog(
      title: person == null ? 'تخفیف های عمومی' : 'تخصیص تخفیفات فردی — ${person.name}',
      width: 860,
      leading: TextButton.icon(
        onPressed: () => setState(() => _list.add(AmountDiscount(id: newId()))),
        icon: const Icon(Icons.add_rounded),
        label: const Text('معرفی تخفیف'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            s.saveAmountDiscounts(_list.where((d) => d.pct > 0).toList(), personId: widget.personId);
            if (person != null) s.upsertPerson(person..priceType = _type);
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (person != null) ...[
          DropdownButtonFormField<int>(
            value: _type,
            decoration: const InputDecoration(labelText: 'نوع خریدار (برای مدل تخفیفات)', isDense: true),
            items: const [
              DropdownMenuItem(value: 0, child: Text('نامشخص')),
              DropdownMenuItem(value: 1, child: Text('خرده فروشی')),
              DropdownMenuItem(value: 2, child: Text('عمده فروشی')),
              DropdownMenuItem(value: 3, child: Text('ویژه')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 0),
          ),
          const SizedBox(height: 10),
        ],
        Text('تخفیف بر اساس جمع فاکتور: اگر جمع اقلام در محدوده باشد، درصد روی کل فاکتور اعمال می‌شود (با «اعمال مدل های تخفیفات و جوایز»).',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final d in _list)
          Padding(
            key: ObjectKey(d),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (person == null) _f('عنوان تخفیف', d.name, (v) => d.name = v.trim(), w: 180),
              _f('از مبلغ', d.fromAmount == 0 ? '' : groupDigits(d.fromAmount), (v) => d.fromAmount = parseMoney(v), money: true),
              _f('تا مبلغ (۰=بی‌سقف)', d.toAmount == 0 ? '' : groupDigits(d.toAmount), (v) => d.toAmount = parseMoney(v), money: true),
              _f('درصد', d.pct == 0 ? '' : fmtQty(d.pct), (v) => d.pct = parseQty(v), w: 90),
              if (person == null) _f('توضیحات', d.note, (v) => d.note = v.trim(), w: 180),
              IconButton(onPressed: () => setState(() => _list.remove(d)), icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935))),
            ]),
          ),
        if (_list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('تخفیفی تعریف نشده («معرفی تخفیف»)')),
      ]),
    );
  }
}

// ================================================================ گروه های یارانه

Future<void> showSubsidyGroups(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Subsidies());

class _Subsidies extends StatefulWidget {
  const _Subsidies();

  @override
  State<_Subsidies> createState() => _SubsidiesState();
}

class _SubsidiesState extends State<_Subsidies> {
  String? _sel;

  Future<void> _edit(AppStore s, [SubsidyGroup? g]) async {
    final x = g == null ? SubsidyGroup(id: newId(), name: '') : SubsidyGroup.fromJson(g.toJson());
    final name = TextEditingController(text: x.name);
    final pct = TextEditingController(text: x.pct == 0 ? '' : fmtQty(x.pct));
    final note = TextEditingController(text: x.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'اطلاعات گروه یارانه',
          width: 460,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام گروه یارانه')),
            const SizedBox(height: 8),
            TextField(controller: pct, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'درصد یارانه', suffixText: '٪')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: x.personId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'حساب یارانه (پرداخت کننده سهم)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('—')),
                for (final p in s.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => set(() => x.personId = v),
            ),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظات')),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: x.isDefault, title: const Text('پیش فرض'), onChanged: (v) => set(() => x.isDefault = v ?? false)),
          ]),
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      s.saveSubsidyGroup(x
        ..name = name.text.trim()
        ..pct = parseQty(pct.text)
        ..note = note.text.trim());
    }
    for (final c in [name, pct, note]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.subsidyGroups;
    final sel = list.where((g) => g.id == _sel).firstOrNull;
    int count(SubsidyGroup g) => s.products.where((p) => p.info['subsidyGroup'] == g.id).length;
    return SakanWindow(
      title: 'گروه های یارانه',
      width: 820,
      height: 560,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            sakanBtn('تعریف گروه یارانه جدید', () => _edit(s), icon: Icons.add_rounded),
            sakanBtn('ویرایش گروه', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            sakanBtn('حذف گروه', sel == null
                ? null
                : () {
                    final e = s.removeSubsidyGroup(sel.id);
                    if (e != null) toast(context, e, error: true);
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('تخصیص گروه های یارانه', sel == null ? null : () => _assign(s, sel), icon: Icons.playlist_add_check_rounded),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('نام گروه', 0), sakanHead('درصد', 80), sakanHead('حساب یارانه', 200), sakanHead('تعداد کالا', 90), sakanHead('پیش فرض', 80)],
              count: list.length,
              empty: 'گروه یارانه‌ای تعریف نشده',
              row: (ctx, i) {
                final g = list[i];
                final on = g.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null);
                return InkWell(
                  onTap: () => setState(() => _sel = g.id),
                  onDoubleTap: () => _edit(s, g),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text(g.name, style: st.copyWith(fontWeight: FontWeight.w700)), 0, align: Alignment.centerRight),
                      sakanCell(Text('${fmtQty(g.pct)}٪', style: st), 80),
                      sakanCell(Text(s.person(g.personId)?.name ?? '', style: st), 200),
                      sakanCell(Text('${count(g)}', style: st), 90),
                      sakanCell(Text(g.isDefault ? '✓' : '', style: st), 80),
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

  /// «تخصیص گروه های یارانه» — pick the products of the group.
  Future<void> _assign(AppStore s, SubsidyGroup g) async {
    final chosen = {for (final p in s.products) if (p.info['subsidyGroup'] == g.id) p.id};
    var q = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final list = s.productsSorted.where((p) => q.isEmpty || p.name.contains(q) || p.code.contains(q)).take(300).toList();
          return FormDialog(
            title: 'تخصیص گروه یارانه — ${g.name}',
            width: 620,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف F10')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
            ],
            child: Column(children: [
              TextField(decoration: const InputDecoration(hintText: 'جستجوی کالا', prefixIcon: Icon(Icons.search_rounded)), onChanged: (v) => set(() => q = v.trim())),
              for (final p in list)
                CheckboxListTile(
                  dense: true,
                  value: chosen.contains(p.id),
                  title: Text(p.name),
                  subtitle: s.subsidyGroupOf(p) != null && s.subsidyGroupOf(p)!.id != g.id ? Text('گروه فعلی: ${s.subsidyGroupOf(p)!.name}') : null,
                  onChanged: (v) => set(() => v == true ? chosen.add(p.id) : chosen.remove(p.id)),
                ),
            ]),
          );
        },
      ),
    );
    if (ok != true) return;
    for (final p in s.products) {
      if (chosen.contains(p.id)) {
        p.info['subsidyGroup'] = g.id;
      } else if (p.info['subsidyGroup'] == g.id) {
        p.info.remove('subsidyGroup');
      }
      s.upsertProduct(p);
    }
  }
}

/// «تعیین گروه های یارانه» of one product (from the product form).
Future<String?> pickSubsidyGroup(BuildContext context, {String? current}) {
  final s = StoreScope.read(context);
  return showDialog<String>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'تعیین گروه یارانه',
      width: 420,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('بدون گروه')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
      ],
      child: Column(children: [
        for (final g in s.subsidyGroups)
          ListTile(dense: true, selected: g.id == current, title: Text(g.name), trailing: Text('${fmtQty(g.pct)}٪'), onTap: () => Navigator.pop(ctx, g.id)),
        if (s.subsidyGroups.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('گروه یارانه‌ای تعریف نشده')),
      ]),
    ),
  );
}
