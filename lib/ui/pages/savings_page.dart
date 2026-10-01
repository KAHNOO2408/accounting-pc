import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/simple_dialogs.dart';
import '../dialogs/txn_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/txn_table.dart';

class SavingsPage extends StatefulWidget {
  const SavingsPage({super.key});

  @override
  State<SavingsPage> createState() => _SavingsPageState();
}

class _SavingsPageState extends State<SavingsPage> {
  String? _selected;

  String? _otherAccount(AppStore store, String exclude) {
    for (final a in store.activeAccounts) {
      if (a.id != exclude && a.type != AccountType.savings) return a.id;
    }
    for (final a in store.activeAccounts) {
      if (a.id != exclude) return a.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final list = store.accounts.where((a) => a.type == AccountType.savings && !a.archived).toList();
    if (_selected == null || !list.any((a) => a.id == _selected)) {
      _selected = list.isEmpty ? null : list.first.id;
    }
    var total = 0;
    var goals = 0;
    for (final a in list) {
      total += store.balance(a.id);
      goals += a.goal;
    }
    final sel = store.account(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'پس‌انداز',
          subtitle: 'صندوق‌های پس‌انداز با هدف و پیشرفت',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final id = await showAccountDialog(context, type: AccountType.savings);
                if (id != null) setState(() => _selected = id);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('صندوق پس‌انداز جدید'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'جمع پس‌انداز',
                  value: total,
                  icon: Icons.savings_outlined,
                  color: AppColors.debt,
                  hint: '${list.length} صندوق',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'جمع هدف‌ها',
                  value: goals,
                  icon: Icons.flag_outlined,
                  color: th.colorScheme.primary,
                  hint: goals == 0 ? null : '${(total * 100 / goals).clamp(0, 100).round()}٪ از کل هدف‌ها',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.savings_outlined,
                  text: 'هنوز صندوق پس‌اندازی نساخته‌اید.\nمثلاً «خرید ماشین» یا «پس‌انداز اضطراری».',
                  action: FilledButton.icon(
                    onPressed: () => showAccountDialog(context, type: AccountType.savings),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('ساخت صندوق'),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 380,
                        child: ListView(
                          children: [
                            for (final a in list) _card(context, store, a),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: sel == null
                            ? const SizedBox()
                            : Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text('گردش «${sel.name}»',
                                                style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                          ),
                                          FilledButton.tonalIcon(
                                            onPressed: () => showTxnDialog(
                                              context,
                                              type: TxnType.transfer,
                                              accountId: _otherAccount(store, sel.id),
                                              toAccountId: sel.id,
                                              title: 'واریز به پس‌انداز',
                                            ),
                                            icon: const Icon(Icons.add_rounded, size: 18),
                                            label: const Text('واریز'),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: () => showTxnDialog(
                                              context,
                                              type: TxnType.transfer,
                                              accountId: sel.id,
                                              toAccountId: _otherAccount(store, sel.id),
                                              title: 'برداشت از پس‌انداز',
                                            ),
                                            icon: const Icon(Icons.remove_rounded, size: 18),
                                            label: const Text('برداشت'),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            tooltip: 'ویرایش صندوق',
                                            onPressed: () => showAccountDialog(context, edit: sel),
                                            icon: const Icon(Icons.edit_outlined),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(),
                                    Expanded(child: _ledger(store, sel)),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _ledger(AppStore store, Account acc) {
    final affecting = store.txns.where((t) => t.accountId == acc.id || t.toAccountId == acc.id).toList();
    final running = <String, int>{};
    var bal = acc.opening;
    for (final t in affecting.reversed) {
      bal += t.effectOn(acc.id);
      running[t.id] = bal;
    }
    return TxnTable(txns: affecting, ledgerAccountId: acc.id, running: running, emptyText: 'هنوز واریزی نداشته‌اید');
  }

  Widget _card(BuildContext context, AppStore store, Account a) {
    final th = Theme.of(context);
    final bal = store.balance(a.id);
    final c = Color(a.color);
    final pct = a.goal > 0 ? (bal / a.goal).clamp(0.0, 1.0).toDouble() : null;
    final sel = a.id == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: sel ? c : th.colorScheme.outlineVariant, width: sel ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = a.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: c.withValues(alpha: 0.15),
                      child: Icon(Icons.savings_outlined, color: c, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    Money(bal, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                if (pct != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      color: c,
                      backgroundColor: c.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('${(pct * 100).round()}٪', style: th.textTheme.labelMedium?.copyWith(color: c)),
                      const Spacer(),
                      Text('هدف: ', style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                      Money(a.goal, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
