import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/invoice_editor.dart';
import '../dialogs/txn_dialog.dart';
import '../shell.dart';
import '../theme.dart';
import 'common.dart';

/// Column layout shared by header and rows.
class _Cols {
  static const date = 110.0;
  static const type = 120.0;
  static const amount = 150.0;
  static const balance = 150.0;
  static const actions = 44.0;
}

/// Desktop-style ledger table. When [ledgerAccountId] is set, amounts are
/// signed relative to that account and a running balance column is shown.
/// When [ledgerPersonId] is set, the person's running balance is shown.
class TxnTable extends StatefulWidget {
  final List<Txn> txns;
  final String? ledgerAccountId;
  final String? ledgerPersonId;
  final Map<String, int>? running;
  final bool shrinkWrap;
  final String emptyText;

  const TxnTable({
    super.key,
    required this.txns,
    this.ledgerAccountId,
    this.ledgerPersonId,
    this.running,
    this.shrinkWrap = false,
    this.emptyText = 'تراکنشی پیدا نشد',
  });

  @override
  State<TxnTable> createState() => _TxnTableState();
}

class _TxnTableState extends State<TxnTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final showBalance = widget.running != null;
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: th.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant)),
      ),
      child: DefaultTextStyle(
        style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
        child: Row(
          children: [
            const SizedBox(width: _Cols.date, child: Text('تاریخ')),
            const SizedBox(width: _Cols.type, child: Text('نوع')),
            const Expanded(child: Text('شرح')),
            const SizedBox(width: _Cols.amount, child: Text('مبلغ', textAlign: TextAlign.left)),
            if (showBalance) const SizedBox(width: _Cols.balance, child: Text('مانده', textAlign: TextAlign.left)),
            const SizedBox(width: _Cols.actions),
          ],
        ),
      ),
    );

    if (widget.txns.isEmpty) {
      return Column(
        mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          header,
          if (widget.shrinkWrap)
            EmptyState(icon: Icons.receipt_long_outlined, text: widget.emptyText)
          else
            Expanded(child: EmptyState(icon: Icons.receipt_long_outlined, text: widget.emptyText)),
        ],
      );
    }

    final list = ListView.builder(
      controller: widget.shrinkWrap ? null : _scroll,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: widget.txns.length,
      itemBuilder: (context, i) => _TxnRow(
        txn: widget.txns[i],
        ledgerAccountId: widget.ledgerAccountId,
        ledgerPersonId: widget.ledgerPersonId,
        running: widget.running?[widget.txns[i].id],
        showBalance: showBalance,
        zebra: i.isOdd,
      ),
    );

    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (widget.shrinkWrap)
          list
        else
          Expanded(child: Scrollbar(controller: _scroll, thumbVisibility: true, child: list)),
      ],
    );
  }
}

class _TxnRow extends StatefulWidget {
  final Txn txn;
  final String? ledgerAccountId;
  final String? ledgerPersonId;
  final int? running;
  final bool showBalance;
  final bool zebra;

  const _TxnRow({
    required this.txn,
    this.ledgerAccountId,
    this.ledgerPersonId,
    this.running,
    required this.showBalance,
    required this.zebra,
  });

  @override
  State<_TxnRow> createState() => _TxnRowState();
}

