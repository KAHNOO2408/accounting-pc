import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/payroll.dart';
import '../../data/store.dart';
import '../print.dart' show openFile, printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

// ============================================================== window

/// «حقوق و دستمزد» — Sakan's payroll in one window.
Future<void> showPayrollWindow(BuildContext context, {int tab = 0}) =>
    showDialog<void>(context: context, builder: (_) => _PayrollWindow(tab: tab));

class _PayrollWindow extends StatefulWidget {
  final int tab;
  const _PayrollWindow({this.tab = 0});

  @override
  State<_PayrollWindow> createState() => _PayrollWindowState();
}

const _tabs = ['پرسنل', 'کارکرد و فیش حقوقی', 'مرخصی', 'ماموریت', 'وام پرسنل', 'گزارشات', 'تنظیمات'];

class _PayrollWindowState extends State<_PayrollWindow> {
  late int _tab = widget.tab;

  @override
  Widget build(BuildContext context) {
    return SakanWindow(
      title: 'حقوق و دستمزد',
      width: 1240,
      height: 780,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < _tabs.length; i++)
              ChoiceChip(label: Text(_tabs[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_tab) {
              0 => const _EmployeesTab(),
              1 => const _PeriodsTab(),
              2 => const _LeavesTab(),
              3 => const _MissionsTab(),
              4 => const _LoansTab(),
              5 => const _ReportsTab(),
              _ => const _SettingsTab(),
            },
          ),
        ]),
      ),
    );
  }
}

// ============================================================== helpers

Widget _tf(TextEditingController c, String label, {double width = 180, bool ltr = false, bool money = false, ValueChanged<String>? onChanged}) => SizedBox(
      width: width,
      child: TextField(
        controller: c,
        textDirection: ltr || money ? TextDirection.ltr : null,
        inputFormatters: money ? [MoneyInputFormatter()] : null,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: onChanged,
      ),
    );

Widget _section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF345))),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children),
      ]),
    );

String _m(int v) => groupDigits(v);
String _jd(DateTime? d) => d == null ? '' : jFormat(d);

Widget _grid({required List<(String, double)> cols, required int count, required List<String> Function(int) cells, int? sel, ValueChanged<int>? onTap, ValueChanged<int>? onDouble, String empty = 'موردی وجود ندارد'}) =>
    SakanGrid(
      header: [for (final c in cols) sakanHead(c.$1, c.$2)],
      count: count,
      empty: empty,
      row: (ctx, i) {
        final on = sel == i;
        final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
        final v = cells(i);
        return InkWell(
          onTap: onTap == null ? null : () => onTap(i),
          onDoubleTap: onDouble == null ? null : () => onDouble(i),
          child: Container(
            color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
            child: Row(children: [
              for (var k = 0; k < cols.length; k++) sakanCell(Text(v[k], style: st, overflow: TextOverflow.ellipsis), cols[k].$2),
            ]),
          ),
        );
      },
    );

// ============================================================== پرسنل

class _EmployeesTab extends StatefulWidget {
  const _EmployeesTab();

  @override
  State<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<_EmployeesTab> {
  int? _sel;
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.employees.where((e) => _showInactive || e.active).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
    final sel = _sel != null && _sel! < list.length ? list[_sel!] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        sakanBtn('پرسنل جدید', () => showEmployeeDialog(context), icon: Icons.person_add_alt_1_outlined),
        sakanBtn('ویرایش', sel == null ? null : () => showEmployeeDialog(context, edit: sel), icon: Icons.edit_outlined),
        sakanBtn('حذف', sel == null
            ? null
            : () async {
                if (!await confirm(context, 'حذف پرسنل', '${sel.fullName} حذف شود؟')) return;
                final e = s.removeEmployee(sel.id);
                if (e != null && context.mounted) toast(context, e, error: true);
                setState(() => _sel = null);
              }, icon: Icons.delete_outline_rounded),
        FilterChip(label: const Text('نمایش غیرفعال‌ها'), selected: _showInactive, onSelected: (v) => setState(() => _showInactive = v)),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: _grid(
          cols: const [('کد پرسنلی', 90), ('نام', 0), ('شماره ملی', 120), ('شغل', 140), ('واحد', 110), ('حقوق ماهیانه', 130), ('شماره بیمه', 110), ('تاریخ استخدام', 100), ('وضعیت', 70)],
          count: list.length,
          sel: _sel,
          onTap: (i) => setState(() => _sel = i),
          onDouble: (i) => showEmployeeDialog(context, edit: list[i]),
          empty: 'پرسنلی تعریف نشده',
          cells: (i) {
            final e = list[i];
            return [e.personnelCode, e.fullName, e.nationalId, e.jobName, e.unit, _m(e.monthlyWage), e.insuranceNo, _jd(e.hireDate), e.active ? 'فعال' : 'غیرفعال'];
          },
        ),
      ),
    ]);
  }
}

Future<void> showEmployeeDialog(BuildContext context, {Employee? edit}) =>
    showDialog<void>(context: context, builder: (_) => _EmployeeDialog(edit: edit));

class _ItemsEditor extends StatefulWidget {
  final String title;
  final List<PayItem2> items;
  final bool flags;
  const _ItemsEditor({required this.title, required this.items, this.flags = true});

  @override
  State<_ItemsEditor> createState() => _ItemsEditorState();
}

class _ItemsEditorState extends State<_ItemsEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF345))),
        const Spacer(),
        TextButton.icon(onPressed: () => setState(() => widget.items.add(PayItem2(name: ''))), icon: const Icon(Icons.add_rounded), label: const Text('ردیف')),
      ]),
      for (final it in widget.items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: it.name,
                decoration: const InputDecoration(labelText: 'عنوان', isDense: true),
                onChanged: (v) => it.name = v.trim(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextFormField(
                initialValue: it.amount == 0 ? '' : groupDigits(it.amount),
                textDirection: TextDirection.ltr,
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'مبلغ', isDense: true),
                onChanged: (v) => it.amount = parseMoney(v),
              ),
            ),
            if (widget.flags) ...[
              Checkbox(value: it.insured, onChanged: (v) => setState(() => it.insured = v ?? true)),
              const Text('بیمه'),
              Checkbox(value: it.taxed, onChanged: (v) => setState(() => it.taxed = v ?? true)),
              const Text('مالیات'),
            ],
            IconButton(onPressed: () => setState(() => widget.items.remove(it)), icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935))),
          ]),
        ),
    ]);
  }
}

