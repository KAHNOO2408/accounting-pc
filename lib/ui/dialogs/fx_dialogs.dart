import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/chart.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart' show printTable;
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, parseQty;

String _fx(double v, Currency? c) => '${v.toStringAsFixed(c?.decimals ?? 2)} ${c?.sign ?? ''}'.trim();

// ================================================================ ارزهای سیستم

Future<void> showCurrenciesWindow(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Currencies());

class _Currencies extends StatefulWidget {
  const _Currencies();

  @override
  State<_Currencies> createState() => _CurrenciesState();
}

class _CurrenciesState extends State<_Currencies> {
  String? _sel;

  Future<void> _edit(AppStore s, [Currency? c]) async {
    final x = c == null ? Currency(id: newId(), name: '') : Currency.fromJson(c.toJson());
    final name = TextEditingController(text: x.name);
    final sign = TextEditingController(text: x.sign);
    final rate = TextEditingController(text: x.rate == 0 ? '' : groupDigits(x.rate));
    final dec = TextEditingController(text: '${x.decimals}');
    final tax = TextEditingController(text: x.taxCode);
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          void ok() {
            x
              ..name = name.text
              ..sign = sign.text.trim()
              ..rate = parseMoney(rate.text)
              ..decimals = (int.tryParse(dec.text.trim()) ?? 2).clamp(0, 6)
              ..taxCode = tax.text.trim();
            final e = s.saveCurrency(x);
            if (e != null) {
              set(() => err = e);
            } else {
              Navigator.pop(ctx);
            }
          }

          return CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.f9): ok},
            child: FormDialog(
              title: 'اطلاعات ارز',
              width: 480,
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف F10')),
                FilledButton(onPressed: ok, child: const Text('تایید F9')),
              ],
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام ارز')),
                const SizedBox(height: 8),
                TextField(controller: sign, decoration: const InputDecoration(labelText: 'علامت (نشانه)', hintText: r'$')),
                const SizedBox(height: 8),
                TextField(
                  controller: rate,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: InputDecoration(labelText: 'فی ارز (به ${s.settings.currency})'),
                ),
                const SizedBox(height: 8),
                TextField(controller: dec, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تعداد رقم اعشار')),
                const SizedBox(height: 8),
                TextField(controller: tax, decoration: const InputDecoration(labelText: 'نوع ارز برای ساخت فایل مالیاتی')),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: x.isDefault,
                  title: const Text('پیش فرض'),
                  onChanged: (v) => set(() => x.isDefault = v ?? false),
                ),
                if (err != null) Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ]),
            ),
          );
        },
      ),
    );
    for (final t in [name, sign, rate, dec, tax]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final sel = s.currency(_sel);
    return SakanWindow(
      title: 'ارزهای سیستم',
      width: 760,
      height: 560,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            sakanBtn('تعریف ارز', () => _edit(s), icon: Icons.add_rounded),
            sakanBtn('ویرایش ارز', sel == null ? null : () => _edit(s, sel), icon: Icons.edit_outlined),
            sakanBtn('حذف ارز', sel == null
                ? null
                : () {
                    final e = s.removeCurrency(sel.id);
                    if (e != null) toast(context, e, error: true);
                    setState(() => _sel = null);
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('تبدیل ارز', () => showCurrencyConverter(context), icon: Icons.calculate_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('ردیف', 50), sakanHead('نام ارز', 0), sakanHead('علامت ارز', 90), sakanHead('فی ارز', 140), sakanHead('اعشار', 70), sakanHead('پیش فرض', 80)],
              count: s.currencies.length,
              empty: 'ارزی تعریف نشده',
              row: (ctx, i) {
                final c = s.currencies[i];
                final on = c.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null);
                return InkWell(
                  onTap: () => setState(() => _sel = c.id),
                  onDoubleTap: () => _edit(s, c),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text('${i + 1}', style: st), 50),
                      sakanCell(Text(c.name, style: st.copyWith(fontWeight: FontWeight.w700)), 0, align: Alignment.centerRight),
                      sakanCell(Text(c.sign, style: st), 90),
                      sakanCell(Text(groupDigits(c.rate), style: st, textDirection: TextDirection.ltr), 140),
                      sakanCell(Text('${c.decimals}', style: st), 70),
                      sakanCell(Text(c.isDefault ? '✓' : '', style: st), 80),
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

/// «تبدیل ارز» — an amount in the system currency in every currency.
Future<void> showCurrencyConverter(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Converter());

class _Converter extends StatefulWidget {
  const _Converter();

  @override
  State<_Converter> createState() => _ConverterState();
}

class _ConverterState extends State<_Converter> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final v = parseMoney(_amount.text);
    return FormDialog(
      title: 'تبدیل ارز',
      width: 520,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _amount,
          autofocus: true,
          textDirection: TextDirection.ltr,
          inputFormatters: [MoneyInputFormatter()],
          decoration: InputDecoration(labelText: 'مبلغ به ${s.settings.currency}'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        for (final c in s.currencies)
          ListTile(
            dense: true,
            title: Text('${c.name} (${c.sign})'),
            subtitle: Text('فی ${groupDigits(c.rate)}'),
            trailing: Text(c.rate == 0 ? '—' : _fx(v / c.rate, c), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }
}

// ================================================================ اشخاص ارزی

/// «جدول اشخاص ارزی» — persons whose account is in a foreign currency.
Future<void> showFxPeople(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _FxPeople());

class _FxPeople extends StatefulWidget {
  const _FxPeople();

  @override
  State<_FxPeople> createState() => _FxPeopleState();
}

class _FxPeopleState extends State<_FxPeople> {
  String? _sel;

  Future<void> _assign(AppStore s, Person p) async {
    String? cur = p.currencyId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => FormDialog(
          title: 'نوع ارز — ${p.name}',
          width: 400,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
          ],
          child: DropdownButtonFormField<String?>(
            value: cur,
            decoration: const InputDecoration(labelText: 'نوع ارز'),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text('ارز سیستم (${s.settings.currency})')),
              for (final c in s.currencies) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => set(() => cur = v),
          ),
        ),
      ),
    );
    if (ok == true) s.upsertPerson(p..currencyId = cur);
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final bal = s.fxBalances();
    final list = s.peopleSorted.where((p) => p.currencyId != null).toList();
    final sel = list.where((p) => p.id == _sel).firstOrNull;
    (double, int) of(Person p) {
      var fx = 0.0, sys = 0;
      bal.forEach((k, v) {
        final x = k.split('|');
        if (x[1] == p.id && x[2] == p.currencyId) {
          fx += v.$1;
          sys += v.$2;
        }
      });
      return (fx, sys);
    }

    return SakanWindow(
      title: 'جدول اشخاص ارزی',
      width: 900,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, children: [
            sakanBtn('تعیین ارز شخص', () async {
              final s2 = StoreScope.read(context);
              final id = await showDialog<String>(
                context: context,
                builder: (ctx) => FormDialog(
                  title: 'انتخاب شخص',
                  width: 420,
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
                  child: Column(children: [for (final p in s2.peopleSorted) ListTile(dense: true, title: Text(p.name), onTap: () => Navigator.pop(ctx, p.id))]),
                ),
              );
              final p = s2.person(id);
              if (p != null && context.mounted) await _assign(s2, p);
            }, icon: Icons.person_add_alt_1_outlined),
            sakanBtn('تغییر ارز', sel == null ? null : () => _assign(s, sel), icon: Icons.currency_exchange_rounded),
            sakanBtn('سند ارزی', () => showFxVoucherDialog(context), icon: Icons.receipt_long_outlined),
            sakanBtn('ارزهای سیستم', () => showCurrenciesWindow(context), icon: Icons.attach_money_rounded),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('نام شخص', 0), sakanHead('ارز', 110), sakanHead('مانده ارزی', 170), sakanHead('ارزش دفتری', 150), sakanHead('به نرخ روز', 150)],
              count: list.length,
              empty: 'شخص ارزی تعریف نشده («تعیین ارز شخص»)',
              row: (ctx, i) {
                final p = list[i];
                final c = s.currency(p.currencyId);
                final b = of(p);
                final on = p.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null);
                return InkWell(
                  onTap: () => setState(() => _sel = p.id),
                  onDoubleTap: () => _assign(s, p),
                  child: Container(
                    color: on ? sakanSel : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                    child: Row(children: [
                      sakanCell(Text(p.name, style: st.copyWith(fontWeight: FontWeight.w700)), 0, align: Alignment.centerRight),
                      sakanCell(Text(c?.name ?? '', style: st), 110),
                      sakanCell(Text(_fx(b.$1, c), style: st, textDirection: TextDirection.ltr), 170),
                      sakanCell(Text(groupDigits(b.$2), style: st, textDirection: TextDirection.ltr), 150),
                      sakanCell(Text(groupDigits((b.$1 * (c?.rate ?? 0)).round()), style: st, textDirection: TextDirection.ltr), 150),
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

// ================================================================ سند ارزی

/// One side of a foreign-currency entry: a ledger and its detail account.
class _Side {
  String moeen;
  String? tafsili;
  _Side(this.moeen);
}

/// «سند ارزی» — moves a foreign amount between two accounts (e.g. اشخاص ارزی → صندوق ارزی).
Future<void> showFxVoucherDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _FxVoucher());

class _FxVoucher extends StatefulWidget {
  const _FxVoucher();

  @override
  State<_FxVoucher> createState() => _FxVoucherState();
}

class _FxVoucherState extends State<_FxVoucher> {
  final _dr = _Side(mCashFx);
  final _cr = _Side(mDebtorsFx);
  String? _cur;
  DateTime _date = DateTime.now();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _desc = TextEditingController();
  String? _err;

  @override
  void dispose() {
    for (final c in [_amount, _rate, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  List<DropdownMenuItem<String>> _ledgers() => [
        for (final c in allMoeens) DropdownMenuItem(value: c.code, child: Text('${c.code}  ${c.name}', overflow: TextOverflow.ellipsis)),
      ];

  Widget _side(AppStore s, _Side x, String title) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: x.moeen,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'دفتر', isDense: true),
            items: _ledgers(),
            onChanged: (v) => setState(() {
              x.moeen = v ?? x.moeen;
              x.tafsili = null;
            }),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            value: x.tafsili,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'تفصیلی (شخص / حساب)', isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              for (final p in s.peopleSorted) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              for (final a in s.accounts) DropdownMenuItem<String?>(value: a.id, child: Text('حساب: ${a.name}')),
            ],
            onChanged: (v) => setState(() {
              x.tafsili = v;
              final p = s.person(v);
              if (p?.currencyId != null) {
                _cur = p!.currencyId;
                _rate.text = groupDigits(s.currency(_cur)?.rate ?? 0);
              }
            }),
          ),
        ]),
      );

  void _save() {
    final s = StoreScope.read(context);
    final c = s.currency(_cur);
    final fx = parseQty(_amount.text);
    final rate = parseMoney(_rate.text);
    if (c == null) return setState(() => _err = 'نوع ارز را انتخاب کنید');
    if (fx <= 0 || rate <= 0) return setState(() => _err = 'مبلغ ارزی و فی ارز را وارد کنید');
    final sys = (fx * rate).round();
    final desc = _desc.text.trim().isEmpty ? '${_fx(fx, c)} به نرخ ${groupDigits(rate)}' : _desc.text.trim();
    s.saveVoucher(Voucher(
      id: newId(),
      number: s.nextVoucherNumber(),
      fixedNumber: s.nextFixedNumber(),
      date: _date,
      desc: desc,
      kind: 'fx',
      lines: [
        VoucherLine(moeen: _dr.moeen, tafsiliId: _dr.tafsili, desc: desc, debit: sys, currencyId: fxLedgers.contains(_dr.moeen) || s.person(_dr.tafsili)?.currencyId != null ? c.id : null, fx: fx),
        VoucherLine(moeen: _cr.moeen, tafsiliId: _cr.tafsili, desc: desc, credit: sys, currencyId: fxLedgers.contains(_cr.moeen) || s.person(_cr.tafsili)?.currencyId != null ? c.id : null, fx: -fx),
      ]..forEach((l) {
          if (l.currencyId == null) l.fx = 0;
        }),
    ));
    Navigator.pop(context);
    toast(context, 'سند ارزی ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final fx = parseQty(_amount.text), rate = parseMoney(_rate.text);
    return FormDialog(
      title: 'سند ارزی',
      width: 820,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(onPressed: _save, child: const Text('تایید F9')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 200, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              value: _cur,
              decoration: const InputDecoration(labelText: 'نوع ارز', isDense: true),
              items: [for (final c in s.currencies) DropdownMenuItem<String?>(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() {
                _cur = v;
                _rate.text = groupDigits(s.currency(v)?.rate ?? 0);
              }),
            ),
          ),
          SizedBox(
            width: 160,
            child: TextField(controller: _amount, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مبلغ ارزی', isDense: true), onChanged: (_) => setState(() {})),
          ),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _rate,
              textDirection: TextDirection.ltr,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(labelText: 'فی ارز', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Text('معادل: ${groupDigits((fx * rate).round())} ${s.settings.currency}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _side(s, _dr, 'بدهکار'),
          const SizedBox(width: 16),
          _side(s, _cr, 'بستانکار'),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'شرح سند', isDense: true)),
        if (s.currencies.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('ابتدا در «ارزهای سیستم» ارز تعریف کنید.', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}

// ================================================================ تسعیر نرخ ارز

Future<void> showRevaluationDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Revalue());

class _Revalue extends StatefulWidget {
  const _Revalue();

  @override
  State<_Revalue> createState() => _RevalueState();
}

class _RevalueState extends State<_Revalue> {
  DateTime _date = DateTime.now();
  final Map<String, TextEditingController> _rates = {};
  final Set<String> _on = {};
  String _gain = mFxGain, _loss = mFxLoss;

  @override
  void dispose() {
    for (final c in _rates.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    for (final c in s.currencies) {
      _rates.putIfAbsent(c.id, () {
        _on.add(c.id);
        return TextEditingController(text: groupDigits(c.rate));
      });
    }
    final inc = chart.where((k) => k.side == Side.income).expand((k) => k.ledgers).toList();
    final exp = chart.where((k) => k.side == Side.expense).expand((k) => k.ledgers).toList();
    return FormDialog(
      title: 'تسعیر نرخ ارز',
      width: 640,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            final v = s.revalue(_date, {for (final id in _on) id: parseMoney(_rates[id]!.text)}, gainAcc: _gain, lossAcc: _loss);
            Navigator.pop(context);
            toast(context, v == null ? 'تفاوتی برای تسعیر وجود ندارد' : 'سند تسعیر شماره ${v.number} ثبت شد');
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 220, child: DateField(label: 'تاریخ سند', value: _date, onChanged: (d) => setState(() => _date = d ?? _date))),
        const SizedBox(height: 10),
        const Text('ارزهای مورد نظر برای تسعیر و نرخ جدید:', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final c in s.currencies)
          Row(children: [
            Checkbox(value: _on.contains(c.id), onChanged: (v) => setState(() => v == true ? _on.add(c.id) : _on.remove(c.id))),
            SizedBox(width: 120, child: Text(c.name)),
            SizedBox(
              width: 180,
              child: TextField(controller: _rates[c.id], textDirection: TextDirection.ltr, inputFormatters: [MoneyInputFormatter()], decoration: const InputDecoration(labelText: 'تعیین نرخ ارز', isDense: true)),
            ),
          ]),
        if (s.currencies.isEmpty) const Text('ارزی تعریف نشده است'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _gain,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'سرفصل درآمد ناشی از نوسانات نرخ ارز', isDense: true),
          items: [for (final m in inc) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}'))],
          onChanged: (v) => setState(() => _gain = v ?? _gain),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _loss,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'سرفصل هزینه ناشی از نوسانات نرخ ارز', isDense: true),
          items: [for (final m in exp) DropdownMenuItem(value: m.code, child: Text('${m.code}  ${m.name}'))],
          onChanged: (v) => setState(() => _loss = v ?? _loss),
        ),
      ]),
    );
  }
}

// ================================================================ گزارش از گردش ارزی

/// «گزارش از گردش ارزی» — every foreign row, with balances per account.
Future<void> showFxTurnover(BuildContext context, {String? tafsiliId}) =>
    showDialog<void>(context: context, builder: (_) => _FxTurnover(tafsiliId: tafsiliId));

class _FxTurnover extends StatelessWidget {
  final String? tafsiliId;
  const _FxTurnover({this.tafsiliId});

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final rows = <(Voucher, VoucherLine)>[];
    for (final v in s.vouchers) {
      for (final l in v.lines) {
        if (l.currencyId != null && (tafsiliId == null || l.tafsiliId == tafsiliId)) rows.add((v, l));
      }
    }
    rows.sort((a, b) => a.$1.date.compareTo(b.$1.date));
    String acc(VoucherLine l) {
      final m = findMoeen(l.moeen)?.name ?? l.moeen;
      final t = s.person(l.tafsiliId)?.name ?? s.account(l.tafsiliId)?.name;
      return t == null ? m : '$m / $t';
    }

    final run = <String, double>{};
    final shown = [
      for (final (v, l) in rows)
        () {
          final k = '${l.moeen}|${l.tafsiliId}|${l.currencyId}';
          run[k] = (run[k] ?? 0) + l.fx;
          final c = s.currency(l.currencyId);
          return [
            jFormat(v.date),
            '${v.number}',
            acc(l),
            c?.name ?? '',
            l.fx > 0 ? _fx(l.fx, c) : '',
            l.fx < 0 ? _fx(-l.fx, c) : '',
            _fx(run[k]!, c),
            groupDigits(l.debit - l.credit),
            l.desc,
          ];
        }(),
    ];
    const heads = ['تاریخ', 'سند', 'حساب', 'ارز', 'بدهکار ارزی', 'بستانکار ارزی', 'مانده ارزی', 'معادل', 'شرح'];
    const w = [95.0, 60.0, 0.0, 80.0, 120.0, 120.0, 120.0, 120.0, 200.0];
    return SakanWindow(
      title: tafsiliId == null ? 'گزارش از گردش ارزی' : 'گردش ارزی ${s.person(tafsiliId)?.name ?? ''}',
      width: 1180,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            sakanBtn('چاپ', () => printTable(store: s, title: 'گزارش از گردش ارزی', headers: heads, rows: shown, fileName: 'fx'), icon: Icons.print_outlined),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [for (var i = 0; i < heads.length; i++) sakanHead(heads[i], w[i])],
              count: shown.length,
              empty: 'گردش ارزی ثبت نشده',
              row: (ctx, i) => Container(
                color: i.isOdd ? const Color(0xFFF3F7FC) : null,
                child: Row(children: [for (var k = 0; k < heads.length; k++) sakanCell(Text(shown[i][k], overflow: TextOverflow.ellipsis), w[k])]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// «جمع مبلغ صندوق های ارزی».
Future<void> showFxCashTotals(BuildContext context) {
  final s = StoreScope.read(context);
  final rows = <List<String>>[];
  s.fxBalances().forEach((k, b) {
    final p = k.split('|');
    if (p[0] != mCashFx && p[0] != mBankFx) return;
    final c = s.currency(p[2]);
    rows.add([s.account(p[1])?.name ?? findMoeen(p[0])?.name ?? '', c?.sign ?? '', fmtQty(b.$1), groupDigits((b.$1 * (c?.rate ?? 0)).round())]);
  });
  return showDialog<void>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'جمع مبلغ صندوق های ارزی',
      width: 620,
      leading: TextButton(
        onPressed: () => printTable(store: s, title: 'جمع مبلغ صندوق های ارزی', headers: const ['نام صندوق', 'علامت ارز', 'مبلغ (ارزی)', 'مبلغ به ارز سیستم'], rows: rows, numeric: const {2, 3}, fileName: 'fx-cash'),
        child: const Text('چاپ F12'),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
      child: Column(children: [
        for (final r in rows) ListTile(dense: true, title: Text(r[0]), subtitle: Text('${r[2]} ${r[1]}'), trailing: Text(r[3], textDirection: TextDirection.ltr)),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('صندوق یا بانک ارزی مانده ندارد')),
      ]),
    ),
  );
}
