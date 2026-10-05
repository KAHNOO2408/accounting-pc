import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../print.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

// ================================================================ اطلاعات دفتر تفصیلی بانک ها

/// «تفصیلی بانک» — the bank account form. Returns the account id.
Future<String?> showBankDialog(BuildContext context, {Account? edit}) =>
    showDialog<String>(context: context, builder: (_) => _BankDialog(edit: edit));

class _BankDialog extends StatefulWidget {
  final Account? edit;
  const _BankDialog({this.edit});

  @override
  State<_BankDialog> createState() => _BankDialogState();
}

class _BankDialogState extends State<_BankDialog> {
  final _c = <String, TextEditingController>{};
  bool _atm = false;
  bool _ask = false;
  String? _err;
  Account? _edit;
  String? _lastId;

  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _load(widget.edit);
  }

  void _load(Account? e) {
    _edit = e;
    final s = StoreScope.read(context);
    c('code').text = e?.info['code'] ?? '${s.nextTafsiliCode()}';
    c('bank').text = e?.bank ?? '';
    c('number').text = e?.number ?? '';
    c('branch').text = e?.info['branch'] ?? '';
    c('kind').text = e?.info['kind'] ?? '';
    c('phone').text = e?.info['phone'] ?? '';
    c('phone2').text = e?.info['phone2'] ?? '';
    c('fax').text = e?.info['fax'] ?? '';
    c('note').text = e?.note ?? '';
    _atm = e?.info['atm'] == '1';
    _err = null;
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  /// تایید — saves; with [next] the form is cleared for another bank («تایید و بعدی»).
  void _save({bool next = false}) {
    final s = StoreScope.read(context);
    final bank = c('bank').text.trim();
    final number = c('number').text.trim();
    if (bank.isEmpty) return setState(() => _err = 'نام بانک را وارد کنید');
    if (number.isEmpty) return setState(() => _err = 'شماره حساب بانکی را وارد کنید');
    final a = _edit ?? Account(id: newId(), name: '', type: AccountType.bank);
    final name = [c('kind').text.trim(), number, bank, c('branch').text.trim()].where((x) => x.isNotEmpty).join(' ');
    a
      ..name = name
      ..bank = bank
      ..number = number
      ..note = c('note').text.trim()
      ..info = {
        ...a.info,
        'code': c('code').text.trim(),
        'branch': c('branch').text.trim(),
        'kind': c('kind').text.trim(),
        'phone': c('phone').text.trim(),
        'phone2': c('phone2').text.trim(),
        'fax': c('fax').text.trim(),
        'atm': _atm ? '1' : '',
      }..removeWhere((_, v) => v.isEmpty);
    if (a.type == AccountType.cash) a.type = AccountType.bank;
    s.upsertAccount(a);
    _lastId = a.id;
    if (next) {
      setState(() => _load(null));
      toast(context, '«$name» ثبت شد');
    } else {
      Navigator.pop(context, a.id);
    }
  }

  Widget _f(String label, String k, {bool yellow = false, bool ltr = false, int lines = 1, bool readOnly = false}) => Row(
        crossAxisAlignment: lines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: TextField(
              controller: c(k),
              readOnly: readOnly,
              minLines: lines,
              maxLines: lines,
              textDirection: ltr ? TextDirection.ltr : null,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: readOnly ? const Color(0xFFEFEFEF) : (yellow ? const Color(0xFFFFF4B8) : Colors.white),
              ),
              onSubmitted: lines > 1 ? null : (_) => _save(),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f12): () => _save(next: true),
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context, _lastId),
      },
      child: SakanWindow(
        title: 'تفصیلی بانک',
        width: 900,
        height: 470,
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: sakanSkyDark), borderRadius: BorderRadius.circular(4)),
                child: const Text('اطلاعات دفتر تفصیلی بانک ها', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: sakanSkyDark), borderRadius: BorderRadius.circular(6)),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _f('کد حساب تفصیلی', 'code', readOnly: true, ltr: true)),
                    const SizedBox(width: 20),
                    const Spacer(),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _f('نام بانک:', 'bank', yellow: true)),
                    const SizedBox(width: 20),
                    Expanded(child: _f('شماره حساب بانکی:', 'number', yellow: true, ltr: true)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _f('نام شعبه:', 'branch', yellow: true)),
                    const SizedBox(width: 20),
                    Expanded(child: _f('نوع حساب:', 'kind', yellow: true)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _f('تلفن:', 'phone', ltr: true)),
                    const SizedBox(width: 20),
                    Expanded(child: _f('تلفن۲:', 'phone2', ltr: true)),
                  ]),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _f('فکس:', 'fax', ltr: true)),
                    const SizedBox(width: 20),
                    Expanded(child: _f('توضیحات:', 'note', lines: 3)),
                  ]),
                ]),
              ),
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              InkWell(
                onTap: () => setState(() => _atm = !_atm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: _atm, onChanged: (v) => setState(() => _atm = v ?? false)),
                  const Text('عابر بانک'),
                ]),
              ),
              const Spacer(),
              Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 200, child: sakanBtn('تایید', _save, key: 'F9', icon: Icons.check_circle_rounded, color: sakanGreen)),
                const SizedBox(height: 4),
                SizedBox(width: 200, child: sakanBtn('تایید و بعدی', () => _save(next: true), key: 'F12')),
              ]),
              const SizedBox(width: 6),
              Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 120, child: sakanBtn('انصراف', () => Navigator.pop(context, _lastId), icon: Icons.cancel_rounded, color: sakanPink)),
                InkWell(
                  onTap: () => setState(() => _ask = !_ask),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 28, height: 28, child: Checkbox(value: _ask, visualDensity: VisualDensity.compact, onChanged: (v) => setState(() => _ask = v ?? false))),
                    const Text('سوال انتخاب', style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ================================================================ واریز به بانک / برداشت بانکی / بین حسابها

enum BankOp { deposit, withdraw, between }

extension BankOpX on BankOp {
  String get title => switch (this) {
        BankOp.deposit => 'واریز به بانک',
        BankOp.withdraw => 'برداشت بانکی از کارت اعتباری',
        BankOp.between => 'دریافت پرداخت بین حسابها',
      };
  String get kind => switch (this) {
        BankOp.deposit => 'bankDeposit',
        BankOp.withdraw => 'bankWithdraw',
        BankOp.between => 'bankTransfer',
      };
  static BankOp? ofKind(String k) => BankOp.values.where((o) => o.kind == k).firstOrNull;
}

/// Opens the bank operation window; [edit] re-opens a saved document.
Future<void> showBankOpsDialog(BuildContext context, BankOp op, {Voucher? edit}) =>
    showDialog<void>(context: context, builder: (_) => _BankOps(op: op, edit: edit));

class _OpRow {
  String? to; // دریافت کننده
  String? from; // پرداخت کننده
  final amount = TextEditingController();
  final ref = TextEditingController(); // شماره حواله / شماره قبض
  final babat = TextEditingController();
  String? feeCat; // سرفصل هزینه کارمزد
  final fee = TextEditingController();

  int get a => parseMoney(amount.text);
  int get f => parseMoney(fee.text);
  bool get isEmpty => to == null && from == null && a == 0;

  Map<String, dynamic> toJson() => {
        'to': to,
        'from': from,
        'amount': a,
        'ref': ref.text.trim(),
        'babat': babat.text.trim(),
        'feeCat': feeCat,
        'fee': f,
      };

  static _OpRow fromJson(Map<String, dynamic> j) {
    final r = _OpRow()
      ..to = j['to'] as String?
      ..from = j['from'] as String?
      ..feeCat = j['feeCat'] as String?;
    final a = (j['amount'] as num?)?.toInt() ?? 0;
    final f = (j['fee'] as num?)?.toInt() ?? 0;
    r.amount.text = a == 0 ? '' : groupDigits(a);
    r.fee.text = f == 0 ? '' : groupDigits(f);
    r.ref.text = '${j['ref'] ?? ''}';
    r.babat.text = '${j['babat'] ?? ''}';
    return r;
  }

  void dispose() {
    for (final c in [amount, ref, babat, fee]) {
      c.dispose();
    }
  }
}

class _BankOps extends StatefulWidget {
  final BankOp op;
  final Voucher? edit;
  const _BankOps({required this.op, this.edit});

  @override
  State<_BankOps> createState() => _BankOpsState();
}

class _BankOpsState extends State<_BankOps> {
  final _rows = <_OpRow>[];
  final _number = TextEditingController();
  final _babat = TextEditingController();
  DateTime _date = DateTime.now();
  String _desc = '';
  String _center = 'اصلی';
  int _sel = 0;
  int _copies = 1;
  String? _err;
  bool _inited = false;

  BankOp get op => widget.op;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final s = StoreScope.read(context);
    final e = widget.edit;
    if (e != null) {
      _number.text = '${e.number}';
      _date = e.date;
      _desc = e.desc;
      _center = e.center;
      _babat.text = '${e.meta['babat'] ?? ''}';
      for (final r in (e.meta['rows'] as List? ?? const [])) {
        if (r is Map<String, dynamic>) _rows.add(_OpRow.fromJson(r));
      }
    } else {
      _number.text = '${s.nextVoucherNumber()}';
    }
    if (_rows.isEmpty) _rows.add(_OpRow());
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _number.dispose();
    _babat.dispose();
    super.dispose();
  }

  int get _total => _rows.fold(0, (a, r) => a + r.a);

  List<Account> _banks(AppStore s) => s.activeAccounts.where((a) => a.type != AccountType.cash).toList();
  List<Account> _all(AppStore s) => s.activeAccounts.toList();

  String _moeenOf(AppStore s, String id) => s.account(id)?.type == AccountType.cash ? mCash : mBank;

  // ---------------------------------------------------------------- columns

  /// (title, width, kind) — kind: to, from, amount, ref, babat, feeCat, fee.
  List<(String, double, String)> get _cols => switch (op) {
        BankOp.deposit => const [
            ('بانک دریافت کننده', 0, 'to'),
            ('حساب پرداخت کننده', 0, 'from'),
            ('مبلغ', 150, 'amount'),
            ('شماره حواله', 140, 'ref'),
            ('بابت', 180, 'babat'),
          ],
        BankOp.withdraw => const [
            ('بانک پرداخت کننده', 0, 'from'),
            ('حساب دریافت کننده', 0, 'to'),
            ('مبلغ', 150, 'amount'),
            ('شماره قبض', 130, 'ref'),
            ('سرفصل هزینه کارمزد', 170, 'feeCat'),
            ('مبلغ هزینه', 120, 'fee'),
          ],
        BankOp.between => const [
            ('حساب دریافت کننده', 0, 'to'),
            ('حساب پرداخت کننده', 0, 'from'),
            ('مبلغ', 150, 'amount'),
            ('سرفصل هزینه کارمزد', 170, 'feeCat'),
            ('مبلغ هزینه', 120, 'fee'),
            ('بابت', 160, 'babat'),
          ],
      };

  bool _bankOnly(String col) => (op == BankOp.deposit && col == 'to') || (op == BankOp.withdraw && col == 'from');

  Widget _cellOf(AppStore s, _OpRow r, String kind) {
    InputDecoration deco() => const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10));
    switch (kind) {
      case 'to' || 'from':
        final list = _bankOnly(kind) ? _banks(s) : _all(s);
        final v = kind == 'to' ? r.to : r.from;
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: list.any((a) => a.id == v) ? v : null,
            isExpanded: true,
            hint: Text(_bankOnly(kind) ? 'انتخاب بانک' : 'انتخاب حساب', style: const TextStyle(color: Colors.black38)),
            items: [for (final a in list) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))],
            onChanged: (x) => setState(() {
              if (kind == 'to') {
                r.to = x;
              } else {
                r.from = x;
              }
            }),
          ),
        );
      case 'feeCat':
        final cats = s.categoriesOf(CategoryKind.expense);
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: cats.any((c) => c.id == r.feeCat) ? r.feeCat : null,
            isExpanded: true,
            hint: const Text(';', style: TextStyle(color: Colors.black38)),
            items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
            onChanged: (x) => setState(() => r.feeCat = x),
          ),
        );
      case 'amount' || 'fee':
        return TextField(
          controller: kind == 'amount' ? r.amount : r.fee,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          inputFormatters: [_Thousands()],
          decoration: deco().copyWith(hintText: '0'),
          onChanged: (_) => setState(() {}),
        );
      case 'ref':
        return TextField(controller: r.ref, textDirection: TextDirection.ltr, textAlign: TextAlign.center, decoration: deco());
      default:
        return TextField(controller: r.babat, decoration: deco());
    }
  }

  // ---------------------------------------------------------------- actions

  void _addRow() => setState(() {
        _rows.add(_OpRow());
        _sel = _rows.length - 1;
      });

  void _removeRow() => setState(() {
        if (_rows.length <= 1) {
          _rows.first.dispose();
          _rows
            ..clear()
            ..add(_OpRow());
        } else {
          _rows.removeAt(_sel.clamp(0, _rows.length - 1)).dispose();
        }
        _sel = _sel.clamp(0, _rows.length - 1);
      });

  Future<void> _docDetails() async {
    final s = StoreScope.read(context);
    final d = TextEditingController(text: _desc);
    var center = _center;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'مشخصات سند',
          width: 480,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: d, decoration: const InputDecoration(labelText: 'شرح سند')),
            const SizedBox(height: 12),
            FieldDropdown<String>(
              label: 'مرکز اسناد',
              value: s.docCenters.contains(center) ? center : s.docCenters.first,
              items: [for (final c in s.docCenters) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => set(() => center = v ?? center),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _desc = d.text.trim();
        _center = center;
      });
    }
    d.dispose();
  }

  File _tempFile(AppStore s) => File('${s.storage.dir.path}${Storage.sep}temp-${op.kind}.json');

  void _saveTemp() {
    final s = StoreScope.read(context);
    _tempFile(s).writeAsStringSync(jsonEncode({'babat': _babat.text, 'rows': [for (final r in _rows) r.toJson()]}));
    toast(context, 'در فایل موقت ثبت شد');
  }

  void _loadTemp() {
    final s = StoreScope.read(context);
    final f = _tempFile(s);
    if (!f.existsSync()) return toast(context, 'فایل موقتی وجود ندارد', error: true);
    final j = jsonDecode(f.readAsStringSync());
    if (j is! Map) return;
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll([for (final r in (j['rows'] as List? ?? const [])) if (r is Map<String, dynamic>) _OpRow.fromJson(r)]);
      if (_rows.isEmpty) _rows.add(_OpRow());
      _babat.text = '${j['babat'] ?? ''}';
      _sel = 0;
    });
  }

  /// خواندن از فایل اکسل — CSV rows: bank (name, number or code), amount, ref, babat.
  Future<void> _fromExcel() async {
    final s = StoreScope.read(context);
    final f = await fs.openFile(acceptedTypeGroups: const [
      fs.XTypeGroup(label: 'CSV / Excel', extensions: ['csv', 'txt']),
    ]);
    if (f == null || !mounted) return;
    var added = 0;
    final text = await f.readAsString();
    for (final line in const LineSplitter().convert(text)) {
      final cells = line.split(RegExp(r'[,;\t]')).map((x) => x.replaceAll('"', '').trim()).toList();
      if (cells.length < 2) continue;
      final amount = parseMoney(cells[1]);
      if (amount <= 0) continue;
      final key = normalizeDigits(cells[0]);
      final bank = _banks(s).where((a) => a.name.contains(key) || a.number == key || a.info['code'] == key).firstOrNull;
      final r = _OpRow()
        ..to = bank?.id
        ..amount.text = groupDigits(amount);
      if (cells.length > 2) r.ref.text = cells[2];
      if (cells.length > 3) r.babat.text = cells[3];
      if (_rows.length == 1 && _rows.first.isEmpty) _rows.removeAt(0).dispose();
      _rows.add(r);
      added++;
    }
    setState(() {});
    if (mounted) toast(context, added == 0 ? 'ردیفی خوانده نشد' : '$added ردیف از فایل خوانده شد', error: added == 0);
  }

  Voucher? _save() {
    final s = StoreScope.read(context);
    final rows = _rows.where((r) => !r.isEmpty).toList();
    String? err;
    if (rows.isEmpty) err = 'حداقل یک ردیف وارد کنید';
    for (var i = 0; i < rows.length && err == null; i++) {
      final r = rows[i];
      if (r.to == null || r.from == null) err = 'ردیف ${i + 1}: حساب دریافت کننده و پرداخت کننده را انتخاب کنید';
      if (err == null && r.to == r.from) err = 'ردیف ${i + 1}: حساب دریافت کننده و پرداخت کننده یکی است';
      if (err == null && r.a <= 0) err = 'ردیف ${i + 1}: مبلغ را وارد کنید';
      if (err == null && r.f > 0 && r.feeCat == null) err = 'ردیف ${i + 1}: سرفصل هزینه کارمزد را انتخاب کنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return null;
    }
    final lines = <VoucherLine>[];
    for (final r in rows) {
      final note = r.babat.text.trim().isNotEmpty ? r.babat.text.trim() : (r.ref.text.trim().isEmpty ? op.title : '${op.title} ${r.ref.text.trim()}');
      lines.add(VoucherLine(moeen: _moeenOf(s, r.to!), tafsiliId: r.to, desc: note, debit: r.a));
      lines.add(VoucherLine(moeen: _moeenOf(s, r.from!), tafsiliId: r.from, desc: note, credit: r.a));
      if (r.f > 0) {
        lines.add(VoucherLine(moeen: mExpense, tafsiliId: r.feeCat, desc: 'کارمزد $note', debit: r.f));
        lines.add(VoucherLine(moeen: _moeenOf(s, r.from!), tafsiliId: r.from, desc: 'کارمزد $note', credit: r.f));
      }
    }
    final babat = _babat.text.trim();
    final v = widget.edit ?? Voucher(id: newId(), number: 0, fixedNumber: s.nextFixedNumber(), date: _date, kind: op.kind);
    v
      ..number = int.tryParse(normalizeDigits(_number.text.trim())) ?? s.nextVoucherNumber()
      ..date = _date
      ..desc = _desc.isNotEmpty ? _desc : (babat.isNotEmpty ? babat : '${rows.length} ردیف')
      ..center = _center
      ..kind = op.kind
      ..lines = lines
      ..meta = {'babat': babat, 'rows': [for (final r in rows) r.toJson()]};
    s.saveVoucher(v);
    return v;
  }

  void _ok() {
    final v = _save();
    if (v == null) return;
    Navigator.pop(context);
    toast(context, '${op.title} — سند ${v.number} ثبت شد');
  }

  void _print(AppStore s, Voucher v) {
    final cols = _cols;
    String cell(Map<String, dynamic> r, String k) => switch (k) {
          'to' || 'from' => s.account(r[k] as String?)?.name ?? '',
          'amount' || 'fee' => groupDigits((r[k] as num?)?.toInt() ?? 0),
          'feeCat' => s.category(r['feeCat'] as String?)?.name ?? '',
          _ => '${r[k] ?? ''}',
        };
    final rows = [
      for (final (i, r) in (v.meta['rows'] as List).cast<Map<String, dynamic>>().indexed) ['${i + 1}', for (final c in cols) cell(r, c.$3)],
    ];
    final total = rows.fold<int>(0, (a, r) => a + parseMoney(r[1 + cols.indexWhere((c) => c.$3 == 'amount')]));
    for (var k = 0; k < _copies; k++) {
      printTable(
        store: s,
        title: '${op.title} — سند ${v.number}',
        subtitle: 'تاریخ ${jFormat(v.date)}${(v.meta['babat'] ?? '') == '' ? '' : ' — بابت: ${v.meta['babat']}'}',
        headers: ['ردیف', for (final c in cols) c.$1],
        rows: rows,
        numeric: {for (var i = 0; i < cols.length; i++) if (cols[i].$3 == 'amount' || cols[i].$3 == 'fee') i + 1},
        footer: ['', for (final c in cols) c.$3 == 'amount' ? groupDigits(total) : (c.$3 == cols.first.$3 ? 'جمع' : '')],
        fileName: '${op.kind}-${v.number}${_copies > 1 ? '-${k + 1}' : ''}',
      );
    }
  }

  void _okAndPrint() {
    final s = StoreScope.read(context);
    final v = _save();
    if (v == null) return;
    Navigator.pop(context);
    try {
      _print(s, v);
    } catch (e) {
      toast(context, 'چاپ ناموفق: $e', error: true);
    }
  }

  Future<void> _printType(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy - 90, pos.dx + box.size.width, 0),
      items: const [
        PopupMenuItem(value: 'doc', child: Text('چاپ سند')),
        PopupMenuItem(value: 'receipt', child: Text('چاپ رسید')),
      ],
    );
    if (r != null && mounted) _okAndPrint();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final cols = _cols;
    final multi = op != BankOp.withdraw;
    if (_sel >= _rows.length) _sel = _rows.length - 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): _docDetails,
        const SingleActivator(LogicalKeyboardKey.f9): _ok,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.f12): _okAndPrint,
        if (multi) const SingleActivator(LogicalKeyboardKey.insert): _addRow,
      },
      child: SakanWindow(
        title: op.title,
        width: 1180,
        height: 620,
        body: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(width: 160, child: sakanBtn('مشخصات سند', _docDetails, key: 'F1')),
              const SizedBox(width: 12),
              const Text('شماره سند:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _number,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              const Text('تاریخ سند:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              SizedBox(width: 220, child: DateField(label: '', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
              const Spacer(),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const SizedBox(width: 60, child: Text('بابت:', style: TextStyle(fontWeight: FontWeight.w700))),
              Expanded(
                child: TextField(controller: _babat, decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white)),
              ),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: sakanSkyDark)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    color: const Color(0xFFEFF5FC),
                    child: Row(children: [
                      sakanHead('چاپ', 44, color: const Color(0xFFE53935), fg: Colors.white),
                      sakanHead('ردیف', 50),
                      for (final (i, c) in cols.indexed) sakanHead(c.$1, c.$2, color: i == 0 ? const Color(0xFFF8D28C) : null),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemExtent: 40,
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final sel = i == _sel;
                        return GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapDown: (_) {
                            if (_sel != i) setState(() => _sel = i);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: i.isOdd ? const Color(0xFFF6FAFE) : Colors.white,
                              border: const Border(bottom: BorderSide(color: Colors.black12)),
                            ),
                            child: Row(children: [
                              sakanCell(Icon(sel ? Icons.arrow_left_rounded : null, color: sakanSel), 44),
                              sakanCell(Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)), 50),
                              for (final (k, c) in cols.indexed)
                                sakanCell(
                                  Container(
                                    color: k == 0 && sel ? const Color(0xFFDCE7FB) : null,
                                    child: _cellOf(s, r, c.$3),
                                  ),
                                  c.$2,
                                  align: Alignment.centerRight,
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              if (multi) ...[
                SizedBox(width: 150, child: sakanBtn('افزودن ردیف', _addRow, icon: Icons.star_rounded)),
                const SizedBox(width: 6),
              ],
              SizedBox(width: 150, child: sakanBtn('حذف ردیف', _removeRow, icon: Icons.close_rounded)),
              if (op == BankOp.deposit) ...[
                const SizedBox(width: 6),
                SizedBox(width: 180, child: sakanBtn('خواندن از فایل اکسل', _fromExcel)),
              ],
              const Spacer(),
              Container(
                width: 360,
                height: 36,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
                child: Text(groupDigits(_total), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w700))),
            const SizedBox(height: 10),
            Row(children: [
              if (op == BankOp.deposit) ...[
                SizedBox(width: 190, child: sakanBtn('ثبت در فایل موقت', _saveTemp, height: 42)),
                const SizedBox(width: 6),
                SizedBox(width: 190, child: sakanBtn('خواندن از فایل موقت', _loadTemp, height: 42)),
              ],
              const Spacer(),
              if (op != BankOp.withdraw) ...[
                Builder(
                  builder: (b) => SizedBox(
                    width: 170,
                    child: sakanBtn('تعیین نوع چاپ', () => _printType(b), key: op == BankOp.between ? 'F12' : '', height: 42, icon: Icons.arrow_drop_down),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(width: 160, child: sakanBtn('تایید و چاپ', _okAndPrint, height: 42, icon: Icons.print_outlined)),
                const SizedBox(width: 4),
                Container(
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 60, child: Text('$_copies', textAlign: TextAlign.center)),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      InkWell(onTap: () => setState(() => _copies++), child: const Icon(Icons.arrow_drop_up, size: 18)),
                      InkWell(onTap: () => setState(() => _copies = _copies > 1 ? _copies - 1 : 1), child: const Icon(Icons.arrow_drop_down, size: 18)),
                    ]),
                  ]),
                ),
              ] else
                SizedBox(width: 200, child: sakanBtn('تایید و چاپ', _okAndPrint, key: 'F12', icon: Icons.print_outlined, height: 42)),
              const SizedBox(width: 8),
              SizedBox(width: 160, child: sakanBtn('تایید', _ok, key: 'F9', icon: Icons.check_circle_rounded, color: sakanGreen, height: 42)),
              const SizedBox(width: 8),
              SizedBox(width: 150, child: sakanBtn('انصراف', () => Navigator.pop(context), key: 'F10', icon: Icons.cancel_rounded, color: sakanPink, height: 42)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Thousands extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = normalizeDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final t = groupDigits(int.parse(digits));
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
