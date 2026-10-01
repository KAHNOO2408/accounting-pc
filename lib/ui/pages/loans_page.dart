import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/common.dart';

// ================================================================ loan dialog

Future<String?> showLoanDialog(BuildContext context, {Loan? edit}) =>
    showDialog<String>(context: context, builder: (_) => _LoanDialog(edit: edit));

class _LoanDialog extends StatefulWidget {
  final Loan? edit;
  const _LoanDialog({this.edit});

  @override
  State<_LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<_LoanDialog> {
  late final TextEditingController _title, _lender, _principal, _inst, _count, _note;
  late DateTime _firstDue;
  late DateTime _receiveDate;
  String? _account;
  bool _record = true;
  String? _err;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    final e = widget.edit;
    final now = dateOnly(DateTime.now());
    _title = TextEditingController(text: e?.title ?? '');
    _lender = TextEditingController(text: e?.lender ?? '');
    _principal = TextEditingController(text: (e?.principal ?? 0) == 0 ? '' : groupDigits(e!.principal));
    _inst = TextEditingController(text: (e?.installmentAmount ?? 0) == 0 ? '' : groupDigits(e!.installmentAmount));
    _count = TextEditingController(text: '${e?.installments ?? 12}');
    _note = TextEditingController(text: e?.note ?? '');
    _firstDue = e?.firstDue ?? Jalali.fromDateTime(now).addMonths(1).toDateTime();
    _receiveDate = now;
    _account = e?.accountId ?? (store.activeAccounts.isEmpty ? null : store.activeAccounts.first.id);
    _record = e == null;
    for (final c in [_principal, _inst, _count]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _lender, _principal, _inst, _count, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _n => int.tryParse(normalizeDigits(_count.text.trim())) ?? 0;

  void _save() {
    final store = StoreScope.read(context);
    final principal = parseMoney(_principal.text);
    final inst = parseMoney(_inst.text);
    String? err;
    if (_title.text.trim().isEmpty) {
      err = 'عنوان وام را وارد کنید';
    } else if (_n <= 0 || _n > 600) {
      err = 'تعداد اقساط معتبر نیست';
    } else if (inst <= 0) {
      err = 'مبلغ هر قسط را وارد کنید';
    } else if (_record && (_account == null || principal <= 0)) {
      err = 'برای ثبت دریافت وام، مبلغ وام و حساب را مشخص کنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    final l = widget.edit ?? Loan(id: newId(), title: '', firstDue: _firstDue);
    l
      ..title = _title.text.trim()
      ..lender = _lender.text.trim()
      ..principal = principal
      ..installmentAmount = inst
      ..installments = _n
      ..firstDue = _firstDue
      ..accountId = _account
      ..note = _note.text.trim();
    l.closed = store.loanPaidCount(l.id) >= l.installments;
    store.saveLoan(l, recordReceive: _record, receiveDate: _receiveDate);
    Navigator.pop(context, l.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final principal = parseMoney(_principal.text);
    final inst = parseMoney(_inst.text);
    final total = inst * _n;
    return FormDialog(
      title: widget.edit == null ? 'ثبت وام' : 'ویرایش وام',
      width: 620,
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
                child: TextField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'عنوان', hintText: 'مثلاً: وام ازدواج'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(controller: _lender, decoration: const InputDecoration(labelText: 'وام‌دهنده (بانک / شخص)')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MoneyField(controller: _principal, label: 'مبلغ دریافتی وام')),
              const SizedBox(width: 12),
              Expanded(child: MoneyField(controller: _inst, label: 'مبلغ هر قسط')),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _count,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'تعداد اقساط'),
                ),
              ),
            ],
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'جمع بازپرداخت: ${groupDigits(total)}'
                '${principal > 0 ? '  ·  سود و کارمزد: ${groupDigits(total - principal)}' : ''}',
                style: th.textTheme.bodySmall?.copyWith(color: AppColors.loan, fontWeight: FontWeight.w600),
              ),
            ),
          DateField(label: 'سررسید قسط اول', value: _firstDue, onChanged: (d) => setState(() => _firstDue = d ?? _firstDue)),
          const SizedBox(height: 14),
          FieldDropdown<String?>(
            label: 'حساب دریافت وام / پرداخت اقساط',
            value: _account,
            items: [for (final a in store.activeAccounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => _account = v),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _record,
            onChanged: (v) => setState(() => _record = v ?? false),
            title: const Text('مبلغ وام به موجودی این حساب اضافه شود'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_record)
            DateField(
              label: 'تاریخ دریافت وام',
              value: _receiveDate,
              onChanged: (d) => setState(() => _receiveDate = d ?? _receiveDate),
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

// ============================================================ pay installment

Future<void> showPayInstallmentDialog(BuildContext context, Loan l) =>
    showDialog<void>(context: context, builder: (_) => _PayDialog(loan: l));

class _PayDialog extends StatefulWidget {
  final Loan loan;
  const _PayDialog({required this.loan});

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final TextEditingController _amount;
  String? _account;
  late DateTime _date;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    _amount = TextEditingController(text: groupDigits(widget.loan.installmentAmount));
    _account = store.account(widget.loan.accountId)?.archived == false
        ? widget.loan.accountId
        : (store.activeAccounts.isEmpty ? null : store.activeAccounts.first.id);
    final due = store.loanNextDue(widget.loan) ?? DateTime.now();
    final today = dateOnly(DateTime.now());
    _date = due.isAfter(today) ? today : due;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final n = store.loanPaidCount(widget.loan.id) + 1;
    return FormDialog(
      title: 'پرداخت قسط $n از ${widget.loan.installments}',
      width: 480,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: _account == null
              ? null
              : () {
                  final a = parseMoney(_amount.text);
                  if (a <= 0) return;
                  store.payInstallment(widget.loan, accountId: _account!, amount: a, date: _date);
                  Navigator.pop(context);
                },
          child: const Text('ثبت پرداخت'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoneyField(controller: _amount, autofocus: true, label: 'مبلغ پرداختی'),
          const SizedBox(height: 6),
          FieldDropdown<String?>(
            label: 'برداشت از حساب',
            value: _account,
            items: [for (final a in store.activeAccounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => _account = v),
          ),
          const SizedBox(height: 14),
          DateField(label: 'تاریخ پرداخت', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
        ],
      ),
    );
  }
}

// ======================================================================= page

class LoansPage extends StatefulWidget {
  const LoansPage({super.key});

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final list = [...store.loans]..sort((a, b) => (a.closed ? 1 : 0).compareTo(b.closed ? 1 : 0));
    if (_selected == null || store.loan(_selected) == null) _selected = list.isEmpty ? null : list.first.id;
    final sel = store.loan(_selected);
    var monthly = 0;
    for (final l in list) {
      if (!l.closed) monthly += l.installmentAmount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'وام‌ها و اقساط',
          subtitle: 'جدول اقساط، پرداخت و مانده هر وام',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final id = await showLoanDialog(context);
                if (id != null) setState(() => _selected = id);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('ثبت وام'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'مانده کل اقساط',
                  value: store.totalLoanRemaining,
                  icon: Icons.account_balance_outlined,
                  color: AppColors.loan,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'جمع قسط ماهانه وام‌های فعال',
                  value: monthly,
                  icon: Icons.event_repeat_outlined,
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.real_estate_agent_outlined,
                  text: 'وامی ثبت نشده',
                  action: FilledButton.icon(
                    onPressed: () => showLoanDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('ثبت وام'),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 360,
                        child: ListView(children: [for (final l in list) _card(context, store, l)]),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: sel == null ? const SizedBox() : _detail(context, store, sel, th)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, AppStore store, Loan l) {
    final th = Theme.of(context);
    final paid = store.loanPaidCount(l.id);
    final next = store.loanNextDue(l);
    final sel = l.id == _selected;
    final overdue = next != null && next.isBefore(dateOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: sel ? AppColors.loan : th.colorScheme.outlineVariant, width: sel ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = l.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (l.closed)
                      const Pill('تسویه شد', color: AppColors.income)
                    else if (overdue)
                      Pill('قسط معوق', color: th.colorScheme.error),
                  ],
                ),
                if (l.lender.isNotEmpty) Text(l.lender, style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: l.installments == 0 ? 0 : paid / l.installments,
                    minHeight: 7,
                    color: AppColors.loan,
                    backgroundColor: AppColors.loan.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('$paid از ${l.installments} قسط', style: th.textTheme.labelMedium),
                    const Spacer(),
                    if (next != null)
                      Text('بعدی: ${jFormat(next)}',
                          style: th.textTheme.labelSmall?.copyWith(color: overdue ? th.colorScheme.error : th.hintColor)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, AppStore store, Loan l, ThemeData th) {
    final payments = store.loanPayments(l.id);
    final paidSum = store.loanPaid(l.id);
    final today = dateOnly(DateTime.now());

    Widget kv(String k, int v, [Color? c]) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
            Money(v, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c)),
          ],
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(child: Text(l.title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                if (!l.closed)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.loan),
                    onPressed: () => showPayInstallmentDialog(context, l),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('پرداخت قسط بعدی'),
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      showLoanDialog(context, edit: l);
                    } else if (v == 'close') {
                      l.closed = !l.closed;
                      store.saveLoan(l);
                    } else if (v == 'delete') {
                      final ok = await confirm(context, 'حذف وام', 'این وام و همه پرداخت‌های ثبت‌شده آن حذف شود؟');
                      if (ok) store.removeLoan(l.id);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem(value: 'close', child: Text(l.closed ? 'باز کردن دوباره' : 'علامت تسویه')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Wrap(
              spacing: 36,
              runSpacing: 10,
              children: [
                kv('مبلغ وام', l.principal),
                kv('جمع بازپرداخت', l.totalPayable),
                kv('سود و کارمزد', l.principal == 0 ? 0 : l.totalPayable - l.principal, AppColors.expense),
                kv('پرداخت‌شده', paidSum, AppColors.income),
                kv('مانده', l.totalPayable - paidSum, AppColors.loan),
              ],
            ),
          ),
          const Divider(),
          Container(
            color: th.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: DefaultTextStyle(
              style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
              child: const Row(
                children: [
                  SizedBox(width: 50, child: Text('قسط')),
                  SizedBox(width: 130, child: Text('سررسید')),
                  Expanded(child: Text('وضعیت')),
                  SizedBox(width: 140, child: Text('مبلغ', textAlign: TextAlign.left)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: l.installments,
              itemBuilder: (context, i) {
                final due = store.installmentDue(l, i);
                final pay = i < payments.length ? payments[i] : null;
                String status;
                Color color;
                if (pay != null) {
                  status = 'پرداخت شد — ${jFormat(pay.date)}';
                  color = AppColors.income;
                } else if (due.isBefore(today)) {
                  status = 'معوق (${today.difference(due).inDays} روز)';
                  color = th.colorScheme.error;
                } else {
                  status = i == payments.length ? 'قسط بعدی' : 'آینده';
                  color = th.hintColor;
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: i == payments.length && !l.closed ? AppColors.loan.withValues(alpha: 0.06) : null,
                    border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant.withValues(alpha: 0.6))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 50, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      SizedBox(width: 130, child: Text(Jalali.fromDateTime(due).format())),
                      Expanded(child: Text(status, style: TextStyle(color: color))),
                      SizedBox(
                        width: 140,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Money(pay?.amount ?? l.installmentAmount,
                              style: TextStyle(fontWeight: FontWeight.w600, color: pay != null ? AppColors.income : null)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
