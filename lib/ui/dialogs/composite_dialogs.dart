import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'simple_dialogs.dart';

// =============================================================== methods

/// Ways to pay (نحوه پرداخت) and receive (نحوه دریافت), as in Sakan.
enum PayMethod {
  // payments — we give to the person
  cashOut('1', 'پرداخت از صندوق', true),
  chequeIssue('2', 'صدور چک', true),
  returnReceivedCheque('3', 'پس دادن چک دریافتی', true, 'F4'),
  endorseCheque('4', 'واگذاری چک وارده', true),
  pettyOut('5', 'پرداخت از تنخواه گردان', true, 'F5'),
  byOtherPerson('6', 'پرداخت توسط سایر اشخاص', true),
  bankOut('7', 'پرداخت بانکی', true, 'F6'),
  fxOut('8', 'پرداخت ارز', true, 'F7'),
  purchaseDiscount('9', 'تخفیف از خرید', true, 'F8'),
  fromPrepayment('', 'کسر از پیش پرداخت', true, 'F11'),
  // receipts — the person gives to us
  cashIn('A', 'دریافت نقدی', false),
  chequeReceive('B', 'دریافت چک', false),
  takeBackIssuedCheque('C', 'پس گرفتن چک صادره', false),
  takeBackEndorsed('D', 'پس گرفتن چک واگذار شده', false),
  bankIn('E', 'واریز به بانک', false),
  pettyIn('F', 'پرداخت به تنخواه گردان', false),
  toOtherPerson('H', 'پرداخت به سایر اشخاص', false),
  fxIn('I', 'دریافت ارز', false),
  saleDiscount('J', 'تخفیف از فروش', false, 'F2'),
  fromAdvance('', 'کسر از پیش دریافت', false);

  final String letter;
  final String label;
  final bool payment;
  final String? key;
  const PayMethod(this.letter, this.label, this.payment, [this.key]);

  bool get disabled => this == fxOut || this == fxIn;
  bool get needsCashAccount => this == cashOut || this == cashIn;
  bool get needsBankAccount => this == bankOut || this == bankIn;
  bool get newCheque => this == chequeIssue || this == chequeReceive;
  bool get pickCheque =>
      this == returnReceivedCheque || this == endorseCheque || this == takeBackIssuedCheque || this == takeBackEndorsed;
  bool get otherPerson => this == byOtherPerson || this == toOtherPerson;
}

class PayItem {
  PayMethod method;
  int amount;
  String? accountId;
  String? otherPersonId;
  String? chequeId;
  DateTime? due;
  String bank;
  String serial;
  String note;

  PayItem(this.method,
      {this.amount = 0, this.accountId, this.otherPersonId, this.chequeId, this.due, this.bank = '', this.serial = '', this.note = ''});

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'amount': amount,
        'accountId': accountId,
        'otherPersonId': otherPersonId,
        'chequeId': chequeId,
        'due': due?.toIso8601String(),
        'bank': bank,
        'serial': serial,
        'note': note,
      };

  factory PayItem.fromJson(Map<String, dynamic> j) => PayItem(
        PayMethod.values.firstWhere((m) => m.name == j['method'], orElse: () => PayMethod.cashOut),
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        accountId: j['accountId'] as String?,
        otherPersonId: j['otherPersonId'] as String?,
        chequeId: j['chequeId'] as String?,
        due: j['due'] == null ? null : DateTime.tryParse('${j['due']}'),
        bank: '${j['bank'] ?? ''}',
        serial: '${j['serial'] ?? ''}',
        note: '${j['note'] ?? ''}',
      );

  String describe(AppStore s) {
    final parts = <String>[];
    if (accountId != null) parts.add(s.account(accountId)?.name ?? '');
    if (otherPersonId != null) parts.add(s.person(otherPersonId)?.name ?? '');
    if (chequeId != null) {
      final c = s.cheque(chequeId);
      if (c != null) parts.add('چک ${c.serial} ${c.bank} — ${jFormat(c.dueDate)}'.trim());
    }
    if (method.newCheque) parts.add('چک ${serial.isEmpty ? '' : '$serial '}${bank.isEmpty ? '' : '$bank '}سررسید ${due == null ? '—' : jFormat(due!)}');
    if (note.isNotEmpty) parts.add(note);
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }
}

int sumPayments(List<PayItem> items) => items.where((i) => i.method.payment).fold(0, (s, i) => s + i.amount);
int sumReceipts(List<PayItem> items) => items.where((i) => !i.method.payment).fold(0, (s, i) => s + i.amount);

