/// Report data of the documents printed with the band designer besides
/// invoices: «سند حسابداری»، «فیش حقوقی»، «چک ها» و «اسناد انتظامی».
library;

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/journal.dart' show buildJournal, TbRow;
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

String _q(double v) => v == 0 ? '' : fmtNum(v);

/// «چاپ تراز آزمایشی».
ReportData trialReportData(AppStore s, List<TbRow> rows, {String level = '', DateTime? from, DateTime? to}) {
  int sum(int Function(TbRow) f, [bool pl = false]) => rows.where((r) => !pl || r.isPl).fold(0, (a, r) => a + f(r));
  final bDr = sum((r) => r.balDr), bCr = sum((r) => r.balCr);
  final net = bDr - bCr;
  return ReportData(
    title: 'تراز آزمایشی',
    fields: {
      'عنوان': level.isEmpty ? 'تراز آزمایشی' : 'تراز آزمایشی ($level)',
      'نام فروشگاه': _shop(s),
      'نام دفتر مالی': _shop(s),
      'تاریخ': jFormat(DateTime.now()),
      'از تاریخ': from == null ? '' : jFormat(from),
      'تا تاریخ': to == null ? '' : jFormat(to),
      'سطح': level,
      'جمع بدهکار ابتدای دوره': groupDigits(sum((r) => r.startDr)),
      'جمع بستانکار ابتدای دوره': groupDigits(sum((r) => r.startCr)),
      'جمع گردش بدهکار': groupDigits(sum((r) => r.turnDr)),
      'جمع گردش بستانکار': groupDigits(sum((r) => r.turnCr)),
      'جمع بدهکار انتهای دوره': groupDigits(sum((r) => r.fullDr)),
      'جمع بستانکار انتهای دوره': groupDigits(sum((r) => r.fullCr)),
      'جمع مانده بدهکار': groupDigits(bDr),
      'جمع مانده بستانکار': groupDigits(bCr),
      'مانده خالص بدهکار': net > 0 ? groupDigits(net) : '0',
      'مانده خالص بستانکار': net < 0 ? groupDigits(-net) : '0',
      'مانده سود و زیان بدهکار': groupDigits(sum((r) => r.balDr, true)),
      'مانده سود و زیان بستانکار': groupDigits(sum((r) => r.balCr, true)),
    },
    rows: [
      for (var i = 0; i < rows.length; i++)
        {
          'ردیف': '${i + 1}',
          'کد حساب': rows[i].code,
          'نام حساب': rows[i].name,
          'بدهکار ابتدای دوره': _m(rows[i].startDr),
          'بستانکار ابتدای دوره': _m(rows[i].startCr),
          'گردش بدهکار': _m(rows[i].turnDr),
          'گردش بستانکار': _m(rows[i].turnCr),
          'بدهکار انتهای دوره': _m(rows[i].fullDr),
          'بستانکار انتهای دوره': _m(rows[i].fullCr),
          'مانده بدهکار': _m(rows[i].balDr),
          'مانده بستانکار': _m(rows[i].balCr),
          'مانده سود و زیانی بدهکار': rows[i].isPl ? _m(rows[i].balDr) : '',
          'مانده سود و زیانی بستانکار': rows[i].isPl ? _m(rows[i].balCr) : '',
          'تشخیص': rows[i].bal > 0 ? 'بد' : (rows[i].bal < 0 ? 'بس' : '-'),
        },
    ],
  );
}

/// «چاپ گزارش موجودی کالا» of [products] (one warehouse with [warehouseId]).
ReportData stockReportData(AppStore s, List<Product> products, {String? warehouseId, String title = 'گزارش موجودی کالا'}) {
  var totalQty = 0.0, totalValue = 0;
  final rows = <Map<String, String>>[];
  for (final p in products) {
    final q = s.stock(p.id, warehouseId: warehouseId);
    final fi = s.avgCost(p.id);
    final v = (q * fi).round();
    totalQty += q;
    totalValue += v;
    double inUnit(int n) => p.hasUnit(n) ? q / p.unitFactor(n) : 0;
    int sold(InvoiceKind k) => 0 + s.realInvoices.where((i) => i.kind == k).expand((i) => i.lines).where((l) => l.productId == p.id && (warehouseId == null || s.whId(l.warehouseId) == warehouseId)).fold(0.0, (a, l) => a + l.qty).round();
    rows.add({
      'ردیف': '${rows.length + 1}',
      'کد کالا': p.code,
      'نام کالا': p.name,
      'واحد': p.unit,
      'موجودی': fmtNum(q),
      'واحد دوم': p.hasUnit(2) ? p.unit2 : '',
      'موجودی واحد دوم': p.hasUnit(2) ? _q(inUnit(2)) : '',
      'واحد سوم': p.hasUnit(3) ? p.unit3 : '',
      'موجودی واحد سوم': p.hasUnit(3) ? _q(inUnit(3)) : '',
      'فی': _m(fi),
      'ارزش موجودی': _m(v),
      'بهای فروش': _m(p.sellPrice),
      'بهای مصرف کننده': p.info['consumerPrice'] ?? '',
      'حداقل موجودی': _q(p.minQty),
      'حداکثر موجودی': p.info['maxQty'] ?? '',
      'نام انبار': warehouseId == null ? 'همه انبارها' : (s.warehouse(warehouseId)?.name ?? ''),
      'خرید': '${sold(InvoiceKind.purchase)}',
      'برگشت از خرید': '${sold(InvoiceKind.purchaseReturn)}',
      'فروش': '${sold(InvoiceKind.sale)}',
      'برگشت از فروش': '${sold(InvoiceKind.saleReturn)}',
    });
  }
  return ReportData(
    title: title,
    fields: {
      'عنوان': title,
      'نام فروشگاه': _shop(s),
      'تاریخ': jFormat(DateTime.now()),
      'نام انبار': warehouseId == null ? 'همه انبارها' : (s.warehouse(warehouseId)?.name ?? ''),
      'جمع ارزش موجودی': groupDigits(totalValue),
      'جمع موجودی': fmtNum(totalQty),
      'تعداد اقلام': '${rows.length}',
    },
    rows: rows,
  );
}