class _EmployeeDialog extends StatefulWidget {
  final Employee? edit;
  const _EmployeeDialog({this.edit});

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  final _c = <String, TextEditingController>{};
  late Employee _e;
  String? _err;
  bool _inited = false;

  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    final src = widget.edit;
    _e = src == null ? Employee(id: newId(), personId: '', personnelCode: s.nextPersonnelCode()) : Employee.fromJson(src.toJson());
    final e = _e;
    for (final (k, v) in [
      ('personnelCode', e.personnelCode), ('cardCode', e.cardCode), ('nationalId', e.nationalId), ('firstName', e.firstName),
      ('lastName', e.lastName), ('fatherName', e.fatherName), ('idNo', e.idNo), ('issuePlace', e.issuePlace),
      ('nationality', e.nationality), ('jobName', e.jobName), ('jobCode', e.jobCode), ('unit', e.unit), ('insuranceNo', e.insuranceNo),
      ('employmentType', e.employmentType), ('education', e.education), ('bankName', e.bankName), ('accountNo', e.accountNo),
      ('cardNo', e.cardNo), ('phone', e.phone), ('address', e.address),
    ]) {
      c(k).text = v;
    }
    c('children').text = e.children == 0 ? '' : '${e.children}';
    c('annualLeaveDays').text = '${e.annualLeaveDays}';
    c('monthlyWage').text = e.monthlyWage == 0 ? '' : groupDigits(e.monthlyWage);
    c('sanavat').text = e.sanavatMonthly == 0 ? '' : groupDigits(e.sanavatMonthly);
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final e = _e
      ..personnelCode = c('personnelCode').text.trim()
      ..cardCode = c('cardCode').text.trim()
      ..nationalId = normalizeDigits(c('nationalId').text.trim())
      ..firstName = c('firstName').text.trim()
      ..lastName = c('lastName').text.trim()
      ..fatherName = c('fatherName').text.trim()
      ..idNo = c('idNo').text.trim()
      ..issuePlace = c('issuePlace').text.trim()
      ..nationality = c('nationality').text.trim()
      ..jobName = c('jobName').text.trim()
      ..jobCode = c('jobCode').text.trim()
      ..unit = c('unit').text.trim()
      ..insuranceNo = c('insuranceNo').text.trim()
      ..employmentType = c('employmentType').text.trim()
      ..education = c('education').text.trim()
      ..bankName = c('bankName').text.trim()
      ..accountNo = c('accountNo').text.trim()
      ..cardNo = c('cardNo').text.trim()
      ..phone = c('phone').text.trim()
      ..address = c('address').text.trim()
      ..children = int.tryParse(normalizeDigits(c('children').text)) ?? 0
      ..annualLeaveDays = int.tryParse(normalizeDigits(c('annualLeaveDays').text)) ?? 26
      ..monthlyWage = parseMoney(c('monthlyWage').text)
      ..sanavatMonthly = parseMoney(c('sanavat').text);
    e.benefits.removeWhere((b) => b.name.isEmpty && b.amount == 0);
    e.deductions.removeWhere((b) => b.name.isEmpty && b.amount == 0);
    if (e.nationalId.isNotEmpty && e.nationalId.length != 10) return setState(() => _err = 'شماره ملی باید ۱۰ رقم باشد');
    final err = s.saveEmployee(e);
    if (err != null) return setState(() => _err = err);
    Navigator.pop(context);
  }

  Widget _date(String label, DateTime? v, ValueChanged<DateTime?> on) =>
      SizedBox(width: 200, child: DateField(label: label, value: v, clearable: true, onChanged: (d) => setState(() => on(d))));

  @override
  Widget build(BuildContext context) {
    final e = _e;
    return FormDialog(
      title: widget.edit == null ? 'پرسنل جدید' : 'پرسنل — ${widget.edit!.fullName}',
      width: 980,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _save, child: const Text('تایید')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section('مشخصات فردی', [
          _tf(c('firstName'), 'نام'),
          _tf(c('lastName'), 'نام خانوادگی'),
          _tf(c('fatherName'), 'نام پدر'),
          _tf(c('nationalId'), 'شماره ملی', ltr: true),
          _tf(c('idNo'), 'شماره شناسنامه', width: 140),
          _tf(c('issuePlace'), 'محل صدور', width: 140),
          _date('تاریخ تولد', e.birthDate, (d) => e.birthDate = d),
          _tf(c('nationality'), 'ملیت', width: 120),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('مرد')), ButtonSegment(value: false, label: Text('زن'))],
            selected: {e.male},
            onSelectionChanged: (v) => setState(() => e.male = v.first),
          ),
          FilterChip(label: const Text('متاهل'), selected: e.married, onSelected: (v) => setState(() => e.married = v)),
          _tf(c('children'), 'تعداد فرزند', width: 100, ltr: true),
          _tf(c('phone'), 'تلفن همراه', ltr: true),
          _tf(c('address'), 'نشانی', width: 380),
          _tf(c('education'), 'مدرک تحصیلی'),
        ]),
        _section('استخدام و بیمه', [
          _tf(c('personnelCode'), 'کد پرسنلی', width: 120, ltr: true),
          _tf(c('cardCode'), 'شماره کارت پرسنلی', width: 150, ltr: true),
          _tf(c('jobName'), 'نام شغل'),
          _tf(c('jobCode'), 'کد شغل (بیمه)', width: 130, ltr: true),
          _tf(c('unit'), 'واحد / بخش', width: 150),
          _tf(c('employmentType'), 'نوع استخدام', width: 150),
          _tf(c('insuranceNo'), 'شماره بیمه', width: 150, ltr: true),
          _date('تاریخ استخدام', e.hireDate, (d) => e.hireDate = d),
          _date('تاریخ انفصال', e.endDate, (d) => e.endDate = d),
          FilterChip(label: const Text('مشاغل سخت و زیان آور'), selected: e.hardJob, onSelected: (v) => setState(() => e.hardJob = v)),
          FilterChip(label: const Text('فعال'), selected: e.active, onSelected: (v) => setState(() => e.active = v)),
        ]),
        _section('حکم حقوقی', [
          _tf(c('monthlyWage'), 'حقوق ماهیانه (مزد پایه)', width: 200, money: true),
          _tf(c('sanavat'), 'حق سنوات ماهانه', width: 170, money: true),
          FilterChip(label: const Text('سنوات مشمول بیمه'), selected: e.sanavatInsured, onSelected: (v) => setState(() => e.sanavatInsured = v)),
          FilterChip(label: const Text('سنوات مشمول مالیات'), selected: e.sanavatTaxed, onSelected: (v) => setState(() => e.sanavatTaxed = v)),
          _tf(c('annualLeaveDays'), 'مرخصی استحقاقی سالانه (روز)', width: 200, ltr: true),
        ]),
        _ItemsEditor(title: 'مزایای مستمر (حق مسکن، بن، حق اولاد …)', items: e.benefits),
        const SizedBox(height: 10),
        _ItemsEditor(title: 'کسورات ثابت ماهانه', items: e.deductions, flags: false),
        const SizedBox(height: 10),
        _section('حساب بانکی', [
          _tf(c('bankName'), 'نام بانک'),
          _tf(c('accountNo'), 'شماره حساب', width: 220, ltr: true),
          _tf(c('cardNo'), 'شماره کارت', width: 220, ltr: true),
        ]),
        if (_err != null) Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    );
  }
}