/// Applies the financial operations: returns voucher lines and performs cheque side effects.
/// When [personId] is null the person side is omitted (the caller supplies the other side).
List<VoucherLine> applyPayItems(AppStore s, String? personId, List<PayItem> items, DateTime date, String desc) {
  final lines = <VoucherLine>[];
  void personDr(int a) {
    if (personId != null) lines.add(VoucherLine(moeen: mDebtorsTrade, tafsiliId: personId, desc: desc, debit: a));
  }

  void personCr(int a) {
    if (personId != null) lines.add(VoucherLine(moeen: mDebtorsTrade, tafsiliId: personId, desc: desc, credit: a));
  }

  String accM(String? id) => s.account(id)?.type == AccountType.cash ? mCash : mBank;

  for (final i in items) {
    final a = i.amount;
    switch (i.method) {
      case PayMethod.cashOut:
      case PayMethod.bankOut:
        personDr(a);
        lines.add(VoucherLine(moeen: accM(i.accountId), tafsiliId: i.accountId, desc: desc, credit: a));
      case PayMethod.cashIn:
      case PayMethod.bankIn:
        lines.add(VoucherLine(moeen: accM(i.accountId), tafsiliId: i.accountId, desc: desc, debit: a));
        personCr(a);
      case PayMethod.pettyOut:
        personDr(a);
        lines.add(VoucherLine(moeen: mPettyCash, desc: desc, credit: a));
      case PayMethod.pettyIn:
        lines.add(VoucherLine(moeen: mPettyCash, desc: desc, debit: a));
        personCr(a);
      case PayMethod.byOtherPerson:
        personDr(a);
        lines.add(VoucherLine(moeen: mDebtorsTrade, tafsiliId: i.otherPersonId, desc: desc, credit: a));
      case PayMethod.toOtherPerson:
        lines.add(VoucherLine(moeen: mDebtorsTrade, tafsiliId: i.otherPersonId, desc: desc, debit: a));
        personCr(a);
      case PayMethod.purchaseDiscount:
        personDr(a);
        lines.add(VoucherLine(moeen: mPurchaseDiscount, desc: desc, credit: a));
      case PayMethod.saleDiscount:
        lines.add(VoucherLine(moeen: mSaleDiscount, desc: desc, debit: a));
        personCr(a);
      case PayMethod.fromPrepayment:
        personDr(a);
        lines.add(VoucherLine(moeen: '10701', desc: desc, credit: a));
      case PayMethod.fromAdvance:
        lines.add(VoucherLine(moeen: '20501', desc: desc, debit: a));
        personCr(a);
      case PayMethod.chequeIssue:
      case PayMethod.chequeReceive:
        s.upsertCheque(Cheque(
          id: newId(),
          direction: i.method == PayMethod.chequeIssue ? ChequeDirection.issued : ChequeDirection.received,
          amount: a,
          dueDate: i.due ?? date,
          issueDate: date,
          personId: personId,
          bank: i.bank,
          serial: i.serial,
          note: desc,
          bankAccountId: i.method == PayMethod.chequeIssue ? i.accountId : null,
          holderId: i.method == PayMethod.chequeReceive ? i.accountId : null,
        ));
      case PayMethod.returnReceivedCheque:
      case PayMethod.takeBackIssuedCheque:
        final c = s.cheque(i.chequeId);
        if (c != null) s.setChequeStatus(c, ChequeStatus.cancelled);
      case PayMethod.takeBackEndorsed:
        final c = s.cheque(i.chequeId);
        if (c != null) s.setChequeStatus(c, ChequeStatus.pending);
      case PayMethod.endorseCheque:
        final c = s.cheque(i.chequeId);
        if (c != null && personId != null) s.endorseCheque(c, toPersonId: personId, date: date);
      case PayMethod.fxOut:
      case PayMethod.fxIn:
        break;
    }
  }
  return lines;
}

/// Saves the settlement (تسویه) of an invoice as a separate document linked to it.
Voucher? saveInvoiceSettlement(AppStore s, Invoice inv, List<PayItem> items) {
  if (items.isEmpty) return null;
  final desc = 'تسویه ${inv.kind.label} شماره ${inv.number}';
  final lines = applyPayItems(s, inv.personId, items, inv.date, desc);
  if (inv.personId == null) {
    // cash customer: the walk-in debtor account takes the other side
    final net = lines.fold<int>(0, (a, l) => a + l.debit - l.credit);
    if (net > 0) lines.add(VoucherLine(moeen: mDebtorsOther, desc: desc, credit: net));
    if (net < 0) lines.add(VoucherLine(moeen: mDebtorsOther, desc: desc, debit: -net));
  }
  if (lines.isEmpty) return null;
  final v = Voucher(
    id: newId(),
    number: s.nextVoucherNumber(),
    fixedNumber: s.nextFixedNumber(),
    date: inv.date,
    desc: desc,
    lines: lines,
    kind: 'settle',
    meta: {'invoice': inv.id},
  );
  s.saveVoucher(v);
  return v;
}

// ===================================================== financial operations window

