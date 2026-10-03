import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showVoucherDialog(BuildContext context, {Voucher? edit}) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VoucherDialog(edit: edit),
    );

/// Detail options (تفصیلی) for a ledger.
List<(String, String)> tafsiliOptions(AppStore store, Moeen m) => switch (m.kind) {
      TafsiliKind.cash => [
          for (final a in store.accounts.where((a) => a.type == AccountType.cash)) (a.id, a.name),
        ],
      TafsiliKind.bank => [
          for (final a in store.accounts.where((a) => a.type != AccountType.cash)) (a.id, a.name),
        ],
      TafsiliKind.person => [for (final p in store.peopleSorted) (p.id, p.name)],
      TafsiliKind.product => [for (final p in store.productsSorted) (p.id, p.name)],
      TafsiliKind.incomeCat => [for (final c in store.categoriesOf(CategoryKind.income)) (c.id, c.name)],
      TafsiliKind.expenseCat => [for (final c in store.categoriesOf(CategoryKind.expense)) (c.id, c.name)],
      TafsiliKind.none => const [],
    };

class VoucherDialog extends StatefulWidget {
  final Voucher? edit;
  const VoucherDialog({super.key, this.edit});

  @override
  State<VoucherDialog> createState() => _VoucherDialogState();
}

class _VoucherDialogState extends State<VoucherDialog> {
  final List<VoucherLine> _lines = [];
  int? _sel;
  final _desc = TextEditingController();
  final _number = TextEditingController();
  final _fixed = TextEditingController();
  final _archive = TextEditingController();
  final _followDesc = TextEditingController();
  String _center = 'اصلی';
  late DateTime _date;
  DateTime? _followDate;
  bool _inited = false;