// ============================================================== دوره و کارکرد

class _PeriodsTab extends StatefulWidget {
  const _PeriodsTab();

  @override
  State<_PeriodsTab> createState() => _PeriodsTabState();
}

class _PeriodsTabState extends State<_PeriodsTab> {
  String? _period;
  int? _sel;

  Future<void> _newPeriod(AppStore s) async {
    final now = Jalali.fromDateTime(DateTime.now());
    var y = now.year, m = now.month;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'دوره حقوقی جدید',
          width: 380,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ایجاد')),
          ],
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: y,
                decoration: const InputDecoration(labelText: 'سال'),
                items: [for (var i = now.year - 3; i <= now.year + 1; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                onChanged: (v) => set(() => y = v ?? y),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: m,
                decoration: const InputDecoration(labelText: 'ماه'),
                items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(jalaliMonthNames[i - 1]))],
                onChanged: (v) => set(() => m = v ?? m),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) setState(() => _period = s.addPayPeriod(y, m).id);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final periods = s.periodsSorted;
    final p = s.payPeriod(_period) ?? periods.firstOrNull;
    final emps = p == null ? <Employee>[] : s.employeesIn(p);
    final results = p == null ? <PayResult>[] : [for (final e in emps) s.payResult(p, e)];
    final sel = _sel != null && _sel! < emps.length ? emps[_sel!] : null;
    final hasVoucher = p?.voucherId != null && s.vouchers.any((v) => v.id == p!.voucherId);
    int sum(int Function(PayResult) f) => results.fold(0, (a, r) => a + f(r));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            value: p?.id,
            isDense: true,
            decoration: const InputDecoration(labelText: 'دوره حقوقی', isDense: true),
            items: [for (final x in periods) DropdownMenuItem(value: x.id, child: Text(x.name))],
            onChanged: (v) => setState(() {
              _period = v;
              _sel = null;
            }),
          ),
        ),
        sakanBtn('دوره جدید', () => _newPeriod(s), icon: Icons.add_rounded),
        sakanBtn('حذف دوره', p == null
            ? null
            : () async {
                if (!await confirm(context, 'حذف دوره', 'دوره ${p.name} و همه فیش‌های آن حذف شود؟')) return;
                final e = s.removePayPeriod(p.id);
                if (e != null && context.mounted) toast(context, e, error: true);
                setState(() => _period = null);
              }, icon: Icons.delete_outline_rounded),
        sakanBtn('افزودن پرسنل به دوره', p == null
            ? null
            : () {
                final n = s.addEmployeesToPeriod(p);
                toast(context, n == 0 ? 'همه پرسنل فعال در این دوره هستند' : '$n نفر به دوره اضافه شد');
              }, icon: Icons.group_add_outlined),
        sakanBtn('کارکرد / فیش', sel == null || p == null ? null : () => showPayslipDialog(context, p, sel), icon: Icons.edit_note_rounded),
        sakanBtn('چاپ فیش', sel == null || p == null ? null : () => printPayslip(s, p, sel), icon: Icons.print_outlined),
        sakanBtn('چاپ همه فیش‌ها', p == null || emps.isEmpty ? null : () => printPayslips(s, p, emps), icon: Icons.print_outlined),
        sakanBtn(hasVoucher ? 'صدور مجدد سند حقوق' : 'صدور سند حقوق', p == null || emps.isEmpty
            ? null
            : () {
                final v = s.postPayroll(p);
                toast(context, 'سند حقوق ${p.name} شماره ${v.number} صادر شد');
                setState(() {});
              }, icon: Icons.receipt_long_outlined, color: hasVoucher ? sakanGreen : null),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: p == null
            ? const Center(child: Text('ابتدا یک دوره حقوقی ایجاد کنید'))
            : _grid(
                cols: const [
                  ('کد', 70), ('نام پرسنل', 0), ('کارکرد', 60), ('حقوق', 110), ('مزایا', 110), ('جمع حقوق و مزایا', 120),
                  ('بیمه کارگر', 95), ('مالیات', 95), ('وام و مساعده', 100), ('سایر کسورات', 95), ('خالص پرداختی', 120),
                ],
                count: emps.length,
                sel: _sel,
                onTap: (i) => setState(() => _sel = i),
                onDouble: (i) => showPayslipDialog(context, p, emps[i]),
                empty: 'پرسنلی در این دوره نیست («افزودن پرسنل به دوره»)',
                cells: (i) {
                  final e = emps[i], r = results[i];
                  return [
                    e.personnelCode, e.fullName, fmtQty(r.workDays), _m(r.hoghoghMahiane), _m(r.jamMazaya), _m(r.jamKol),
                    _m(r.bimeSahmBimeShode), _m(r.maliat), _m(r.vam + r.mosaede), _m(r.jarime + r.kosoratSabet), _m(r.khales),
                  ];
                },
              ),
      ),
      if (p != null) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 18, children: [
          Text('جمع حقوق و مزایا: ${_m(sum((r) => r.jamKol))}'),
          Text('بیمه کارگر: ${_m(sum((r) => r.bimeSahmBimeShode))}'),
          Text('بیمه کارفرما و بیکاری: ${_m(sum((r) => r.bimeSahmKarfarma + r.bimeBikari + r.bimeMashagheleSakht))}'),
          Text('مالیات: ${_m(sum((r) => r.maliat))}'),
          Text('خالص پرداختی: ${_m(sum((r) => r.khales))}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ],
    ]);
  }
}

Future<void> showPayslipDialog(BuildContext context, PayPeriod p, Employee e) =>
    showDialog<void>(context: context, builder: (_) => _PayslipDialog(period: p, employee: e));

class _PayslipDialog extends StatefulWidget {
  final PayPeriod period;
  final Employee employee;
  const _PayslipDialog({required this.period, required this.employee});

  @override
  State<_PayslipDialog> createState() => _PayslipDialogState();
}

