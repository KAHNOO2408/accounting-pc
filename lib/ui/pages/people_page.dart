import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/simple_dialogs.dart';
import '../dialogs/sms_dialogs.dart';
import '../dialogs/txn_dialog.dart';
import '../theme.dart';
import '../dialogs/ledger_dialogs.dart' show debtorBlue, creditorRed;
import '../widgets/common.dart';
import '../widgets/txn_table.dart';

enum _PFilter { all, receivable, payable, settled }

class PeoplePage extends StatefulWidget {
  final String? initialPersonId;
  const PeoplePage({super.key, this.initialPersonId});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String? _selected;
  String _q = '';
  _PFilter _filter = _PFilter.all;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPersonId;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final balances = {for (final p in store.people) p.id: store.personBalance(p.id)};
    final list = store.peopleSorted.where((p) {
      if (_q.isNotEmpty && !p.name.contains(_q) && !p.phone.contains(_q)) return false;
      final b = balances[p.id] ?? 0;
      return switch (_filter) {
        _PFilter.all => true,
        _PFilter.receivable => b > 0,
        _PFilter.payable => b < 0,
        _PFilter.settled => b == 0,
      };
    }).toList();
    if (_selected != null && store.person(_selected) == null) _selected = null;
    _selected ??= list.isNotEmpty ? list.first.id : null;
    final person = store.person(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'مخاطبین، بدهی و طلب',
          subtitle: 'حساب‌وکتاب با افراد و مشتری‌ها',
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final id = await showPersonDialog(context);
                if (id != null) setState(() => _selected = id);
              },
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('شخص جدید'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'جمع طلب‌ها (دیگران به شما)',
                  value: store.totalReceivable,
                  icon: Icons.call_made_rounded,
                  color: debtorBlue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'جمع بدهی‌ها (شما به دیگران)',
                  value: store.totalPayable,
                  icon: Icons.call_received_rounded,
                  color: creditorRed,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'خالص',
                  value: store.totalReceivable - store.totalPayable,
                  icon: Icons.balance_rounded,
                  color: AppColors.debt,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 330,
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'جستجوی نام یا تلفن',
                              prefixIcon: Icon(Icons.search_rounded, size: 20),
                            ),
                            onChanged: (v) => setState(() => _q = v.trim()),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Wrap(
                            spacing: 6,
                            children: [
                              for (final f in _PFilter.values)
                                ChoiceChip(
                                  label: Text(switch (f) {
                                    _PFilter.all => 'همه',
                                    _PFilter.receivable => 'طلبکارم',
                                    _PFilter.payable => 'بدهکارم',
                                    _PFilter.settled => 'تسویه',
                                  }),
                                  selected: _filter == f,
                                  onSelected: (_) => setState(() => _filter = f),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        Expanded(
                          child: list.isEmpty
                              ? const EmptyState(icon: Icons.people_outline, text: 'کسی پیدا نشد')
                              : ListView.builder(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: list.length,
                                  itemBuilder: (_, i) {
                                    final p = list[i];
                                    final b = balances[p.id] ?? 0;
                                    final sel = p.id == _selected;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: ListTile(
                                        selected: sel,
                                        selectedTileColor: th.colorScheme.primary.withValues(alpha: 0.08),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        leading: CircleAvatar(
                                          radius: 18,
                                          backgroundColor: th.colorScheme.primary.withValues(alpha: 0.12),
                                          child: Text(p.name.isEmpty ? '?' : p.name.characters.first,
                                              style: TextStyle(color: th.colorScheme.primary, fontWeight: FontWeight.w700)),
                                        ),
                                        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        subtitle: Text(
                                          b == 0 ? 'تسویه' : (b > 0 ? 'طلبکار هستید' : 'بدهکار هستید'),
                                          style: th.textTheme.bodySmall?.copyWith(
                                            color: b == 0 ? null : (b > 0 ? debtorBlue : creditorRed),
                                          ),
                                        ),
                                        trailing: Money(b.abs(), style: const TextStyle(fontWeight: FontWeight.w700)),
                                        onTap: () => setState(() => _selected = p.id),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: person == null
                      ? const Card(
                          child: EmptyState(icon: Icons.person_search_outlined, text: 'یک شخص انتخاب کنید یا شخص جدید بسازید'))
                      : _detail(context, store, person),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, AppStore store, Person p) {
    final th = Theme.of(context);
    final related = store.txns.where((t) => t.personId == p.id).toList();
    final running = <String, int>{};
    var bal = 0;
    for (final t in related.reversed) {
      bal += t.type.personSign * t.amount;
      running[t.id] = bal;
    }
    final color = bal == 0 ? th.hintColor : (bal > 0 ? debtorBlue : creditorRed);
    final pendingCheques = store.cheques.where((c) => c.personId == p.id && c.status == ChequeStatus.pending).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Text(p.name.isEmpty ? '?' : p.name.characters.first,
                      style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        [if (p.phone.isNotEmpty) p.phone, if (p.note.isNotEmpty) p.note].join('  ·  '),
                        style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(bal == 0 ? 'حساب تسویه است' : (bal > 0 ? 'از ایشان طلب دارید' : 'به ایشان بدهکارید'),
                        style: th.textTheme.bodySmall?.copyWith(color: color)),
                    Money(bal.abs(), showUnit: true, style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _act(context, 'قرض دادم', Icons.call_made_rounded, () => showTxnDialog(context, type: TxnType.lend, personId: p.id)),
                _act(context, 'قرض گرفتم', Icons.call_received_rounded, () => showTxnDialog(context, type: TxnType.borrow, personId: p.id)),
                _act(context, 'طلب را گرفتم', Icons.download_rounded, () => showTxnDialog(context, type: TxnType.collect, personId: p.id)),
                _act(context, 'بدهی را دادم', Icons.upload_rounded, () => showTxnDialog(context, type: TxnType.repay, personId: p.id)),
                if (p.phone.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => showPersonSms(context, p),
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('ارسال پیامک'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => showPersonDialog(context, edit: p),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('ویرایش'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (store.personInUse(p.id)) {
                      toast(context, 'این شخص تراکنش یا چک ثبت‌شده دارد و قابل حذف نیست', error: true);
                      return;
                    }
                    final ok = await confirm(context, 'حذف شخص', '«${p.name}» حذف شود؟');
                    if (ok) {
                      store.removePerson(p.id);
                      setState(() => _selected = null);
                    }
                  },
                  icon: Icon(Icons.delete_outline, size: 18, color: th.colorScheme.error),
                  label: Text('حذف', style: TextStyle(color: th.colorScheme.error)),
                ),
              ],
            ),
          ),
          if (pendingCheques.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text(
                '${pendingCheques.length} چک در انتظار با این شخص دارید (جمع ${groupDigits(pendingCheques.fold<int>(0, (s, c) => s + c.amount))})',
                style: th.textTheme.bodySmall?.copyWith(color: AppColors.debt),
              ),
            ),
          const Divider(),
          Expanded(
            child: TxnTable(
              txns: related,
              ledgerPersonId: p.id,
              running: running,
              emptyText: 'هنوز گردش حسابی با این شخص ثبت نشده',
            ),
          ),
        ],
      ),
    );
  }

  Widget _act(BuildContext context, String label, IconData icon, VoidCallback onTap) => FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}