/// [before] overrides the previous balance of the person, [docAmount] is the
/// signed amount of the document being settled (sale +, purchase −) and
/// [receiveSide] activates only the receipts (true) or payments (false) column.
Future<List<PayItem>?> showPayMethodsDialog(BuildContext context,
        {required String? personId,
        required List<PayItem> items,
        int extraDue = 0,
        int? before,
        int docAmount = 0,
        bool? receiveSide,
        String? title,
        String? skipLabel}) =>
    showDialog<List<PayItem>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayMethodsDialog(
          personId: personId,
          initial: items,
          extraDue: extraDue,
          before: before,
          docAmount: docAmount,
          receiveSide: receiveSide,
          title: title,
          skipLabel: skipLabel),
    );

class _PayMethodsDialog extends StatefulWidget {
  final String? personId;
  final List<PayItem> initial;
  final int extraDue;
  final int? before;
  final int docAmount;
  final bool? receiveSide;
  final String? title;

  /// When set, a button saves the document without any financial operation.
  final String? skipLabel;
  const _PayMethodsDialog(
      {required this.personId,
      required this.initial,
      this.extraDue = 0,
      this.before,
      this.docAmount = 0,
      this.receiveSide,
      this.title,
      this.skipLabel});

  @override
  State<_PayMethodsDialog> createState() => _PayMethodsDialogState();
}

class _PayMethodsDialogState extends State<_PayMethodsDialog> {
  late final List<PayItem> _items = [...widget.initial];
  bool _printAfter = false;
  late bool _payOn = widget.receiveSide != true;
  late bool _recOn = widget.receiveSide != false;