class _PayslipDialogState extends State<_PayslipDialog> {
  late Payslip _p;
  final _c = <String, TextEditingController>{};
  bool _inited = false;

  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);

  static const _qtyKeys = ['workDays', 'overtimeHours', 'shortHours', 'eveningShiftHours', 'nightShiftHours', 'leaveBuybackDays'];
  static const _moneyKeys = ['shiftPay', 'bonus', 'arrears', 'otherCash', 'eydi', 'leaveBuyback', 'fine', 'advance', 'loanInstallment'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    _p = Payslip.fromJson(s.payslipOf(widget.period, widget.employee).toJson());
    final j = _p.toJson();
    for (final k in _qtyKeys) {
      c(k).text = fmtQty((j[k] as num).toDouble());
    }
    for (final k in _moneyKeys) {
      final v = j[k] as int;
      c(k).text = v == 0 ? '' : groupDigits(v);
    }
    c('note').text = _p.note;
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final j = _p.toJson();
    for (final k in _qtyKeys) {
      j[k] = parseQty(c(k).text);
    }
    for (final k in _moneyKeys) {
      j[k] = parseMoney(c(k).text);
    }
    j['note'] = c('note').text.trim();
    final extraB = _p.extraBenefits, extraD = _p.extraDeductions;
    _p = Payslip.fromJson(j)
      ..extraBenefits = extraB
      ..extraDeductions = extraD;
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    _apply();
    final e = widget.employee, p = widget.period;
    final r = computePayslip(
      e: e,
      period: p,
      p: _p,
      rules: s.payrollRules,
      leaves: s.leavesIn(e, p),
      missions: s.missionsIn(e, p),
      loanInstallment: s.autoInstallment(e, p),
    );
    void ch(String _) => setState(() {});
    Widget q(String k, String label) => _tf(c(k), label, width: 150, ltr: true, onChanged: ch);
    Widget mo(String k, String label) => _tf(c(k), label, width: 170, money: true, onChanged: ch);
    Widget line(String a, int v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null))),
            Text(_m(v), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    return FormDialog(
      title: 'کارکرد و فیش حقوقی — ${e.fullName} — ${p.name}',
      width: 1100,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        OutlinedButton(onPressed: () => printPayslip(s, p, e), child: const Text('چاپ فیش')),
        FilledButton(
          onPressed: () {
            s.savePayslip(_p);
            Navigator.pop(context);
          },
          child: const Text('ذخیره'),
        ),
      ],
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _section('کارکرد', [
              q('workDays', 'روزهای کارکرد (دوره ${p.days} روز)'),
              q('overtimeHours', 'ساعت اضافه کار'),
              q('shortHours', 'ساعت کسر کار'),
              q('eveningShiftHours', 'ساعت شیفت عصر'),
              q('nightShiftHours', 'ساعت شیفت شب'),
            ]),
            _section('مزایای این ماه', [
              mo('shiftPay', 'حق شیفت (مبلغ)'),
              mo('bonus', 'پاداش'),
              FilterChip(label: const Text('پاداش مشمول بیمه'), selected: _p.bonusInsured, onSelected: (v) => setState(() => _p.bonusInsured = v)),
              mo('arrears', 'پرداخت های معوقه'),
              mo('otherCash', 'سایر پرداخت های نقدی'),
              mo('eydi', 'عیدی'),
              q('leaveBuybackDays', 'روز بازخرید مرخصی'),
              mo('leaveBuyback', 'یا مبلغ بازخرید مرخصی'),
            ]),
            _section('کسورات این ماه', [
              mo('advance', 'مساعده'),
              mo('fine', 'جریمه'),
              mo('loanInstallment', 'قسط وام (خالی = خودکار)'),
            ]),
            _ItemsEditor(title: 'سایر مزایای این ماه', items: _p.extraBenefits),
            _ItemsEditor(title: 'سایر کسورات این ماه', items: _p.extraDeductions, flags: false),
            const SizedBox(height: 8),
            TextField(controller: c('note'), decoration: const InputDecoration(labelText: 'توضیحات', isDense: true)),
            const SizedBox(height: 8),
            Text(
              'مرخصی: استحقاقی ${fmtQty(r.paidLeaveDays)}، استعلاجی ${fmtQty(r.sickLeaveDays)}، بدون حقوق ${fmtQty(r.unpaidLeaveDays)}، غیبت ${fmtQty(r.absenceDays)} — ماموریت ${fmtQty(r.missionDays)} روز (از سربرگ‌های مرخصی و ماموریت)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 330,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF3F7FC), border: Border.all(color: sakanSkyDark), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('فیش حقوقی', style: TextStyle(fontWeight: FontWeight.w800)),
              const Divider(),
              line('حقوق ماهیانه', r.hoghoghMahiane),
              line('حق سنوات', r.haghSanavat),
              line('مزایای مستمر', r.mazayaMostamar + r.extraBenefits),
              line('اضافه کاری', r.ezafeKari),
              line('حق شیفت', r.haghShift),
              line('حق ماموریت و سفر', r.haghMamoriat + r.safar),
              line('پاداش', r.padash),
              line('معوقه و سایر نقدی', r.pardakhthayeMoavaghe + r.sayerPardakhthayeNaghdy),
              line('عیدی', r.eydi),
              line('بازخرید مرخصی', r.bazKharidMorkhasi),
              line('کسر کار', -r.kasrKar),
              line('جمع حقوق و مزایا', r.jamKol, bold: true),
              const Divider(),
              line('مشمول بیمه', r.dastmozdMashmoolBime),
              line('بیمه سهم بیمه شده', r.bimeSahmBimeShode),
              line('مشمول مالیات', r.mashmoolMaliat),
              line('مالیات', r.maliat),
              line('قسط وام', r.vam),
              line('مساعده', r.mosaede),
              line('جریمه و سایر کسورات', r.jarime + r.kosoratSabet),
              line('جمع کسورات', r.jamKosorat, bold: true),
              const Divider(),
              line('خالص پرداختی', r.khales, bold: true),
              const SizedBox(height: 6),
              line('بیمه سهم کارفرما', r.bimeSahmKarfarma),
              line('بیمه بیکاری', r.bimeBikari),
              if (e.hardJob) line('مشاغل سخت', r.bimeMashagheleSakht),
            ]),
          ),
        ),
      ]),
    );
  }
}

List<(String, String)> _slipRows(AppStore s, PayPeriod p, Employee e, PayResult r) => [
      ('نام و نام خانوادگی', e.fullName),
      ('کد پرسنلی', e.personnelCode),
      ('دوره', p.name),
      ('روزهای کارکرد', fmtQty(r.workDays)),
      ('حقوق ماهیانه', _m(r.hoghoghMahiane)),
      ('حق سنوات', _m(r.haghSanavat)),
      for (final b in e.benefits) (b.name, _m(b.amount)),
      for (final b in s.payslipOf(p, e).extraBenefits) (b.name, _m(b.amount)),
      ('اضافه کاری', _m(r.ezafeKari)),
      ('حق شیفت', _m(r.haghShift)),
      ('حق ماموریت', _m(r.haghMamoriat)),
      ('هزینه سفر و فوق العاده ماموریت', _m(r.safar)),
      ('پاداش', _m(r.padash)),
      ('پرداخت های معوقه', _m(r.pardakhthayeMoavaghe)),
      ('سایر پرداخت های نقدی', _m(r.sayerPardakhthayeNaghdy)),
      ('عیدی', _m(r.eydi)),
      ('بازخرید ایام مرخصی', _m(r.bazKharidMorkhasi)),
      ('کسر کار', _m(r.kasrKar)),
      ('جمع حقوق و مزایا', _m(r.jamKol)),
      ('بیمه سهم بیمه شده', _m(r.bimeSahmBimeShode)),
      ('مالیات', _m(r.maliat)),
      ('وام', _m(r.vam)),
      ('مساعده', _m(r.mosaede)),
      ('جریمه', _m(r.jarime)),
      for (final d in e.deductions) (d.name, _m(d.amount)),
      for (final d in s.payslipOf(p, e).extraDeductions) (d.name, _m(d.amount)),
      ('جمع کسورات', _m(r.jamKosorat)),
      ('مبلغ پرداختی', _m(r.khales)),
      ('مانده وام', _m(s.loanRemaining(e) )),
    ];

