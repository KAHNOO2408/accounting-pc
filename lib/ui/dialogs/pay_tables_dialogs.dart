/// «فرم جداول پایه پرسنل»، لیست و اطلاعات هر جدول، «مزایای غیر نقدی غیر
/// مستمر»، «هزینه های غیر مستمر پرداختی معاف از مالیات توسط مودی» و «مالیات
/// بر درآمد» با «جزییات محاسبه مالیات».
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart' show newId;
import '../../data/pay_tables.dart';
import '../../data/payroll.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'cost_center_dialogs.dart' show showCostCenters;
import 'payroll_dialogs.dart' show showPayrollWindow;

/// «فرم جداول پایه پرسنل».
Future<void> showPayBaseTables(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => SakanWindow(
        title: 'فرم جداول پایه پرسنل',
        width: 640,
        height: 560,
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 4.6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  sakanBtn('معرفی پرسنل', () => showPayrollWindow(ctx, tab: 0), icon: Icons.badge_outlined, lines: 2, height: 48),
                  sakanBtn('مرکز هزینه', () => showCostCenters(ctx), icon: Icons.workspaces_outline, lines: 2, height: 48),
                  for (final k in PayTableKind.values) sakanBtn(k.label, () => showPayTables(ctx, k), icon: Icons.table_chart_outlined, lines: 2, height: 48),
                ],
              ),
            ),
            Align(alignment: AlignmentDirectional.centerEnd, child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت F10'))),
          ]),
        ),
      ),
    );

/// «لیست جداول …» of one kind.
Future<void> showPayTables(BuildContext context, PayTableKind kind) => showDialog<void>(context: context, builder: (_) => _TableList(kind));

class _TableList extends StatefulWidget {
  final PayTableKind kind;
  const _TableList(this.kind);
  @override
  State<_TableList> createState() => _TableListState();
}

class _TableListState extends State<_TableList> {
  String? _sel;

  Future<void> _edit(AppStore s, [PayTable? t]) async {
    await showPayTableForm(context, widget.kind, edit: t);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final k = widget.kind;
    final list = s.payTablesOf(k);
    final sel = list.where((t) => t.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'لیست ${k.label.replaceFirst('جدول ', 'جداول ')}',
      width: 820,
      height: 560,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            sakanBtn('افزودن', () => _edit(s), icon: Icons.add_rounded),
            sakanBtn('ویرایش', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            sakanBtn('حذف', sel == null
                ? null
                : () async {
                    if (!await confirm(context, 'حذف جدول', '«${sel.title}» حذف شود؟')) return;
                    final e = s.removePayTable(sel.id);
                    if (!context.mounted) return;
                    if (e != null) return toast(context, e, error: true);
                    setState(() => _sel = null);
                  }, icon: Icons.delete_outline),
            sakanBtn('انتخاب به عنوان پیش فرض', sel == null ? null : () => s.setDefaultPayTable(sel.id), icon: Icons.star_outline_rounded),
            sakanBtn('مشاهده لیست پرسنل استفاده شده', sel == null ? null : () => showTableUsers(context, sel), icon: Icons.people_outline),
            sakanBtn('اختصاص به پرسنل', sel == null ? null : () => _assign(s, sel), icon: Icons.assignment_ind_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد', 70), sakanHead('عنوان', 0), sakanHead('پیش فرض', 80), sakanHead('پرسنل', 80)],
              count: list.length,
              empty: 'جدولی تعریف نشده — تا وقتی جدولی نباشد «تنظیمات بیمه و مالیات» عمومی استفاده می شود',
              row: (_, i) {
                final t = list[i];
                return Material(
                  color: t.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() => _sel = t.id),
                    onDoubleTap: () => _edit(s, t),
                    child: Row(children: [
                      sakanCell(Text('${t.code}'), 70),
                      sakanCell(Text(t.title), 0, align: Alignment.centerRight),
                      sakanCell(t.isDefault ? const Icon(Icons.check_rounded, size: 18, color: Colors.green) : const SizedBox(), 80),
                      sakanCell(Text('${s.employeesUsing(t).length}'), 80),
                    ]),
                  ),
                );
              },
            ),
          ),
          Align(alignment: AlignmentDirectional.centerEnd, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت F10'))),
        ]),
      ),
    );
  }

  Future<void> _assign(AppStore s, PayTable t) async {
    final ids = await pickEmployees(context, title: 'اختصاص «${t.title}» به پرسنل', selected: {for (final e in s.employees) if (e.tables[t.kind.name] == t.id) e.id});
    if (ids == null) return;
    for (final e in s.employees.where((e) => e.tables[t.kind.name] == t.id && !ids.contains(e.id))) {
      e.tables.remove(t.kind.name);
    }
    s.assignPayTable(t.kind, t.id, ids);
    if (mounted) setState(() {});
  }
}

