import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/cheque_dialogs.dart';
import '../dialogs/invoice_editor.dart';
import '../dialogs/txn_dialog.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/txn_table.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final now = Jalali.now();
    final mt = store.monthTotals(now);
    final prev = store.monthTotals(now.addMonths(-1));
    final sales = store.profit(now.firstOfMonth.toDateTime(), now.lastOfMonth.toDateTime());

    final months = <MonthBar>[];
    for (var i = 5; i >= 0; i--) {
      final m = now.addMonths(-i);
      final t = store.monthTotals(m);
      months.add(MonthBar(m.monthName, t.income, t.expense));
    }

    String delta(int cur, int old) {
      if (old == 0) return 'ماه قبل: ۰';
      final p = ((cur - old) * 100 / old).round();
      return 'نسبت به ماه قبل: ${p >= 0 ? '+' : ''}$p٪';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'پیشخوان',
          subtitle: '${now.formatWithWeekday()} — خلاصه وضعیت مالی شما',
          actions: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.income),
              onPressed: () => showInvoiceEditor(context, kind: InvoiceKind.sale),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('فاکتور فروش (F6)'),
            ),
            OutlinedButton.icon(
              onPressed: () => showInvoiceEditor(context, kind: InvoiceKind.purchase),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18, color: AppColors.expense),
              label: const Text('فاکتور خرید (F5)'),
            ),
            OutlinedButton.icon(
              onPressed: () => showTxnDialog(context, type: TxnType.expense),
              icon: const Icon(Icons.north_east_rounded, size: 18, color: AppColors.expense),
              label: const Text('هزینه (Ctrl+E)'),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1100;
            final tiles = [
              StatTile(
                label: 'موجودی حساب‌ها',
                value: store.totalBalance,
                icon: Icons.account_balance_wallet_outlined,
                color: th.colorScheme.primary,
                hint: '${store.activeAccounts.length} حساب فعال',
              ),
              StatTile(
                label: 'فروش و درآمد ${now.monthName}',
                value: sales.netSales + mt.income,
                icon: Icons.south_west_rounded,
                color: AppColors.income,
                hint: 'سود ناخالص فروش: ${compactMoney(sales.grossProfit)}',
              ),
              StatTile(
                label: 'هزینه ${now.monthName}',
                value: mt.expense,
                icon: Icons.north_east_rounded,
                color: AppColors.expense,
                hint: delta(mt.expense, prev.expense),
              ),
              StatTile(
                label: 'دارایی خالص',
                value: store.netWorth,
                icon: Icons.insights_rounded,
                color: AppColors.debt,
                hint: 'طلب ${compactMoney(store.totalReceivable)} · بدهی ${compactMoney(store.totalPayable)}',
              ),
            ];

            final chart = Panel(
              title: 'درآمد و هزینه ۶ ماه اخیر',
              child: IncomeExpenseChart(data: months, height: 220),
            );
            final accounts = _AccountsPanel(store: store);
            final recent = Panel(
              title: 'آخرین تراکنش‌ها',
              flush: true,
              trailing: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: TextButton(
                  onPressed: () => Nav.of(context).go(AppPage.transactions),
                  child: const Text('همه تراکنش‌ها'),
                ),
              ),
              child: TxnTable(
                txns: store.txns.take(8).toList(),
                shrinkWrap: true,
                emptyText: 'هنوز تراکنشی ثبت نشده. با Ctrl+N اولین تراکنش را ثبت کنید.',
              ),
            );
            final upcoming = _UpcomingPanel(store: store);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        Expanded(child: tiles[i]),
                      ]
                    ])
                  else
                    Column(children: [
                      Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 16), Expanded(child: tiles[1])]),
                      const SizedBox(height: 16),
                      Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 16), Expanded(child: tiles[3])]),
                    ]),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: chart),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: accounts),
                      ],
                    )
                  else ...[
                    chart,
                    const SizedBox(height: 16),
                    accounts,
                  ],
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: recent),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: upcoming),
                      ],
                    )
                  else ...[
                    recent,
                    const SizedBox(height: 16),
                    upcoming,
                  ],
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  final AppStore store;
  const _AccountsPanel({required this.store});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final list = store.activeAccounts;
    return Panel(
      title: 'حساب‌ها',
      trailing: TextButton(
        onPressed: () => Nav.of(context).go(AppPage.accounts),
        child: const Text('مدیریت'),
      ),
      child: list.isEmpty
          ? const EmptyState(icon: Icons.account_balance_outlined, text: 'حسابی تعریف نشده')
          : Column(
              children: [
                for (final a in list.take(7))
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Nav.of(context).go(AppPage.accounts, accountId: a.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(a.color).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(accountIcon(a.type), size: 18, color: Color(a.color)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(a.bank.isEmpty ? a.type.label : a.bank,
                                    style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                              ],
                            ),
                          ),
                          Money(store.balance(a.id), colorBySign: false, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                if (list.length > 7)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('و ${list.length - 7} حساب دیگر', style: th.textTheme.bodySmall),
                  ),
              ],
            ),
    );
  }
}

