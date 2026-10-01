import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../dialogs/cheque_dialogs.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ChequesPage extends StatefulWidget {
  final ChequeDirection initialDirection;
  final ChequeStatus? initialStatus;
  const ChequesPage({super.key, this.initialDirection = ChequeDirection.received, this.initialStatus = ChequeStatus.pending});

  @override
  State<ChequesPage> createState() => _ChequesPageState();
}

class _ChequesPageState extends State<ChequesPage> {
  late ChequeDirection _dir = widget.initialDirection;
  late ChequeStatus? _status = widget.initialStatus;

  Color _statusColor(ChequeStatus s, ThemeData th) => switch (s) {
        ChequeStatus.pending => AppColors.transfer,
        ChequeStatus.deposited => AppColors.discount,
        ChequeStatus.cleared => AppColors.income,
        ChequeStatus.bounced => th.colorScheme.error,
        ChequeStatus.endorsed => AppColors.debt,
        ChequeStatus.cancelled => th.hintColor,
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final list = store.cheques.where((c) => c.direction == _dir && (_status == null || c.status == _status)).toList()
      ..sort((a, b) => _status == ChequeStatus.pending ? a.dueDate.compareTo(b.dueDate) : b.dueDate.compareTo(a.dueDate));
    final total = list.fold<int>(0, (s, c) => s + c.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'چک‌ها',
          subtitle: 'پیگیری چک‌های دریافتی و پرداختی',
          actions: [
            FilledButton.icon(
              onPressed: () => showChequeDialog(context, direction: _dir),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('ثبت چک'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'چک‌های دریافتی در انتظار',
                  value: store.pendingChequesIn,
                  icon: Icons.download_rounded,
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatTile(
                  label: 'چک‌های پرداختی در انتظار',
                  value: store.pendingChequesOut,
                  icon: Icons.upload_rounded,
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Row(
            children: [
              SegmentedButton<ChequeDirection>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ChequeDirection.received, label: Text('دریافتی')),
                  ButtonSegment(value: ChequeDirection.issued, label: Text('پرداختی')),
                ],
                selected: {_dir},
                onSelectionChanged: (s) => setState(() => _dir = s.first),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(label: const Text('همه'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                    for (final s in ChequeStatus.values)
                      ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                  ],
                ),
              ),
              Text('${list.length} چک · جمع ', style: th.textTheme.bodySmall),
              Money(total, showUnit: true, style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: th.colorScheme.surfaceContainerLow,
                    child: DefaultTextStyle(
                      style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w600),
                      child: const Row(
                        children: [
                          SizedBox(width: 160, child: Text('سررسید')),
                          Expanded(flex: 2, child: Text('طرف حساب')),
                          Expanded(flex: 2, child: Text('بانک / شماره')),
                          SizedBox(width: 110, child: Text('وضعیت')),
                          SizedBox(width: 150, child: Text('مبلغ', textAlign: TextAlign.left)),
                          SizedBox(width: 220),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(icon: Icons.request_page_outlined, text: 'چکی در این بخش نیست')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, i) {
                              final c = list[i];
                              final days = c.dueDate.difference(today).inDays;
                              final overdue = c.status == ChequeStatus.pending && days < 0;
                              final soon = c.status == ChequeStatus.pending && days >= 0 && days <= 3;
                              return InkWell(
                                onTap: () => showChequeDialog(context, edit: c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 160,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(jFormat(c.dueDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                                            if (c.status == ChequeStatus.pending)
                                              Text(
                                                overdue ? '${-days} روز گذشته' : (days == 0 ? 'امروز' : '$days روز مانده'),
                                                style: th.textTheme.bodySmall?.copyWith(
                                                  color: overdue ? th.colorScheme.error : (soon ? AppColors.expense : th.hintColor),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(store.person(c.personId)?.name ?? '—', overflow: TextOverflow.ellipsis),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          [if (c.bank.isNotEmpty) c.bank, if (c.serial.isNotEmpty) c.serial].join(' · '),
                                          overflow: TextOverflow.ellipsis,
                                          style: th.textTheme.bodySmall,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 110,
                                        child: Align(
                                          alignment: AlignmentDirectional.centerStart,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Pill(c.status.label, color: _statusColor(c.status, th)),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 150,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Money(c.amount, style: const TextStyle(fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 220,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            if (c.status == ChequeStatus.pending ||
                                                c.status == ChequeStatus.deposited ||
                                                c.status == ChequeStatus.bounced)
                                              TextButton.icon(
                                                onPressed: () => showClearChequeDialog(context, c),
                                                icon: const Icon(Icons.check_circle_outline, size: 18, color: AppColors.income),
                                                label: Text(c.direction == ChequeDirection.issued
                                                    ? 'پاس شد'
                                                    : (c.status == ChequeStatus.deposited ? 'وصول نزد بانک' : 'وصول نقدی')),
                                              ),
                                            PopupMenuButton<String>(
                                              tooltip: 'گزینه‌ها',
                                              onSelected: (v) async {
                                                switch (v) {
                                                  case 'bounce':
                                                    store.setChequeStatus(c, ChequeStatus.bounced);
                                                  case 'cancel':
                                                    store.setChequeStatus(c, ChequeStatus.cancelled);
                                                  case 'pending':
                                                    store.setChequeStatus(c, ChequeStatus.pending);
                                                  case 'deposit':
                                                    showDepositChequeDialog(context, c);
                                                  case 'endorse':
                                                    showEndorseChequeDialog(context, c);
                                                  case 'edit':
                                                    showChequeDialog(context, edit: c);
                                                  case 'delete':
                                                    final ok = await confirm(
                                                      context,
                                                      'حذف چک',
                                                      c.txnId != null
                                                          ? 'تراکنش ثبت‌شده برای پاس شدن این چک هم حذف می‌شود. ادامه می‌دهید؟'
                                                          : 'این چک حذف شود؟',
                                                    );
                                                    if (ok) store.removeCheque(c.id);
                                                }
                                              },
                                              itemBuilder: (_) {
                                                final rec = c.direction == ChequeDirection.received;
                                                final st = c.status;
                                                return [
                                                  const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                                  if (rec && st == ChequeStatus.pending) ...[
                                                    const PopupMenuItem(value: 'deposit', child: Text('به حساب گذاشتن (نزد بانک)')),
                                                    const PopupMenuItem(value: 'endorse', child: Text('واگذاری چک')),
                                                  ],
                                                  if (st == ChequeStatus.pending || st == ChequeStatus.deposited)
                                                    PopupMenuItem(
                                                      value: 'bounce',
                                                      child: Text(st == ChequeStatus.deposited ? 'عدم وصول چک نزد بانک' : 'برگشت خورد (عدم وصول)'),
                                                    ),
                                                  if (st == ChequeStatus.pending || st == ChequeStatus.bounced)
                                                    PopupMenuItem(
                                                      value: 'cancel',
                                                      child: Text(rec ? 'پس دادن چک وارده' : 'پس گرفتن چک صادره'),
                                                    ),
                                                  if (st == ChequeStatus.endorsed)
                                                    const PopupMenuItem(value: 'pending', child: Text('پس گرفتن چک واگذار شده')),
                                                  if (st != ChequeStatus.pending && st != ChequeStatus.endorsed)
                                                    const PopupMenuItem(value: 'pending', child: Text('برگرداندن به «در انتظار»')),
                                                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                                ];
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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