  Future<void> _open(PayMethod m) async {
    if (m.payment ? !_payOn : !_recOn) return;
    if (m.disabled) {
      toast(context, 'حساب ارزی تعریف نشده است');
      return;
    }
    final r = await showDialog<List<PayItem>>(
      context: context,
      builder: (_) => _MethodItemsDialog(method: m, personId: widget.personId, items: _items.where((i) => i.method == m).toList()),
    );
    if (r == null) return;
    setState(() {
      _items
        ..removeWhere((i) => i.method == m)
        ..addAll(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final pay = sumPayments(_items);
    final rec = sumReceipts(_items);
    final before = widget.before ?? (widget.personId == null ? 0 : store.personBalance(widget.personId!)) + widget.extraDue;
    final after = before + widget.docAmount + pay - rec;
    final keys = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f9): () => Navigator.pop(context, _items),
      const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
    };
    for (final m in PayMethod.values) {
      if (m.key == null) continue;
      final k = switch (m.key) {
        'F2' => LogicalKeyboardKey.f2,
        'F4' => LogicalKeyboardKey.f4,
        'F5' => LogicalKeyboardKey.f5,
        'F6' => LogicalKeyboardKey.f6,
        'F7' => LogicalKeyboardKey.f7,
        'F8' => LogicalKeyboardKey.f8,
        _ => LogicalKeyboardKey.f11,
      };
      keys[SingleActivator(k)] = () => _open(m);
    }

    Widget column(bool payment) {
      final color = payment ? AppColors.expense : AppColors.income;
      final on = payment ? _payOn : _recOn;
      return Opacity(
        opacity: on ? 1 : 0.45,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(payment ? 'پرداخت' : 'دریافت', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 12),
            Checkbox(
              value: on,
              onChanged: (v) => setState(() {
                if (payment) {
                  _payOn = v ?? false;
                  if (!_payOn) _items.removeWhere((i) => i.method.payment);
                } else {
                  _recOn = v ?? false;
                  if (!_recOn) _items.removeWhere((i) => !i.method.payment);
                }
              }),
            ),
            const Text('فعال'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(payment ? 'نحوه پرداخت' : 'نحوه دریافت', style: th.textTheme.labelMedium?.copyWith(color: th.hintColor))),
            SizedBox(width: 60, child: Text('تعداد', textAlign: TextAlign.center, style: th.textTheme.labelMedium?.copyWith(color: th.hintColor))),
            SizedBox(width: 150, child: Text('مبلغ', textAlign: TextAlign.center, style: th.textTheme.labelMedium?.copyWith(color: th.hintColor))),
          ]),
          const SizedBox(height: 4),
          for (final m in PayMethod.values.where((m) => m.payment == payment))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Expanded(
                  child: Material(
                    color: th.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _open(m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        child: Row(children: [
                          if (m.letter.isNotEmpty)
                            Text('${m.letter} : ', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Expanded(
                            child: Text(m.label,
                                style: TextStyle(color: m.disabled ? th.hintColor : null, fontWeight: FontWeight.w500)),
                          ),
                          if (m.key != null) Text(m.key!, style: TextStyle(fontSize: 11, color: AppColors.expense.withValues(alpha: 0.8))),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _box('${_items.where((i) => i.method == m).length}', color, 54),
                const SizedBox(width: 6),
                _box(groupDigits(_items.where((i) => i.method == m).fold<int>(0, (s, i) => s + i.amount)), color, 144),
              ]),
            ),
        ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: keys,
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 1100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(children: [
                  Text(widget.title ?? 'عملیات مالی — نحوه دریافت و پرداخت', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(width: 12),
                  if (widget.personId != null) Pill(store.person(widget.personId)?.name ?? '', color: Colors.white),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: column(true)),
                    const SizedBox(width: 24),
                    Expanded(child: column(false)),
                  ]),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(children: [
                      _sum(th, 'جمع پرداختی', pay, AppColors.expense),
                      const SizedBox(height: 6),
                      _sum(th, 'جمع دریافتی', rec, AppColors.income),
                    ]),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(children: [
                      _sum(th, before >= 0 ? 'بدهی قبلی' : 'طلب قبلی', before.abs(), th.colorScheme.primary),
                      if (widget.docAmount != 0) ...[
                        const SizedBox(height: 6),
                        _sum(th, 'مبلغ این سند', widget.docAmount.abs(), AppColors.loan),
                      ],
                      const SizedBox(height: 6),
                      _sum(th, after >= 0 ? 'مانده دریافتنی' : 'مانده پرداختنی', after.abs(), after == 0 ? AppColors.income : AppColors.debt),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                child: Row(children: [
                  Checkbox(value: _printAfter, onChanged: (v) => setState(() => _printAfter = v ?? false)),
                  const Flexible(child: Text('چاپ عملیات انجام شده در بخش عملیات مالی بعد از ثبت')),
                  const Spacer(),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                  const SizedBox(width: 8),
                  if (widget.skipLabel != null) ...[
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, const <PayItem>[]),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(widget.skipLabel!),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(onPressed: () => Navigator.pop(context, _items), child: const Text('تایید (F9)')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _box(String t, Color c, double w) => Container(
        width: w,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(t, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _sum(ThemeData th, String label, int v, Color c) => Row(children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Money(v, style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
        ),
      ]);
}

// ---------------------------------------------------- items of one method

class _MethodItemsDialog extends StatefulWidget {
  final PayMethod method;
  final String? personId;
  final List<PayItem> items;
  const _MethodItemsDialog({required this.method, required this.personId, required this.items});

  @override
  State<_MethodItemsDialog> createState() => _MethodItemsDialogState();
}

class _MethodItemsDialogState extends State<_MethodItemsDialog> {
  late final List<PayItem> _items = widget.items.map((i) => PayItem.fromJson(i.toJson())).toList();
  final _amount = TextEditingController();
  final _bank = TextEditingController();
  final _serial = TextEditingController();
  final _note = TextEditingController();
  String? _account;
  String? _other;
  String? _cheque;
  DateTime? _due;
  String? _err;

  PayMethod get m => widget.method;

  @override
  void dispose() {
    for (final c in [_amount, _bank, _serial, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Cheque> _chequeChoices(AppStore s) {
    final used = _items.map((i) => i.chequeId).toSet();
    return switch (m) {
      PayMethod.returnReceivedCheque => s.cheques
          .where((c) => c.direction == ChequeDirection.received && c.status == ChequeStatus.pending && c.personId == widget.personId)
          .toList(),
      PayMethod.endorseCheque => s.cheques
          .where((c) => c.direction == ChequeDirection.received && c.status == ChequeStatus.pending && c.personId != widget.personId)
          .toList(),
      PayMethod.takeBackIssuedCheque => s.cheques
          .where((c) => c.direction == ChequeDirection.issued && c.status == ChequeStatus.pending && c.personId == widget.personId)
          .toList(),
      PayMethod.takeBackEndorsed => s.cheques
          .where((c) => c.status == ChequeStatus.endorsed && c.endorsedTo == widget.personId)
          .toList(),
      _ => <Cheque>[],
    }
        .where((c) => !used.contains(c.id))
        .toList();
  }

  void _add() {
    final s = StoreScope.read(context);
    var amount = parseMoney(_amount.text);
    if (m.pickCheque) {
      final c = s.cheque(_cheque);
      if (c == null) {
        setState(() => _err = 'چک را انتخاب کنید');
        return;
      }
      amount = c.amount;
    }
    String? err;
    if (amount <= 0) {
      err = 'مبلغ را وارد کنید';
    } else if ((m.needsCashAccount || m.needsBankAccount) && _account == null) {
      err = 'حساب را انتخاب کنید';
    } else if (m.otherPerson && _other == null) {
      err = 'شخص را انتخاب کنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    setState(() {
      _items.add(PayItem(m,
          amount: amount,
          accountId: _account,
          otherPersonId: _other,
          chequeId: _cheque,
          due: _due,
          bank: _bank.text.trim(),
          serial: _serial.text.trim(),
          note: _note.text.trim()));
      _amount.clear();
      _bank.clear();
      _serial.clear();
      _note.clear();
      _cheque = null;
      _err = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final accounts = s.activeAccounts
        .where((a) => (m.needsCashAccount || m == PayMethod.chequeReceive) ? a.type == AccountType.cash : a.type != AccountType.cash)
        .toList();
    final freeLeaves = m == PayMethod.chequeIssue && _account != null ? s.freeSerials(_account!) : const <String>[];
    final cheques = _chequeChoices(s);
    if (_account == null && accounts.isNotEmpty && (m.needsCashAccount || m.needsBankAccount || m == PayMethod.chequeReceive)) {
      _account = accounts.first.id;
    }
    final total = _items.fold<int>(0, (a, i) => a + i.amount);
    return FormDialog(
      title: m.label,
      width: 640,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, _items), child: const Text('تایید')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.pickCheque)
            FieldDropdown<String?>(
              label: 'انتخاب چک',
              value: _cheque,
              items: [
                for (final c in cheques)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text('${groupDigits(c.amount)} — ${jFormat(c.dueDate)} — ${s.person(c.personId)?.name ?? ''} ${c.serial}'),
                  ),
              ],
              onChanged: (v) => setState(() => _cheque = v),
            )
          else
            MoneyField(controller: _amount, autofocus: true),
          if (m.pickCheque && cheques.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('چک مناسبی برای این عملیات وجود ندارد', style: TextStyle(color: th.colorScheme.error)),
            ),
          if (m.needsCashAccount || m.needsBankAccount) ...[
            const SizedBox(height: 6),
            FieldDropdown<String?>(
              label: m.needsCashAccount ? 'صندوق' : 'حساب بانکی',
              value: _account,
              items: [for (final a in accounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _account = v),
            ),
          ],
          if (m.otherPerson) ...[
            const SizedBox(height: 10),
            FieldDropdown<String?>(
              label: m == PayMethod.byOtherPerson ? 'پرداخت کننده' : 'دریافت کننده',
              value: _other,
              items: [
                for (final p in s.peopleSorted.where((p) => p.id != widget.personId))
                  DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _other = v),
            ),
          ],
          if (m.newCheque) ...[
            const SizedBox(height: 6),
            FieldDropdown<String?>(
              label: m == PayMethod.chequeIssue ? 'حساب بانکی (دسته چک)' : 'صندوق نگهدارنده چک',
              value: _account,
              items: [for (final a in accounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() {
                _account = v;
                if (m == PayMethod.chequeIssue) {
                  _serial.clear();
                  _bank.text = _bankName(s.account(v));
                }
              }),
            ),
            if (freeLeaves.isNotEmpty) ...[
              const SizedBox(height: 6),
              FieldDropdown<String?>(
                label: 'برگه چک از دسته چک',
                value: freeLeaves.contains(_serial.text) ? _serial.text : null,
                items: [for (final l in freeLeaves) DropdownMenuItem<String?>(value: l, child: Text(l, textDirection: TextDirection.ltr))],
                onChanged: (v) => setState(() => _serial.text = v ?? ''),
              ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: DateField(label: 'سررسید', value: _due, onChanged: (d) => setState(() => _due = d))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _bank, decoration: const InputDecoration(labelText: 'بانک'))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(controller: _serial, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره چک')),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'شرح')),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: TextStyle(color: th.colorScheme.error))),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('افزودن')),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant))),
              child: Row(children: [
                SizedBox(width: 30, child: Text('${i + 1}')),
                Expanded(child: Text(_items[i].describe(s), overflow: TextOverflow.ellipsis)),
                Money(_items[i].amount, style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  onPressed: () => setState(() => _items.removeAt(i)),
                  icon: Icon(Icons.close_rounded, size: 18, color: th.colorScheme.error),
                ),
              ]),
            ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Text('جمع ${m.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Money(total, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
        ],
      ),
    );
  }
}

// ================================================== دریافت پرداخت مرکب

Future<void> showCompositeDialog(BuildContext context) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _CompositeDialog());

class _CompositeDialog extends StatefulWidget {
  const _CompositeDialog();

  @override
  State<_CompositeDialog> createState() => _CompositeDialogState();
}

class _CompositeDialogState extends State<_CompositeDialog> {
  String? _person;
  List<PayItem> _items = [];
  DateTime _date = dateOnly(DateTime.now());
  final _number = TextEditingController();
  final _desc = TextEditingController();
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _number.text = '${StoreScope.read(context).nextVoucherNumber()}';
  }

  @override
  void dispose() {
    _number.dispose();
    _desc.dispose();
    super.dispose();
  }

  File _temp(AppStore s) => File('${s.storage.dir.path}${Storage.sep}composite_draft.json');

  Future<void> _methods() async {
    if (_person == null) {
      toast(context, 'قبل از تعیین نحوه دریافت و پرداخت لطفاً شخص را تعیین کنید', error: true);
      return;
    }
    final r = await showPayMethodsDialog(context, personId: _person, items: _items);
    if (r != null) setState(() => _items = r);
  }

  Future<void> _settleInvoice() async {
    final s = StoreScope.read(context);
    if (_person == null) {
      toast(context, 'ابتدا طرف حساب را انتخاب کنید', error: true);
      return;
    }
    final open = s.realInvoices.where((i) => i.personId == _person && i.remaining > 0).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (open.isEmpty) {
      toast(context, 'فاکتور باز (تسویه نشده) برای این شخص وجود ندارد');
      return;
    }
    final inv = await showDialog<Invoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('تسویه فاکتور'),
        children: [
          for (final i in open)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Row(children: [
                Expanded(child: Text('${i.kind.label} ${i.number} — ${jFormat(i.date)}')),
                Text('مانده: ${groupDigits(i.remaining)}'),
              ]),
            ),
        ],
      ),
    );
    if (inv == null) return;
    setState(() => _desc.text = 'تسویه ${inv.kind.label} شماره ${inv.number}');
    if (!mounted) return;
    toast(context, 'مانده فاکتور ${groupDigits(inv.remaining)} است؛ نحوه دریافت/پرداخت را تعیین کنید');
    _methods();
  }

  void _save() {
    final s = StoreScope.read(context);
    if (_person == null) {
      toast(context, 'طرف حساب را انتخاب کنید', error: true);
      return;
    }
    if (_items.isEmpty) {
      toast(context, 'هیچ عملیات دریافت یا پرداختی تعیین نشده', error: true);
      return;
    }
    final desc = _desc.text.trim().isEmpty ? 'دریافت و پرداخت مرکب — ${s.person(_person)?.name ?? ''}' : _desc.text.trim();
    final lines = applyPayItems(s, _person, _items, _date, desc);
    if (lines.isNotEmpty) {
      s.saveVoucher(Voucher(
        id: newId(),
        number: int.tryParse(normalizeDigits(_number.text.trim())) ?? s.nextVoucherNumber(),
        fixedNumber: s.nextFixedNumber(),
        date: _date,
        desc: desc,
        lines: lines,
        kind: 'composite',
      ));
    }
    Navigator.pop(context);
    toast(context, 'دریافت و پرداخت مرکب ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'دریافت پرداخت مرکب',
        width: 760,
        actions: [
          OutlinedButton(
            onPressed: () {
              _temp(s).writeAsStringSync(jsonEncode({
                'person': _person,
                'desc': _desc.text,
                'items': _items.map((i) => i.toJson()).toList(),
              }));
              toast(context, 'در فایل موقت ثبت شد');
            },
            child: const Text('ثبت در فایل موقت'),
          ),
          OutlinedButton(
            onPressed: () {
              final f = _temp(s);
              if (!f.existsSync()) {
                toast(context, 'فایل موقتی وجود ندارد', error: true);
                return;
              }
              final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
              setState(() {
                _person = j['person'] as String?;
                _desc.text = '${j['desc'] ?? ''}';
                _items = (j['items'] as List).whereType<Map<String, dynamic>>().map(PayItem.fromJson).toList();
              });
            },
            child: const Text('خواندن از فایل موقت'),
          ),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند')),
              ),
              const SizedBox(width: 10),
              Expanded(child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FieldDropdown<String?>(
                  label: 'طرف حساب',
                  value: _person,
                  items: [
                    for (final p in s.peopleSorted)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Row(children: [
                          Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                          Money(s.personBalance(p.id), colorBySign: true, style: th.textTheme.labelSmall),
                        ]),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _person = v;
                    _items = [];
                  }),
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
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Column(children: [
                  _sum(th, 'جمع پرداختی', sumPayments(_items), AppColors.expense),
                  const SizedBox(height: 6),
                  _sum(th, 'جمع دریافتی', sumReceipts(_items), AppColors.income),
                ]),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: _methods,
                icon: const Icon(Icons.swap_vert_rounded, size: 18),
                label: const Text('نحوه دریافت و پرداخت'),
              ),
            ]),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final i in _items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(i.method.payment ? Icons.north_east_rounded : Icons.south_west_rounded,
                        size: 16, color: i.method.payment ? AppColors.expense : AppColors.income),
                    const SizedBox(width: 6),
                    Text(i.method.label),
                    const SizedBox(width: 6),
                    Expanded(child: Text(i.describe(s), style: th.textTheme.bodySmall?.copyWith(color: th.hintColor), overflow: TextOverflow.ellipsis)),
                    Money(i.amount),
                  ]),
                ),
            ],
            const SizedBox(height: 14),
            TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح سند')),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(onPressed: _settleInvoice, icon: const Icon(Icons.receipt_long_outlined, size: 18), label: const Text('تسویه فاکتور')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sum(ThemeData th, String label, int v, Color c) => Row(children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Money(v, style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
        ),
      ]);
}

// ============================================== پرداخت هزینه‌های مرکب

Future<void> showCompositeExpenseDialog(BuildContext context) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _ExpenseDialog());

class _ExpRow {
  String? key; // category id (accounts tab) or product id (products tab)
  final amount = TextEditingController();
  final note = TextEditingController();
  int get v => parseMoney(amount.text);
  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog();

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  bool _misc = false; // متفرقه: no payee account
  String? _payee;
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _number = TextEditingController();
  final _duty = TextEditingController();
  final _tax = TextEditingController();
  String? _dutyAcc;
  String? _taxAcc;
  DateTime _date = dateOnly(DateTime.now());
  final List<_ExpRow> _accRows = [];
  final List<_ExpRow> _prodRows = [];
  List<PayItem> _items = [];
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _number.text = '${StoreScope.read(context).nextVoucherNumber()}';
    for (final c in [_amount, _duty, _tax]) {
      c.addListener(() => setState(() {}));
    }
    _addRow(_accRows);
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in [_amount, _desc, _number, _duty, _tax]) {
      c.dispose();
    }
    for (final r in [..._accRows, ..._prodRows]) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow(List<_ExpRow> list) {
    final r = _ExpRow();
    r.amount.addListener(() => setState(() {}));
    setState(() => list.add(r));
  }

  int get _allocated =>
      _accRows.fold<int>(0, (s, r) => s + r.v) + _prodRows.fold<int>(0, (s, r) => s + r.v) + parseMoney(_duty.text) + parseMoney(_tax.text);

  int get _total => parseMoney(_amount.text);

  Future<void> _ops() async {
    if (!_misc && _payee == null) {
      toast(context, 'قبل از تعیین نحوه دریافت و پرداخت لطفاً شخص را تعیین کنید', error: true);
      return;
    }
    final r = await showPayMethodsDialog(context, personId: _misc ? null : _payee, items: _items, extraDue: _misc ? 0 : -_total);
    if (r != null) setState(() => _items = r);
  }

  void _save() {
    final s = StoreScope.read(context);
    final total = _total;
    String? err;
    if (total <= 0) {
      err = 'مبلغ را وارد کنید';
    } else if (!_misc && _payee == null) {
      err = 'دریافت کننده را انتخاب کنید (یا «متفرقه» را بزنید)';
    } else if (_allocated != total) {
      err = 'جمع سهم هزینه‌ها و عوارض/مالیات (${groupDigits(_allocated)}) با مبلغ (${groupDigits(total)}) برابر نیست';
    } else if (_accRows.any((r) => r.v > 0 && r.key == null) || _prodRows.any((r) => r.v > 0 && r.key == null)) {
      err = 'برای هر ردیف دارای مبلغ، عنوان حساب را انتخاب کنید';
    } else if ((parseMoney(_duty.text) > 0 && _dutyAcc == null) || (parseMoney(_tax.text) > 0 && _taxAcc == null)) {
      err = 'برای عوارض/مالیات عنوان حساب را انتخاب کنید';
    } else if (_misc && sumPayments(_items) - sumReceipts(_items) != total) {
      err = 'در حالت متفرقه باید کل مبلغ از طریق «عملیات مالی» پرداخت شود';
    }
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    final desc = _desc.text.trim().isEmpty ? 'پرداخت هزینه‌های مرکب' : _desc.text.trim();
    final lines = <VoucherLine>[];
    for (final r in _accRows.where((r) => r.v > 0)) {
      lines.add(VoucherLine(moeen: mExpense, tafsiliId: r.key, desc: r.note.text.trim().isEmpty ? desc : r.note.text.trim(), debit: r.v));
    }
    for (final r in _prodRows.where((r) => r.v > 0)) {
      lines.add(VoucherLine(moeen: mStock, tafsiliId: r.key, desc: r.note.text.trim().isEmpty ? desc : r.note.text.trim(), debit: r.v));
    }
    if (parseMoney(_duty.text) > 0) lines.add(VoucherLine(moeen: _dutyAcc!, desc: 'عوارض (VAT)', debit: parseMoney(_duty.text)));
    if (parseMoney(_tax.text) > 0) lines.add(VoucherLine(moeen: _taxAcc!, desc: 'مالیات (VAT)', debit: parseMoney(_tax.text)));
    if (!_misc) lines.add(VoucherLine(moeen: mDebtorsTrade, tafsiliId: _payee, desc: desc, credit: total));
    lines.addAll(applyPayItems(s, _misc ? null : _payee, _items, _date, desc));
    s.saveVoucher(Voucher(
      id: newId(),
      number: int.tryParse(normalizeDigits(_number.text.trim())) ?? s.nextVoucherNumber(),
      fixedNumber: s.nextFixedNumber(),
      date: _date,
      desc: desc,
      lines: lines,
      kind: 'expense',
    ));
    Navigator.pop(context);
    toast(context, 'پرداخت هزینه‌های مرکب ثبت شد');
  }

  Widget _rowsTable(List<_ExpRow> rows, bool products) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final opts = products
        ? [for (final p in s.productsSorted) (p.id, p.code.isEmpty ? '—' : p.code, p.name)]
        : [for (final c in s.categoriesOf(CategoryKind.expense)) (c.id, '$mExpense', c.name)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: th.colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DefaultTextStyle(
            style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w700),
            child: Row(children: [
              const SizedBox(width: 40, child: Text('ردیف')),
              SizedBox(width: 80, child: Text(products ? 'کد کالا' : 'کد حساب')),
              Expanded(flex: 3, child: Text(products ? 'نام کالا' : 'عنوان حساب')),
              const SizedBox(width: 160, child: Text('مبلغ سهم هزینه', textAlign: TextAlign.center)),
              const Expanded(flex: 2, child: Text('توضیحات')),
              const SizedBox(width: 40),
            ]),
          ),
        ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(children: [
              SizedBox(width: 40, child: Text('${i + 1}')),
              SizedBox(width: 80, child: Text(opts.where((o) => o.$1 == rows[i].key).map((o) => o.$2).firstOrNull ?? '')),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  value: rows[i].key,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [for (final o in opts) DropdownMenuItem<String?>(value: o.$1, child: Text(o.$3))],
                  onChanged: (v) => setState(() => rows[i].key = v),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 154,
                child: TextField(
                  controller: rows[i].amount,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: TextField(controller: rows[i].note, decoration: const InputDecoration(isDense: true))),
              SizedBox(
                width: 40,
                child: IconButton(
                  onPressed: () => setState(() => rows.removeAt(i).dispose()),
                  icon: Icon(Icons.close_rounded, size: 18, color: th.colorScheme.error),
                ),
              ),
            ]),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(onPressed: () => _addRow(rows), icon: const Icon(Icons.add_rounded), label: const Text('افزودن ردیف')),
        ),
        if (!products && opts.isEmpty)
          Text('دسته هزینه‌ای تعریف نشده است', style: TextStyle(color: th.colorScheme.error)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final liabMoeens = [for (final k in chart.where((k) => k.side == Side.liability || k.side == Side.asset || k.side == Side.expense)) ...k.ledgers.where((m) => !m.hasEntity)];
    final remaining = _total - _allocated;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f2): _ops,
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: size.width > 1180 ? 1140 : size.width - 40,
          height: size.height * 0.92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(children: [
                  Text('پرداخت هزینه های مرکب', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند')),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: DateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        FilterChip(
                          label: const Text('متفرقه'),
                          selected: _misc,
                          onSelected: (v) => setState(() {
                            _misc = v;
                            if (v) _payee = null;
                            _items = [];
                          }),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: _misc
                              ? const InputDecorator(
                                  decoration: InputDecoration(labelText: 'دریافت کننده'),
                                  child: Text('متفرقه (پرداخت مستقیم)'),
                                )
                              : FieldDropdown<String?>(
                                  label: 'دریافت کننده (عنوان حساب)',
                                  value: _payee,
                                  items: [for (final p in s.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name))],
                                  onChanged: (v) => setState(() {
                                    _payee = v;
                                    _items = [];
                                  }),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: MoneyField(controller: _amount, label: 'مبلغ')),
                      ]),
                      TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح')),
                      const SizedBox(height: 12),
                      for (final e in [
                        ('مبلغ عوارض (VAT)', _duty, _dutyAcc, (String? v) => _dutyAcc = v),
                        ('مبلغ مالیات (VAT)', _tax, _taxAcc, (String? v) => _taxAcc = v),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                              child: TextField(
                                controller: e.$2,
                                textDirection: TextDirection.ltr,
                                inputFormatters: [MoneyInputFormatter()],
                                decoration: InputDecoration(labelText: e.$1),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FieldDropdown<String?>(
                                label: 'عنوان حساب',
                                value: e.$3,
                                items: [for (final m in liabMoeens) DropdownMenuItem<String?>(value: m.code, child: Text('${m.code}  ${m.name}'))],
                                onChanged: (v) => setState(() => e.$4(v)),
                              ),
                            ),
                          ]),
                        ),
                      TabBar(controller: _tab, tabs: const [Tab(text: 'حساب ها'), Tab(text: 'کالا ها')], onTap: (_) => setState(() {})),
                      const SizedBox(height: 8),
                      _tab.index == 0 ? _rowsTable(_accRows, false) : _rowsTable(_prodRows, true),
                      if (_tab.index == 1)
                        Text('سهم هزینه کالاها به بهای تمام‌شده همان کالا اضافه می‌شود (مثلاً کرایه حمل).',
                            style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: Row(children: [
                  OutlinedButton.icon(onPressed: _ops, icon: const Icon(Icons.swap_vert_rounded, size: 18), label: const Text('عملیات مالی (F2)')),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [const Text('جمع پرداختی: '), Money(sumPayments(_items), style: const TextStyle(fontWeight: FontWeight.w700))]),
                    Row(children: [const Text('جمع دریافتی: '), Money(sumReceipts(_items), style: const TextStyle(fontWeight: FontWeight.w700))]),
                  ]),
                  const SizedBox(width: 18),
                  if (_total > 0)
                    Pill(remaining == 0 ? 'سهم‌ها کامل است' : 'تخصیص نیافته: ${groupDigits(remaining)}',
                        color: remaining == 0 ? AppColors.income : th.colorScheme.error),
                  const Spacer(),
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _bankName(Account? a) => a == null ? '' : (a.bank.isNotEmpty ? a.bank : a.name);
