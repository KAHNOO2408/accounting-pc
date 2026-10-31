/// «حقوق و دستمزد» — Sakan's payroll: personnel, payroll periods, payslips
/// (مزایا / کسورات), leaves, missions, loans, insurance and salary tax.
///
/// Field names follow Sakan's SalaryFishHoghogh / SalaryBime / SalaryMaliatDisk
/// (see docs/sakan/forms). Legal rates live in [PayrollRules] and are editable.
library;

import 'models.dart' show newId;
import 'pay_tables.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? d);
double _dbl(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? d;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
String? _ds(DateTime? d) => d?.toIso8601String().substring(0, 10);
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

// ===================================================================== rules

/// One step of the salary tax table (monthly, from [from] upward).
class TaxStep {
  int from;
  double rate;
  TaxStep(this.from, this.rate);
  Map<String, dynamic> toJson() => {'from': from, 'rate': rate};
  factory TaxStep.fromJson(Map<String, dynamic> j) => TaxStep(_i(j['from']), _dbl(j['rate']));
}

/// Insurance and tax rates. The defaults are the 1404 figures (in the app
/// currency, تومان); every year they must be checked and edited.
class PayrollRules {
  double workerPct; // بیمه سهم بیمه شده
  double employerPct; // بیمه سهم کارفرما
  double unemploymentPct; // بیمه بیکاری سهم کارفرما
  double hardPct; // بیمه مشاغل سخت و زیان آور
  int insuranceCapDaily; // سقف تعلق بیمه برای یک روز کاری (0 = بدون سقف)
  int taxExempt; // معافیت ماهانه مالیات حقوق
  List<TaxStep> steps; // نرخ‌های پلکانی بالاتر از معافیت
  int eydiTaxExempt; // سقف معافیت مالیاتی عیدی
  String label;

  PayrollRules({
    this.workerPct = 7,
    this.employerPct = 20,
    this.unemploymentPct = 3,
    this.hardPct = 4,
    this.insuranceCapDaily = 0,
    this.taxExempt = 24000000,
    List<TaxStep>? steps,
    this.eydiTaxExempt = 0,
    this.label = 'جدول ۱۴۰۴ (پیش فرض — برای سال جاری بررسی و اصلاح شود)',
  }) : steps = steps ??
            [
              TaxStep(24000000, 10),
              TaxStep(30000000, 15),
              TaxStep(38000000, 20),
              TaxStep(50000000, 25),
              TaxStep(66666667, 30),
            ];

  /// Monthly salary tax of [taxable] (after the insured share is deducted).
  int tax(int taxable) {
    if (taxable <= taxExempt) return 0;
    final st = [...steps]..sort((a, b) => a.from.compareTo(b.from));
    var t = 0.0;
    for (var i = 0; i < st.length; i++) {
      final lo = st[i].from;
      final hi = i + 1 < st.length ? st[i + 1].from : null;
      if (taxable <= lo) break;
      final top = hi == null || taxable < hi ? taxable : hi;
      t += (top - lo) * st[i].rate / 100;
    }
    return t.round();
  }

  Map<String, dynamic> toJson() => {
        'workerPct': workerPct,
        'employerPct': employerPct,
        'unemploymentPct': unemploymentPct,
        'hardPct': hardPct,
        'insuranceCapDaily': insuranceCapDaily,
        'taxExempt': taxExempt,
        'steps': steps.map((e) => e.toJson()).toList(),
        'eydiTaxExempt': eydiTaxExempt,
        'label': label,
      };

  factory PayrollRules.fromJson(Map<String, dynamic> j) => PayrollRules(
        workerPct: _dbl(j['workerPct'], 7),
        employerPct: _dbl(j['employerPct'], 20),
        unemploymentPct: _dbl(j['unemploymentPct'], 3),
        hardPct: _dbl(j['hardPct'], 4),
        insuranceCapDaily: _i(j['insuranceCapDaily']),
        taxExempt: _i(j['taxExempt'], 24000000),
        steps: j['steps'] is List ? _list(j['steps']).map(TaxStep.fromJson).toList() : null,
        eydiTaxExempt: _i(j['eydiTaxExempt']),
        label: _s(j['label']),
      );
}

// ===================================================================== workshop

/// «کارگاه» — header of the insurance list (DSKKAR).
class Workshop {
  String code; // شماره کارگاه
  String name; // نام کارگاه
  String employer; // نام کارفرما
  String address;
  String insuranceOffice; // نام مرکز بیمه
  Workshop({this.code = '', this.name = '', this.employer = '', this.address = '', this.insuranceOffice = ''});
  Map<String, dynamic> toJson() => {'code': code, 'name': name, 'employer': employer, 'address': address, 'insuranceOffice': insuranceOffice};
  factory Workshop.fromJson(Map<String, dynamic> j) => Workshop(
      code: _s(j['code']), name: _s(j['name']), employer: _s(j['employer']), address: _s(j['address']), insuranceOffice: _s(j['insuranceOffice']));
}

// ===================================================================== personnel

/// A fixed monthly item of an employee's «حکم» (مزایای مستمر) or deduction.
class PayItem2 {
  String name;
  int amount;
  bool insured; // مشمول بیمه
  bool taxed; // مشمول مالیات
  bool nonCash; // مزایای غیر نقدی (کالا، خدمات): مشمول، ولی نقدی پرداخت نمی‌شود
  PayItem2({required this.name, this.amount = 0, this.insured = true, this.taxed = true, this.nonCash = false});
  Map<String, dynamic> toJson() => {'name': name, 'amount': amount, 'insured': insured, 'taxed': taxed, if (nonCash) 'nonCash': true};
  factory PayItem2.fromJson(Map<String, dynamic> j) =>
      PayItem2(name: _s(j['name']), amount: _i(j['amount']), insured: j['insured'] != false, taxed: j['taxed'] != false, nonCash: j['nonCash'] == true);
}

/// «پرسنل» — linked to a person account (حساب تفصیلی) for the salary payable.
class Employee {
  String id;
  String personId;
  String personnelCode; // کد پرسنلی
  String cardCode; // شماره کارت پرسنلی
  String nationalId; // شماره ملی
  String firstName;
  String lastName;
  String fatherName;
  String idNo; // شماره شناسنامه
  String issuePlace; // محل صدور
  DateTime? birthDate;
  bool male;
  bool married;
  int children;
  String nationality; // ملیت
  String jobName;
  String jobCode; // کد شغل بیمه
  bool hardJob; // مشاغل سخت
  String unit; // واحد / بخش
  String insuranceNo; // شماره بیمه
  DateTime? hireDate;
  DateTime? endDate; // تاریخ انفصال
  String employmentType; // نوع استخدام
  String education; // مدرک تحصیلی
  String bankName;
  String accountNo;
  String cardNo;
  String phone;
  String address;

  /// «حقوق ماهیانه» (base monthly wage for a full period).
  int monthlyWage;
  int sanavatMonthly; // حق سنوات ماهانه
  bool sanavatInsured;
  bool sanavatTaxed;
  int annualLeaveDays; // مرخصی استحقاقی سالانه
  List<PayItem2> benefits; // مزایای مستمر

  /// «هزینه های مستمر پرداختی معاف از مالیات توسط مودی» (e.g. supplementary
  /// insurance premiums) deducted from the taxable pay each month.
  int taxExemptMonthly = 0;

  /// «گروه حقوق» this employee follows.
  String? payGroupId;

  /// «جداول پایه پرسنل»: [PayTableKind] name → table id.
  Map<String, String> tables = {};
  List<PayItem2> deductions; // کسورات ثابت
  bool active;

  Employee({
    required this.id,
    required this.personId,
    this.personnelCode = '',
    this.cardCode = '',
    this.nationalId = '',
    this.firstName = '',
    this.lastName = '',
    this.fatherName = '',
    this.idNo = '',
    this.issuePlace = '',
    this.birthDate,
    this.male = true,
    this.married = false,
    this.children = 0,
    this.nationality = 'ایرانی',
    this.jobName = '',
    this.jobCode = '',
    this.hardJob = false,
    this.unit = '',
    this.insuranceNo = '',
    this.hireDate,
    this.endDate,
    this.employmentType = 'قراردادی',
    this.education = '',
    this.bankName = '',
    this.accountNo = '',
    this.cardNo = '',
    this.phone = '',
    this.address = '',
    this.monthlyWage = 0,
    this.sanavatMonthly = 0,
    this.sanavatInsured = false,
    this.sanavatTaxed = false,
    this.annualLeaveDays = 26,
    List<PayItem2>? benefits,
    List<PayItem2>? deductions,
    this.active = true,
  })  : benefits = benefits ?? [],
        deductions = deductions ?? [];

  String get fullName => '$firstName $lastName'.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'personId': personId,
        'personnelCode': personnelCode,
        'cardCode': cardCode,
        'nationalId': nationalId,
        'firstName': firstName,
        'lastName': lastName,
        'fatherName': fatherName,
        'idNo': idNo,
        'issuePlace': issuePlace,
        'birthDate': _ds(birthDate),
        'male': male,
        'married': married,
        'children': children,
        'nationality': nationality,
        'jobName': jobName,
        'jobCode': jobCode,
        'hardJob': hardJob,
        'unit': unit,
        'insuranceNo': insuranceNo,
        'hireDate': _ds(hireDate),
        'endDate': _ds(endDate),
        'employmentType': employmentType,
        'education': education,
        'bankName': bankName,
        'accountNo': accountNo,
        'cardNo': cardNo,
        'phone': phone,
        'address': address,
        'monthlyWage': monthlyWage,
        'sanavatMonthly': sanavatMonthly,
        'sanavatInsured': sanavatInsured,
        'sanavatTaxed': sanavatTaxed,
        'annualLeaveDays': annualLeaveDays,
        'benefits': benefits.map((e) => e.toJson()).toList(),
        if (taxExemptMonthly != 0) 'taxExemptMonthly': taxExemptMonthly,
        if (payGroupId != null) 'payGroupId': payGroupId,
        if (tables.isNotEmpty) 'tables': tables,
        'deductions': deductions.map((e) => e.toJson()).toList(),
        'active': active,
      };

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: _s(j['id']),
        personId: _s(j['personId']),
        personnelCode: _s(j['personnelCode']),
        cardCode: _s(j['cardCode']),
        nationalId: _s(j['nationalId']),
        firstName: _s(j['firstName']),
        lastName: _s(j['lastName']),
        fatherName: _s(j['fatherName']),
        idNo: _s(j['idNo']),
        issuePlace: _s(j['issuePlace']),
        birthDate: _dt(j['birthDate']),
        male: j['male'] != false,
        married: j['married'] == true,
        children: _i(j['children']),
        nationality: _s(j['nationality']).isEmpty ? 'ایرانی' : _s(j['nationality']),
        jobName: _s(j['jobName']),
        jobCode: _s(j['jobCode']),
        hardJob: j['hardJob'] == true,
        unit: _s(j['unit']),
        insuranceNo: _s(j['insuranceNo']),
        hireDate: _dt(j['hireDate']),
        endDate: _dt(j['endDate']),
        employmentType: _s(j['employmentType']),
        education: _s(j['education']),
        bankName: _s(j['bankName']),
        accountNo: _s(j['accountNo']),
        cardNo: _s(j['cardNo']),
        phone: _s(j['phone']),
        address: _s(j['address']),
        monthlyWage: _i(j['monthlyWage']),
        sanavatMonthly: _i(j['sanavatMonthly']),
        sanavatInsured: j['sanavatInsured'] == true,
        sanavatTaxed: j['sanavatTaxed'] == true,
        annualLeaveDays: _i(j['annualLeaveDays'], 26),
        benefits: _list(j['benefits']).map(PayItem2.fromJson).toList(),
        deductions: _list(j['deductions']).map(PayItem2.fromJson).toList(),
        active: j['active'] != false,
      )
        ..taxExemptMonthly = _i(j['taxExemptMonthly'])
        ..payGroupId = j['payGroupId'] is String ? j['payGroupId'] as String : null
        ..tables = j['tables'] is Map ? {for (final e in (j['tables'] as Map).entries) '${e.key}': '${e.value}'} : {};
}

