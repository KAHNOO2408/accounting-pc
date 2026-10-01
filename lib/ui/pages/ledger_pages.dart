import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';

// ============================================================ balance sheet

class BalanceSheetPage extends StatelessWidget {
  const BalanceSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);

    final assets = <(String, int)>[];
    final liabilities = <(String, int)>[];
    for (final a in store.accounts) {
      final b = store.balance(a.id);
      if (b > 0) assets.add((a.name, b));
      if (b < 0) liabilities.add(('${a.name} (منفی)', -b));
    }
    assets
      ..add(('حساب‌های دریافتنی (طلب از اشخاص)', store.totalReceivable))
      ..add(('اسناد دریافتنی (چک‌های در جریان)', store.pendingChequesIn))
      ..add(('موجودی کالا (به قیمت تمام‌شده)', store.stockValue()));
    for (final m in allMoeens.where((m) => !m.hasEntity)) {
      if (m.side != Side.asset && m.side != Side.liability) continue;
      final v = store.ledgerBalance(m.code);
      if (v == 0) continue;
      (m.side == Side.asset ? assets : liabilities).add((m.name, v));
    }
    liabilities
      ..add(('حساب‌های پرداختنی (بدهی به اشخاص)', store.totalPayable))
      ..add(('اسناد پرداختنی (چک‌های صادره)', store.pendingChequesOut))
      ..add(('مانده وام‌ها', store.totalLoanRemaining));
    final tA = assets.fold<int>(0, (s, e) => s + e.$2);
    final tL = liabilities.fold<int>(0, (s, e) => s + e.$2);

    Widget side(String title, List<(String, int)> rows, int total, Color color) => Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: color.withValues(alpha: 0.08),
                padding: const EdgeInsets.all(16),
                child: Text(title, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ),
              for (final r in rows.where((r) => r.$2 != 0))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant))),
                  child: Row(children: [
                    Expanded(child: Text(r.$1)),
                    Money(r.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: Text('جمع', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  Money(total, showUnit: true, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
                ]),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: 'ترازنامه', subtitle: 'وضعیت دارایی‌ها و بدهی‌ها در ${Jalali.now().formatLong()}'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: side('دارایی‌ها', assets, tA, AppColors.income)),
                    const SizedBox(width: 16),
                    Expanded(child: side('بدهی‌ها', liabilities, tL, AppColors.expense)),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      Icon(Icons.balance_rounded, color: th.colorScheme.primary, size: 32),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('سرمایه (حقوق صاحب کسب‌وکار)', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text('دارایی‌ها منهای بدهی‌ها', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                        ]),
                      ),
                      Money(tA - tL,
                          showUnit: true,
                          colorBySign: true,
                          style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ======================================================= accounts table (Ctrl+A)

enum _Tab { people, money, products }

class AccountsTablePage extends StatefulWidget {
  const AccountsTablePage({super.key});

  @override
  State<AccountsTablePage> createState() => _AccountsTablePageState();
}

class _AccountsTablePageState extends State<AccountsTablePage> {
  _Tab _tab = _Tab.people;
  String _q = '';
  bool _nonZero = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();

    // (name, sub, debit/they owe, credit/I owe, onTap)
    final rows = <(String, String, int, int, VoidCallback)>[];
    switch (_tab) {
      case _Tab.people:
        for (final p in store.peopleSorted) {
          final b = store.personBalance(p.id);
          rows.add((p.name, p.phone, b > 0 ? b : 0, b < 0 ? -b : 0, () => Nav.of(context).go(AppPage.people, personId: p.id)));
        }
      case _Tab.money:
        for (final a in store.accounts) {
          final b = store.balance(a.id);
          rows.add((a.name, a.type.label, b > 0 ? b : 0, b < 0 ? -b : 0,
              () => Nav.of(context).go(AppPage.accounts, accountId: a.id)));
        }
      case _Tab.products:
        for (final p in store.productsSorted) {
          final v = (store.stock(p.id) * store.avgCost(p.id)).round();
          rows.add((p.name, p.code, v > 0 ? v : 0, v < 0 ? -v : 0, () => Nav.of(context).go(AppPage.products)));
        }
    }
    final shown = rows
        .where((r) =>
            (q.isEmpty || r.$1.toLowerCase().contains(q) || r.$2.toLowerCase().contains(q)) &&
            (!_nonZero || r.$3 != 0 || r.$4 != 0))
        .toList();
    final tD = shown.fold<int>(0, (s, r) => s + r.$3);
    final tC = shown.fold<int>(0, (s, r) => s + r.$4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'جدول و مشاهده حساب‌ها', subtitle: 'مانده همه حساب‌ها در یک نگاه؛ روی هر ردیف بزنید تا گردشش باز شود'),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Row(
            children: [
              SegmentedButton<_Tab>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Tab.people, label: Text('اشخاص'), icon: Icon(Icons.people_alt_outlined, size: 16)),
                  ButtonSegment(value: _Tab.money, label: Text('صندوق و بانک'), icon: Icon(Icons.account_balance_outlined, size: 16)),
                  ButtonSegment(value: _Tab.products, label: Text('کالاها'), icon: Icon(Icons.inventory_2_outlined, size: 16)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(width: 12),
              FilterChip(label: const Text('فقط دارای مانده'), selected: _nonZero, onSelected: (v) => setState(() => _nonZero = v)),
              const Spacer(),
              SizedBox(
                width: 280,
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'جستجو…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            ],
          ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: DefaultTextStyle(
                      style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
                      child: Row(children: [
                        const SizedBox(width: 50, child: Text('ردیف')),
                        const Expanded(child: Text('نام حساب')),
                        SizedBox(width: 160, child: Text(_tab == _Tab.products ? 'ارزش موجودی' : 'بدهکار', textAlign: TextAlign.left)),
                        if (_tab != _Tab.products) const SizedBox(width: 160, child: Text('بستانکار', textAlign: TextAlign.left)),
                        const SizedBox(width: 110, child: Text('تشخیص', textAlign: TextAlign.center)),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? const EmptyState(icon: Icons.table_rows_outlined, text: 'موردی نیست')
                        : ListView.separated(
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final r = shown[i];
                              final status = r.$3 > 0 ? 'بدهکار' : (r.$4 > 0 ? 'بستانکار' : 'تسویه');
                              final c = r.$3 > 0 ? AppColors.income : (r.$4 > 0 ? AppColors.expense : th.hintColor);
                              return InkWell(
                                onTap: r.$5,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  child: Row(children: [
                                    SizedBox(width: 50, child: Text('${i + 1}', style: TextStyle(color: th.hintColor))),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        if (r.$2.isNotEmpty)
                                          Text(r.$2, style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                                      ]),
                                    ),
                                    SizedBox(width: 160, child: Align(alignment: Alignment.centerLeft, child: Money(r.$3))),
                                    if (_tab != _Tab.products)
                                      SizedBox(width: 160, child: Align(alignment: Alignment.centerLeft, child: Money(r.$4))),
                                    SizedBox(
                                      width: 110,
                                      child: Center(
                                        child: _tab == _Tab.products ? const SizedBox() : Pill(status, color: c),
                                      ),
                                    ),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    color: th.colorScheme.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(children: [
                      const SizedBox(width: 50),
                      Expanded(child: Text('جمع (${shown.length} حساب)', style: const TextStyle(fontWeight: FontWeight.w700))),
                      SizedBox(width: 160, child: Align(alignment: Alignment.centerLeft, child: Money(tD, style: const TextStyle(fontWeight: FontWeight.w800)))),
                      if (_tab != _Tab.products)
                        SizedBox(width: 160, child: Align(alignment: Alignment.centerLeft, child: Money(tC, style: const TextStyle(fontWeight: FontWeight.w800)))),
                      const SizedBox(width: 110),
                    ]),
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
