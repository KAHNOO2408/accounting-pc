import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
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
    _account = widget.cheque.depositAccountId ??
        store.activeAccounts.where((a) => a.type == AccountType.bank).map((a) => a.id).firstOrNull ??
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
      title: widget.cheque.direction == ChequeDirection.received ? 'اعلام وصول چک' : 'پاس شدن چک',
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


// ------------------------------------------------------------- deposit to bank

Future<void> showDepositChequeDialog(BuildContext context, Cheque c) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final store = StoreScope.read(ctx);
        final banks = store.activeAccounts.where((a) => a.type == AccountType.bank).toList();
        final list = banks.isEmpty ? store.activeAccounts : banks;
        String? acc = list.isEmpty ? null : list.first.id;
        return StatefulBuilder(
          builder: (ctx, setS) => FormDialog(
            title: 'به حساب گذاشتن چک',
            width: 460,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              FilledButton(
                onPressed: acc == null
                    ? null
                    : () {
                        store.depositCheque(c, acc!);
                        Navigator.pop(ctx);
                      },
                child: const Text('ثبت'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('چک به بانک سپرده می‌شود و پس از «اعلام وصول نزد بانک» به موجودی این حساب اضافه می‌شود.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 14),
                FieldDropdown<String?>(
                  label: 'حساب بانکی',
                  value: acc,
                  items: [for (final a in list) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
                  onChanged: (v) => setS(() => acc = v),
                ),
              ],
            ),
          ),
        );
      },
    );

// ------------------------------------------------------------------ endorse

Future<void> showEndorseChequeDialog(BuildContext context, Cheque c) => showDialog<void>(
      context: context,
      builder: (ctx) {
        String? person;
        var date = dateOnly(DateTime.now());
        return StatefulBuilder(builder: (ctx, setS) {
          final store = StoreScope.of(ctx);
          return FormDialog(
            title: 'واگذاری چک',
            width: 480,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              FilledButton(
                onPressed: person == null
                    ? null
                    : () {
                        store.endorseCheque(c, toPersonId: person!, date: date);
                        Navigator.pop(ctx);
                      },
                child: const Text('واگذار شد'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('چک دریافتی به شخص دیگری داده می‌شود؛ از بدهی شما به او کم و حساب صادرکننده تسویه می‌شود.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 14),
                FieldDropdown<String?>(
                  label: 'واگذار به',
                  value: person,
                  items: [
                    for (final p in store.peopleSorted.where((p) => p.id != c.personId))
                      DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setS(() => person = v),
                ),
                const SizedBox(height: 14),
                DateField(label: 'تاریخ واگذاری', value: date, onChanged: (d) => setS(() => date = d ?? date)),
              ],
            ),
          );
        });
      },
    );

// ------------------------------------------------------ weighted due (راس‌گیری)

Future<void> showChequeAverageDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _AverageDialog(),
    );

class _AverageDialog extends StatefulWidget {
  const _AverageDialog();

  @override
  State<_AverageDialog> createState() => _AverageDialogState();
}

class _AverageDialogState extends State<_AverageDialog> {
  ChequeDirection _dir = ChequeDirection.received;
  final Set<String> _sel = {};

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final list = store.cheques
        .where((c) =>
            c.direction == _dir && (c.status == ChequeStatus.pending || c.status == ChequeStatus.deposited))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final chosen = list.where((c) => _sel.contains(c.id)).toList();
    final avg = store.averageDue(chosen);
    final total = chosen.fold<int>(0, (s, c) => s + c.amount);
    return FormDialog(
      title: 'راس‌گیری چک‌ها',
      width: 620,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ChequeDirection>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ChequeDirection.received, label: Text('چک‌های دریافتی')),
              ButtonSegment(value: ChequeDirection.issued, label: Text('چک‌های پرداختی')),
            ],
            selected: {_dir},
            onSelectionChanged: (s) => setState(() {
              _dir = s.first;
              _sel.clear();
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(onPressed: () => setState(() => _sel.addAll(list.map((c) => c.id))), child: const Text('انتخاب همه')),
              TextButton(onPressed: () => setState(_sel.clear), child: const Text('هیچ‌کدام')),
            ],
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('چک باز (در انتظار وصول) وجود ندارد', textAlign: TextAlign.center),
            ),
          for (final c in list)
            CheckboxListTile(
              dense: true,
              value: _sel.contains(c.id),
              onChanged: (v) => setState(() => v == true ? _sel.add(c.id) : _sel.remove(c.id)),
              title: Text('${jFormat(c.dueDate)}  ·  ${store.person(c.personId)?.name ?? '—'}'),
              secondary: Money(c.amount, style: const TextStyle(fontWeight: FontWeight.w600)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: th.colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${chosen.length} چک · جمع', style: th.textTheme.bodySmall),
                      Money(total, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('سررسید میانگین (راس)', style: th.textTheme.bodySmall),
                    Text(avg == null ? '—' : Jalali.fromDateTime(avg).formatWithWeekday(),
                        style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: th.colorScheme.primary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