/// «گروه حقوق»: a wage and fixed benefits shared by a group of employees.
class PayGroup {
  String id;
  String name;
  int monthlyWage;
  List<PayItem2> benefits;
  PayGroup({required this.id, required this.name, this.monthlyWage = 0, List<PayItem2>? benefits}) : benefits = benefits ?? [];
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'monthlyWage': monthlyWage, 'benefits': benefits.map((e) => e.toJson()).toList()};
  factory PayGroup.fromJson(Map<String, dynamic> j) =>
      PayGroup(id: _s(j['id']), name: _s(j['name']), monthlyWage: _i(j['monthlyWage']), benefits: _list(j['benefits']).map(PayItem2.fromJson).toList());

  /// Copies the group's wage and benefits to [e].
  void applyTo(Employee e) {
    e
      ..payGroupId = id
      ..monthlyWage = monthlyWage
      ..benefits = [for (final b in benefits) PayItem2.fromJson(b.toJson())];
  }
}

// ===================================================================== leaves, missions, loans

enum LeaveKind { paid, sick, unpaid, absence }

extension LeaveKindX on LeaveKind {
  String get label => switch (this) {
        LeaveKind.paid => 'مرخصی استحقاقی',
        LeaveKind.sick => 'مرخصی استعلاجی',
        LeaveKind.unpaid => 'مرخصی بدون حقوق',
        LeaveKind.absence => 'غیبت',
      };
}

