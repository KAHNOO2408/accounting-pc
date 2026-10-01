import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart';
import '../theme.dart';
import '../widgets/common.dart';

// ================================================================ سند اختتامیه

Future<void> showClosingDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ClosingDialog());

class _ClosingDialog extends StatefulWidget {
  const _ClosingDialog();

  @override
  State<_ClosingDialog> createState() => _ClosingDialogState();
}

class _ClosingDialogState extends State<_ClosingDialog> {
  late final TextEditingController _number;
  final _desc = TextEditingController();
  late DateTime _date;
  bool _skipChecks = false;
  List<String> _issues = [];

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    _number = TextEditingController(text: '${s.nextVoucherNumber()}');
    final n = DateTime.now();
    _date = DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _number.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _details() => showDialog<void>(
        context: context,
        builder: (ctx) => FormDialog(
          title: 'مشخصات سند',
          width: 460,
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تایید'))],
          child: TextField(controller: _desc, autofocus: true, maxLines: 3, decoration: const InputDecoration(labelText: 'شرح سند')),
        ),
      );

  void _save() {
    final s = StoreScope.read(context);
    if (!_skipChecks) {
      final issues = closingIssues(s, _date);
      if (issues.isNotEmpty) {
        setState(() => _issues = issues);
        return;
      }
    }
    final lines = closingLines(s, _date);
    if (lines.isEmpty) {
      setState(() => _issues = ['هیچ حسابی مانده ندارد']);
      return;
    }
    final v = Voucher(
      id: newId(),
      number: int.tryParse(normalizeDigits(_number.text.trim())) ?? s.nextVoucherNumber(),
      fixedNumber: s.nextFixedNumber(),
      date: _date,
      desc: _desc.text.trim().isEmpty ? 'سند اختتامیه ${jFormat(_date)}' : _desc.text.trim(),
      lines: lines,
      kind: 'closing',
    );
    s.saveVoucher(v);
    Navigator.pop(context);
    toast(context, 'سند اختتامیه شماره ${v.number} با ${lines.length} ردیف ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final preview = closingLines(s, _date);
    final total = preview.fold<int>(0, (a, l) => a + l.debit);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): _details,
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'تراز اختتامیه - حسابهای ترازنامه ای',
        width: 640,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              FilledButton.tonalIcon(
                onPressed: _details,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('مشخصات سند (F1)'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DateField(
                  label: 'تاریخ سند',
                  value: _date,
                  onChanged: (d) => setState(() {
                    _date = d ?? _date;
                    _issues = [];
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _skipChecks,
              onChanged: (v) => setState(() => _skipChecks = v ?? false),
              title: Text('عدم انجام بررسی های لازم برای ثبت تراز اختتامیه', style: TextStyle(color: th.colorScheme.error)),
            ),
            const SizedBox(height: 6),
            const InputDecorator(
              decoration: InputDecoration(labelText: 'عنوان حساب'),
              child: Text('تراز اختتامیه'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Brand.of(context).accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('${preview.length} حساب دارای مانده تا تاریخ ${jFormat(_date)} بسته می‌شود — جمع گردش ')),
                Money(total, style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
            if (_issues.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final i in _issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: th.colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(child: Text(i, style: TextStyle(color: th.colorScheme.error))),
                  ]),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              'دقت نمایید که مابین سند خلاصه حساب سود و زیان و سند اختتامیه، سند سود و زیانی قرار نگیرد',
              style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================= انتقال تراز اختتامیه به تراز افتتاحیه

Future<void> showTransferClosingDialog(BuildContext context) async {
  final s = StoreScope.read(context);
  final closing = s.pendingClosing;
  if (closing == null) {
    toast(context, 'سند اختتامیه‌ای برای انتقال وجود ندارد. ابتدا سند اختتامیه را ثبت کنید.', error: true);
    return;
  }
  await showDialog<void>(context: context, builder: (_) => _TransferDialog(closing: closing));
}

class _TransferDialog extends StatefulWidget {
  final Voucher closing;
  const _TransferDialog({required this.closing});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late final TextEditingController _number;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: '${StoreScope.read(context).nextVoucherNumber()}');
    final d = widget.closing.date;
    _date = DateTime(d.year, d.month, d.day + 1);
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final v = s.transferClosing(widget.closing, date: _date, number: int.tryParse(normalizeDigits(_number.text.trim())));
    Navigator.pop(context);
    toast(context, 'سند افتتاحیه شماره ${v.number} از تراز اختتامیه ساخته شد');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.closing;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'انتقال تراز اختتامیه به تراز افتتاحیه',
        width: 560,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('سند اختتامیه شماره ${c.number} — ${jFormat(c.date)} — ${c.lines.length} ردیف'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(controller: _number, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'شماره سند افتتاحیه')),
            ),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'تاریخ سند افتتاحیه', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
          ]),
          const SizedBox(height: 10),
          Text('مانده حساب‌های ترازنامه‌ای دوباره باز می‌شود و سود یا زیان دوره به «سود و زیان انباشته» منتقل می‌گردد.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
        ]),
      ),
    );
  }
}