void printPayslip(AppStore s, PayPeriod p, Employee e) {
  final r = s.payResult(p, e);
  printTable(
    store: s,
    title: 'فیش حقوقی ${e.fullName}',
    subtitle: 'دوره ${p.name}  —  کد پرسنلی ${e.personnelCode}',
    headers: const ['شرح', 'مبلغ / مقدار'],
    rows: [for (final x in _slipRows(s, p, e, r)) [x.$1, x.$2]],
    numeric: const {1},
    fileName: 'fish-${e.personnelCode}',
  );
}

void printPayslips(AppStore s, PayPeriod p, List<Employee> emps) {
  final rs = [for (final e in emps) s.payResult(p, e)];
  printTable(
    store: s,
    title: 'لیست حقوق و دستمزد ${p.name}',
    headers: const ['کد', 'نام', 'کارکرد', 'حقوق', 'مزایا', 'اضافه کار', 'جمع', 'بیمه', 'مالیات', 'وام', 'مساعده', 'سایر کسور', 'پرداختی'],
    rows: [
      for (var i = 0; i < emps.length; i++)
        [
          emps[i].personnelCode, emps[i].fullName, fmtQty(rs[i].workDays), _m(rs[i].hoghoghMahiane), _m(rs[i].jamMazaya - rs[i].ezafeKari),
          _m(rs[i].ezafeKari), _m(rs[i].jamKol), _m(rs[i].bimeSahmBimeShode), _m(rs[i].maliat), _m(rs[i].vam), _m(rs[i].mosaede),
          _m(rs[i].jarime + rs[i].kosoratSabet), _m(rs[i].khales),
        ],
    ],
    numeric: const {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
    footer: ['', 'جمع', '', _m(rs.fold(0, (a, r) => a + r.hoghoghMahiane)), '', '', _m(rs.fold(0, (a, r) => a + r.jamKol)),
      _m(rs.fold(0, (a, r) => a + r.bimeSahmBimeShode)), _m(rs.fold(0, (a, r) => a + r.maliat)), '', '', '', _m(rs.fold(0, (a, r) => a + r.khales))],
    fileName: 'list-hoghogh-${p.name.replaceAll('/', '-')}',
  );
}

// ============================================================== مرخصی و ماموریت

Future<String?> _pickEmployee(BuildContext context, {String? current}) async {
  final s = StoreScope.read(context);
  return showDialog<String>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'انتخاب پرسنل',
      width: 420,
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
      child: Column(children: [
        for (final e in s.activeEmployees)
          ListTile(dense: true, selected: e.id == current, title: Text(e.fullName), subtitle: Text(e.personnelCode), onTap: () => Navigator.pop(ctx, e.id)),
        if (s.activeEmployees.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('پرسنلی تعریف نشده')),
      ]),
    ),
  );
}

class _LeavesTab extends StatefulWidget {
  const _LeavesTab();

  @override
  State<_LeavesTab> createState() => _LeavesTabState();
}

class _LeavesTabState extends State<_LeavesTab> {
  int? _sel;

  Future<void> _edit(AppStore s, [Leave? l]) async {
    final empId = l?.employeeId ?? await _pickEmployee(context);
    if (empId == null || !mounted) return;
    final x = l == null ? Leave(id: newId(), employeeId: empId, start: DateTime.now(), end: DateTime.now(), days: 1) : Leave.fromJson(l.toJson());
    final days = TextEditingController(text: fmtQty(x.days));
    final hours = TextEditingController(text: x.hours == 0 ? '' : fmtQty(x.hours));
    final form = TextEditingController(text: x.formNo);
    final note = TextEditingController(text: x.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'مرخصی — ${s.employee(empId)?.fullName ?? ''}',
          width: 560,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<LeaveKind>(
                value: x.kind,
                decoration: const InputDecoration(labelText: 'نوع', isDense: true),
                items: [for (final k in LeaveKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                onChanged: (v) => set(() => x.kind = v ?? x.kind),
              ),
            ),
            _tf(form, 'شماره برگه', width: 140),
            SizedBox(width: 200, child: DateField(label: 'از تاریخ', value: x.start, onChanged: (d) => set(() => x.start = d ?? x.start))),
            SizedBox(width: 200, child: DateField(label: 'تا تاریخ', value: x.end, onChanged: (d) => set(() => x.end = d ?? x.end))),
            _tf(days, 'تعداد روز', width: 110, ltr: true),
            _tf(hours, 'یا ساعت', width: 110, ltr: true),
            _tf(note, 'توضیحات', width: 500),
          ]),
        ),
      ),
    );
    if (ok == true) {
      x
        ..days = parseQty(days.text)
        ..hours = parseQty(hours.text)
        ..formNo = form.text.trim()
        ..note = note.text.trim();
      s.saveLeave(x);
    }
    for (final t in [days, hours, form, note]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = [...s.leaves]..sort((a, b) => b.start.compareTo(a.start));
    final sel = _sel != null && _sel! < list.length ? list[_sel!] : null;
    final year = Jalali.fromDateTime(DateTime.now()).year;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, children: [
        sakanBtn('ثبت مرخصی', () => _edit(s), icon: Icons.add_rounded),
        sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
        sakanBtn('حذف', sel == null ? null : () => setState(() => s.removeLeave(sel.id)), icon: Icons.delete_outline_rounded),
        sakanBtn('مانده مرخصی $year', () {
          printTable(
            store: s,
            title: 'مانده مرخصی پرسنل سال $year',
            headers: const ['کد', 'نام', 'واحد', 'مجاز', 'استفاده شده', 'مانده'],
            rows: [
              for (final e in s.activeEmployees)
                [e.personnelCode, e.fullName, e.unit, ...() {
                  final b = s.leaveBalance(e, year);
                  return [fmtQty(b.$1), fmtQty(b.$2), fmtQty(b.$3)];
                }()],
            ],
            numeric: const {3, 4, 5},
            fileName: 'mande-morkhasi',
          );
        }, icon: Icons.print_outlined),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: _grid(
          cols: const [('پرسنل', 0), ('نوع', 150), ('برگه', 80), ('از', 100), ('تا', 100), ('روز', 60), ('ساعت', 60), ('توضیحات', 200)],
          count: list.length,
          sel: _sel,
          onTap: (i) => setState(() => _sel = i),
          onDouble: (i) => _edit(s, list[i]),
          empty: 'مرخصی ثبت نشده',
          cells: (i) {
            final l = list[i];
            return [s.employee(l.employeeId)?.fullName ?? '', l.kind.label, l.formNo, _jd(l.start), _jd(l.end), fmtQty(l.days), fmtQty(l.hours), l.note];
          },
        ),
      ),
    ]);
  }
}

