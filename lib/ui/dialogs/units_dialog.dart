import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// «واحدهای شمارش» — Sakan's list of counting units (نام واحد، نام لاتین).
Future<void> showUnitsWindow(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _UnitsWindow());

class _UnitsWindow extends StatefulWidget {
  const _UnitsWindow();

  @override
  State<_UnitsWindow> createState() => _UnitsWindowState();
}

class _UnitsWindowState extends State<_UnitsWindow> {
  String? _sel;

  Future<void> _edit(AppStore s, [CountUnit? u]) async {
    final name = TextEditingController(text: u?.name ?? '');
    final latin = TextEditingController(text: u?.latin ?? '');
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          void ok() {
            final e = s.saveUnit(CountUnit(id: u?.id ?? newId(), name: name.text, latin: latin.text.trim()), oldName: u?.name);
            if (e != null) {
              set(() => err = e);
            } else {
              Navigator.pop(ctx);
            }
          }

          return CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.f9): ok},
            child: FormDialog(
              title: u == null ? 'واحد جدید' : 'ویرایش واحد',
              width: 420,
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
                FilledButton(onPressed: ok, child: const Text('تایید F9')),
              ],
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام واحد'), onSubmitted: (_) => ok()),
                const SizedBox(height: 10),
                TextField(
                  controller: latin,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'نام لاتین', hintText: 'Number'),
                  onSubmitted: (_) => ok(),
                ),
                if (u != null) ...[
                  const SizedBox(height: 8),
                  Text('تغییر نام، در کالاهایی که این واحد را دارند هم اعمال می‌شود.', style: Theme.of(ctx).textTheme.bodySmall),
                ],
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ]),
            ),
          );
        },
      ),
    );
    name.dispose();
    latin.dispose();
  }

  Future<void> _remove(AppStore s) async {
    final u = s.units.where((x) => x.id == _sel).firstOrNull;
    if (u == null) return;
    if (!await confirm(context, 'حذف واحد', 'واحد «${u.name}» حذف شود؟')) return;
    final e = s.removeUnit(u);
    if (!mounted) return;
    if (e != null) {
      toast(context, e, error: true);
    } else {
      setState(() => _sel = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    int uses(CountUnit u) => s.products.where((p) => p.unit == u.name || p.unit2 == u.name || p.unit3 == u.name).length;
    final sel = s.units.where((x) => x.id == _sel).firstOrNull;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _edit(s),
        const SingleActivator(LogicalKeyboardKey.f3): () {
          if (sel != null) _edit(s, sel);
        },
        const SingleActivator(LogicalKeyboardKey.delete): () => _remove(s),
      },
      child: Focus(
        autofocus: true,
        child: SakanWindow(
          title: 'واحدهای شمارش',
          width: 620,
          height: 560,
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                sakanBtn('جدید', () => _edit(s), key: 'F2', icon: Icons.add_rounded),
                const SizedBox(width: 6),
                sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), key: 'F3', icon: Icons.edit_outlined),
                const SizedBox(width: 6),
                sakanBtn('حذف', sel == null ? null : () => _remove(s), key: 'Del', icon: Icons.delete_outline_rounded),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: SakanGrid(
                  header: [
                    sakanHead('ردیف', 50),
                    sakanHead('نام واحد', 0),
                    sakanHead('نام لاتین', 180),
                    sakanHead('تعداد کالا', 90),
                  ],
                  count: s.units.length,
                  row: (ctx, i) {
                    final u = s.units[i];
                    final on = u.id == _sel;
                    final st = TextStyle(color: on ? Colors.white : null);
                    return InkWell(
                      onTap: () => setState(() => _sel = u.id),
                      onDoubleTap: () => _edit(s, u),
                      child: Container(
                        color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                        child: Row(children: [
                          sakanCell(Text('${i + 1}', style: st), 50),
                          sakanCell(Text(u.name, style: st.copyWith(fontWeight: FontWeight.w700)), 0, align: Alignment.centerRight),
                          sakanCell(Text(u.latin, style: st, textDirection: TextDirection.ltr), 180),
                          sakanCell(Text('${uses(u)}', style: st), 90),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text('واحد دوم و سوم هر کالا و نسبتشان در فرم «کالا» تعیین می‌شود.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}
