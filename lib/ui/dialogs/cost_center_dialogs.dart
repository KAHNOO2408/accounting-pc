import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// «مدیریت مراکز رکورد (هزینه)» with groups and reports.
Future<void> showCostCenters(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Centers());

class _Centers extends StatefulWidget {
  const _Centers();

  @override
  State<_Centers> createState() => _CentersState();
}

class _CentersState extends State<_Centers> {
  String? _sel;
  DateTime? _from, _to;

  Future<void> _edit(AppStore s, [CostCenter? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final note = TextEditingController(text: c?.note ?? '');
    String? group = c?.groupId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: c == null ? 'تعریف مرکز رکورد (هزینه)' : 'ویرایش مرکز ${c.code}',
          width: 420,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بازگشت F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید F9')),
          ],
          child: Column(children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام مرکز')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: group,
              decoration: const InputDecoration(labelText: 'گروه'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('—')), for (final g in s.costCenterGroups) DropdownMenuItem<String?>(value: g.id, child: Text(g.name))],
              onChanged: (v) => set(() => group = v),
            ),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
          ]),
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final x = c ?? CostCenter(id: newId(), code: s.nextCostCenterCode(), name: '');
      x
        ..name = name.text.trim()
        ..groupId = group
        ..note = note.text.trim();
      if (c == null) s.costCenters.add(x);
      s.updateSettings((_) {});
      setState(() => _sel = x.id);
    }
    name.dispose();
    note.dispose();
  }

  Future<void> _groups(AppStore s) async {
    final c = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'تعریف گروه مرکز هزینه (رکورد)',
          width: 420,
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(controller: c, decoration: const InputDecoration(labelText: 'نام گروه', isDense: true))),
              IconButton(
                onPressed: () {
                  if (c.text.trim().isEmpty) return;
                  s.costCenterGroups.add(CostCenterGroup(id: newId(), name: c.text.trim()));
                  s.updateSettings((_) {});
                  c.clear();
                  set(() {});
                },
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
            for (final g in s.costCenterGroups)
              ListTile(
                dense: true,
                title: Text(g.name),
                subtitle: Text('${s.costCenters.where((x) => x.groupId == g.id).length} مرکز'),
                trailing: IconButton(
                  onPressed: () => set(() {
                    s.costCenterGroups.remove(g);
                    for (final x in s.costCenters.where((x) => x.groupId == g.id)) {
                      x.groupId = null;
                    }
                    s.updateSettings((_) {});
                  }),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
          ]),
        ),
      ),
    );
    c.dispose();
    if (mounted) setState(() {});
  }

  void _print(AppStore s, {bool byGroup = false}) {
    final rows = s.costCenterRows(from: _from, to: _to);
    final sums = <String, (int, int)>{};
    for (final r in rows) {
      final c = s.costCenters.where((x) => x.id == r.$1).firstOrNull;
      final k = byGroup ? (s.costCenterGroups.where((g) => g.id == c?.groupId).firstOrNull?.name ?? 'بدون گروه') : (c == null ? '؟' : '${c.code}  ${c.name}');
      final o = sums[k] ?? (0, 0);
      sums[k] = (o.$1 + r.$4, o.$2 + r.$5);
    }
    printTable(
      store: s,
      title: byGroup ? 'تهیه گزارش از گروه مراکز رکورد (هزینه)' : 'گزارش از مراکز رکورد (هزینه)',
      subtitle: '${_from == null ? '' : 'از ${jFormat(_from!)} '}${_to == null ? '' : 'تا ${jFormat(_to!)}'}',
      headers: const ['مرکز', 'هزینه (بدهکار)', 'درآمد (بستانکار)', 'خالص'],
      rows: [for (final e in sums.entries) [e.key, groupDigits(e.value.$1), groupDigits(e.value.$2), groupDigits(e.value.$2 - e.value.$1)]],
      numeric: const {1, 2, 3},
      footer: [
        'جمع',
        groupDigits(sums.values.fold(0, (a, v) => a + v.$1)),
        groupDigits(sums.values.fold(0, (a, v) => a + v.$2)),
        groupDigits(sums.values.fold(0, (a, v) => a + v.$2 - v.$1)),
      ],
      fileName: 'markaz-hazine',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = s.costCenterRows(from: _from, to: _to);
    final sel = s.costCenters.where((c) => c.id == _sel).firstOrNull;
    final mine = rows.where((r) => r.$1 == _sel).toList();
    int dr(String id) => rows.where((r) => r.$1 == id).fold(0, (a, r) => a + r.$4);
    int cr(String id) => rows.where((r) => r.$1 == id).fold(0, (a, r) => a + r.$5);
    return SakanWindow(
      title: 'مدیریت مراکز رکورد (هزینه)',
      width: 1150,
      height: 660,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('تعریف مرکز', () => _edit(s), icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            sakanBtn('حذف', sel == null || rows.any((r) => r.$1 == sel.id)
                ? null
                : () {
                    s.costCenters.remove(sel);
                    s.updateSettings((_) {});
                    setState(() => _sel = null);
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('گروه مراکز', () => _groups(s), icon: Icons.hub_outlined),
            sakanBtn('گزارش مراکز', () => _print(s), icon: Icons.print_outlined),
            sakanBtn('گزارش گروه مراکز', () => _print(s, byGroup: true), icon: Icons.account_tree_outlined),
            SizedBox(width: 160, child: DateField(label: 'از تاریخ', value: _from, clearable: true, onChanged: (d) => setState(() => _from = d))),
            SizedBox(width: 160, child: DateField(label: 'تا تاریخ', value: _to, clearable: true, onChanged: (d) => setState(() => _to = d))),
          ]),
          const SizedBox(height: 6),
          const Text('هزینه‌ها و درآمدها را در «ثبت هزینه/درآمد» یا ردیف سند دستی به مرکز نسبت دهید.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 470,
                child: SakanGrid(
                  header: [sakanHead('کد', 60), sakanHead('نام مرکز', 0), sakanHead('گروه', 110), sakanHead('هزینه', 110)],
                  count: s.costCenters.length,
                  empty: 'مرکزی تعریف نشده',
                  row: (ctx, i) {
                    final c = s.costCenters[i];
                    final on = c.id == _sel;
                    final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                    return InkWell(
                      onTap: () => setState(() => _sel = c.id),
                      onDoubleTap: () => _edit(s, c),
                      child: Container(
                        color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                        child: Row(children: [
                          sakanCell(Text('${c.code}', style: st), 60),
                          sakanCell(Text(c.name, style: st), 0, align: Alignment.centerRight),
                          sakanCell(Text(s.costCenterGroups.where((g) => g.id == c.groupId).firstOrNull?.name ?? '', style: st), 110),
                          sakanCell(Text(groupDigits(dr(c.id) - cr(c.id)), style: st), 110),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SakanGrid(
                  header: [sakanHead('تاریخ', 95), sakanHead('شرح', 0), sakanHead('بدهکار', 120), sakanHead('بستانکار', 120)],
                  count: mine.length,
                  empty: sel == null ? 'یک مرکز انتخاب کنید' : 'گردشی ندارد',
                  row: (ctx, i) {
                    final r = mine[i];
                    return Container(
                      color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                      child: Row(children: [
                        sakanCell(Text(jFormat(r.$2)), 95),
                        sakanCell(Text(r.$3, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                        sakanCell(Text(groupDigits(r.$4)), 120),
                        sakanCell(Text(groupDigits(r.$5)), 120),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