/// «مرخصی» (Sakan SalaryMorkhasi) — [days] whole days or [hours] for hourly leave.
class Leave {
  String id;
  String employeeId;
  LeaveKind kind;
  DateTime start;
  DateTime end;
  double days;
  double hours;
  String formNo; // شماره برگه
  String note;
  Leave({
    required this.id,
    required this.employeeId,
    this.kind = LeaveKind.paid,
    required this.start,
    required this.end,
    this.days = 0,
    this.hours = 0,
    this.formNo = '',
    this.note = '',
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'kind': kind.name,
        'start': _ds(start),
        'end': _ds(end),
        'days': days,
        'hours': hours,
        'formNo': formNo,
        'note': note,
      };
  factory Leave.fromJson(Map<String, dynamic> j) => Leave(
        id: _s(j['id']),
        employeeId: _s(j['employeeId']),
        kind: LeaveKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => LeaveKind.paid),
        start: _dt(j['start']) ?? DateTime(2000),
        end: _dt(j['end']) ?? DateTime(2000),
        days: _dbl(j['days']),
        hours: _dbl(j['hours']),
        formNo: _s(j['formNo']),
        note: _s(j['note']),
      );
}

/// «ماموریت» (Sakan SalaryMamoriat).
class Mission {
  String id;
  String employeeId;
  DateTime start;
  DateTime end;
  double days;
  int amount; // حق ماموریت
  int travelCost; // هزینه سفر و فوق العاده ماموریت
  String formNo;
  String note;
  Mission({
    required this.id,
    required this.employeeId,
    required this.start,
    required this.end,
    this.days = 0,
    this.amount = 0,
    this.travelCost = 0,
    this.formNo = '',
    this.note = '',
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'start': _ds(start),
        'end': _ds(end),
        'days': days,
        'amount': amount,
        'travelCost': travelCost,
        'formNo': formNo,
        'note': note,
      };
  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        id: _s(j['id']),
        employeeId: _s(j['employeeId']),
        start: _dt(j['start']) ?? DateTime(2000),
        end: _dt(j['end']) ?? DateTime(2000),
        days: _dbl(j['days']),
        amount: _i(j['amount']),
        travelCost: _i(j['travelCost']),
        formNo: _s(j['formNo']),
        note: _s(j['note']),
      );
}