class _MissionsTab extends StatefulWidget {
  const _MissionsTab();

  @override
  State<_MissionsTab> createState() => _MissionsTabState();
}

class _MissionsTabState extends State<_MissionsTab> {
  int? _sel;

  Future<void> _edit(AppStore s, [Mission? m]) async {
    final empId = m?.employeeId ?? await _pickEmployee(context);
    if (empId == null || !mounted) return;
    final x = m == null ? Mission(id: newId(), employeeId: empId, start: DateTime.now(), end: DateTime.now(), days: 1) : Mission.fromJson(m.toJson());
    final days = TextEditingController(text: fmtQty(x.days));
    final amount = TextEditingController(text: x.amount == 0 ? '' : groupDigits(x.amount));
    final travel = TextEditingController(text: x.travelCost == 0 ? '' : groupDigits(x.travelCost));
    final form = TextEditingController(text: x.formNo);
    final note = TextEditingController(text: x.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'ماموریت — ${s.employee(empId)?.fullName ?? ''}',
          width: 560,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            _tf(form, 'شماره برگه', width: 140),
            SizedBox(width: 200, child: DateField(label: 'شروع', value: x.start, onChanged: (d) => set(() => x.start = d ?? x.start))),
            SizedBox(width: 200, child: DateField(label: 'پایان', value: x.end, onChanged: (d) => set(() => x.end = d ?? x.end))),
            _tf(days, 'مدت (روز)', width: 110, ltr: true),
            _tf(amount, 'حق ماموریت', width: 160, money: true),
            _tf(travel, 'هزینه سفر', width: 160, money: true),
            _tf(note, 'شرح', width: 500),
          ]),
        ),
      ),
    );
    if (ok == true) {
      x
        ..days = parseQty(days.text)
        ..amount = parseMoney(amount.text)
        ..travelCost = parseMoney(travel.text)
        ..formNo = form.text.trim()
        ..note = note.text.trim();
      s.saveMission(x);
    }
    for (final t in [days, amount, travel, form, note]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = [...s.missions]..sort((a, b) => b.start.compareTo(a.start));
    final sel = _sel != null && _sel! < list.length ? list[_sel!] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, children: [
        sakanBtn('ثبت ماموریت', () => _edit(s), icon: Icons.add_rounded),
        sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
        sakanBtn('حذف', sel == null ? null : () => setState(() => s.removeMission(sel.id)), icon: Icons.delete_outline_rounded),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: _grid(
          cols: const [('پرسنل', 0), ('برگه', 80), ('شروع', 100), ('پایان', 100), ('روز', 60), ('حق ماموریت', 120), ('هزینه سفر', 120), ('شرح', 200)],
          count: list.length,
          sel: _sel,
          onTap: (i) => setState(() => _sel = i),
          onDouble: (i) => _edit(s, list[i]),
          empty: 'ماموریت ثبت نشده',
          cells: (i) {
            final m = list[i];
            return [s.employee(m.employeeId)?.fullName ?? '', m.formNo, _jd(m.start), _jd(m.end), fmtQty(m.days), _m(m.amount), _m(m.travelCost), m.note];
          },
        ),
      ),
    ]);
  }
}

// ============================================================== وام

class _LoansTab extends StatefulWidget {
  const _LoansTab();

  @override
  State<_LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends State<_LoansTab> {
  int? _sel;

  Future<void> _edit(AppStore s, [StaffLoan? l]) async {
    final empId = l?.employeeId ?? await _pickEmployee(context);
    if (empId == null || !mounted) return;
    final x = l == null ? StaffLoan(id: newId(), employeeId: empId, date: DateTime.now()) : StaffLoan.fromJson(l.toJson());
    final amount = TextEditingController(text: x.amount == 0 ? '' : groupDigits(x.amount));
    final n = TextEditingController(text: '${x.installments}');
    final note = TextEditingController(text: x.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'وام پرسنل — ${s.employee(empId)?.fullName ?? ''}',
          width: 560,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 200, child: DateField(label: 'تاریخ پرداخت', value: x.date, onChanged: (d) => set(() => x.date = d ?? x.date))),
            _tf(amount, 'مبلغ وام', width: 180, money: true),
            _tf(n, 'تعداد اقساط', width: 120, ltr: true),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                value: x.accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'پرداخت از (صندوق / بانک)', isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— بدون سند پرداخت —')),
                  for (final a in s.accounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => set(() => x.accountId = v),
              ),
            ),
            _tf(note, 'توضیحات', width: 500),
          ]),
        ),
      ),
    );
    if (ok == true) {
      x
        ..amount = parseMoney(amount.text)
        ..installments = int.tryParse(normalizeDigits(n.text)) ?? 1
        ..note = note.text.trim();
      s.saveStaffLoan(x);
    }
    for (final t in [amount, n, note]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = [...s.staffLoans]..sort((a, b) => b.date.compareTo(a.date));
    final sel = _sel != null && _sel! < list.length ? list[_sel!] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, children: [
        sakanBtn('وام جدید', () => _edit(s), icon: Icons.add_rounded),
        sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
        sakanBtn('حذف', sel == null ? null : () => setState(() => s.removeStaffLoan(sel.id)), icon: Icons.delete_outline_rounded),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: _grid(
          cols: const [('پرسنل', 0), ('تاریخ', 100), ('مبلغ', 130), ('اقساط', 70), ('مبلغ قسط', 120), ('مانده فعلی', 130), ('پرداخت از', 150)],
          count: list.length,
          sel: _sel,
          onTap: (i) => setState(() => _sel = i),
          onDouble: (i) => _edit(s, list[i]),
          empty: 'وامی ثبت نشده',
          cells: (i) {
            final l = list[i];
            final e = s.employee(l.employeeId);
            return [e?.fullName ?? '', _jd(l.date), _m(l.amount), '${l.installments}', _m(l.installment), e == null ? '' : _m(s.loanRemaining(e)), s.account(l.accountId)?.name ?? ''];
          },
        ),
      ),
    ]);
  }
}

