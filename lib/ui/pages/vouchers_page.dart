import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/chequebook_dialogs.dart';
import '../dialogs/closing_dialogs.dart';
import '../dialogs/invoice_editor.dart';
import '../dialogs/opening_dialog.dart';
import '../dialogs/txn_dialog.dart';
import '../dialogs/voucher_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Which documents the list shows.
enum DocFilter { all, vouchers, invoices, payments }

extension on DocFilter {
  String get label => switch (this) {
        DocFilter.all => 'همه اسناد',
        DocFilter.vouchers => 'اسناد حسابداری',
        DocFilter.invoices => 'فاکتورها',
        DocFilter.payments => 'دریافت و پرداخت',
      };
}

/// One row of «لیست اسناد» — a voucher, an invoice or a financial operation.
class _Doc {
  final DocFilter group;
  final String number;
  final String fixed;
  final DateTime date;
  final String kind;
  final Color color;
  final String desc;
  final int rows;
  final int debit;
  final int credit;
  final int order;
  final void Function(BuildContext) open;
  const _Doc({
    required this.group,
    required this.number,
    this.fixed = '',
    required this.date,
    required this.kind,
    required this.color,
    required this.desc,
    required this.rows,
    required this.debit,
    required this.credit,
    required this.order,
    required this.open,
  });
}