/// «وام پرسنل» (Sakan SalaryLoan) — repaid by installments in payslips.
class StaffLoan {
  String id;
  String employeeId;
  DateTime date;
  int amount;
  int installments;
  String note;

  /// Paying the loan out (from a cash box or bank).
  String? accountId;
  StaffLoan({required this.id, required this.employeeId, required this.date, this.amount = 0, this.installments = 1, this.note = '', this.accountId});

  int get installment => installments <= 0 ? amount : (amount / installments).ceil();

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'date': _ds(date),
        'amount': amount,
        'installments': installments,
        'note': note,
        'accountId': accountId,
      };
  factory StaffLoan.fromJson(Map<String, dynamic> j) => StaffLoan(
        id: _s(j['id']),
        employeeId: _s(j['employeeId']),
        date: _dt(j['date']) ?? DateTime(2000),
        amount: _i(j['amount']),
        installments: _i(j['installments'], 1),
        note: _s(j['note']),
        accountId: j['accountId'] is String && (j['accountId'] as String).isNotEmpty ? j['accountId'] as String : null,
      );
}

// ===================================================================== period & payslip

/// «دوره حقوقی».
class PayPeriod {
  String id;
  int year; // Jalali
  int month; // 1..12
  int days; // تعداد روزهای دوره
  DateTime start;
  DateTime end;
  bool closed;

  /// Voucher posted for the period («سند حقوق»).
  String? voucherId;
  PayPeriod({
    required this.id,
    required this.year,
    required this.month,
    required this.days,
    required this.start,
    required this.end,
    this.closed = false,
    this.voucherId,
  });

  String get name => '$year/${month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'month': month,
        'days': days,
        'start': _ds(start),
        'end': _ds(end),
        'closed': closed,
        'voucherId': voucherId,
      };
  factory PayPeriod.fromJson(Map<String, dynamic> j) => PayPeriod(
        id: _s(j['id']),
        year: _i(j['year']),
        month: _i(j['month']),
        days: _i(j['days'], 30),
        start: _dt(j['start']) ?? DateTime(2000),
        end: _dt(j['end']) ?? DateTime(2000),
        closed: j['closed'] == true,
        voucherId: j['voucherId'] is String && (j['voucherId'] as String).isNotEmpty ? j['voucherId'] as String : null,
      );
}