// ============================================================== گزارشات

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  String? _period;

  void _xlsx(AppStore s, String name, List<String> headers, List<List<String>> rows, List<String> title) {
    final path = s.exportTableXlsx(headers, rows, name: name, titleLines: title);
    openFile(path);
    toast(context, 'فایل اکسل ذخیره شد: $path');
  }

  /// «لیست بیمه» — columns of the insurance list (DSKWOR) for the period.
  (List<String>, List<List<String>>) _insurance(AppStore s, PayPeriod p) {
    const h = ['ردیف', 'شماره بیمه', 'نام', 'نام خانوادگی', 'نام پدر', 'شماره شناسنامه', 'محل صدور', 'تاریخ تولد', 'جنسیت', 'ملیت', 'شغل', 'کد شغل',
      'تاریخ شروع', 'تاریخ ترک کار', 'روزهای کارکرد', 'دستمزد روزانه', 'دستمزد ماهانه', 'مزایای ماهانه مشمول', 'جمع دستمزد و مزایای مشمول', 'جمع کل دستمزد و مزایا',
      'حق بیمه سهم بیمه شده', 'حق بیمه سهم کارفرما', 'بیمه بیکاری', 'مشاغل سخت', 'شماره ملی'];
    final rows = <List<String>>[];
    var i = 0;
    for (final e in s.employeesIn(p)) {
      final r = s.payResult(p, e);
      i++;
      rows.add([
        '$i', e.insuranceNo, e.firstName, e.lastName, e.fatherName, e.idNo, e.issuePlace, _jd(e.birthDate), e.male ? 'مرد' : 'زن', e.nationality,
        e.jobName, e.jobCode, _jd(e.hireDate), e.endDate != null && !e.endDate!.isAfter(p.end) ? _jd(e.endDate) : '', fmtQty(r.workDays),
        _m(r.dailyWage), _m(r.hoghoghMahiane), _m(r.dastmozdMashmoolBime - r.hoghoghMahiane), _m(r.dastmozdMashmoolBime), _m(r.jamKol),
        _m(r.bimeSahmBimeShode), _m(r.bimeSahmKarfarma), _m(r.bimeBikari), _m(r.bimeMashagheleSakht), e.nationalId,
      ]);
    }
    return (h, rows);
  }

  /// «لیست مالیات حقوق».
  (List<String>, List<List<String>>) _tax(AppStore s, PayPeriod p) {
    const h = ['ردیف', 'شماره ملی', 'نام', 'نام خانوادگی', 'نام پدر', 'شغل', 'تاریخ استخدام', 'حقوق و مزایای مستمر', 'مزایای غیرمستمر', 'عیدی', 'جمع پرداختی',
      'بیمه سهم کارگر', 'مشمول مالیات', 'مالیات'];
    final rows = <List<String>>[];
    var i = 0;
    for (final e in s.employeesIn(p)) {
      final r = s.payResult(p, e);
      i++;
      final mostamar = r.hoghoghMahiane + r.mazayaMostamar + r.haghSanavat;
      rows.add([
        '$i', e.nationalId, e.firstName, e.lastName, e.fatherName, e.jobName, _jd(e.hireDate), _m(mostamar), _m(r.jamKol - mostamar - r.eydi), _m(r.eydi),
        _m(r.jamKol), _m(r.bimeSahmBimeShode), _m(r.mashmoolMaliat), _m(r.maliat),
      ]);
    }
    return (h, rows);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final periods = s.periodsSorted;
    final p = s.payPeriod(_period) ?? periods.firstOrNull;
    final w = s.workshop;
    final title = p == null ? <String>[] : ['کارگاه: ${w.name} (${w.code})  کارفرما: ${w.employer}', 'دوره ${p.name}'];
    Widget card(String t, String sub, List<Widget> btns) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: btns),
            ]),
          ),
        );
    return ListView(children: [
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String>(
          value: p?.id,
          decoration: const InputDecoration(labelText: 'دوره حقوقی', isDense: true),
          items: [for (final x in periods) DropdownMenuItem(value: x.id, child: Text(x.name))],
          onChanged: (v) => setState(() => _period = v),
        ),
      ),
      const SizedBox(height: 10),
      if (p == null) const Text('ابتدا در «کارکرد و فیش حقوقی» یک دوره ایجاد کنید'),
      if (p != null) ...[
        card('لیست حقوق و دستمزد', 'همه پرسنل دوره با جمع ستون‌ها', [
          sakanBtn('چاپ', () => printPayslips(s, p, s.employeesIn(p)), icon: Icons.print_outlined),
          sakanBtn('چاپ همه فیش‌ها (جدا)', () {
            for (final e in s.employeesIn(p)) {
              printPayslip(s, p, e);
            }
          }, icon: Icons.receipt_outlined),
        ]),
        card('لیست بیمه', 'ستون‌های لیست ماهانه تامین اجتماعی (کارگاه از سربرگ تنظیمات)', [
          sakanBtn('چاپ', () {
            final (h, rows) = _insurance(s, p);
            printTable(store: s, title: 'لیست بیمه ${p.name}', subtitle: title.join('  —  '), headers: h, rows: rows, fileName: 'list-bime');
          }, icon: Icons.print_outlined),
          sakanBtn('خروجی اکسل', () {
            final (h, rows) = _insurance(s, p);
            _xlsx(s, 'list-bime-${p.year}-${p.month}', h, rows, title);
          }, icon: Icons.table_view_outlined),
        ]),
        card('لیست مالیات حقوق', 'مبالغ پرداختی و مالیات هر نفر', [
          sakanBtn('چاپ', () {
            final (h, rows) = _tax(s, p);
            printTable(store: s, title: 'لیست مالیات حقوق ${p.name}', subtitle: title.join('  —  '), headers: h, rows: rows, fileName: 'list-maliat');
          }, icon: Icons.print_outlined),
          sakanBtn('خروجی اکسل', () {
            final (h, rows) = _tax(s, p);
            _xlsx(s, 'list-maliat-${p.year}-${p.month}', h, rows, title);
          }, icon: Icons.table_view_outlined),
        ]),
        card('بیمه سهم کارفرما', 'سهم کارفرما، بیکاری و مشاغل سخت', [
          sakanBtn('چاپ', () {
            final emps = s.employeesIn(p);
            final rs = [for (final e in emps) s.payResult(p, e)];
            printTable(
              store: s,
              title: 'گزارش بیمه سهم کارفرما ${p.name}',
              headers: const ['کد', 'نام', 'سهم کارفرما', 'بیکاری', 'مشاغل سخت', 'جمع'],
              rows: [
                for (var i = 0; i < emps.length; i++)
                  [emps[i].personnelCode, emps[i].fullName, _m(rs[i].bimeSahmKarfarma), _m(rs[i].bimeBikari), _m(rs[i].bimeMashagheleSakht),
                    _m(rs[i].bimeSahmKarfarma + rs[i].bimeBikari + rs[i].bimeMashagheleSakht)],
              ],
              numeric: const {2, 3, 4, 5},
              fileName: 'bime-karfarma',
            );
          }, icon: Icons.print_outlined),
        ]),
        card('نتیجه کارکرد ماهانه', 'روزهای حضور، مرخصی، غیبت، ماموریت و ساعات اضافه/کسر کار', [
          sakanBtn('چاپ', () {
            final emps = s.employeesIn(p);
            printTable(
              store: s,
              title: 'نتیجه کارکرد پرسنل ${p.name}',
              headers: const ['کد', 'نام', 'کارکرد', 'استحقاقی', 'استعلاجی', 'بدون حقوق', 'غیبت', 'ماموریت', 'اضافه کار', 'کسر کار'],
              rows: [
                for (final e in emps)
                  () {
                    final r = s.payResult(p, e);
                    final sl = s.payslipOf(p, e);
                    return [e.personnelCode, e.fullName, fmtQty(r.workDays), fmtQty(r.paidLeaveDays), fmtQty(r.sickLeaveDays), fmtQty(r.unpaidLeaveDays),
                      fmtQty(r.absenceDays), fmtQty(r.missionDays), fmtQty(sl.overtimeHours), fmtQty(sl.shortHours)];
                  }(),
              ],
              fileName: 'karkard',
            );
          }, icon: Icons.print_outlined),
        ]),
      ],
      card('مشخصات پرسنلی کارکنان', 'لیست کامل مشخصات و حساب بانکی', [
        sakanBtn('چاپ', () {
          printTable(
            store: s,
            title: 'مشخصات پرسنلی کارکنان',
            headers: const ['کد', 'نام', 'نام پدر', 'شماره ملی', 'تاریخ تولد', 'شغل', 'واحد', 'استخدام', 'شماره بیمه', 'بانک', 'شماره حساب', 'تلفن'],
            rows: [
              for (final e in s.activeEmployees)
                [e.personnelCode, e.fullName, e.fatherName, e.nationalId, _jd(e.birthDate), e.jobName, e.unit, _jd(e.hireDate), e.insuranceNo, e.bankName, e.accountNo, e.phone],
            ],
            fileName: 'personel',
          );
        }, icon: Icons.print_outlined),
      ]),
    ]);
  }
}