/// لیست اسناد — every document of the ledger.
class VouchersPage extends StatefulWidget {
  const VouchersPage({super.key});

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> {
  String _q = '';
  DocFilter _filter = DocFilter.all;

  List<_Doc> _docs(AppStore store, ThemeData th) {
    final out = <_Doc>[];
    for (final v in store.vouchers) {
      out.add(_Doc(
        group: DocFilter.vouchers,
        number: '${v.number}',
        fixed: '${v.fixedNumber}',
        date: v.date,
        kind: v.kindLabel,
        color: switch (v.kind) {
          'manual' => th.colorScheme.primary,
          'expense' || 'closing' => AppColors.expense,
          'chequeMove' => AppColors.discount,
          'reopen' || 'settle' || 'assetSell' => AppColors.income,
          'assetBuy' || 'depreciation' => AppColors.loan,
          _ => AppColors.debt,
        },
        desc: [v.desc.isEmpty ? (v.lines.isEmpty ? '' : v.lines.first.desc) : v.desc, ...v.lines.map((l) => store.tafsiliName(l))].join(' '),
        rows: v.lines.length,
        debit: v.totalDebit,
        credit: v.totalCredit,
        order: v.createdAt,
        open: (c) => switch (v.kind) {
          'chequeMove' => showChequeMoveDialog(c, edit: v),
          'closing' || 'reopen' || 'settle' || 'assetBuy' || 'assetSell' || 'depreciation' || 'profitSplit' || 'shareSplit' =>
            showYearEndVoucher(c, v),
          _ => showVoucherDialog(c, edit: v),
        },
      ));
    }
    for (final inv in store.realInvoices) {
      out.add(_Doc(
        group: DocFilter.invoices,
        number: '${inv.number}',
        date: inv.date,
        kind: inv.kind.label,
        color: switch (inv.kind) {
          InvoiceKind.sale => AppColors.income,
          InvoiceKind.purchase => AppColors.expense,
          _ => AppColors.loan,
        },
        desc: '${store.person(inv.personId)?.name ?? 'متفرقه'} ${inv.note}',
        rows: inv.lines.length,
        debit: inv.total,
        credit: inv.total,
        order: inv.createdAt,
        open: (c) => showInvoiceEditor(c, edit: inv),
      ));
    }
    for (final t in store.txns) {
      if (t.invoiceId != null) continue;
      out.add(_Doc(
        group: DocFilter.payments,
        number: '—',
        date: t.date,
        kind: t.type.label,
        color: AppColors.transfer,
        desc: [store.person(t.personId)?.name ?? '', store.account(t.accountId)?.name ?? '', t.note].where((x) => x.isNotEmpty).join(' — '),
        rows: 1,
        debit: t.amount,
        credit: t.amount,
        order: t.createdAt,
        open: (c) => showTxnDialog(c, edit: t),
      ));
    }
    out.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.order.compareTo(a.order);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final all = _docs(store, th);
    final list = all.where((d) {
      if (_filter != DocFilter.all && d.group != _filter) return false;
      if (q.isEmpty) return true;
      return '${d.number} ${d.fixed} ${d.kind} ${d.desc} ${jFormat(d.date)}'.toLowerCase().contains(q);
    }).toList();
    final od = store.settings.openingDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'لیست اسناد',
          subtitle: 'همه اسناد: حسابداری، فاکتورها و دریافت و پرداخت‌ها',
          actions: [
            SizedBox(
              width: 170,
              child: FieldDropdown<DocFilter>(
                label: 'نوع سند',
                value: _filter,
                items: [for (final f in DocFilter.values) DropdownMenuItem(value: f, child: Text(f.label))],
                onChanged: (v) => setState(() => _filter = v ?? DocFilter.all),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(hintText: 'شماره، شرح، طرف حساب…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => openOpeningVoucher(context),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('سند افتتاحیه'),
            ),
            FilledButton.icon(
              onPressed: () => showVoucherDialog(context),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('سند حسابداری دستی (Alt+F2)'),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: th.colorScheme.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: DefaultTextStyle(
                      style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w700),
                      child: const Row(children: [
                        SizedBox(width: 90, child: Text('شماره')),
                        SizedBox(width: 90, child: Text('شماره ثابت')),
                        SizedBox(width: 110, child: Text('تاریخ')),
                        SizedBox(width: 190, child: Text('نوع سند')),
                        Expanded(child: Text('شرح')),
                        SizedBox(width: 70, child: Text('ردیف‌ها', textAlign: TextAlign.center)),
                        SizedBox(width: 150, child: Text('جمع بدهکار', textAlign: TextAlign.left)),
                        SizedBox(width: 150, child: Text('جمع بستانکار', textAlign: TextAlign.left)),
                      ]),
                    ),
                  ),
                  if (od != null && (_filter == DocFilter.all || _filter == DocFilter.vouchers))
                    InkWell(
                      onTap: () => openOpeningVoucher(context),
                      child: Container(
                        color: AppColors.loan.withValues(alpha: 0.06),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(children: [
                          const SizedBox(width: 90, child: Text('افتتاحیه', style: TextStyle(fontWeight: FontWeight.w700))),
                          const SizedBox(width: 90, child: Text('—')),
                          SizedBox(width: 110, child: Text(jFormat(od))),
                          const SizedBox(width: 190),
                          const Expanded(child: Text('سند افتتاحیه')),
                        ]),
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(icon: Icons.list_alt_rounded, text: 'سندی ثبت نشده')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final d = list[i];
                              return InkWell(
                                onTap: () => d.open(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                  child: Row(children: [
                                    SizedBox(width: 90, child: Text(d.number, style: const TextStyle(fontWeight: FontWeight.w700))),
                                    SizedBox(width: 90, child: Text(d.fixed)),
                                    SizedBox(width: 110, child: Text(jFormat(d.date))),
                                    SizedBox(
                                      width: 190,
                                      child: Align(alignment: AlignmentDirectional.centerStart, child: Pill(d.kind, color: d.color)),
                                    ),
                                    Expanded(child: Text(d.desc.trim(), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: 70, child: Text('${d.rows}', textAlign: TextAlign.center)),
                                    SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Money(d.debit))),
                                    SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Money(d.credit))),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    color: th.colorScheme.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '${list.length} سند — ${all.where((d) => d.group == DocFilter.vouchers).length} سند حسابداری، '
                      '${all.where((d) => d.group == DocFilter.invoices).length} فاکتور، '
                      '${all.where((d) => d.group == DocFilter.payments).length} دریافت/پرداخت',
                      style: th.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
