/// Report data of the documents printed with the band designer besides
/// invoices: «سند حسابداری»، «فیش حقوقی»، «چک ها» و «اسناد انتظامی».
library;

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart' show buildJournal;
import '../../data/models.dart';
import '../../data/payroll.dart';
import '../../data/store.dart';
import 'report_render.dart';

String _m(int v) => v == 0 ? '' : groupDigits(v);
String _shop(AppStore s) => s.settings.businessName.isEmpty ? s.settings.ownerName : s.settings.businessName;

ReportData voucherReportData(AppStore s, Voucher v) {
  final dr = v.lines.fold<int>(0, (a, l) => a + l.debit), cr = v.lines.fold<int>(0, (a, l) => a + l.credit);
  return ReportData(
    title: 'سند ${v.number}',
    fields: {
      'شماره سند': '${v.number}',
      'شماره ثابت': '${v.fixedNumber}',
      'تاریخ سند': jFormat(v.date),
      'شرح سند': v.desc,
      'بابت': v.desc,
      'نوع سند': v.kindLabel,
      'مرکز اسناد': v.center,
      'نام فروشگاه': _shop(s),
      'جمع بدهکار': groupDigits(dr),
      'جمع بستانکار': groupDigits(cr),
      'مبلغ به حروف': '${amountInWords(dr)} ${s.settings.currency}',
      'تنظیم کننده': s.currentUser.name,
      'تاریخ': jFormat(DateTime.now()),
    },
    rows: [
      for (var i = 0; i < v.lines.length; i++)
        () {
          final l = v.lines[i];
          final m = findMoeen(l.moeen);
          final k = kolOf(l.moeen);
          final t = l.tafsiliId == null ? '' : s.tafsiliName(l);
          return {
            'ردیف': '${i + 1}',
            'کد کل': k.code,
            'نام کل': k.name,
            'کد معین': l.moeen,
            'نام معین': m?.name ?? '',
            'کد تفصیلی': l.tafsiliId == null ? '' : '${s.person(l.tafsiliId)?.code ?? s.product(l.tafsiliId)?.code ?? ''}',
            'نام تفصیلی': t,
            'نام حساب': t.isEmpty ? (m?.name ?? l.moeen) : '${m?.name ?? ''} / $t',
            'شرح ردیف': l.desc.isEmpty ? v.desc : l.desc,
            'بدهکار': _m(l.debit),
            'بستانکار': _m(l.credit),
          };
        }(),
    ],
  );
}

