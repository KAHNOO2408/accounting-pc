import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/simple_dialogs.dart';
import '../dialogs/txn_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/txn_table.dart';
import 'transactions_page.dart' show RangePreset, RangePresetX;

class AccountsPage extends StatefulWidget {
  final String? initialAccountId;
  const AccountsPage({super.key, this.initialAccountId});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  String? _selected;
  bool _showArchived = false;
  RangePreset _preset = RangePreset.all;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialAccountId;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final list = store.accounts.where((a) => _showArchived || !a.archived).toList();
    if (_selected == null || store.account(_selected) == null) {
      _selected = list.isNotEmpty ? list.first.id : null;
    }
    final acc = store.account(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'حساب‌ها و بانک',
          subtitle: 'دفتر هر حساب با مانده لحظه‌ای',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final id = await showAccountDialog(context);
                if (id != null) setState(() => _selected = id);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('حساب جدید'),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                          child: Row(
                            children: [
                              Text('جمع موجودی', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                              const Spacer(),
                              Money(store.totalBalance, showUnit: true, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        CheckboxListTile(
                          dense: true,
                          value: _showArchived,
                          onChanged: (v) => setState(() => _showArchived = v ?? false),
                          title: const Text('نمایش حساب‌های بایگانی‌شده'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const Divider(),
                        Expanded(
                          child: list.isEmpty
                              ? const EmptyState(icon: Icons.account_balance_outlined, text: 'حسابی وجود ندارد')
                              : ListView.builder(
                                  padding: const EdgeInsets.all(10),
                                  itemCount: list.length,
                                  itemBuilder: (_, i) => _AccountTile(
                                    account: list[i],
                                    balance: store.balance(list[i].id),
                                    selected: list[i].id == _selected,
                                    onTap: () => setState(() => _selected = list[i].id),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: acc == null
                      ? const Card(child: EmptyState(icon: Icons.touch_app_outlined, text: 'یک حساب انتخاب کنید'))
                      : _ledger(context, store, acc),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ledger(BuildContext context, AppStore store, Account acc) {
    final th = Theme.of(context);
    // running balance, oldest -> newest
    final affecting = store.txns.where((t) => t.accountId == acc.id || t.toAccountId == acc.id).toList();
    final asc = affecting.reversed.toList();
    final running = <String, int>{};
    var bal = acc.opening;
    var inSum = 0, outSum = 0;
    for (final t in asc) {
      final e = t.effectOn(acc.id);
      bal += e;
      running[t.id] = bal;
    }
    final r = _preset.range();
    final shown = affecting.where((t) {
      if (r.$1 != null && t.date.isBefore(r.$1!)) return false;
      if (r.$2 != null && t.date.isAfter(r.$2!)) return false;
      return true;
    }).toList();
    for (final t in shown) {
      final e = t.effectOn(acc.id);
      if (e > 0) inSum += e;
      if (e < 0) outSum += -e;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [Color(acc.color).withValues(alpha: 0.16), Color(acc.color).withValues(alpha: 0.02)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: Color(acc.color), borderRadius: BorderRadius.circular(14)),
                  child: Icon(accountIcon(acc.type), color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(acc.name, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        if (acc.archived) ...[const SizedBox(width: 8), Pill('بایگانی', color: th.hintColor)],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        [acc.type.label, if (acc.bank.isNotEmpty) acc.bank, if (acc.number.isNotEmpty) acc.number].join('  ·  '),
                        style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('مانده فعلی', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                    Money(bal, showUnit: true, colorBySign: bal < 0, style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in RangePreset.values.where((p) => p != RangePreset.custom))
                        ChoiceChip(label: Text(p.label), selected: _preset == p, onSelected: (_) => setState(() => _preset = p)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'واریز / درآمد به این حساب',
                  child: IconButton.filledTonal(
                    onPressed: () => showTxnDialog(context, type: TxnType.income, accountId: acc.id),
                    icon: const Icon(Icons.south_west_rounded, color: AppColors.income),
                  ),
                ),
                Tooltip(
                  message: 'برداشت / هزینه از این حساب',
                  child: IconButton.filledTonal(
                    onPressed: () => showTxnDialog(context, type: TxnType.expense, accountId: acc.id),
                    icon: const Icon(Icons.north_east_rounded, color: AppColors.expense),
                  ),
                ),
                Tooltip(
                  message: 'انتقال از این حساب',
                  child: IconButton.filledTonal(
                    onPressed: () => showTxnDialog(context, type: TxnType.transfer, accountId: acc.id),
                    icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.transfer),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'گزینه‌ها',
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await showAccountDialog(context, edit: acc);
                    } else if (v == 'archive') {
                      acc.archived = !acc.archived;
                      store.upsertAccount(acc);
                    } else if (v == 'delete') {
                      final ok = await confirm(
                        context,
                        'حذف حساب',
                        store.accountInUse(acc.id)
                            ? 'این حساب تراکنش دارد؛ به جای حذف، بایگانی می‌شود. ادامه می‌دهید؟'
                            : 'حساب «${acc.name}» حذف شود؟',
                      );
                      if (ok) {
                        final deleted = store.removeAccount(acc.id);
                        if (context.mounted) toast(context, deleted ? 'حساب حذف شد' : 'حساب بایگانی شد');
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('ویرایش حساب')),
                    PopupMenuItem(value: 'archive', child: Text(acc.archived ? 'خروج از بایگانی' : 'بایگانی')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Wrap(
              spacing: 24,
              children: [
                _kv(context, 'موجودی اول دوره', acc.opening, null),
                _kv(context, 'ورودی بازه', inSum, AppColors.income),
                _kv(context, 'خروجی بازه', outSum, AppColors.expense),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: TxnTable(txns: shown, ledgerAccountId: acc.id, running: running)),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, int v, Color? c) {
    final th = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
        Money(v, style: TextStyle(fontWeight: FontWeight.w600, color: c)),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final Account account;
  final int balance;
  final bool selected;
  final VoidCallback onTap;

  const _AccountTile({required this.account, required this.balance, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final c = Color(account.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? c.withValues(alpha: 0.10) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.withValues(alpha: 0.6) : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(accountIcon(account.type), color: c, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: account.archived ? th.hintColor : null)),
                      Text(account.bank.isEmpty ? account.type.label : account.bank,
                          style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                    ],
                  ),
                ),
                Money(balance, colorBySign: balance < 0, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