/// Checklist of the active personnel.
Future<Set<String>?> pickEmployees(BuildContext context, {required String title, Set<String> selected = const {}}) {
  final s = StoreScope.read(context);
  final sel = {...selected};
  final list = s.employees.where((e) => e.active).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(children: [
            Row(children: [
              TextButton(onPressed: () => set(() => sel.addAll(list.map((e) => e.id))), child: const Text('همه')),
              TextButton(onPressed: () => set(sel.clear), child: const Text('هیچ')),
            ]),
            Expanded(
              child: ListView(children: [
                for (final e in list)
                  CheckboxListTile(
                    dense: true,
                    value: sel.contains(e.id),
                    title: Text(e.fullName),
                    subtitle: Text('کد پرسنلی ${e.personnelCode}'),
                    onChanged: (v) => set(() => v == true ? sel.add(e.id) : sel.remove(e.id)),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('تایید')),
        ],
      ),
    ),
  );
}

/// «لیست پرسنل استفاده از کد جدول».
Future<void> showTableUsers(BuildContext context, PayTable t) {
  final s = StoreScope.read(context);
  final list = s.employeesUsing(t);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('لیست پرسنل استفاده از کد جدول ${t.code} — ${t.title}'),
      content: SizedBox(
        width: 420,
        child: list.isEmpty
            ? const Text('پرسنلی از این جدول استفاده نمی کند')
            : ListView(shrinkWrap: true, children: [
                for (final e in list) ListTile(dense: true, title: Text(e.fullName), subtitle: Text('کد پرسنلی ${e.personnelCode}${e.tables[t.kind.name] == null ? ' — از طریق پیش فرض' : ''}')),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت F10'))],
    ),
  );
}

// ================================================================ فرم اطلاعات جدول

Future<void> showPayTableForm(BuildContext context, PayTableKind kind, {PayTable? edit}) =>
    showDialog<void>(context: context, builder: (_) => _TableForm(kind, edit));

class _TableForm extends StatefulWidget {
  final PayTableKind kind;
  final PayTable? edit;
  const _TableForm(this.kind, this.edit);
  @override
  State<_TableForm> createState() => _TableFormState();
}

class _TableFormState extends State<_TableForm> {
  late final PayTable _t;
  final _c = <String, TextEditingController>{};
  String? _err;

  TextEditingController c(String k, [String init = '']) => _c.putIfAbsent(k, () => TextEditingController(text: init));

  @override
  void initState() {
    super.initState();
    final s = StoreScope.read(context);
    _t = widget.edit?.copy() ?? PayTable(id: newId(), kind: widget.kind, code: s.nextPayTableCode(widget.kind), title: '', v: payTableDefaults(widget.kind));
    c('code', '${_t.code}');
    c('title', _t.title);
    for (final (key, _, type) in payTableParams(widget.kind)) {
      final v = _t.v[key];
      if (type == 'money') c(key, v is num && v != 0 ? groupDigits(v.round()) : '');
      if (type == 'num') c(key, v is num ? (v == v.roundToDouble() ? '${v.round()}' : '$v') : '');
      if (type == 'text') c(key, v is String ? v : '');
    }
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
    _t
      ..code = int.tryParse(normalizeDigitsLocal(c('code').text)) ?? _t.code
      ..title = c('title').text;
    for (final (key, _, type) in payTableParams(widget.kind)) {
      switch (type) {
        case 'money':
          _t.v[key] = parseMoney(c(key).text);
        case 'num':
          _t.v[key] = double.tryParse(normalizeDigitsLocal(c(key).text)) ?? 0;
        case 'text':
          _t.v[key] = c(key).text.trim();
      }
    }
    final e = s.savePayTable(_t);
    if (e != null) return setState(() => _err = e);
    Navigator.pop(context);
  }

  Widget _param(PayParam p) {
    final (key, label, type) = p;
    if (type == 'bool') {
      return SizedBox(width: 300, child: CheckboxListTile(dense: true, value: _t.f(key), title: Text(label), onChanged: (v) => setState(() => _t.v[key] = v ?? false)));
    }
    if (type.startsWith('choice:')) {
      final opts = type.substring(7).split('|');
      return SizedBox(
        width: 300,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          value: opts.contains(_t.t(key)) ? _t.t(key) : opts.first,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => setState(() => _t.v[key] = v ?? opts.first),
        ),
      );
    }
    return SizedBox(
      width: type == 'text' ? 300 : 220,
      child: type == 'money'
          ? MoneyField(controller: c(key), label: label)
          : TextField(controller: c(key), decoration: InputDecoration(labelText: label, isDense: true), textDirection: type == 'num' ? TextDirection.ltr : null),
    );
  }

  List<(String, double)> get _cols => switch (widget.kind) {
        PayTableKind.tax => const [('از مبلغ', 150), ('تا مبلغ', 150), ('درصد', 80)],
        PayTableKind.nonCash => const [('شرح', 0), ('مبلغ', 120), ('نوع', 90), ('بیمه', 50), ('مالیات', 55), ('مبلغ معاف از مالیات', 130)],
        PayTableKind.benefit => const [('عنوان', 0), ('مبلغ', 140), ('بیمه', 50), ('مالیات', 55)],
        _ => const [('عنوان', 0), ('مبلغ', 160)],
      };

  Widget _num(PayTableItem it, int Function() get, void Function(int) set, String key, double w) => sakanCell(
      TextFormField(
        key: ValueKey('$key-${identityHashCode(it)}'),
        initialValue: get() == 0 ? '' : groupDigits(get()),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
        onChanged: (v) => set(parseMoney(v)),
      ),
      w);

  Widget _row(PayTableItem it) {
    final k = widget.kind;
    Widget text() => sakanCell(
        TextFormField(
            key: ValueKey('n-${identityHashCode(it)}'),
            initialValue: it.name,
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            onChanged: (v) => it.name = v),
        0);
    Widget chk(bool v, void Function(bool) f, double w) => sakanCell(Checkbox(value: v, onChanged: (x) => setState(() => f(x ?? false))), w);
    final cells = switch (k) {
      PayTableKind.tax => [
          _num(it, () => it.amount, (v) => it.amount = v, 'a', 150),
          _num(it, () => it.to, (v) => it.to = v, 't', 150),
          sakanCell(
              TextFormField(
                  key: ValueKey('p-${identityHashCode(it)}'),
                  initialValue: it.pct == 0 ? '' : '${it.pct}',
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  onChanged: (v) => it.pct = double.tryParse(normalizeDigitsLocal(v)) ?? 0),
              80),
        ],
      PayTableKind.nonCash => [
          text(),
          _num(it, () => it.amount, (v) => it.amount = v, 'a', 120),
          sakanCell(
              DropdownButton<String>(
                isDense: true,
                value: const ['مسکن', 'وسیله', 'سایر'].contains(it.kind) ? it.kind : 'سایر',
                items: [for (final o in const ['مسکن', 'وسیله', 'سایر']) DropdownMenuItem(value: o, child: Text(o))],
                onChanged: (v) => setState(() => it.kind = v ?? 'سایر'),
              ),
              90),
          chk(it.insured, (v) => it.insured = v, 50),
          chk(it.taxed, (v) => it.taxed = v, 55),
          _num(it, () => it.exempt, (v) => it.exempt = v, 'e', 130),
        ],
      PayTableKind.benefit => [text(), _num(it, () => it.amount, (v) => it.amount = v, 'a', 140), chk(it.insured, (v) => it.insured = v, 50), chk(it.taxed, (v) => it.taxed = v, 55)],
      _ => [text(), _num(it, () => it.amount, (v) => it.amount = v, 'a', 160)],
    };
    return Row(children: [
      ...cells,
      sakanCell(IconButton(iconSize: 18, onPressed: () => setState(() => _t.items.remove(it)), icon: const Icon(Icons.close_rounded)), 40),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    return SakanWindow(
      title: k.formTitle,
      width: 860,
      height: k.hasItems ? 640 : 600,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 120, child: TextField(controller: c('code'), textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'کد :', isDense: true))),
            SizedBox(width: 360, child: TextField(controller: c('title'), autofocus: true, decoration: InputDecoration(labelText: 'عنوان ${k.label}:', isDense: true))),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _t.isDefault,
              title: const Text('پیش فرض'),
              onChanged: (v) => setState(() => _t.isDefault = v ?? false),
            ).constrained(160),
          ]),
          const SizedBox(height: 10),
          if (payTableParams(k).isNotEmpty)
            Flexible(
              flex: k.hasItems ? 0 : 1,
              child: SingleChildScrollView(child: Wrap(spacing: 10, runSpacing: 10, children: [for (final p in payTableParams(k)) _param(p)])),
            ),
          if (k.hasItems) ...[
            Row(children: [
              Text(k == PayTableKind.tax ? 'رکورد مالیات (پلکان)' : 'ردیف ها', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              sakanBtn('افزودن', () => setState(() => _t.items.add(PayTableItem(kind: 'سایر'))), icon: Icons.add_rounded),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: SakanGrid(
                header: [for (final (h, w) in _cols) sakanHead(h, w), sakanHead('', 40)],
                count: _t.items.length,
                empty: k == PayTableKind.tax ? 'پله های مالیات را وارد کنید (پله اول با درصد صفر = معافیت)' : 'ردیفی وارد نشده',
                row: (_, i) => _row(_t.items[i]),
              ),
            ),
          ],
          if (_err != null) Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('تایید F9')),
          ]),
        ]),
      ),
    );
  }
}