/// «کارکرد» and variable items of one employee in one period. The amounts of
/// the payslip are computed from this with [computePayslip].
class Payslip {
  String id;
  String periodId;
  String employeeId;
  double workDays; // روزهای کارکرد
  double overtimeHours; // ساعت اضافه کار
  double shortHours; // ساعت کسر کار
  double nightShiftHours;
  double eveningShiftHours;
  int shiftPay; // حق شیفت
  int bonus; // پاداش
  bool bonusInsured;
  int arrears; // پرداخت های معوقه
  int otherCash; // سایر پرداخت های نقدی
  int eydi; // عیدی
  int leaveBuyback; // بازخرید ایام مرخصی
  double leaveBuybackDays;
  int fine; // جریمه
  int advance; // مساعده
  int loanInstallment; // قسط وام (computed when 0 and a loan is open)
  List<PayItem2> extraBenefits;
  List<PayItem2> extraDeductions;
  String note;

  Payslip({
    required this.id,
    required this.periodId,
    required this.employeeId,
    this.workDays = 30,
    this.overtimeHours = 0,
    this.shortHours = 0,
    this.nightShiftHours = 0,
    this.eveningShiftHours = 0,
    this.shiftPay = 0,
    this.bonus = 0,
    this.bonusInsured = false,
    this.arrears = 0,
    this.otherCash = 0,
    this.eydi = 0,
    this.leaveBuyback = 0,
    this.leaveBuybackDays = 0,
    this.fine = 0,
    this.advance = 0,
    this.loanInstallment = 0,
    List<PayItem2>? extraBenefits,
    List<PayItem2>? extraDeductions,
    this.note = '',
  })  : extraBenefits = extraBenefits ?? [],
        extraDeductions = extraDeductions ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'periodId': periodId,
        'employeeId': employeeId,
        'workDays': workDays,
        'overtimeHours': overtimeHours,
        'shortHours': shortHours,
        'nightShiftHours': nightShiftHours,
        'eveningShiftHours': eveningShiftHours,
        'shiftPay': shiftPay,
        'bonus': bonus,
        'bonusInsured': bonusInsured,
        'arrears': arrears,
        'otherCash': otherCash,
        'eydi': eydi,
        'leaveBuyback': leaveBuyback,
        'leaveBuybackDays': leaveBuybackDays,
        'fine': fine,
        'advance': advance,
        'loanInstallment': loanInstallment,
        'extraBenefits': extraBenefits.map((e) => e.toJson()).toList(),
        'extraDeductions': extraDeductions.map((e) => e.toJson()).toList(),
        'note': note,
      };
  factory Payslip.fromJson(Map<String, dynamic> j) => Payslip(
        id: _s(j['id']),
        periodId: _s(j['periodId']),
        employeeId: _s(j['employeeId']),
        workDays: _dbl(j['workDays'], 30),
        overtimeHours: _dbl(j['overtimeHours']),
        shortHours: _dbl(j['shortHours']),
        nightShiftHours: _dbl(j['nightShiftHours']),
        eveningShiftHours: _dbl(j['eveningShiftHours']),
        shiftPay: _i(j['shiftPay']),
        bonus: _i(j['bonus']),
        bonusInsured: j['bonusInsured'] == true,
        arrears: _i(j['arrears']),
        otherCash: _i(j['otherCash']),
        eydi: _i(j['eydi']),
        leaveBuyback: _i(j['leaveBuyback']),
        leaveBuybackDays: _dbl(j['leaveBuybackDays']),
        fine: _i(j['fine']),
        advance: _i(j['advance']),
        loanInstallment: _i(j['loanInstallment']),
        extraBenefits: _list(j['extraBenefits']).map(PayItem2.fromJson).toList(),
        extraDeductions: _list(j['extraDeductions']).map(PayItem2.fromJson).toList(),
        note: _s(j['note']),
      );
}

/// The computed payslip («فیش حقوقی»), named like Sakan's SalaryFishHoghogh.
class PayResult {
  int hoghoghMahiane = 0; // حقوق ماهیانه (for the days worked)
  int dailyWage = 0; // دستمزد روزانه
  int haghSanavat = 0;
  int mazayaMostamar = 0; // مزایای مستمر
  int ezafeKari = 0;
  int kasrKar = 0;
  int haghShift = 0;
  int haghMamoriat = 0;
  int safar = 0;
  int padash = 0;
  int pardakhthayeMoavaghe = 0;
  int sayerPardakhthayeNaghdy = 0;
  int eydi = 0;
  int bazKharidMorkhasi = 0;
  int extraBenefits = 0;

  int dastmozdMashmoolBime = 0;
  int dastmozdGheirMashmoolBime = 0;
  int mashmoolMaliat = 0;

  int gheirNaghdi = 0; // مزایای غیر نقدی (در جمع حقوق هست، نقدی پرداخت نمی‌شود)
  int bimeSahmBimeShode = 0;
  int bimeSahmKarfarma = 0;
  int bimeBikari = 0;
  int bimeMashagheleSakht = 0;
  int maliat = 0;