ReportData payslipReportData(AppStore s, PayPeriod p, Employee e) {
  final r = s.payResult(p, e);
  final slip = s.payslipOf(p, e);
  final leaves = s.leavesIn(e, p);
  final absence = leaves.where((l) => l.kind == LeaveKind.absence).fold<double>(0, (a, l) => a + l.days);
  final unpaid = leaves.where((l) => l.kind == LeaveKind.unpaid).fold<double>(0, (a, l) => a + l.days);
  final ben = <(String, int)>[
    ('حقوق ماهیانه', r.hoghoghMahiane),
    ('حق سنوات', r.haghSanavat),
    for (final b in e.benefits) (b.name, (b.amount * (r.workDays / (p.days <= 0 ? 30 : p.days))).round()),
    for (final b in slip.extraBenefits) (b.name, b.amount),
    ('اضافه کار', r.ezafeKari),
    ('حق شیفت', r.haghShift),
    ('حق ماموریت', r.haghMamoriat + r.safar),
    ('پاداش', r.padash),
    ('پرداخت های معوقه', r.pardakhthayeMoavaghe),
    ('سایر پرداخت ها', r.sayerPardakhthayeNaghdy),
    ('عیدی', r.eydi),
    ('بازخرید مرخصی', r.bazKharidMorkhasi),
  ].where((x) => x.$2 != 0).toList();
  final ded = <(String, int)>[
    ('کسر کار', r.kasrKar),
    ('بیمه سهم بیمه شده', r.bimeSahmBimeShode),
    ('مالیات', r.maliat),
    ('قسط وام', r.vam),
    ('مساعده', r.mosaede),
    ('جریمه', r.jarime),
    for (final d in e.deductions) (d.name, d.amount),
    for (final d in slip.extraDeductions) (d.name, d.amount),
    if (r.gheirNaghdi != 0) ('مزایای غیر نقدی', r.gheirNaghdi),
  ].where((x) => x.$2 != 0).toList();
  final n = ben.length > ded.length ? ben.length : ded.length;
  final net = r.khales;
  return ReportData(
    title: 'فیش حقوقی ${e.fullName} ${p.name}',
    fields: {
      'نام': e.firstName,
      'نام خانوادگی': e.lastName,
      'نام و نام خانوادگی': e.fullName,
      'نام پدر': e.fatherName,
      'کد پرسنلی': e.personnelCode,
      'کد ملی': e.nationalId,
      'شماره بیمه': e.insuranceNo,
      'نوع استخدام': e.employmentType,
      'شغل': e.jobName,
      'شماره حساب': e.accountNo,
      'نام بانک': e.bankName,
      'دوره': p.name,
      'سال': '${p.year}',
      'ماه': jalaliMonthNames[(p.month - 1).clamp(0, 11)],
      'روزهای کارکرد': fmtNum(r.workDays),
      'حقوق ماهیانه': _m(r.hoghoghMahiane),
      'دستمزد روزانه': _m(r.dailyWage),
      'اضافه کار': _m(r.ezafeKari),
      'ساعت اضافه کار': fmtNum(slip.overtimeHours),
      'کسر کار': _m(r.kasrKar),
      'ساعت کسر کار': fmtNum(slip.shortHours),
      'حق شیفت': _m(r.haghShift),
      'حق ماموریت': _m(r.haghMamoriat),
      'پاداش': _m(r.padash),
      'عیدی': _m(r.eydi),
      'بازخرید مرخصی': _m(r.bazKharidMorkhasi),
      'حق سنوات': _m(r.haghSanavat),
      'پرداخت های معوقه': _m(r.pardakhthayeMoavaghe),
      'مزایای مستمر': _m(r.mazayaMostamar),
      'مزایای غیر نقدی': _m(r.gheirNaghdi),
      'جمع حقوق و مزایا': groupDigits(r.jamKol),
      'بیمه سهم بیمه شده': _m(r.bimeSahmBimeShode),
      'مالیات': _m(r.maliat),
      'وام': _m(r.vam),
      'مساعده': _m(r.mosaede),
      'جریمه': _m(r.jarime),
      'غیبت': _m((absence * r.dailyWage).round()),
      'روزهای غیبت': fmtNum(absence),
      'مرخصی بدون حقوق': _m((unpaid * r.dailyWage).round()),
      'روزهای مرخصی بدون حقوق': fmtNum(unpaid),
      'سایر کسورات': _m(r.kosoratSabet),
      'جمع کسورات': groupDigits(r.jamKosorat),
      'خالص پرداختی': groupDigits(net),
      'مبلغ به حروف': '${amountInWords(net < 0 ? -net : net)} ${s.settings.currency}',
      'مانده دفتر': groupDigits(s.personBalance(e.personId)),
      'نام فروشگاه': _shop(s),
      'نام کارگاه': s.workshop.name.isEmpty ? _shop(s) : s.workshop.name,
      'تاریخ': jFormat(DateTime.now()),
    },
    rows: [
      for (var i = 0; i < n; i++)
        {
          'ردیف': '${i + 1}',
          'عنوان': [if (i < ben.length) ben[i].$1, if (i < ded.length) ded[i].$1].join(' / '),
          'مزایا': i < ben.length ? groupDigits(ben[i].$2) : '',
          'کسورات': i < ded.length ? groupDigits(ded[i].$2) : '',
        },
    ],
  );
}

