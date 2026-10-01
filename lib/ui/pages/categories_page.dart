import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/simple_dialogs.dart';
import '../widgets/common.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'دسته‌بندی‌ها',
          subtitle: 'دسته‌های درآمد و هزینه برای گزارش‌گیری',
          actions: [
            OutlinedButton.icon(
              onPressed: () => showCategoryDialog(context, kind: CategoryKind.income),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('دسته درآمد'),
            ),
            FilledButton.icon(
              onPressed: () => showCategoryDialog(context, kind: CategoryKind.expense),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('دسته هزینه'),
            ),
          ],
        ),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 28, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _CatList(kind: CategoryKind.expense)),
                SizedBox(width: 16),
                Expanded(child: _CatList(kind: CategoryKind.income)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CatList extends StatelessWidget {
  final CategoryKind kind;
  const _CatList({required this.kind});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final cats = store.categoriesOf(kind, includeArchived: true)
      ..sort((a, b) => a.archived == b.archived ? 0 : (a.archived ? 1 : -1));
    final now = Jalali.now();
    final from = now.firstOfMonth.toDateTime();
    final to = now.lastOfMonth.toDateTime();
    final monthMap = {
      for (final e in store.categoryTotals(from, to, kind == CategoryKind.income ? TxnType.income : TxnType.expense))
        e.key: e.value
    };
    final counts = <String, int>{};
    for (final t in store.txns) {
      if (t.categoryId != null) counts[t.categoryId!] = (counts[t.categoryId!] ?? 0) + 1;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Text(kind == CategoryKind.income ? 'دسته‌های درآمد' : 'دسته‌های هزینه',
                    style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('جمع ${now.monthName}', style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: cats.isEmpty
                ? const EmptyState(icon: Icons.category_outlined, text: 'دسته‌ای تعریف نشده')
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: cats.length,
                    itemBuilder: (_, i) {
                      final c = cats[i];
                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        leading: ColorDot(c.color, size: 14),
                        title: Text(c.name,
                            style: TextStyle(
                              color: c.archived ? th.hintColor : null,
                              decoration: c.archived ? TextDecoration.lineThrough : null,
                            )),
                        subtitle: Text('${counts[c.id] ?? 0} تراکنش${c.archived ? ' · بایگانی' : ''}',
                            style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Money(monthMap[c.id] ?? 0, style: const TextStyle(fontWeight: FontWeight.w600)),
                            PopupMenuButton<String>(
                              tooltip: 'گزینه‌ها',
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  showCategoryDialog(context, kind: kind, edit: c);
                                } else if (v == 'archive') {
                                  c.archived = !c.archived;
                                  store.upsertCategory(c);
                                } else if (v == 'delete') {
                                  final used = (counts[c.id] ?? 0) > 0;
                                  final ok = await confirm(
                                    context,
                                    'حذف دسته',
                                    used ? 'این دسته استفاده شده و بایگانی می‌شود. ادامه؟' : '«${c.name}» حذف شود؟',
                                  );
                                  if (ok) store.removeCategory(c.id);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                PopupMenuItem(value: 'archive', child: Text(c.archived ? 'خروج از بایگانی' : 'بایگانی')),
                                const PopupMenuItem(value: 'delete', child: Text('حذف')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => showCategoryDialog(context, kind: kind, edit: c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