class _UpcomingPanel extends StatelessWidget {
  final AppStore store;
  const _UpcomingPanel({required this.store});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final cheques = store.upcomingCheques(days: 30);
    final debts = store.upcomingDue(days: 30);

    String when(DateTime d) {
      final diff = d.difference(today).inDays;
      if (diff < 0) return '${-diff} روز گذشته';
      if (diff == 0) return 'امروز';
      if (diff == 1) return 'فردا';
      return '$diff روز دیگر';
    }

    Color whenColor(DateTime d) {
      final diff = d.difference(today).inDays;
      if (diff < 0) return th.colorScheme.error;
      if (diff <= 3) return AppColors.expense;
      return th.hintColor;
    }

    final items = <Widget>[
      for (final c in cheques)
        _UpRow(
          icon: c.direction == ChequeDirection.received ? Icons.download_rounded : Icons.upload_rounded,
          color: c.direction == ChequeDirection.received ? AppColors.income : AppColors.expense,
          title:
              'چک ${c.direction == ChequeDirection.received ? 'دریافتی' : 'پرداختی'} ${store.person(c.personId)?.name ?? ''}',
          sub: '${jFormat(c.dueDate)} · ${when(c.dueDate)}',
          subColor: whenColor(c.dueDate),
          amount: c.amount,
          onTap: () => showChequeDialog(context, edit: c),
        ),
      for (final t in debts)
        _UpRow(
          icon: t.type == TxnType.lend ? Icons.call_made_rounded : Icons.call_received_rounded,
          color: AppColors.debt,
          title: '${t.type == TxnType.lend ? 'طلب از' : 'بدهی به'} ${store.person(t.personId)?.name ?? ''}',
          sub: '${jFormat(t.dueDate!)} · ${when(t.dueDate!)}',
          subColor: whenColor(t.dueDate!),
          amount: t.amount,
          onTap: () => Nav.of(context).go(AppPage.people, personId: t.personId),
        ),
      for (final l in store.loans)
        if (store.loanNextDue(l) != null && !store.loanNextDue(l)!.isAfter(today.add(const Duration(days: 30))))
          _UpRow(
            icon: Icons.event_repeat_outlined,
            color: AppColors.loan,
            title: 'قسط ${l.title}',
            sub: '${jFormat(store.loanNextDue(l)!)} · ${when(store.loanNextDue(l)!)}',
            subColor: whenColor(store.loanNextDue(l)!),
            amount: l.installmentAmount,
            onTap: () => Nav.of(context).go(AppPage.loans),
          ),
    ];

    return Panel(
      title: 'سررسیدهای ۳۰ روز آینده',
      child: items.isEmpty
          ? const EmptyState(icon: Icons.event_available_outlined, text: 'سررسید نزدیکی ندارید')
          : Column(children: items),
    );
  }
}

class _UpRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final Color subColor;
  final int amount;
  final VoidCallback onTap;

  const _UpRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.subColor,
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 16, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(sub, style: th.textTheme.bodySmall?.copyWith(color: subColor)),
                ],
              ),
            ),
            Money(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