/// «لیست حقوق / بیمه / مالیات» of a pay period.
ReportData salaryListReportData(AppStore s, PayPeriod p, {String title = 'لیست حقوق و دستمزد'}) {
  final w = s.workshop;
  final list = s.employeesIn(p);
  var jam = 0, kos = 0, khales = 0, bime = 0, karf = 0, bik = 0, mash = 0, mal = 0, mashMal = 0;
  final rows = <Map<String, String>>[];
  for (final e in list) {
    final r = s.payResult(p, e);
    jam += r.jamKol;
    kos += r.jamKosorat;
    khales += r.khales;
    bime += r.bimeSahmBimeShode;
    karf += r.bimeSahmKarfarma;
    bik += r.bimeBikari;
    mash += r.dastmozdMashmoolBime;
    mal += r.maliat;
    mashMal += r.mashmoolMaliat;
    rows.add({
      'ردیف': '${rows.length + 1}',
      'نام': e.firstName,
      'نام خانوادگی': e.lastName,
      'نام و نام خانوادگی': e.fullName,
      'نام پدر': e.fatherName,
      'کد ملی': e.nationalId,
      'شماره شناسنامه': e.idNo,
      'شماره بیمه': e.insuranceNo,
      'کد پرسنلی': e.personnelCode,
      'شغل': e.jobName,
      'جنسیت': e.male ? 'مرد' : 'زن',
      'ملیت': e.nationality.isEmpty ? 'ایرانی' : e.nationality,
      'تاریخ استخدام': e.hireDate == null ? '' : jFormat(e.hireDate!),
      'تاریخ ترک کار': e.endDate == null ? '' : jFormat(e.endDate!),
      'روزهای کارکرد': fmtNum(r.workDays),
      'دستمزد روزانه': _m(r.dailyWage),
      'حقوق ماهیانه': _m(r.hoghoghMahiane),
      'مزایای مستمر': _m(r.mazayaMostamar),
      'اضافه کار': _m(r.ezafeKari),
      'جمع حقوق و مزایا': _m(r.jamKol),
      'دستمزد مشمول بیمه': _m(r.dastmozdMashmoolBime),
      'دستمزد غیر مشمول بیمه': _m(r.dastmozdGheirMashmoolBime),
      'بیمه سهم بیمه شده': _m(r.bimeSahmBimeShode),
      'بیمه سهم کارفرما': _m(r.bimeSahmKarfarma),
      'بیمه بیکاری': _m(r.bimeBikari),
      'جمع بیمه': _m(r.bimeSahmBimeShode + r.bimeSahmKarfarma + r.bimeBikari),
      'مشمول مالیات': _m(r.mashmoolMaliat),
      'مالیات': _m(r.maliat),
      'جمع کسورات': _m(r.jamKosorat),
      'خالص پرداختی': _m(r.khales),
      'شماره حساب': e.accountNo,
    });
  }
  return ReportData(
    title: title,
    fields: {
      'عنوان': title,
      'نام فروشگاه': _shop(s),
      'نام کارگاه': w.name,
      'شماره کارگاه': w.code,
      'نام کارفرما': w.employer,
      'آدرس کارگاه': w.address,
      'نام مرکز بیمه': w.insuranceOffice,
      'دوره': p.name,
      'سال': '${p.year}',
      'ماه': '${p.month}',
      'تاریخ': jFormat(DateTime.now()),
      'جمع حقوق و مزایا': groupDigits(jam),
      'جمع کسورات': groupDigits(kos),
      'جمع خالص پرداختی': groupDigits(khales),
      'جمع بیمه سهم بیمه شده': groupDigits(bime),
      'جمع بیمه سهم کارفرما': groupDigits(karf),
      'جمع بیمه بیکاری': groupDigits(bik),
      'جمع کل بیمه': groupDigits(bime + karf + bik),
      'جمع دستمزد مشمول بیمه': groupDigits(mash),
      'جمع مالیات': groupDigits(mal),
      'جمع مشمول مالیات': groupDigits(mashMal),
      'تعداد پرسنل': '${list.length}',
    },
    rows: rows,
  );
}

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
    case PrintDocType.trialBalance:
      final j = buildJournal(s);
      final m = <String, TbRow>{};
      for (final p in j) {
        final r = m.putIfAbsent(p.moeen, () => TbRow(p.moeen, p.moeen, findMoeen(p.moeen)?.name ?? p.moeen));
        r
          ..turnDr += p.debit
          ..turnCr += p.credit
          ..bal += p.debit - p.credit;
      }
      return trialReportData(s, m.values.toList()..sort((a, b) => a.code.compareTo(b.code)), level: 'معین');
    case PrintDocType.stock:
      return stockReportData(s, s.productsSorted.where((p) => !p.archived).take(30).toList());
    case PrintDocType.salaryList:
      final p = s.periodsSorted.firstOrNull;
      if (p != null) return salaryListReportData(s, p);
      return ReportData(title: 'لیست حقوق', fields: {'عنوان': 'لیست حقوق و دستمزد', 'دوره': '1405/07', 'تعداد پرسنل': '1'}, rows: [
        {'ردیف': '1', 'نام و نام خانوادگی': 'پرسنل نمونه', 'روزهای کارکرد': '30', 'جمع حقوق و مزایا': '120,000,000', 'خالص پرداختی': '105,000,000'},
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
