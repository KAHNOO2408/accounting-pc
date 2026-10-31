import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// A checklist window («تعیین سطح دسترسی …»): returns the ticked ids, or an
/// empty set when «همه» is on (= no restriction).
Future<Set<String>?> showAccessChecklist(BuildContext context, {required String title, required List<(String, String)> items, required Set<String> selected}) =>
    showDialog<Set<String>>(context: context, builder: (_) => _Checklist(title: title, items: items, selected: selected));

class _Checklist extends StatefulWidget {
  final String title;
  final List<(String, String)> items;
  final Set<String> selected;
  const _Checklist({required this.title, required this.items, required this.selected});
  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  late final Set<String> _sel = {...widget.selected};
  late bool _all = widget.selected.isEmpty;

  @override
  Widget build(BuildContext context) => SakanWindow(
        title: widget.title,
        width: 520,
        height: 560,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            CheckboxListTile(
              dense: true,
              value: _all,
              title: const Text('دسترسی به همه (بدون محدودیت)'),
              onChanged: (v) => setState(() => _all = v ?? false),
            ),
            const Divider(height: 1),
            Expanded(
              child: Container(
                color: Colors.white,
                child: ListView(children: [
                  for (final (id, name) in widget.items)
                    CheckboxListTile(
                      dense: true,
                      enabled: !_all,
                      value: _all || _sel.contains(id),
                      title: Text(name),
                      onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id)),
                    ),
                  if (widget.items.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('موردی تعریف نشده'))),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  if (!_all && _sel.isEmpty) return toast(context, 'حداقل یک مورد را انتخاب کنید', error: true);
                  Navigator.pop(context, _all ? <String>{} : _sel);
                },
                child: const Text('تایید F9'),
              ),
            ]),
          ]),
        ),
      );
}

/// «دسترسی شعب» / «دسترسی انبار ها» / «دسترسی حسابها» of [user].
Future<void> showUserAccess(BuildContext context, AppUser user, String what) async {
  final s = StoreScope.read(context);
  switch (what) {
    case 'branches':
      final r = await showAccessChecklist(context,
          title: 'تعیین سطح دسترسی شعب — ${user.name}', items: [for (final b in s.branches) (b.id, '${b.code} - ${b.name}')], selected: user.branches);
      if (r != null) s.setUserAccess(user.id, branches: r);
    case 'warehouses':
      final r = await showAccessChecklist(context,
          title: 'تعیین سطح دسترسی انبار — ${user.name}', items: [for (final w in s.warehouses) (w.id, '${w.code} - ${w.name}')], selected: user.warehouses);
      if (r != null) s.setUserAccess(user.id, warehouses: r);
    case 'accounts':
      final r = await showAccessChecklist(context,
          title: 'دسترسی حسابها (صندوق و بانک) — ${user.name}', items: [for (final a in s.accounts) (a.id, a.name)], selected: user.accounts);
      if (r != null) s.setUserAccess(user.id, accounts: r);
  }
}

/// «انتخاب شعبه»: the branch this session works in, or «بدون شعبه».
Future<void> showSelectBranch(BuildContext context) async {
  final s = StoreScope.read(context);
  final list = s.myBranches;
  String? sel = s.currentBranchId;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('انتخاب شعبه'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (list.isEmpty) const Text('شعبه ای تعریف نشده یا به هیچ شعبه ای دسترسی ندارید'),
            for (final b in list)
              RadioListTile<String?>(dense: true, value: b.id, groupValue: sel, title: Text(b.name), subtitle: Text('${b.warehouseIds.length} انبار'), onChanged: (v) => set(() => sel = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          OutlinedButton(
            onPressed: () {
              sel = null;
              Navigator.pop(ctx, true);
            },
            child: const Text('بدون شعبه'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
      ),
    ),
  );
  if (ok == true) {
    if (sel == null && !s.currentUser.admin && s.currentUser.branches.isNotEmpty && s.branches.isNotEmpty) {
      if (context.mounted) toast(context, 'کار بدون شعبه برای شما مجاز نیست', error: true);
      return;
    }
    s.selectBranch(sel);
    if (context.mounted) toast(context, sel == null ? 'بدون شعبه' : 'شعبه فعال: ${s.currentBranch!.name}');
  }
}

/// «معرفی شعب»: branches with their warehouses.
Future<void> showBranches(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Branches());

class _Branches extends StatefulWidget {
  const _Branches();
  @override
  State<_Branches> createState() => _BranchesState();
}

class _BranchesState extends State<_Branches> {
  String? _sel;

  Future<void> _edit(AppStore s, [Branch? b]) async {
    final name = TextEditingController(text: b?.name ?? '');
    final note = TextEditingController(text: b?.note ?? '');
    final whs = {...?b?.warehouseIds};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(b == null ? 'شعبه جدید' : 'ویرایش شعبه'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام شعبه')),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظات')),
              const SizedBox(height: 10),
              const Text('انبارهای شعبه:', style: TextStyle(fontWeight: FontWeight.w700)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(shrinkWrap: true, children: [
                  for (final w in s.warehouses)
                    CheckboxListTile(dense: true, value: whs.contains(w.id), title: Text(w.name), onChanged: (v) => set(() => v == true ? whs.add(w.id) : whs.remove(w.id))),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final x = b ?? Branch(id: newId(), code: s.nextBranchCode(), name: '');
    x
      ..name = name.text
      ..note = note.text
      ..warehouseIds = whs;
    final err = s.saveBranch(x);
    if (err != null) return toast(context, err, error: true);
    setState(() => _sel = x.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final sel = s.branch(_sel);
    return SakanWindow(
      title: 'معرفی شعب',
      width: 760,
      height: 520,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            sakanBtn('شعبه جدید', () => _edit(s), icon: Icons.add_business_outlined),
            sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (await confirm(context, 'حذف شعبه', 'شعبه «${sel.name}» حذف شود؟')) {
                      s.removeBranch(sel.id);
                      setState(() => _sel = null);
                    }
                  }, icon: Icons.delete_outline),
            sakanBtn('انتخاب شعبه', () => showSelectBranch(context), icon: Icons.storefront_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 60), sakanHead('نام شعبه', 200), sakanHead('انبارها', 0), sakanHead('فعال', 60)],
              count: s.branches.length,
              empty: 'شعبه ای تعریف نشده',
              row: (_, i) {
                final b = s.branches[i];
                return Material(
                  color: b.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() => _sel = b.id),
                    onDoubleTap: () => _edit(s, b),
                    child: Row(children: [
                      sakanCell(Text('${b.code}'), 60),
                      sakanCell(Text(b.name), 200),
                      sakanCell(Text(b.warehouseIds.isEmpty ? 'همه انبارها' : [for (final id in b.warehouseIds) s.warehouse(id)?.name ?? ''].join('، '), overflow: TextOverflow.ellipsis), 0),
                      sakanCell(b.id == s.currentBranchId ? const Icon(Icons.check_rounded, color: Colors.green, size: 18) : const SizedBox(), 60),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