class _TxnRowState extends State<_TxnRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final t = widget.txn;
    final color = txnColor(t.type);

    // signed amount relative to the ledger context
    int signed;
    if (widget.ledgerAccountId != null) {
      signed = t.effectOn(widget.ledgerAccountId!);
    } else if (widget.ledgerPersonId != null) {
      signed = t.type.personSign != 0
          ? t.type.personSign * t.amount
          : (t.type == TxnType.income ? t.amount : -t.amount);
    } else {
      signed = t.type == TxnType.transfer ? t.amount : t.type.accountSign * t.amount;
    }

    final title = _title(store, t);
    final sub = <String>[
      if (t.note.isNotEmpty) t.note,
      if (t.dueDate != null) 'سررسید ${jFormat(t.dueDate!)}',
      if (t.chequeId != null) 'مرتبط با چک',
    ].join('  ·  ');

    final bg = _hover
        ? th.colorScheme.primary.withValues(alpha: 0.05)
        : (widget.zebra ? th.colorScheme.surfaceContainerLow.withValues(alpha: 0.6) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: () => openTxn(context, t),
        child: Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: _Cols.date,
                child: Text(jFormat(t.date), style: th.textTheme.bodySmall),
              ),
              SizedBox(
                width: _Cols.type,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Pill(t.type.label, color: color, icon: txnIcon(t.type)),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                  ],
                ),
              ),
              SizedBox(
                width: _Cols.amount,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Money(
                    signed,
                    signed: widget.ledgerAccountId != null || widget.ledgerPersonId != null,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: t.type == TxnType.transfer && widget.ledgerAccountId == null
                          ? AppColors.transfer
                          : (signed >= 0 ? AppColors.income : AppColors.expense),
                    ),
                  ),
                ),
              ),
              if (widget.showBalance)
                SizedBox(
                  width: _Cols.balance,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.running == null
                        ? const SizedBox()
                        : Money(widget.running!, style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
                  ),
                ),
              SizedBox(
                width: _Cols.actions,
                child: PopupMenuButton<String>(
                  tooltip: 'گزینه‌ها',
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (v) async {
                    if (v == 'open') {
                      openTxn(context, t);
                    } else if (v == 'edit') {
                      showTxnDialog(context, edit: t);
                    } else if (v == 'dup') {
                      showTxnDialog(context, edit: t, duplicate: true);
                    } else if (v == 'del') {
                      final ok = await confirm(context, 'حذف تراکنش', 'این تراکنش حذف شود؟');
                      if (ok) store.removeTxn(t.id);
                    }
                  },
                  itemBuilder: (_) => t.type.isSystem
                      ? [
                          PopupMenuItem(
                            value: 'open',
                            child: Text(t.invoiceId != null ? 'باز کردن فاکتور' : 'باز کردن'),
                          ),
                          if (t.type == TxnType.loanPay) const PopupMenuItem(value: 'del', child: Text('حذف این پرداخت')),
                        ]
                      : const [
                          PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                          PopupMenuItem(value: 'dup', child: Text('کپی به عنوان تراکنش جدید')),
                          PopupMenuItem(value: 'del', child: Text('حذف')),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title(AppStore store, Txn t) {
    final acc = store.account(t.accountId)?.name;
    final to = store.account(t.toAccountId)?.name;
    final cat = store.category(t.categoryId)?.name;
    final per = store.person(t.personId)?.name;
    switch (t.type) {
      case TxnType.transfer:
        return '${acc ?? '?'}  ←  ${to ?? '?'}';
      case TxnType.income:
      case TxnType.expense:
        return [cat ?? 'بدون دسته', if (per != null) per, if (acc != null && widget.ledgerAccountId == null) acc]
            .join('  ·  ');
      default:
        if (t.type.isLoan) {
          return [store.loan(t.loanId)?.title ?? 'وام', if (acc != null && widget.ledgerAccountId == null) acc]
              .join('  ·  ');
        }
        if (t.invoiceId != null && per == null) {
          final inv = store.invoice(t.invoiceId);
          final who = inv == null || !inv.kind.buySide ? 'مشتری نقدی' : 'فروشنده متفرقه';
          return [who, if (acc != null && widget.ledgerAccountId == null) acc].join('  ·  ');
        }
        return [per ?? 'بدون طرف حساب', if (acc != null && widget.ledgerAccountId == null) acc].join('  ·  ');
    }
  }
}

/// Opens the right editor for a ledger row (invoice, loan or plain transaction).
void openTxn(BuildContext context, Txn t) {
  final store = StoreScope.read(context);
  if (t.invoiceId != null) {
    final inv = store.invoice(t.invoiceId);
    if (inv != null) showInvoiceEditor(context, edit: inv);
    return;
  }
  if (t.type.isLoan) return;
  showTxnDialog(context, edit: t);
}