String fmtNum(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

ReportData chequeReportData(AppStore s, List<Cheque> list, {String title = 'لیست چک ها'}) => ReportData(
      title: title,
      fields: {
        'عنوان': title,
        'نام فروشگاه': _shop(s),
        'تاریخ': jFormat(DateTime.now()),
        'جمع مبلغ': groupDigits(list.fold(0, (a, c) => a + c.amount)),
        'تعداد': '${list.length}',
      },
      rows: [
        for (var i = 0; i < list.length; i++)
          {
            'ردیف': '${i + 1}',
            'شماره چک': list[i].serial,
            'مبلغ': groupDigits(list[i].amount),
            'سررسید': jFormat(list[i].dueDate),
            'تاریخ صدور': jFormat(list[i].issueDate),
            'بانک': list[i].bank,
            'طرف حساب': s.person(list[i].personId)?.name ?? '',
            'دریافت کننده': list[i].direction == ChequeDirection.issued ? (s.person(list[i].personId)?.name ?? '') : _shop(s),
            'وضعیت': list[i].status.label,
            'نوع': list[i].direction == ChequeDirection.received ? 'دریافتی' : 'پرداختی',
            'شرح': list[i].note,
          },
      ],
    );

ReportData guaranteeReportData(AppStore s, GuaranteeDoc g) => ReportData(
      title: '${g.label} ${g.number}',
      fields: {
        'شماره سند': '${g.number}',
        'تاریخ سند': jFormat(g.date),
        'نوع سند': g.label,
        'طرف حساب': s.person(g.personId)?.name ?? '',
        'بابت': g.babat,
        'جمع مبلغ': groupDigits(g.total),
        'مبلغ به حروف': '${amountInWords(g.total)} ${s.settings.currency}',
        'نام فروشگاه': _shop(s),
        'تاریخ': jFormat(DateTime.now()),
      },
      rows: [
        for (var i = 0; i < g.items.length; i++)
          {
            'ردیف': '${i + 1}',
            'نوع': g.items[i].kind.label,
            'شماره سریال': g.items[i].serial,
            'مبلغ': groupDigits(g.items[i].amount),
            'سررسید': g.items[i].dueDate == null ? '' : jFormat(g.items[i].dueDate!),
            'بانک': g.items[i].bank,
            'مکان نگهداری': g.items[i].place,
            'متعلق به': g.items[i].owner,
            'وضعیت': g.items[i].open ? 'عودت نشده' : 'عودت ${jFormat(g.items[i].returnedOn!)}',
          },
      ],
    );

/// Sample data for the designer.
ReportData sampleDocData(AppStore s, PrintDocType t) {
  final now = DateTime.now();
  switch (t) {
    case PrintDocType.voucher:
      return voucherReportData(
        s,
        s.vouchers.lastOrNull ??
            Voucher(id: 'x', number: 1, fixedNumber: 1, date: now, desc: 'سند نمونه', lines: [
              VoucherLine(moeen: mCash, debit: 1000000, desc: 'دریافت نقدی'),
              VoucherLine(moeen: mDebtorsTrade, credit: 1000000, desc: 'دریافت نقدی'),
            ]),
      );
    case PrintDocType.payslip:
      final p = s.periodsSorted.firstOrNull;
      final e = p == null ? null : s.employeesIn(p).firstOrNull;
      if (p != null && e != null) return payslipReportData(s, p, e);
      return ReportData(title: 'فیش حقوقی', fields: {'نام و نام خانوادگی': 'پرسنل نمونه', 'دوره': '1405/07', 'جمع حقوق و مزایا': '120,000,000', 'جمع کسورات': '15,000,000', 'خالص پرداختی': '105,000,000'}, rows: [
        {'ردیف': '1', 'عنوان': 'حقوق ماهیانه / بیمه سهم بیمه شده', 'مزایا': '100,000,000', 'کسورات': '8,400,000'},
        {'ردیف': '2', 'عنوان': 'حق مسکن / مالیات', 'مزایا': '20,000,000', 'کسورات': '6,600,000'},
      ]);
    case PrintDocType.cheque:
      return chequeReportData(
        s,
        s.cheques.isNotEmpty
            ? s.cheques.take(10).toList()
            : [Cheque(id: 'x', direction: ChequeDirection.received, amount: 5000000, dueDate: now, issueDate: now, serial: '123456', bank: 'ملی')],
      );
    default:
      return guaranteeReportData(
        s,
        s.guarantees.lastOrNull ?? GuaranteeDoc(id: 'x', number: 1, date: now, babat: 'نمونه', items: [GuaranteeItem(id: 'y', serial: '1001', amount: 50000000)]),
      );
  }
}

/// The accounting rows of any document (invoice, receipt, voucher…) as a voucher for printing.
Voucher docAsVoucher(AppStore s, String key, {required int number, required int fixed, required DateTime date, required String desc}) {
  final v = s.vouchers.where((v) => 'v:${v.id}' == key).firstOrNull;
  if (v != null) return v;
  return Voucher(
    id: key,
    number: number,
    fixedNumber: fixed,
    date: date,
    desc: desc,
    lines: [
      for (final p in buildJournal(s).where((p) => p.docKey == key))
        VoucherLine(moeen: p.moeen, tafsiliId: p.tafsiliId, desc: p.desc, debit: p.debit, credit: p.credit),
    ],
  );
}