// ============================================================== تنظیمات

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _c = <String, TextEditingController>{};
  late PayrollRules _r;
  bool _inited = false;

  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    _r = PayrollRules.fromJson(s.payrollRules.toJson());
    c('worker').text = fmtQty(_r.workerPct);
    c('employer').text = fmtQty(_r.employerPct);
    c('unemp').text = fmtQty(_r.unemploymentPct);
    c('hard').text = fmtQty(_r.hardPct);
    c('cap').text = _r.insuranceCapDaily == 0 ? '' : groupDigits(_r.insuranceCapDaily);
    c('exempt').text = groupDigits(_r.taxExempt);
    c('eydi').text = _r.eydiTaxExempt == 0 ? '' : groupDigits(_r.eydiTaxExempt);
    c('label').text = _r.label;
    final w = s.workshop;
    c('wcode').text = w.code;
    c('wname').text = w.name;
    c('wemp').text = w.employer;
    c('waddr').text = w.address;
    c('woffice').text = w.insuranceOffice;
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _save(AppStore s) {
    _r
      ..workerPct = parseQty(c('worker').text)
      ..employerPct = parseQty(c('employer').text)
      ..unemploymentPct = parseQty(c('unemp').text)
      ..hardPct = parseQty(c('hard').text)
      ..insuranceCapDaily = parseMoney(c('cap').text)
      ..taxExempt = parseMoney(c('exempt').text)
      ..eydiTaxExempt = parseMoney(c('eydi').text)
      ..label = c('label').text.trim();
    _r.steps.removeWhere((x) => x.from <= 0 && x.rate <= 0);
    s.updatePayrollRules(PayrollRules.fromJson(_r.toJson()));
    s.updateWorkshop(Workshop(code: c('wcode').text.trim(), name: c('wname').text.trim(), employer: c('wemp').text.trim(), address: c('waddr').text.trim(), insuranceOffice: c('woffice').text.trim()));
    toast(context, 'تنظیمات حقوق و دستمزد ذخیره شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    return ListView(children: [
      _section('کارگاه (سربرگ لیست بیمه)', [
        _tf(c('wcode'), 'شماره کارگاه', ltr: true),
        _tf(c('wname'), 'نام کارگاه', width: 260),
        _tf(c('wemp'), 'نام کارفرما', width: 220),
        _tf(c('woffice'), 'شعبه تامین اجتماعی', width: 220),
        _tf(c('waddr'), 'آدرس کارگاه', width: 480),
      ]),
      _section('نرخ‌های بیمه (درصد)', [
        _tf(c('worker'), 'سهم بیمه شده', width: 130, ltr: true),
        _tf(c('employer'), 'سهم کارفرما', width: 130, ltr: true),
        _tf(c('unemp'), 'بیمه بیکاری', width: 130, ltr: true),
        _tf(c('hard'), 'مشاغل سخت', width: 130, ltr: true),
        _tf(c('cap'), 'سقف دستمزد روزانه مشمول بیمه (خالی = بدون سقف)', width: 340, money: true),
      ]),
      _section('مالیات حقوق (ماهانه)', [
        _tf(c('label'), 'عنوان جدول', width: 420),
        _tf(c('exempt'), 'معافیت ماهانه', width: 200, money: true),
        _tf(c('eydi'), 'سقف معافیت عیدی (خالی = عیدی معاف)', width: 260, money: true),
      ]),
      Text('پله‌های مالیات (از مبلغ ← درصد):', style: th.textTheme.titleSmall),
      for (final st in _r.steps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 200,
              child: TextFormField(
                initialValue: groupDigits(st.from),
                textDirection: TextDirection.ltr,
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'از مبلغ', isDense: true),
                onChanged: (v) => st.from = parseMoney(v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextFormField(
                initialValue: fmtQty(st.rate),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'درصد', isDense: true),
                onChanged: (v) => st.rate = parseQty(v),
              ),
            ),
            IconButton(onPressed: () => setState(() => _r.steps.remove(st)), icon: const Icon(Icons.close_rounded, color: Color(0xFFE53935))),
          ]),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(onPressed: () => setState(() => _r.steps.add(TaxStep(0, 0))), icon: const Icon(Icons.add_rounded), label: const Text('پله جدید')),
      ),
      const SizedBox(height: 6),
      Text(
        'نرخ‌ها و پله‌های پیش‌فرض مربوط به ۱۴۰۴ است؛ هر سال آنها را با بخشنامه سازمان امور مالیاتی و تامین اجتماعی تطبیق دهید. مبالغ به ${s.settings.currency} است.',
        style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.error),
      ),
      const SizedBox(height: 12),
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton(onPressed: () => _save(s), child: const Text('ذخیره تنظیمات'))),
    ]);
  }
}
