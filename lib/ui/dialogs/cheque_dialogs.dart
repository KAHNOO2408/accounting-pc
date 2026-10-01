import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import 'simple_dialogs.dart';

Future<void> showChequeDialog(BuildContext context, {Cheque? edit, ChequeDirection? direction}) =>
    showDialog<void>(context: context, builder: (_) => _ChequeDialog(edit: edit, direction: direction));

class _ChequeDialog extends StatefulWidget {
  final Cheque? edit;
  final ChequeDirection? direction;
  const _ChequeDialog({this.edit, this.direction});

  @override
  State<_ChequeDialog> createState() => _ChequeDialogState();
}

class _ChequeDialogState extends State<_ChequeDialog> {
  late ChequeDirection _dir;
  late DateTime _due;
  late DateTime _issue;
  String? _person;
  late final TextEditingController _amount;
  late final TextEditingController _bank;
  late final TextEditingController _serial;
  late final TextEditingController _note;
  String? _err;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    final now = DateTime.now();
    _dir = e?.direction ?? widget.direction ?? ChequeDirection.received;
    _due = e?.dueDate ?? DateTime(now.year, now.month, now.day);
    _issue = e?.issueDate ?? DateTime(now.year, now.month, now.day);
    _person = e?.personId;
    _amount = TextEditingController(text: e == null ? '' : groupDigits(e.amount));
    _bank = TextEditingController(text: e?.bank ?? '');
    _serial = TextEditingController(text: e?.serial ?? '');
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_amount, _bank, _serial, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final amount = parseMoney(_amount.text);
    if (amount <= 0) {
      setState(() => _err = 'مبلغ چک را وارد کنید');
      return;
    }
    final c = widget.edit ??
        Cheque(id: newId(), direction: _dir, amount: amount, dueDate: _due, issueDate: _issue);
    c
      ..direction = _dir
      ..amount = amount
      ..dueDate = _due
      ..issueDate = _issue
      ..personId = _person
      ..bank = _bank.text.trim()
      ..serial = _serial.text.trim()
      ..note = _note.text.trim();
    StoreScope.read(context).upsertCheque(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    return FormDialog(
      title: widget.edit == null ? 'ثبت چک' : 'ویرایش چک',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ChequeDirection>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ChequeDirection.received, label: Text('چک دریافتی'), icon: Icon(Icons.download_rounded, size: 16)),
              ButtonSegment(value: ChequeDirection.issued, label: Text('چک پرداختی'), icon: Icon(Icons.upload_rounded, size: 16)),
            ],
            selected: {_dir},
            onSelectionChanged: widget.edit?.status == ChequeStatus.cleared ? null : (s) => setState(() => _dir = s.first),
          ),
          const SizedBox(height: 18),
          MoneyField(controller: _amount, autofocus: true, label: 'مبلغ چک'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: DateField(label: 'تاریخ سررسید', value: _due, onChanged: (d) => setState(() => _due = d ?? _due))),
              const SizedBox(width: 12),
              Expanded(child: DateField(label: 'تاریخ صدور / دریافت', value: _issue, onChanged: (d) => setState(() => _issue = d ?? _issue))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FieldDropdown<String?>(
                  label: _dir == ChequeDirection.received ? 'دریافت از' : 'در وجه',
                  value: _person,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    for (final p in store.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _person = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'شخص جدید',
                onPressed: () async {
                  final id = await showPersonDialog(context);
                  if (id != null) setState(() => _person = id);
                },
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: TextField(controller: _bank, decoration: const InputDecoration(labelText: 'بانک'))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serial,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'شماره / سریال چک'),
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

// ------------------------------------------------------------- clear cheque

Future<void> showClearChequeDialog(BuildContext context, Cheque c) =>
    showDialog<void>(context: context, builder: (_) => _ClearDialog(cheque: c));

class _ClearDialog extends StatefulWidget {
  final Cheque cheque;
  const _ClearDialog({required this.cheque});

  @override
  State<_ClearDialog> createState() => _ClearDialogState();
}

class _ClearDialogState extends State<_ClearDialog> {
  String? _account;
  late TxnType _as;
  String? _category;
  late DateTime _date;
  bool _inited = false;

  bool get _received => widget.cheque.direction == ChequeDirection.received;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    _account = store.activeAccounts.where((a) => a.type == AccountType.bank).map((a) => a.id).firstOrNull ??
        store.activeAccounts.map((a) => a.id).firstOrNull;
    final hasPerson = widget.cheque.personId != null;
    _as = _received
        ? (hasPerson ? TxnType.collect : TxnType.income)
        : (hasPerson ? TxnType.repay : TxnType.expense);
    final now = DateTime.now();
    final due = widget.cheque.dueDate;
    _date = due.isAfter(now) ? DateTime(now.year, now.month, now.day) : due;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final options = _received ? [TxnType.collect, TxnType.income] : [TxnType.repay, TxnType.expense];
    final kind = _received ? CategoryKind.income : CategoryKind.expense;
    final hasPerson = widget.cheque.personId != null;
    return FormDialog(
      title: 'پاس شدن چک',
      width: 500,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: _account == null
              ? null
              : () {
                  store.clearCheque(widget.cheque,
                      accountId: _account!, asType: _as, categoryId: _category, date: _date);
                  Navigator.pop(context);
                },
          child: const Text('ثبت پاس شدن'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('مبلغ چک: ', style: th.textTheme.bodyMedium),
              Money(widget.cheque.amount, showUnit: true, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          FieldDropdown<String?>(
            label: _received ? 'واریز به حساب' : 'برداشت از حساب',
            value: _account,
            items: [
              for (final a in store.activeAccounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _account = v),
          ),
          const SizedBox(height: 14),
          DateField(label: 'تاریخ پاس شدن', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
          const SizedBox(height: 8),
          Text('ثبت در دفتر به عنوان', style: th.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<TxnType>(
            showSelectedIcon: false,
            segments: [
              for (final o in options)
                ButtonSegment(value: o, label: Text(o.label), enabled: o.needsPerson ? hasPerson : true),
            ],
            selected: {_as},
            onSelectionChanged: (s) => setState(() => _as = s.first),
          ),
          if (_as.hasCategory) ...[
            const SizedBox(height: 14),
            FieldDropdown<String?>(
              label: 'دسته‌بندی',
              value: _category,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('بدون دسته')),
                for (final c in store.categoriesOf(kind)) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ],
        ],
      ),
    );
  }
}