extension on Widget {
  Widget constrained(double w) => SizedBox(width: w, child: this);
}

String normalizeDigitsLocal(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i = fa.indexOf(c), j = ar.indexOf(c);
    b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : c));
  }
  return b.toString().replaceAll(',', '').replaceAll('٬', '').trim();
}

// ================================================================ اقلام غیر مستمر

/// «مزایای غیر نقدی غیر مستمر» ([exempt] false) or «هزینه های غیر مستمر
/// پرداختی معاف از مالیات توسط مودی» ([exempt] true) of a period.
Future<void> showPayOnce(BuildContext context, {required bool exempt}) => showDialog<void>(context: context, builder: (_) => _Once(exempt));

class _Once extends StatefulWidget {
  final bool exempt;
  const _Once(this.exempt);
  @override
  State<_Once> createState() => _OnceState();
}

class _OnceState extends State<_Once> {
  String? _period;
  String? _sel;

  String get _title => widget.exempt ? 'هزینه های غیر مستمر پرداختی معاف از مالیات توسط مودی' : 'مزایای غیر نقدی غیر مستمر';

  Future<void> _add(AppStore s, PayPeriod p) async {
    final code = TextEditingController(text: '${s.payOnce.fold<int>(0, (a, o) => o.code > a ? o.code : a) + 1}');
    final title = TextEditingController();
    final amount = TextEditingController();
    final cap = TextEditingController();
    var insured = false, taxed = !widget.exempt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(widget.exempt ? 'هزینه معاف از مالیات' : 'اختصاص گروهی مزایای غیر نقدی غیر مستمر'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'کد:', isDense: true)),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'شرح', isDense: true)),
              MoneyField(controller: amount, label: 'مبلغ:'),
              if (!widget.exempt) ...[
                MoneyField(controller: cap, label: 'سقف معافیت مالیاتی:'),
                CheckboxListTile(dense: true, value: insured, title: const Text('بیمه'), onChanged: (v) => set(() => insured = v ?? false)),
                CheckboxListTile(dense: true, value: taxed, title: const Text('مالیات'), onChanged: (v) => set(() => taxed = v ?? true)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت F10')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پرسنل ←')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final ids = await pickEmployees(context, title: 'پرسنل', selected: {for (final e in s.employeesIn(p)) e.id});
    if (ids == null || ids.isEmpty) return;
    s.addPayOnce(
      p,
      ids,
      PayOnce(
        id: '',
        periodId: p.id,
        employeeId: '',
        code: int.tryParse(normalizeDigitsLocal(code.text)) ?? 0,
        title: title.text.trim(),
        amount: parseMoney(amount.text),
        exemptExpense: widget.exempt,
        insured: insured,
        taxed: taxed,
        taxCap: parseMoney(cap.text),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final periods = s.periodsSorted;
    final p = periods.where((x) => x.id == _period).firstOrNull ?? periods.firstOrNull;
    final list = p == null ? const <PayOnce>[] : s.payOnce.where((o) => o.periodId == p.id && o.exemptExpense == widget.exempt).toList();
    String name(String id) => s.employees.where((e) => e.id == id).firstOrNull?.fullName ?? '';
    return SakanWindow(
      title: _title,
      width: 900,
      height: 580,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('دوره: '),
            DropdownButton<String>(
              value: p?.id,
              hint: const Text('دوره حقوقی تعریف نشده'),
              items: [for (final x in periods) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setState(() => _period = v),
            ),
            sakanBtn('افزودن', p == null ? null : () => _add(s, p), icon: Icons.add_rounded),
            sakanBtn('حذف', _sel == null
                ? null
                : () => setState(() {
                      s.removePayOnce(_sel!);
                      _sel = null;
                    }), icon: Icons.delete_outline),
            sakanBtn('چاپ F12', list.isEmpty
                ? null
                : () => printTable(
                      store: s,
                      title: _title,
                      subtitle: 'دوره ${p!.name}',
                      headers: const ['ردیف', 'کد', 'پرسنل', 'شرح', 'مبلغ'],
                      numeric: const {4},
                      rows: [
                        for (var i = 0; i < list.length; i++) ['${i + 1}', '${list[i].code}', name(list[i].employeeId), list[i].title, groupDigits(list[i].amount)],
                      ],
                      fileName: 'once',
                    ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('کد', 60),
                sakanHead('پرسنل', 0),
                sakanHead('شرح', 200),
                sakanHead('مبلغ', 130),
                if (!widget.exempt) ...[sakanHead('بیمه', 50), sakanHead('مالیات', 55), sakanHead('سقف معافیت', 110)],
              ],
              count: list.length,
              row: (_, i) {
                final o = list[i];
                return Material(
                  color: o.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() => _sel = o.id),
                    child: Row(children: [
                      sakanCell(Text('${o.code}'), 60),
                      sakanCell(Text(name(o.employeeId)), 0),
                      sakanCell(Text(o.title), 200),
                      sakanCell(Text(groupDigits(o.amount)), 130),
                      if (!widget.exempt) ...[
                        sakanCell(Icon(o.insured ? Icons.check : Icons.remove, size: 16), 50),
                        sakanCell(Icon(o.taxed ? Icons.check : Icons.remove, size: 16), 55),
                        sakanCell(Text(o.taxCap == 0 ? '' : groupDigits(o.taxCap)), 110),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ مالیات بر درآمد

/// «مالیات بر درآمد»: taxable pay and tax of each employee in a period, with
/// «نمایش جزییات محاسبه».
Future<void> showIncomeTax(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _IncomeTax());

class _IncomeTax extends StatefulWidget {
  const _IncomeTax();
  @override
  State<_IncomeTax> createState() => _IncomeTaxState();
}

class _IncomeTaxState extends State<_IncomeTax> {
  String? _period;
  String? _sel;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final periods = s.periodsSorted;
    final p = periods.where((x) => x.id == _period).firstOrNull ?? periods.firstOrNull;
    final emps = p == null ? const <Employee>[] : s.employeesIn(p).where((e) => _q.isEmpty || e.fullName.contains(_q) || e.personnelCode.contains(_q)).toList();
    final res = {for (final e in emps) e.id: s.payResult(p!, e)};
    final taxable = res.values.fold<int>(0, (a, r) => a + r.mashmoolMaliat);
    final tax = res.values.fold<int>(0, (a, r) => a + r.maliat);
    final pay = res.values.fold<int>(0, (a, r) => a + r.jamKol);
    final sel = emps.where((e) => e.id == _sel).firstOrNull;
    return SakanWindow(
      title: 'اطلاعات مالیات بر درآمد حقوق',
      width: 980,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('دوره: '),
            DropdownButton<String>(
              value: p?.id,
              hint: const Text('دوره حقوقی تعریف نشده'),
              items: [for (final x in periods) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setState(() => _period = v),
            ),
            SizedBox(width: 200, child: TextField(decoration: const InputDecoration(labelText: 'فیلتر بر اساس:', isDense: true), onChanged: (v) => setState(() => _q = v.trim()))),
            sakanBtn('نمایش جزییات محاسبه', sel == null ? null : () => showTaxDetail(context, sel, res[sel.id]!), icon: Icons.calculate_outlined),
            sakanBtn('چاپ', emps.isEmpty
                ? null
                : () => printTable(
                      store: s,
                      title: 'لیست مالیات بر درآمد حقوق',
                      subtitle: 'دوره ${p!.name}',
                      headers: const ['ردیف', 'کد پرسنلی', 'نام', 'کد ملی', 'جمع حقوق و مزایا', 'مشمول مالیات', 'مالیات'],
                      numeric: const {4, 5, 6},
                      rows: [
                        for (var i = 0; i < emps.length; i++)
                          [
                            '${i + 1}',
                            emps[i].personnelCode,
                            emps[i].fullName,
                            emps[i].nationalId,
                            groupDigits(res[emps[i].id]!.jamKol),
                            groupDigits(res[emps[i].id]!.mashmoolMaliat),
                            groupDigits(res[emps[i].id]!.maliat),
                          ],
                      ],
                      footer: ['', '', 'جمع', '', groupDigits(pay), groupDigits(taxable), groupDigits(tax)],
                      fileName: 'maliat-hoghogh',
                    ), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('کد پرسنلی', 90), sakanHead('نام', 0), sakanHead('جمع حقوق و مزایا', 150), sakanHead('مشمول مالیات', 150), sakanHead('مالیات', 130)],
              count: emps.length,
              row: (_, i) {
                final e = emps[i];
                final r = res[e.id]!;
                return Material(
                  color: e.id == _sel ? const Color(0xFFDDEBFA) : Colors.white,
                  child: InkWell(
                    onTap: () => setState(() => _sel = e.id),
                    onDoubleTap: () => showTaxDetail(context, e, r),
                    child: Row(children: [
                      sakanCell(Text(e.personnelCode), 90),
                      sakanCell(Text(e.fullName), 0),
                      sakanCell(Text(groupDigits(r.jamKol)), 150),
                      sakanCell(Text(groupDigits(r.mashmoolMaliat)), 150),
                      sakanCell(Text(groupDigits(r.maliat)), 130),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 24, children: [
            Text('جمع حقوق و مزایای نقدی، غیر نقدی، عیدی و پاداش پرداختنی: ${groupDigits(pay)}'),
            Text('جمع حقوق و مزایای مشمول مالیات: ${groupDigits(taxable)}'),
            Text('جمع مالیات متعلقه: ${groupDigits(tax)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}

/// «جزییات محاسبه مالیات».
Future<void> showTaxDetail(BuildContext context, Employee e, PayResult r) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('جزییات محاسبه مالیات — ${e.fullName}'),
        content: SizedBox(
          width: 640,
          child: ListView(shrinkWrap: true, children: [
            for (final x in r.taxDetail.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('${x.key}:', style: const TextStyle(fontSize: 13))),
                  Text(groupDigits(x.value), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت F10'))],
      ),
    );
