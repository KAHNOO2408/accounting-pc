import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';

// ================================================================ گزارش از وضعیت حساب

/// One row of «گزارش از وضعیت حساب» (Sakan AmarReport).
class AccountStatusRow {
  final Person person;
  int recvNotDue = 0, recvDue = 0, paidNotDue = 0, paidDue = 0;
  int balance = 0;
  AccountStatusRow(this.person);
}

/// Open cheques by due state and the balance of every person.
List<AccountStatusRow> accountStatus(AppStore s, {DateTime? at}) {
  final today = dateOnly(at ?? DateTime.now());
  final rows = {for (final p in s.peopleSorted) p.id: AccountStatusRow(p)};
  for (final c in s.cheques) {
    final r = rows[c.personId];
    if (r == null) continue;
    if (c.status != ChequeStatus.pending && c.status != ChequeStatus.deposited) continue;
    final due = !dateOnly(c.dueDate).isAfter(today);
    final recv = c.direction == ChequeDirection.received;
    if (recv && due) {
      r.recvDue += c.amount;
    } else if (recv) {
      r.recvNotDue += c.amount;
    } else if (due) {
      r.paidDue += c.amount;
    } else {
      r.paidNotDue += c.amount;
    }
  }
  for (final r in rows.values) {
    r.balance = s.personBalance(r.person.id);
  }
  return rows.values.where((r) => r.balance != 0 || r.recvDue + r.recvNotDue + r.paidDue + r.paidNotDue != 0).toList();
}

Future<void> showAccountStatus(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Status());

class _Status extends StatefulWidget {
  const _Status();

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = accountStatus(s).where((r) => _q.isEmpty || r.person.name.contains(_q) || '${r.person.code}' == _q).toList();
    final w = [80.0, 0.0, 120.0, 120.0, 120.0, 120.0, 120.0, 120.0];
    int sum(int Function(AccountStatusRow) f) => rows.fold(0, (a, r) => a + f(r));
    return SakanWindow(
      title: 'گزارش از وضعیت حساب',
      width: 1150,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 240, child: TextField(decoration: const InputDecoration(hintText: 'نام یا کد دفتر', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            const Spacer(),
            sakanBtn('چاپ', () => printTable(
                  store: s,
                  title: 'گزارش از وضعیت حساب',
                  headers: const ['کد دفتر', 'نام دفتر', 'چک دریافتی سررسید نشده', 'چک دریافتی سررسید شده', 'چک پرداختی سررسید نشده', 'چک پرداختی سررسید شده', 'بدهکار', 'بستانکار'],
                  rows: [
                    for (final r in rows)
                      [
                        '${r.person.code}',
                        r.person.name,
                        groupDigits(r.recvNotDue),
                        groupDigits(r.recvDue),
                        groupDigits(r.paidNotDue),
                        groupDigits(r.paidDue),
                        groupDigits(r.balance > 0 ? r.balance : 0),
                        groupDigits(r.balance < 0 ? -r.balance : 0),
                      ],
                  ],
                  numeric: const {2, 3, 4, 5, 6, 7},
                  footer: [
                    '',
                    'جمع',
                    groupDigits(sum((r) => r.recvNotDue)),
                    groupDigits(sum((r) => r.recvDue)),
                    groupDigits(sum((r) => r.paidNotDue)),
                    groupDigits(sum((r) => r.paidDue)),
                    groupDigits(sum((r) => r.balance > 0 ? r.balance : 0)),
                    groupDigits(sum((r) => r.balance < 0 ? -r.balance : 0)),
                  ],
                  fileName: 'vazeyat-hesab',
                ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('کد دفتر', w[0]),
                sakanHead('نام دفتر', w[1]),
                sakanHead('دریافتی سررسید نشده', w[2]),
                sakanHead('دریافتی سررسید شده', w[3]),
                sakanHead('پرداختی سررسید نشده', w[4]),
                sakanHead('پرداختی سررسید شده', w[5]),
                sakanHead('بدهکار', w[6]),
                sakanHead('بستانکار', w[7]),
              ],
              count: rows.length,
              row: (ctx, i) {
                final r = rows[i];
                return Container(
                  color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                  child: Row(children: [
                    sakanCell(Text('${r.person.code}'), w[0]),
                    sakanCell(Text(r.person.name, overflow: TextOverflow.ellipsis), w[1], align: Alignment.centerRight),
                    sakanCell(Text(groupDigits(r.recvNotDue)), w[2]),
                    sakanCell(Text(groupDigits(r.recvDue), style: TextStyle(color: r.recvDue > 0 ? Colors.red.shade700 : null)), w[3]),
                    sakanCell(Text(groupDigits(r.paidNotDue)), w[4]),
                    sakanCell(Text(groupDigits(r.paidDue), style: TextStyle(color: r.paidDue > 0 ? Colors.red.shade700 : null)), w[5]),
                    sakanCell(Text(groupDigits(r.balance > 0 ? r.balance : 0)), w[6]),
                    sakanCell(Text(groupDigits(r.balance < 0 ? -r.balance : 0)), w[7]),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ نمودار سود و زیان

/// Net profit of each Jalali month of [year] (Sakan «نمودار سود و زیان»).
List<(String, int)> monthlyProfit(AppStore s, int year) => [
      for (var m = 1; m <= 12; m++)
        () {
          final from = Jalali(year, m, 1).toDateTime();
          final to = Jalali(year, m, Jalali.monthLength(year, m)).toDateTime();
          return (jalaliMonthNames[m - 1], s.profit(from, to).netProfit);
        }(),
    ];

Future<void> showProfitChart(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Chart());

class _Chart extends StatefulWidget {
  const _Chart();

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  int _year = Jalali.fromDateTime(DateTime.now()).year;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final data = monthlyProfit(s, _year);
    final maxAbs = data.fold<int>(1, (a, d) => d.$2.abs() > a ? d.$2.abs() : a);
    final total = data.fold<int>(0, (a, d) => a + d.$2);
    return FormDialog(
      title: 'نمودار سود و زیان',
      width: 900,
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_right_rounded)),
        Text('سال $_year', style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_left_rounded)),
      ]),
      actions: [
        TextButton(
          onPressed: () => printTable(
            store: s,
            title: 'سود و زیان ماهانه سال $_year',
            headers: const ['دوره', 'سود/زیان'],
            rows: [for (final d in data) [d.$1, groupDigits(d.$2)]],
            numeric: const {1},
            footer: ['جمع', groupDigits(total)],
            fileName: 'nemodar-sod-zian',
          ),
          child: const Text('چاپ'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 320,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (name, v) in data)
              Expanded(
                child: Tooltip(
                  message: '$name: ${groupDigits(v)}',
                  child: Column(children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: v > 0 ? Container(margin: const EdgeInsets.symmetric(horizontal: 6), height: 140 * v / maxAbs, color: Colors.green.shade600) : null,
                      ),
                    ),
                    Container(height: 1, color: Colors.black54),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: v < 0 ? Container(margin: const EdgeInsets.symmetric(horizontal: 6), height: 140 * -v / maxAbs, color: Colors.red.shade600) : null,
                      ),
                    ),
                    Text(name, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text('جمع سال: ${groupDigits(total)} ${total >= 0 ? '(سود)' : '(زیان)'}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
