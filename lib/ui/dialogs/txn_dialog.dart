import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import 'simple_dialogs.dart';

Future<void> showTxnDialog(
  BuildContext context, {
  Txn? edit,
  TxnType? type,
  String? accountId,
  String? personId,
  bool duplicate = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => TxnDialog(edit: edit, type: type, accountId: accountId, personId: personId, duplicate: duplicate),
  );
}

enum _Group { income, expense, transfer, debt }

class TxnDialog extends StatefulWidget {
  final Txn? edit;
  final TxnType? type;
  final String? accountId;
  final String? personId;
  final bool duplicate;

  const TxnDialog({super.key, this.edit, this.type, this.accountId, this.personId, this.duplicate = false});

  @override
  State<TxnDialog> createState() => _TxnDialogState();
}

class _TxnDialogState extends State<TxnDialog> {
  final _form = GlobalKey<FormState>();
  late TxnType _type;
  late DateTime _date;
  String? _account;
  String? _toAccount;
  String? _category;
  String? _person;
  DateTime? _due;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _err;
  bool _inited = false;

  bool get _isEdit => widget.edit != null && !widget.duplicate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    final e = widget.edit;
    if (e != null) {
      _type = e.type;
      _date = widget.duplicate ? DateTime.now() : e.date;
      _account = e.accountId;
      _toAccount = e.toAccountId;
      _category = e.categoryId;
      _person = e.personId;
      _due = e.dueDate;
      _amount.text = groupDigits(e.amount);
      _note.text = e.note;
    } else {
      _type = widget.type ?? TxnType.expense;
      _date = DateTime.now();
      _account = widget.accountId ?? (store.activeAccounts.isNotEmpty ? store.activeAccounts.first.id : null);
      _person = widget.personId;
    }
    _date = DateTime(_date.year, _date.month, _date.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  _Group get _group => switch (_type) {
        TxnType.income => _Group.income,
        TxnType.expense => _Group.expense,
        TxnType.transfer => _Group.transfer,
        _ => _Group.debt,
      };

  void _setGroup(_Group g) {
    setState(() {
      _err = null;
      switch (g) {
        case _Group.income:
          _type = TxnType.income;
        case _Group.expense:
          _type = TxnType.expense;
        case _Group.transfer:
          _type = TxnType.transfer;
        case _Group.debt:
          if (!_type.isDebt) _type = TxnType.lend;
      }
      final store = StoreScope.read(context);
      final c = store.category(_category);
      if (c != null &&
          ((_type == TxnType.income && c.kind != CategoryKind.income) ||
              (_type == TxnType.expense && c.kind != CategoryKind.expense))) {
        _category = null;
      }
    });
  }

  bool _save({bool again = false}) {
    final store = StoreScope.read(context);
    final amount = parseMoney(_amount.text);
    String? err;
    if (amount <= 0) {
      err = 'مبلغ را وارد کنید';
    } else if (_type.isDebt && _person == null) {
      err = 'شخص را انتخاب کنید';
    } else if (!_type.isDebt && _account == null) {
      err = 'حساب را انتخاب کنید';
    } else if (_type == TxnType.transfer && (_toAccount == null || _toAccount == _account)) {
      err = 'حساب مقصد معتبر نیست';
    }
    if (err != null) {
      setState(() => _err = err);
      return false;
    }
    final t = (_isEdit ? widget.edit! : Txn(id: newId(), type: _type, amount: amount, date: _date));
    t
      ..type = _type
      ..amount = amount
      ..date = _date
      ..accountId = _account
      ..toAccountId = _type == TxnType.transfer ? _toAccount : null
      ..categoryId = _type.hasCategory ? _category : null
      ..personId = _person
      ..dueDate = (_type == TxnType.lend || _type == TxnType.borrow) ? _due : null
      ..note = _note.text.trim();
    if (_isEdit) t.chequeId = widget.edit!.chequeId;
    store.upsertTxn(t);
    if (again) {
      setState(() {
        _amount.clear();
        _note.clear();
        _err = null;
      });
      toast(context, 'ثبت شد');
    } else {
      Navigator.pop(context);
    }
    return true;
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'حذف تراکنش', 'این تراکنش حذف شود؟');
    if (!ok || !mounted) return;
    StoreScope.read(context).removeTxn(widget.edit!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final accounts = store.accounts.where((a) => !a.archived || a.id == _account || a.id == _toAccount).toList();
    final kind = _type == TxnType.income ? CategoryKind.income : CategoryKind.expense;
    final cats = store.categories.where((c) => c.kind == kind && (!c.archived || c.id == _category)).toList();
    final people = store.peopleSorted;
    final th = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _save(again: !_isEdit),
      },
      child: FormDialog(
        title: _isEdit ? 'ویرایش تراکنش' : (widget.duplicate ? 'کپی تراکنش' : 'تراکنش جدید'),
        width: 620,
        leading: _isEdit
            ? TextButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline, color: th.colorScheme.error),
                label: Text('حذف', style: TextStyle(color: th.colorScheme.error)),
              )
            : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          if (!_isEdit)
            OutlinedButton(onPressed: () => _save(again: true), child: const Text('ثبت و بعدی (Ctrl+Enter)')),
          FilledButton.icon(
            onPressed: () => _save(),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('ذخیره (Ctrl+S)'),
          ),
        ],
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Group>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Group.expense, label: Text('هزینه'), icon: Icon(Icons.north_east_rounded, size: 16)),
                  ButtonSegment(value: _Group.income, label: Text('درآمد'), icon: Icon(Icons.south_west_rounded, size: 16)),
                  ButtonSegment(value: _Group.transfer, label: Text('انتقال'), icon: Icon(Icons.swap_horiz_rounded, size: 16)),
                  ButtonSegment(value: _Group.debt, label: Text('بدهی و طلب'), icon: Icon(Icons.handshake_outlined, size: 16)),
                ],
                selected: {_group},
                onSelectionChanged: (s) => _setGroup(s.first),
              ),
              if (_group == _Group.debt) ...[
                const SizedBox(height: 10),
                SegmentedButton<TxnType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TxnType.lend, label: Text('قرض دادم')),
                    ButtonSegment(value: TxnType.borrow, label: Text('قرض گرفتم')),
                    ButtonSegment(value: TxnType.collect, label: Text('طلب را گرفتم')),
                    ButtonSegment(value: TxnType.repay, label: Text('بدهی را دادم')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _debtHint(_type),
                  style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: MoneyField(controller: _amount, autofocus: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DateField(label: 'تاریخ', value: _date, onChanged: (d) {
                      if (d != null) setState(() => _date = d);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FieldDropdown<String?>(
                      label: _type == TxnType.transfer ? 'از حساب' : (_type.isDebt ? 'حساب (اختیاری)' : 'حساب'),
                      value: _account,
                      items: [
                        if (_type.isDebt) const DropdownMenuItem<String?>(value: null, child: Text('بدون حساب (فقط ثبت در دفتر)')),
                        for (final a in accounts)
                          DropdownMenuItem<String?>(
                            value: a.id,
                            child: Row(children: [
                              ColorDot(a.color),
                              const SizedBox(width: 8),
                              Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                              Money(store.balance(a.id), style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                            ]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _account = v),
                    ),
                  ),
                  if (_type == TxnType.transfer) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FieldDropdown<String?>(
                        label: 'به حساب',
                        value: _toAccount,
                        items: [
                          for (final a in accounts.where((a) => a.id != _account))
                            DropdownMenuItem<String?>(
                              value: a.id,
                              child: Row(children: [
                                ColorDot(a.color),
                                const SizedBox(width: 8),
                                Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                              ]),
                            ),
                        ],
                        onChanged: (v) => setState(() => _toAccount = v),
                      ),
                    ),
                  ],
                ],
              ),
              if (_type.hasCategory) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FieldDropdown<String?>(
                        label: 'دسته‌بندی',
                        value: _category,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('بدون دسته')),
                          for (final c in cats)
                            DropdownMenuItem<String?>(
                              value: c.id,
                              child: Row(children: [ColorDot(c.color), const SizedBox(width: 8), Text(c.name)]),
                            ),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'دسته جدید',
                      onPressed: () async {
                        final id = await showCategoryDialog(context, kind: kind);
                        if (id != null) setState(() => _category = id);
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ],
              if (_type != TxnType.transfer) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FieldDropdown<String?>(
                        label: _type.isDebt ? 'طرف حساب' : 'طرف حساب (اختیاری)',
                        value: _person,
                        items: [
                          if (!_type.isDebt) const DropdownMenuItem<String?>(value: null, child: Text('—')),
                          for (final p in people)
                            DropdownMenuItem<String?>(
                              value: p.id,
                              child: Row(children: [
                                Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                                Money(store.personBalance(p.id),
                                    colorBySign: true, style: th.textTheme.labelSmall),
                              ]),
                            ),
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
              ],
              if (_type == TxnType.lend || _type == TxnType.borrow) ...[
                const SizedBox(height: 14),
                DateField(
                  label: 'سررسید (اختیاری)',
                  value: _due,
                  clearable: true,
                  onChanged: (d) => setState(() => _due = d),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'توضیحات'),
              ),
              if (_err != null) ...[
                const SizedBox(height: 12),
                Text(_err!, style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _debtHint(TxnType t) => switch (t) {
        TxnType.lend => 'پولی که به کسی داده‌اید و باید پس بگیرید (طلب شما زیاد می‌شود).',
        TxnType.borrow => 'پولی که از کسی گرفته‌اید و باید پس بدهید (بدهی شما زیاد می‌شود).',
        TxnType.collect => 'دریافت بخشی یا کل طلب از طرف حساب.',
        TxnType.repay => 'پرداخت بخشی یا کل بدهی به طرف حساب.',
        _ => '',
      };
}