  bool get _isEdit => widget.edit != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final store = StoreScope.read(context);
    final e = widget.edit;
    if (e != null) {
      _lines.addAll(e.lines.map((l) => l.copy()));
      _desc.text = e.desc;
      _number.text = '${e.number}';
      _fixed.text = '${e.fixedNumber}';
      _archive.text = e.archivePath;
      _followDesc.text = e.followDesc;
      _center = e.center;
      _date = e.date;
      _followDate = e.followDate;
    } else {
      _number.text = '${store.nextVoucherNumber()}';
      _fixed.text = '${store.nextFixedNumber()}';
      _date = dateOnly(DateTime.now());
    }
  }

  @override
  void dispose() {
    for (final c in [_desc, _number, _fixed, _archive, _followDesc]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _dr => _lines.fold(0, (s, l) => s + l.debit);
  int get _cr => _lines.fold(0, (s, l) => s + l.credit);

  File _tempFile(AppStore store) => File('${store.storage.dir.path}${Storage.sep}voucher_draft.json');

  Map<String, dynamic> _draftJson() => {
        'desc': _desc.text,
        'archive': _archive.text,
        'followDesc': _followDesc.text,
        'date': _date.toIso8601String(),
        'lines': _lines.map((l) => l.toJson()).toList(),
      };

  Future<void> _addOrEdit({int? index}) async {
    final r = await showDialog<VoucherLine>(
      context: context,
      builder: (_) => _LineDialog(
        initial: index == null ? null : _lines[index],
        suggestDebit: _cr - _dr,
        lastDesc: _lines.isEmpty ? _desc.text : _lines.last.desc,
      ),
    );
    if (r == null) return;
    setState(() {
      if (index == null) {
        _lines.add(r);
        _sel = _lines.length - 1;
      } else {
        _lines[index] = r;
      }
    });
  }

  void _removeSel() {
    if (_sel == null || _sel! >= _lines.length) return;
    setState(() {
      _lines.removeAt(_sel!);
      _sel = null;
    });
  }

  String? _validate() {
    if (_lines.isEmpty) return 'سند هیچ ردیفی ندارد';
    if (_dr == 0) return 'جمع مبالغ سند صفر است';
    if (_dr != _cr) return 'سند تراز نیست؛ اختلاف بدهکار و بستانکار ${groupDigits((_dr - _cr).abs())}';
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      final m = findMoeen(l.moeen);
      if (m == null) return 'ردیف ${i + 1}: حساب معین مشخص نیست';
      if (m.hasEntity && l.tafsiliId == null && m.kind != TafsiliKind.incomeCat && m.kind != TafsiliKind.expenseCat) {
        return 'ردیف ${i + 1}: حساب تفصیلی «${m.name}» را انتخاب کنید';
      }
    }
    return null;
  }

  void _check() {
    final err = _validate();
    if (err == null) {
      toast(context, 'سند تراز و قابل ثبت است');
    } else {
      toast(context, err, error: true);
    }
  }

  void _save() {
    final err = _validate();
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    final store = StoreScope.read(context);
    final v = widget.edit ??
        Voucher(id: newId(), number: 0, fixedNumber: 0, date: _date);
    v
      ..number = int.tryParse(normalizeDigits(_number.text.trim())) ?? store.nextVoucherNumber()
      ..fixedNumber = int.tryParse(normalizeDigits(_fixed.text.trim())) ?? store.nextFixedNumber()
      ..date = _date
      ..desc = _desc.text.trim()
      ..center = _center
      ..archivePath = _archive.text.trim()
      ..followDate = _followDate
      ..followDesc = _followDesc.text.trim()
      ..lines = _lines.map((l) => l.copy()).toList();
    store.saveVoucher(v);
    Navigator.pop(context);
    toast(context, 'سند شماره ${v.number} ثبت شد');
  }

  Future<void> _close() async {
    if (_lines.isNotEmpty && !_isEdit) {
      final ok = await confirm(context, 'خروج', 'سند ثبت نشده است. بدون ثبت خارج می‌شوید؟', ok: 'خروج');
      if (!ok || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final nums = store.vouchers.map((v) => v.number).toList()..sort();
    final range = nums.isEmpty ? 'هنوز سندی ثبت نشده' : 'از شماره ${nums.first} تا شماره ${nums.last}';
    final diff = _dr - _cr;

    Widget head(String t, {double? w, bool end = false}) => SizedBox(
          width: w,
          child: Text(t, textAlign: end ? TextAlign.left : TextAlign.start),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.insert): () => _addOrEdit(),
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: size.width > 1240 ? 1200 : size.width - 40,
          height: size.height * 0.92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderBand(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(children: [
                  Text(_isEdit ? 'ویرایش سند حسابداری' : 'ثبت سند',
                      style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  const Spacer(),
                  IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(),
              // ------------------------------------------------------- grid
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      border: Border.all(color: th.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          color: th.colorScheme.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: DefaultTextStyle(
                            style: th.textTheme.labelMedium!.copyWith(color: th.hintColor, fontWeight: FontWeight.w700),
                            child: Row(children: [
                              head('ردیف', w: 50),
                              head('کل', w: 150),
                              head('معین', w: 180),
                              head('تفصیلی', w: 170),
                              const Expanded(child: Text('شرح')),
                              head('بدهکار', w: 140, end: true),
                              head('بستانکار', w: 140, end: true),
                            ]),
                          ),
                        ),
                        Expanded(
                          child: _lines.isEmpty
                              ? Center(
                                  child: Text('برای افزودن ردیف «افزودن ردیف» یا کلید Insert را بزنید',
                                      style: TextStyle(color: th.hintColor)),
                                )
                              : ListView.builder(
                                  itemCount: _lines.length,
                                  itemBuilder: (context, i) {
                                    final l = _lines[i];
                                    final m = findMoeen(l.moeen);
                                    final sel = i == _sel;
                                    return InkWell(
                                      onTap: () => setState(() => _sel = i),
                                      onDoubleTap: () => _addOrEdit(index: i),
                                      child: Container(
                                        color: sel ? th.colorScheme.primary.withValues(alpha: 0.10) : (i.isOdd ? th.colorScheme.surfaceContainerLow.withValues(alpha: 0.5) : null),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                        child: Row(children: [
                                          SizedBox(width: 50, child: Text('${i + 1}')),
                                          SizedBox(width: 150, child: Text(m?.kol.name ?? '', overflow: TextOverflow.ellipsis)),
                                          SizedBox(width: 180, child: Text(m?.name ?? '', overflow: TextOverflow.ellipsis)),
                                          SizedBox(width: 170, child: Text(store.tafsiliName(l), overflow: TextOverflow.ellipsis)),
                                          Expanded(child: Text(l.desc, overflow: TextOverflow.ellipsis)),
                                          SizedBox(
                                            width: 140,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: l.debit == 0 ? const Text('') : Money(l.debit, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 140,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: l.credit == 0 ? const Text('') : Money(l.credit, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            ),
                                          ),
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
              // ---------------------------------------------- totals & row buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('افزودن ردیف'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _sel == null ? null : () => _addOrEdit(index: _sel),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('ویرایش'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _sel == null ? null : _removeSel,
                    icon: Icon(Icons.close_rounded, size: 18, color: th.colorScheme.error),
                    label: const Text('حذف ردیف'),
                  ),
                  const Spacer(),
                  _total(th, 'جمع بدهکاری', _dr, null),
                  const SizedBox(width: 18),
                  _total(th, 'جمع بستانکاری', _cr, null),
                  const SizedBox(width: 18),
                  _total(th, 'اختلاف بدهکاری و بستانکاری', diff.abs(), diff == 0 ? AppColors.income : th.colorScheme.error),
                ]),
              ),
              // --------------------------------------------------- header fields
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح سند')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _number,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'شماره سند'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _fixed,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'شماره ثابت'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FieldDropdown<String>(
                        label: 'مرکز اسناد',
                        value: _center,
                        items: [
                          for (final c in {...store.docCenters, _center}) DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() => _center = v ?? _center),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(range, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: TextField(controller: _archive, decoration: const InputDecoration(labelText: 'مسیر بایگانی'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DateField(
                        label: 'تاریخ پیگرد',
                        value: _followDate,
                        clearable: true,
                        onChanged: (d) => setState(() => _followDate = d),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: TextField(controller: _followDesc, decoration: const InputDecoration(labelText: 'شرح پیگرد'))),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(children: [
                  OutlinedButton(
                    onPressed: () {
                      try {
                        _tempFile(store).writeAsStringSync(jsonEncode(_draftJson()));
                        toast(context, 'سند در فایل موقت ذخیره شد');
                      } catch (e) {
                        toast(context, 'خطا: $e', error: true);
                      }
                    },
                    child: const Text('ثبت در فایل موقت'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      try {
                        final f = _tempFile(store);
                        if (!f.existsSync()) {
                          toast(context, 'فایل موقتی وجود ندارد', error: true);
                          return;
                        }
                        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
                        setState(() {
                          _desc.text = '${j['desc'] ?? ''}';
                          _archive.text = '${j['archive'] ?? ''}';
                          _followDesc.text = '${j['followDesc'] ?? ''}';
                          final d = DateTime.tryParse('${j['date']}');
                          if (d != null) _date = dateOnly(d);
                          _lines
                            ..clear()
                            ..addAll((j['lines'] as List).whereType<Map<String, dynamic>>().map(VoucherLine.fromJson));
                          _sel = null;
                        });
                        toast(context, 'فایل موقت خوانده شد');
                      } catch (e) {
                        toast(context, 'خطا در خواندن فایل موقت: $e', error: true);
                      }
                    },
                    child: const Text('خواندن فایل موقت'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _check, child: const Text('چک')),
                  const Spacer(),
                  if (_isEdit) ...[
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await confirm(context, 'حذف سند', 'این سند حذف شود؟');
                        if (!ok || !mounted) return;
                        StoreScope.read(context).removeVoucher(widget.edit!.id);
                        if (mounted) Navigator.pop(context);
                      },
                      icon: Icon(Icons.delete_outline, color: th.colorScheme.error),
                      label: Text('حذف سند', style: TextStyle(color: th.colorScheme.error)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('ثبت (F9)'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _close,
                    icon: Icon(Icons.close_rounded, size: 18, color: th.colorScheme.error),
                    label: const Text('خروج'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _total(ThemeData th, String label, int v, Color? c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: th.textTheme.bodySmall),
          Container(
            constraints: const BoxConstraints(minWidth: 110),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: th.colorScheme.surfaceContainerLow,
              border: Border.all(color: th.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Money(v, style: TextStyle(fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      );
}

// ======================================================================== row

class _LineDialog extends StatefulWidget {
  final VoucherLine? initial;
  final int suggestDebit;
  final String lastDesc;
  const _LineDialog({this.initial, required this.suggestDebit, required this.lastDesc});

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  String? _kol;
  String? _moeen;
  String? _tafsili;
  final _desc = TextEditingController();
  final _debit = TextEditingController();
  final _credit = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    if (l != null) {
      _moeen = l.moeen;
      _kol = findMoeen(l.moeen)?.kolCode;
      _tafsili = l.tafsiliId;
      _desc.text = l.desc;
      if (l.debit > 0) _debit.text = groupDigits(l.debit);
      if (l.credit > 0) _credit.text = groupDigits(l.credit);
    } else {
      _desc.text = widget.lastDesc;
      // pre-fill the balancing amount
      if (widget.suggestDebit > 0) _debit.text = groupDigits(widget.suggestDebit);
      if (widget.suggestDebit < 0) _credit.text = groupDigits(-widget.suggestDebit);
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _debit.dispose();
    _credit.dispose();
    super.dispose();
  }

  void _ok() {
    final d = parseMoney(_debit.text);
    final c = parseMoney(_credit.text);
    final m = findMoeen(_moeen);
    String? err;
    if (m == null) {
      err = 'حساب کل و معین را انتخاب کنید';
    } else if (d > 0 && c > 0) {
      err = 'هر ردیف فقط بدهکار یا فقط بستانکار است';
    } else if (d == 0 && c == 0) {
      err = 'مبلغ بدهکار یا بستانکار را وارد کنید';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    Navigator.pop(
      context,
      VoucherLine(moeen: _moeen!, tafsiliId: m!.hasEntity ? _tafsili : null, desc: _desc.text.trim(), debit: d, credit: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final kol = _kol == null ? null : chart.firstWhere((k) => k.code == _kol);
    final m = findMoeen(_moeen);
    final opts = m == null ? const <(String, String)>[] : tafsiliOptions(store, m);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _ok},
      child: FormDialog(
        title: widget.initial == null ? 'افزودن ردیف' : 'ویرایش ردیف',
        width: 620,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: _ok, child: const Text('تایید')),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: FieldDropdown<String?>(
                  label: 'حساب کل',
                  value: _kol,
                  items: [for (final k in chart) DropdownMenuItem<String?>(value: k.code, child: Text('${k.code}  ${k.name}'))],
                  onChanged: (v) => setState(() {
                    _kol = v;
                    _moeen = null;
                    _tafsili = null;
                    final k = chart.firstWhere((k) => k.code == v);
                    if (k.ledgers.length == 1) _moeen = k.ledgers.first.code;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldDropdown<String?>(
                  label: 'حساب معین',
                  value: _moeen,
                  items: [
                    if (kol != null)
                      for (final x in kol.ledgers) DropdownMenuItem<String?>(value: x.code, child: Text('${x.code}  ${x.name}')),
                  ],
                  onChanged: (v) => setState(() {
                    _moeen = v;
                    _tafsili = null;
                  }),
                ),
              ),
            ]),
            if (m != null && m.hasEntity) ...[
              const SizedBox(height: 12),
              FieldDropdown<String?>(
                label: 'حساب تفصیلی',
                value: _tafsili,
                items: [
                  if (m.kind == TafsiliKind.incomeCat || m.kind == TafsiliKind.expenseCat)
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final o in opts) DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
                ],
                onChanged: (v) => setState(() => _tafsili = v),
              ),
              if (opts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('هنوز تفصیلی برای این حساب تعریف نشده', style: th.textTheme.labelSmall?.copyWith(color: th.colorScheme.error)),
                ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح')),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: MoneyField(controller: _debit, label: 'بدهکار')),
              const SizedBox(width: 10),
              Expanded(child: MoneyField(controller: _credit, label: 'بستانکار')),
            ]),
            if (_err != null) Text(_err!, style: TextStyle(color: th.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}

/// Short Jalali date for voucher lists.
String voucherDate(Voucher v) => Jalali.fromDateTime(v.date).format();