// ======================================================= read-only view

Future<void> showYearEndVoucher(BuildContext context, Voucher v) =>
    showDialog<void>(context: context, builder: (_) => _YearEndView(v: v));

class _YearEndView extends StatelessWidget {
  final Voucher v;
  const _YearEndView({required this.v});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    String name(VoucherLine l) {
      final m = findMoeen(l.moeen);
      final t = s.tafsiliName(l);
      return '${m?.name ?? l.moeen}${t.isEmpty ? '' : ' — $t'}';
    }

    final String? blocked = switch (v.kind) {
      'closing' when v.meta['reopen'] != null => 'ابتدا سند افتتاحیه انتقالی این اختتامیه را حذف کنید',
      'depreciation' => 'استهلاک را از «جدول اموال» ویرایش کنید',
      'assetBuy' when s.assets.any((a) => a.buyVoucherId == v.id && a.sold) => 'ابتدا سند فروش این اموال را حذف کنید',
      _ => null,
    };
    return FormDialog(
      title: '${v.kindLabel} شماره ${v.number} — ${jFormat(v.date)}',
      width: 820,
      leading: TextButton.icon(
        onPressed: () async {
          if (blocked != null) {
            toast(context, blocked, error: true);
            return;
          }
          final ok = await confirm(context, 'حذف سند', 'سند ${v.number} حذف شود؟');
          if (!ok || !context.mounted) return;
          s.removeVoucher(v.id);
          Navigator.pop(context);
        },
        icon: Icon(Icons.delete_outline_rounded, color: th.colorScheme.error),
        label: Text('حذف سند', style: TextStyle(color: th.colorScheme.error)),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => printTable(
            store: s,
            title: '${v.kindLabel} شماره ${v.number}',
            subtitle: jFormat(v.date),
            headers: const ['ردیف', 'کد', 'شرح حساب', 'بدهکار', 'بستانکار'],
            rows: [
              for (var i = 0; i < v.lines.length; i++)
                ['${i + 1}', v.lines[i].moeen, name(v.lines[i]), groupDigits(v.lines[i].debit), groupDigits(v.lines[i].credit)],
            ],
            numeric: const {3, 4},
            footer: ['', '', 'جمع', groupDigits(v.totalDebit), groupDigits(v.totalCredit)],
            fileName: '${v.kind}_${v.number}',
          ),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('چاپ'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in v.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 70, child: Text(l.moeen, style: TextStyle(color: th.hintColor))),
              Expanded(child: Text(name(l), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: l.debit == 0 ? const Text('') : Money(l.debit))),
              SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: l.credit == 0 ? const Text('') : Money(l.credit))),
            ]),
          ),
        const Divider(),
        Row(children: [
          const Expanded(child: Text('جمع', style: TextStyle(fontWeight: FontWeight.w800))),
          SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: Money(v.totalDebit, style: const TextStyle(fontWeight: FontWeight.w800)))),
          SizedBox(width: 140, child: Align(alignment: Alignment.centerLeft, child: Money(v.totalCredit, style: const TextStyle(fontWeight: FontWeight.w800)))),
        ]),
      ]),
    );
  }
}
