import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';

// ============================================================== Account

Future<String?> showAccountDialog(BuildContext context, {Account? edit}) =>
    showDialog<String>(context: context, builder: (_) => _AccountDialog(edit: edit));

class _AccountDialog extends StatefulWidget {
  final Account? edit;
  const _AccountDialog({this.edit});

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _name;
  late final TextEditingController _bank;
  late final TextEditingController _number;
  late final TextEditingController _opening;
  late final TextEditingController _note;
  late AccountType _type;
  late int _color;
  late bool _negOpening;
  String? _err;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _name = TextEditingController(text: e?.name ?? '');
    _bank = TextEditingController(text: e?.bank ?? '');
    _number = TextEditingController(text: e?.number ?? '');
    _opening = TextEditingController(text: e == null || e.opening == 0 ? '' : groupDigits(e.opening.abs()));
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? AccountType.bank;
    _color = e?.color ?? palette[1];
    _negOpening = (e?.opening ?? 0) < 0;
  }

  @override
  void dispose() {
    for (final c in [_name, _bank, _number, _opening, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'نام حساب را وارد کنید');
      return;
    }
    final store = StoreScope.read(context);
    final op = parseMoney(_opening.text) * (_negOpening ? -1 : 1);
    final a = widget.edit ?? Account(id: newId(), name: '');
    a
      ..name = _name.text.trim()
      ..type = _type
      ..bank = _bank.text.trim()
      ..number = _number.text.trim()
      ..opening = op
      ..color = _color
      ..note = _note.text.trim();
    store.upsertAccount(a);
    Navigator.pop(context, a.id);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return FormDialog(
      title: widget.edit == null ? 'حساب جدید' : 'ویرایش حساب',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام حساب', hintText: 'مثلاً: ملت شخصی'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          FieldDropdown<AccountType>(
            label: 'نوع',
            value: _type,
            items: [
              for (final t in AccountType.values)
                DropdownMenuItem(
                  value: t,
                  child: Row(children: [Icon(accountIcon(t), size: 18), const SizedBox(width: 8), Text(t.label)]),
                ),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: TextField(controller: _bank, decoration: const InputDecoration(labelText: 'بانک / موسسه'))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _number,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'شماره حساب / کارت / شبا'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MoneyField(controller: _opening, label: 'موجودی اول دوره')),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('مثبت')),
                    ButtonSegment(value: true, label: Text('منفی')),
                  ],
                  selected: {_negOpening},
                  onSelectionChanged: (s) => setState(() => _negOpening = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('رنگ', style: th.textTheme.labelLarge),
          const SizedBox(height: 8),
          ColorPickerRow(value: _color, onChanged: (c) => setState(() => _color = c)),
          const SizedBox(height: 14),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'یادداشت')),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

// ============================================================== Category

Future<String?> showCategoryDialog(BuildContext context, {required CategoryKind kind, TxnCategory? edit}) =>
    showDialog<String>(context: context, builder: (_) => _CategoryDialog(kind: kind, edit: edit));

class _CategoryDialog extends StatefulWidget {
  final CategoryKind kind;
  final TxnCategory? edit;
  const _CategoryDialog({required this.kind, this.edit});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name;
  late CategoryKind _kind;
  late int _color;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.edit?.name ?? '');
    _kind = widget.edit?.kind ?? widget.kind;
    _color = widget.edit?.color ?? palette[5];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final c = widget.edit ?? TxnCategory(id: newId(), name: '', kind: _kind);
    c
      ..name = _name.text.trim()
      ..kind = _kind
      ..color = _color;
    StoreScope.read(context).upsertCategory(c);
    Navigator.pop(context, c.id);
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.edit == null ? 'دسته‌بندی جدید' : 'ویرایش دسته‌بندی',
      width: 440,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<CategoryKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: CategoryKind.expense, label: Text('هزینه')),
              ButtonSegment(value: CategoryKind.income, label: Text('درآمد')),
            ],
            selected: {_kind},
            onSelectionChanged: widget.edit != null ? null : (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام دسته'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          ColorPickerRow(value: _color, onChanged: (c) => setState(() => _color = c)),
        ],
      ),
    );
  }
}

// ============================================================== Person

Future<String?> showPersonDialog(BuildContext context, {Person? edit}) =>
    showDialog<String>(context: context, builder: (_) => _PersonDialog(edit: edit));

class _PersonDialog extends StatefulWidget {
  final Person? edit;
  const _PersonDialog({this.edit});

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.edit?.name ?? '');
    _phone = TextEditingController(text: widget.edit?.phone ?? '');
    _note = TextEditingController(text: widget.edit?.note ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final p = widget.edit ?? Person(id: newId(), name: '');
    p
      ..name = _name.text.trim()
      ..phone = _phone.text.trim()
      ..note = _note.text.trim();
    StoreScope.read(context).upsertPerson(p);
    Navigator.pop(context, p.id);
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.edit == null ? 'طرف حساب جدید' : 'ویرایش طرف حساب',
      width: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'تلفن'),
          ),
          const SizedBox(height: 14),
          TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'یادداشت')),
        ],
      ),
    );
  }
}
