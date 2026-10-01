import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/store.dart';
import '../dialogs/opening_dialog.dart';
import '../dialogs/voucher_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// لیست اسناد — manual accounting vouchers.
class VouchersPage extends StatefulWidget {
  const VouchersPage({super.key});

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_q.trim()).toLowerCase();
    final list = store.vouchersSorted.reversed.where((v) {
      if (q.isEmpty) return true;
      final hay = [
        '${v.number}',
        '${v.fixedNumber}',
        v.desc,
        jFormat(v.date),
        ...v.lines.map((l) => '${l.desc} ${store.tafsiliName(l)}'),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
    final od = store.settings.openingDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'لیست اسناد',
          subtitle: 'اسناد حسابداری دستی و سند افتتاحیه',
          actions: [
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(hintText: 'شماره، شرح، تفصیلی…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
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
                        SizedBox(width: 90, child: Text('شماره سند')),
                        SizedBox(width: 90, child: Text('شماره ثابت')),
                        SizedBox(width: 110, child: Text('تاریخ')),
                        Expanded(child: Text('شرح سند')),
                        SizedBox(width: 70, child: Text('ردیف‌ها', textAlign: TextAlign.center)),
                        SizedBox(width: 150, child: Text('جمع بدهکار', textAlign: TextAlign.left)),
                        SizedBox(width: 150, child: Text('جمع بستانکار', textAlign: TextAlign.left)),
                      ]),
                    ),
                  ),
                  if (od != null)
                    InkWell(
                      onTap: () => openOpeningVoucher(context),
                      child: Container(
                        color: AppColors.loan.withValues(alpha: 0.06),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(children: [
                          const SizedBox(width: 90, child: Text('افتتاحیه', style: TextStyle(fontWeight: FontWeight.w700))),
                          const SizedBox(width: 90, child: Text('—')),
                          SizedBox(width: 110, child: Text(jFormat(od))),
                          const Expanded(child: Text('سند افتتاحیه')),
                        ]),
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(icon: Icons.list_alt_rounded, text: 'سند حسابداری دستی ثبت نشده')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final v = list[i];
                              return InkWell(
                                onTap: () => showVoucherDialog(context, edit: v),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                  child: Row(children: [
                                    SizedBox(width: 90, child: Text('${v.number}', style: const TextStyle(fontWeight: FontWeight.w700))),
                                    SizedBox(width: 90, child: Text('${v.fixedNumber}')),
                                    SizedBox(width: 110, child: Text(jFormat(v.date))),
                                    Expanded(
                                      child: Text(
                                        v.desc.isEmpty ? (v.lines.isEmpty ? '' : v.lines.first.desc) : v.desc,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 70, child: Text('${v.lines.length}', textAlign: TextAlign.center)),
                                    SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Money(v.totalDebit))),
                                    SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: Money(v.totalCredit))),
                                  ]),
                                ),
                              );
                            },
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