  int vam = 0;
  int mosaede = 0;
  int jarime = 0;
  int kosoratSabet = 0;

  /// «جزییات محاسبه مالیات» (label → amount).
  final Map<String, int> taxDetail = {};

  // attendance counts (SalaryNatijeAmalkarMonth)
  double workDays = 0;
  double paidLeaveDays = 0;
  double sickLeaveDays = 0;
  double unpaidLeaveDays = 0;
  double absenceDays = 0;
  double missionDays = 0;

  int get jamMazaya =>
      haghSanavat + mazayaMostamar + ezafeKari + haghShift + haghMamoriat + safar + padash + pardakhthayeMoavaghe + sayerPardakhthayeNaghdy + eydi + bazKharidMorkhasi + extraBenefits;
  int get jamKol => hoghoghMahiane + jamMazaya - kasrKar; // جمع حقوق و مزایا
  int get jamKosorat => bimeSahmBimeShode + maliat + vam + mosaede + jarime + kosoratSabet;
  int get khales => jamKol - jamKosorat - gheirNaghdi; // مبلغ پرداختی
  int get employerCost => jamKol + bimeSahmKarfarma + bimeBikari + bimeMashagheleSakht;
}

/// Computes a payslip. [leaves] and [missions] are those of the employee in the period.
PayResult computePayslip({
  required Employee e,
  required PayPeriod period,
  required Payslip p,
  required PayrollRules rules,
  List<Leave> leaves = const [],
  List<Mission> missions = const [],
  int loanInstallment = 0,
  PaySetup setup = PaySetup.none,
  List<PayOnce> once = const [],
}) {
  final r = PayResult();
  final sal = setup[PayTableKind.salary], ins = setup[PayTableKind.insurance], taxT = setup[PayTableKind.tax];
  final sev = setup[PayTableKind.severance], exm = setup[PayTableKind.taxExemption];
  final days = period.days <= 0 ? 30 : period.days;
  for (final l in leaves) {
    switch (l.kind) {
      case LeaveKind.paid:
        r.paidLeaveDays += l.days + l.hours / 8;
      case LeaveKind.sick:
        r.sickLeaveDays += l.days;
      case LeaveKind.unpaid:
        r.unpaidLeaveDays += l.days + l.hours / 8;
      case LeaveKind.absence:
        r.absenceDays += l.days + l.hours / 8;
    }
  }
  // sick leave is paid by the insurance; unpaid leave and absence are not paid
  final paidDays = (p.workDays - r.sickLeaveDays - r.unpaidLeaveDays - r.absenceDays).clamp(0, 31).toDouble();
  r.workDays = paidDays;
  // «مرکز حقوق»: daily wage and performance coefficient
  final perf = sal == null || sal.n('perf') == 0 ? 1.0 : sal.n('perf').toDouble();
  final monthly = ((sal != null && sal.n('dailyWage') > 0 ? sal.n('dailyWage') * days : e.monthlyWage) * perf).round();
  r.dailyWage = (monthly / days).round();
  final byPeriod = sal != null && sal.t('basis') == 'بر اساس تعداد روزهای دوره';
  final ratio = byPeriod ? (p.workDays >= days ? 1.0 : p.workDays / days) : paidDays / days;
  r.hoghoghMahiane = (monthly * ratio).round();
  // «مزایای پایان خدمت»
  var sevInsured = e.sanavatInsured, sevTaxed = e.sanavatTaxed;
  if (sev != null) {
    r.haghSanavat = ((sev.n('daily') + sev.n('diffDaily')) * paidDays).round();
    sevInsured = sev.f('insured');
    sevTaxed = sev.f('taxed');
  } else {
    r.haghSanavat = (e.sanavatMonthly * ratio).round();
  }
  var benefitsInsured = 0, benefitsTaxed = 0;
  for (final b in e.benefits) {
    final v = (b.amount * ratio).round();
    r.mazayaMostamar += v;
    if (b.nonCash) r.gheirNaghdi += v;
    if (b.insured) benefitsInsured += v;
    if (b.taxed) benefitsTaxed += v;
  }
  var nonCashTaxed = 0, onceTaxed = 0;
  // «جدول مزایای نقدی مستمر»
  for (final b in setup[PayTableKind.benefit]?.items ?? const <PayTableItem>[]) {
    final v = (b.amount * ratio).round();
    r.mazayaMostamar += v;
    if (b.insured) benefitsInsured += v;
    if (b.taxed) benefitsTaxed += v;
  }
  // «جدول مزایای غیر نقدی مستمر» (مسکن، وسیله، سایر)
  for (final b in setup[PayTableKind.nonCash]?.items ?? const <PayTableItem>[]) {
    final v = (b.amount * ratio).round();
    r.mazayaMostamar += v;
    r.gheirNaghdi += v;
    if (b.insured) benefitsInsured += v;
    if (b.taxed) nonCashTaxed += (v - b.exempt).clamp(0, v).toInt();
  }
  // «مزایای غیر نقدی غیر مستمر»
  for (final o in once.where((o) => !o.exemptExpense)) {
    r.extraBenefits += o.amount;
    r.gheirNaghdi += o.amount;
    if (o.insured) benefitsInsured += o.amount;
    if (o.taxed) onceTaxed += (o.amount - o.taxCap).clamp(0, o.amount).toInt();
  }
  for (final b in p.extraBenefits) {
    r.extraBenefits += b.amount;
    if (b.nonCash) r.gheirNaghdi += b.amount;
    if (b.insured) benefitsInsured += b.amount;
    if (b.taxed) benefitsTaxed += b.amount;
  }
  final hourly = monthly / 220; // ۲۲۰ ساعت کار ماهانه (قانون کار)
  num rate(String k, num legal) => sal != null && sal.n(k) > 0 ? sal.n(k) : legal;
  r.ezafeKari = (p.overtimeHours * rate('overtimeHour', hourly * 1.4)).round();
  r.kasrKar = (p.shortHours * rate('shortHour', hourly)).round();
  r.haghShift = p.shiftPay + (p.eveningShiftHours * rate('eveningHour', hourly * 0.10)).round() + (p.nightShiftHours * rate('nightHour', hourly * 0.35)).round();
  if (sal != null && sal.n('shiftDay') > 0 && (p.eveningShiftHours > 0 || p.nightShiftHours > 0) && p.shiftPay == 0) {
    r.haghShift += (sal.n('shiftDay') * paidDays).round();
  }
  for (final m in missions) {
    r.missionDays += m.days;
    r.haghMamoriat += m.amount == 0 && sal != null ? (m.days * sal.n('missionDay')).round() : m.amount;
    r.safar += m.travelCost;
  }
  r.padash = p.bonus;
  r.pardakhthayeMoavaghe = p.arrears;
  r.sayerPardakhthayeNaghdy = p.otherCash;
  r.eydi = p.eydi;
  r.bazKharidMorkhasi = p.leaveBuyback != 0 ? p.leaveBuyback : (p.leaveBuybackDays * r.dailyWage).round();

  // بیمه: مزد، مزایای مستمر مشمول، اضافه کاری، شیفت، معوقه، پاداش (در صورت مشمول بودن)
  final otIns = sal?.f('otIns', true) ?? true, shiftIns = sal?.f('shiftIns', true) ?? true, missionIns = sal?.f('missionIns') ?? false;
  var insured = r.hoghoghMahiane + benefitsInsured + (otIns ? r.ezafeKari : 0) + (shiftIns ? r.haghShift : 0) + (missionIns ? r.haghMamoriat : 0) + r.pardakhthayeMoavaghe - r.kasrKar;
  if (sevInsured) insured += r.haghSanavat;
  if (p.bonusInsured) insured += r.padash;
  // «جدول بیمه»
  final noIns = ins != null && ins.t('type') == 'ندارد';
  final capDaily = ins != null ? ins.n('capDaily').toInt() : rules.insuranceCapDaily;
  if (capDaily > 0) {
    final insDays = ins != null && ins.t('basis') == 'بر اساس تعداد روزهای دوره' ? days : paidDays;
    final cap = (capDaily * insDays).round();
    if (insured > cap) insured = cap;
  }
  if (insured < 0 || noIns) insured = 0;
  double pct(String k, double legal) => ins == null ? legal : ins.n(k).toDouble();
  r.dastmozdMashmoolBime = insured;
  r.dastmozdGheirMashmoolBime = r.jamKol - insured;
  r.bimeSahmBimeShode = (insured * pct('worker', rules.workerPct) / 100).round();
  r.bimeSahmKarfarma = (insured * pct('employer', rules.employerPct) / 100).round();
  r.bimeBikari = (insured * pct('unemployment', rules.unemploymentPct) / 100).round();
  r.bimeMashagheleSakht = e.hardJob ? (insured * pct('hard', rules.hardPct) / 100).round() : 0;

  // مالیات: حقوق و مزایای مشمول، منهای سهم بیمه کارگر (ماده ۱۳۷)
  final otTax = sal?.f('otTax', true) ?? true, shiftTax = sal?.f('shiftTax', true) ?? true, missionTax = sal?.f('missionTax', true) ?? true;
  final eydiTaxed = rules.eydiTaxExempt > 0 && r.eydi > rules.eydiTaxExempt ? r.eydi - rules.eydiTaxExempt : 0;
  final exemptExp = e.taxExemptMonthly +
      (setup[PayTableKind.exemptExpense]?.items ?? const <PayTableItem>[]).fold<int>(0, (a, x) => a + x.amount) +
      once.where((o) => o.exemptExpense).fold<int>(0, (a, o) => a + o.amount);
  final insFree = ins == null || ins.f('taxFree', true);
  final d = r.taxDetail;
  d['ناخالص حقوق و دستمزد و مستمر نقدی (حقوق ماهانه + حق شیفت + مزایا + حق سنوات)'] = r.hoghoghMahiane + r.haghShift + r.mazayaMostamar - r.gheirNaghdi + r.haghSanavat;
  d['ناخالص اضافه کاری'] = r.ezafeKari;
  d['ناخالص اضافه کاری مشمول مالیات'] = otTax ? r.ezafeKari : 0;
  d['پرداخت مزایای مستمر غیر نقدی مشمول مالیات'] = nonCashTaxed;
  d['پرداخت مزایای غیر مستمر غیر نقدی مشمول مالیات'] = onceTaxed;
  d['پاداش موردی مشمول مالیات'] = r.padash;
  d['پرداخت های غیر مستمر نقدی معوقه مشمول مالیات'] = r.pardakhthayeMoavaghe;
  d['سایر پرداخت های غیر مستمر نقدی مشمول مالیات'] = r.sayerPardakhthayeNaghdy + (missionTax ? r.haghMamoriat : 0);
  d['بازخرید مرخصی و بازخرید سنوات مشمول مالیات'] = r.bazKharidMorkhasi + (sevTaxed ? r.haghSanavat : 0);
  d['عیدی و مزایای پایان سال'] = r.eydi;
  d['عیدی و مزایای پایان سال مشمول مالیات'] = eydiTaxed;
  d['حق بیمه پرداختی موضوع ماده 137 ق.م.م'] = insFree ? r.bimeSahmBimeShode : 0;
  d['هزینه های معاف از مالیات پرداختی توسط مودی'] = exemptExp;
  var taxable = r.hoghoghMahiane + benefitsTaxed + nonCashTaxed + onceTaxed + (otTax ? r.ezafeKari : 0) + (shiftTax ? r.haghShift : 0) + (missionTax ? r.haghMamoriat : 0) + r.padash + r.pardakhthayeMoavaghe + r.sayerPardakhthayeNaghdy + r.bazKharidMorkhasi - r.kasrKar;
  if (sevTaxed) taxable += r.haghSanavat;
  taxable += eydiTaxed;
  d['جمع حقوق مزایای مستمر و غیر مستمر نقدی و غیر نقدی عیدی و مزایای پایان سال و بازخرید مرخصی و سنوات'] = r.jamKol;
  d['جمع حقوق مزایای مستمر و غیر مستمر نقدی و غیر نقدی عیدی و مزایای پایان سال و بازخرید مرخصی و سنوات مشمول مالیات'] = taxable;
  if (insFree) taxable -= r.bimeSahmBimeShode;
  taxable -= exemptExp;
  if (taxable < 0) taxable = 0;
  r.mashmoolMaliat = taxable;
  // «مرکز مالیات» (پلکان) or the general table; «معافیت ماده ۹۱/۹۲»
  var tax = taxT != null && taxT.items.isNotEmpty ? bracketTax(taxT, taxable) : rules.tax(taxable);
  if (exm != null && exm.n('pct') > 0) {
    final off = (tax * exm.n('pct') / 100).round();
    d['معافیت مالیاتی (${exm.t('article')})'] = off;
    tax -= off;
  }
  r.maliat = tax;
  d['مشمول مالیات پس از کسر معافیت ها'] = taxable;
  d['مالیات متعلقه'] = tax;

  r.vam = p.loanInstallment != 0 ? p.loanInstallment : loanInstallment;
  r.mosaede = p.advance;
  r.jarime = p.fine + (sal == null ? 0 : (r.absenceDays * sal.n('absenceDay')).round());
  r.kosoratSabet = e.deductions.fold<int>(0, (a, x) => a + x.amount) +
      p.extraDeductions.fold<int>(0, (a, x) => a + x.amount) +
      (setup[PayTableKind.deduction]?.items ?? const <PayTableItem>[]).fold<int>(0, (a, x) => a + x.amount);
  return r;
}

String newPayrollId() => newId();

/// «جدول ساخت ذخیره مزایای پایان خدمت کارکنان»: one month of service reserve
/// (حقوق و مزایای مستمر × روزهای کارکرد ÷ ۳۶۵) — accrues a month's pay per year.
int serviceReserve(Employee e, PayResult r) => ((r.hoghoghMahiane + r.mazayaMostamar) * 30 / 365).round();
