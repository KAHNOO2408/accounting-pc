import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../core/xlsx.dart';
import '../../data/models.dart';
import '../../data/scale.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'device_dialogs.dart' show showScaleSettings;

/// «مدیریت ساخت فایل ترازوی توزین صدر»: step 1 products, step 2 keys,
/// step 3 files; plus «لیست فاکتورهای ثبت شده در ترازو».
Future<void> showSadrScale(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final s = StoreScope.of(ctx);
        Future<void> save(String name, String text) async {
          final loc = await fs.getSaveLocation(suggestedName: name);
          if (loc == null) return;
          File(loc.path).writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(text)], flush: true);
          if (ctx.mounted) toast(ctx, '$name ذخیره شد');
        }

        Widget step(String title, String sub, List<Widget> btns) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(sub, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: btns),
                ]),
              ),
            );
        return FormDialog(
          title: 'مدیریت ساخت فایل ترازوی توزین صدر',
          width: 640,
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بازگشت'))],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('تعداد حافظه دستگاه: ${s.scale.memory}    تعداد استفاده شده: ${s.scaleProducts().length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            step('مرحله اول', 'تعیین لیست کالاهایی که باید به ترازو انتقال پیدا کند', [
              sakanBtn('تعیین لیست کالاها', () => showScaleGoods(ctx), icon: Icons.checklist_rounded),
              sakanBtn('تنظیمات بارکد وزنی', () => showScaleSettings(ctx), icon: Icons.settings_outlined),
            ]),
            step('مرحله دوم', 'تعیین کلیدهای میانبر ترازو (40 یا 63 کلید)', [
              sakanBtn('تعیین کلیدهای ترازو', () => showScaleKeys(ctx), icon: Icons.keyboard_alt_outlined),
            ]),
            step('مرحله سوم', 'ساخت فایل؛ فایل‌های ساخته شده را به مسیر برنامه ترازو منتقل کنید', [
              sakanBtn('ساخت فایل LSG', () => save('PLU.txt', s.lsgFile()), icon: Icons.save_alt_rounded),
              sakanBtn('ذخیره برای مدل Vista Plus', () => save('PLU-VistaPlus.csv', s.lsgFile(vista: true)), icon: Icons.save_alt_rounded),
              sakanBtn('ذخیره کلیدها', () => save('KEYS.txt', s.keysFile()), icon: Icons.keyboard_rounded),
            ]),
            step('فروش ترازو', 'فاکتورهای ثبت شده در ترازو را وارد کنید تا فاکتور فروش شوند', [
              sakanBtn('لیست فاکتورهای ترازو', () => showScaleInvoices(ctx), icon: Icons.receipt_long_outlined),
            ]),
            const Text(
              'توجه: در صورتی که مرحله اول را دوباره تایید کنید و کالایی از لیست خارج شود، کلید آن در مرحله دوم پاک می‌شود.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        );
      },
    );

/// «تعیین کالاهایی که به حافظه ترازو انتقال پیدا می کند».
Future<void> showScaleGoods(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Goods());

class _Goods extends StatefulWidget {
  const _Goods();

  @override
  State<_Goods> createState() => _GoodsState();
}

class _GoodsState extends State<_Goods> {
  String _q = '';
  bool _zero = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.productsSorted.where((p) => !p.archived && (_q.isEmpty || p.name.contains(_q) || p.code.contains(_q) || (p.info['barcode'] ?? '').contains(_q)) && (!_zero || p.sellPrice == 0)).toList();
    final used = s.scaleProducts().length;
    void setInfo(Product p, String k, String v) {
      if (v.isEmpty) {
        p.info.remove(k);
      } else {
        p.info[k] = v;
      }
    }

    int nextPlu() => s.scaleProducts().fold<int>(0, (a, p) => (int.tryParse(pluOf(p)) ?? 0) > a ? int.parse(pluOf(p)) : a) + 1;
    return SakanWindow(
      title: 'تعیین کالاهایی که به حافظه ترازو انتقال پیدا می کند',
      width: 1200,
      height: 700,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 240, child: TextField(decoration: const InputDecoration(hintText: 'فیلتر کلی (نام، کد، بارکد)', prefixIcon: Icon(Icons.search_rounded), isDense: true), onChanged: (v) => setState(() => _q = normalizeDigits(v.trim())))),
            FilterChip(label: const Text('فیلتر کالاها با فی صفر'), selected: _zero, onSelected: (v) => setState(() => _zero = v)),
            sakanBtn('همه', () => setState(() {
              for (final p in list) {
                if (p.info['scale'] != '1') {
                  if ((p.info['plu'] ?? '').isEmpty) p.info['plu'] = '${nextPlu()}';
                  p.info['scale'] = '1';
                }
              }
            }), icon: Icons.select_all_rounded),
            sakanBtn('هیچ', () => setState(() {
              for (final p in list) {
                p.info.remove('scale');
              }
            }), icon: Icons.deselect_rounded),
            Text('حافظه استفاده شده $used از ${s.scale.memory}', style: TextStyle(fontWeight: FontWeight.w800, color: used > s.scale.memory ? Colors.red : null)),
            FilledButton(
              onPressed: () {
                // keys of products no longer on the scale are cleared
                s.scale.keys.removeWhere((_, id) => s.product(id)?.info['scale'] != '1');
                s.updateSettings((_) {});
                Navigator.pop(context);
              },
              child: const Text('تایید'),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('انتخاب', 50),
                sakanHead('شماره حافظه', 90),
                sakanHead('کد کالا', 80),
                sakanHead('نام کالا', 0),
                sakanHead('بارکد', 130),
                sakanHead('قیمت واحد', 110),
                sakanHead('کالای تعدادی', 80),
                sakanHead('تاریخ انقضا پس از چند روز', 100),
                sakanHead('چاپ تاریخ انقضا', 80),
                sakanHead('IP ترازو', 120),
              ],
              count: list.length,
              row: (ctx, i) {
                final p = list[i];
                final on = p.info['scale'] == '1';
                Widget tf(String k, double w, {String? init}) => SizedBox(
                      width: w,
                      child: TextFormField(
                        key: ValueKey('${p.id}$k$on'),
                        initialValue: init ?? p.info[k] ?? '',
                        enabled: on,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                        onChanged: (v) => setInfo(p, k, normalizeDigits(v.trim())),
                      ),
                    );
                return Container(
                  color: on ? const Color(0xFFE6F6E6) : (i.isOdd ? const Color(0xFFF3F7FC) : null),
                  child: Row(children: [
                    sakanCell(
                      Checkbox(
                        value: on,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            if ((p.info['plu'] ?? '').isEmpty) p.info['plu'] = '${nextPlu()}';
                            p.info['scale'] = '1';
                          } else {
                            p.info.remove('scale');
                          }
                        }),
                      ),
                      50,
                    ),
                    sakanCell(tf('plu', 90, init: on ? pluOf(p) : ''), 90),
                    sakanCell(Text(p.code), 80),
                    sakanCell(Text(p.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                    sakanCell(Text(p.info['barcode'] ?? '', style: const TextStyle(fontSize: 11.5)), 130),
                    sakanCell(Text(groupDigits(p.sellPrice)), 110),
                    sakanCell(
                      Checkbox(value: p.info['scaleType'] == 'n', onChanged: on ? (v) => setState(() => setInfo(p, 'scaleType', v == true ? 'n' : '')) : null),
                      80,
                    ),
                    sakanCell(tf('shelfDays', 100), 100),
                    sakanCell(
                      Checkbox(value: p.info['printExpiry'] == '1', onChanged: on ? (v) => setState(() => setInfo(p, 'printExpiry', v == true ? '1' : '')) : null),
                      80,
                    ),
                    sakanCell(tf('scaleIp', 120), 120),
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

/// «تعیین کلیدهای ترازو».
Future<void> showScaleKeys(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Keys());

class _Keys extends StatefulWidget {
  const _Keys();

  @override
  State<_Keys> createState() => _KeysState();
}

class _KeysState extends State<_Keys> {
  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final goods = s.scaleProducts();
    final c = s.scale;
    return FormDialog(
      title: 'تعیین کلیدهای ترازو',
      width: 900,
      leading: SegmentedButton<int>(
        segments: const [ButtonSegment(value: 40, label: Text('40 کلید سریع')), ButtonSegment(value: 63, label: Text('63 کلید سریع'))],
        selected: {c.keyCount},
        onSelectionChanged: (v) => setState(() {
          c.keyCount = v.first;
          c.keys.removeWhere((k, _) => (int.tryParse(k) ?? 0) > c.keyCount);
        }),
      ),
      actions: [
        TextButton(onPressed: () => setState(c.keys.clear), child: const Text('پاک کردن همه')),
        FilledButton(
          onPressed: () {
            s.updateSettings((_) {});
            Navigator.pop(context);
          },
          child: const Text('تایید'),
        ),
      ],
      child: goods.isEmpty
          ? const Text('ابتدا در مرحله اول کالاهای ترازو را تعیین کنید')
          : Wrap(spacing: 6, runSpacing: 6, children: [
              for (var k = 1; k <= c.keyCount; k++)
                SizedBox(
                  width: 205,
                  child: Row(children: [
                    SizedBox(width: 30, child: Text('$k', style: const TextStyle(fontWeight: FontWeight.w800))),
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        isDense: true,
                        value: goods.any((p) => p.id == c.keys['$k']) ? c.keys['$k'] : null,
                        hint: const Text('—', style: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('—')),
                          for (final p in goods) DropdownMenuItem<String?>(value: p.id, child: Text('${pluOf(p)}  ${p.name}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() {
                          if (v == null) {
                            c.keys.remove('$k');
                          } else {
                            c.keys['$k'] = v;
                          }
                        }),
                      ),
                    ),
                  ]),
                ),
            ]),
    );
  }
}

/// «لیست فاکتورهای ثبت شده در ترازو»: reads the scale's sales file and makes sale invoices.
Future<void> showScaleInvoices(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ScaleInvoices());

class _ScaleInvoices extends StatefulWidget {
  const _ScaleInvoices();

  @override
  State<_ScaleInvoices> createState() => _ScaleInvoicesState();
}

class _ScaleInvoicesState extends State<_ScaleInvoices> {
  List<ScaleSaleRow> _rows = [];
  final Set<String> _sel = {};
  String? _acc;
  String? _msg;

  Future<void> _open() async {
    final f = await fs.openFile(acceptedTypeGroups: const [fs.XTypeGroup(label: 'Excel / CSV / TXT', extensions: ['xlsx', 'csv', 'txt'])]);
    if (f == null) return;
    final bytes = await File(f.path).readAsBytes();
    final rows = f.path.toLowerCase().endsWith('.xlsx')
        ? readXlsx(bytes)
        : [for (final l in const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true))) l.split(RegExp(r'[,;\t]'))];
    setState(() {
      _rows = parseScaleSales(rows);
      _sel
        ..clear()
        ..addAll(_rows.map((r) => r.ref));
      _msg = '${_rows.length} ردیف از ${_sel.length} فاکتور ترازو خوانده شد';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    _acc ??= s.activeAccounts.firstOrNull?.id;
    final done = {for (final i in s.invoices) if ((i.info['scaleRef'] ?? '').isNotEmpty) i.info['scaleRef']!};
    final total = _rows.where((r) => _sel.contains(r.ref)).fold<int>(0, (a, r) => a + r.total);
    return SakanWindow(
      title: 'لیست فاکتورهای ثبت شده در ترازو',
      width: 1150,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('خواندن فایل فروش ترازو', _open, icon: Icons.upload_file_rounded),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: _acc,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'دریافت به صندوق', isDense: true),
                items: [const DropdownMenuItem<String?>(value: null, child: Text('نسیه')), for (final a in s.activeAccounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _acc = v),
              ),
            ),
            sakanBtn('حذف فاکتورهای منتخب', _sel.isEmpty
                ? null
                : () => setState(() {
                      _rows.removeWhere((r) => _sel.contains(r.ref));
                      _sel.clear();
                    }), icon: Icons.delete_outline_rounded),
            FilledButton.icon(
              onPressed: _sel.isEmpty
                  ? null
                  : () {
                      final (n, unknown) = s.importScaleSales(_rows.where((r) => _sel.contains(r.ref)).toList(), accountId: _acc);
                      setState(() => _msg = '$n فاکتور فروش ثبت شد${unknown.isEmpty ? '' : ' — کدهای ناشناخته: ${unknown.take(10).join('، ')}'}');
                    },
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('تایید'),
            ),
          ]),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: const TextStyle(fontWeight: FontWeight.w700))),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('ستون‌های فایل: شماره ترازو، شماره فاکتور، تاریخ و ساعت، کد/بارکد کالا، تعداد/وزن، فی واحد، قیمت کل', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('انتخاب', 50),
                sakanHead('شماره ترازو', 80),
                sakanHead('شماره فاکتور', 90),
                sakanHead('تاریخ و ساعت', 130),
                sakanHead('کد کالا', 110),
                sakanHead('نام کالا', 0),
                sakanHead('تعداد / وزن', 90),
                sakanHead('فی واحد', 110),
                sakanHead('قیمت کل', 120),
                sakanHead('وضعیت', 80),
              ],
              count: _rows.length,
              empty: 'فایل فروش ترازو را بخوانید',
              row: (ctx, i) {
                final r = _rows[i];
                final p = s.matchScan(r.code)?.$1 ?? s.products.where((p) => pluOf(p) == r.code || int.tryParse(pluOf(p)) == int.tryParse(r.code)).firstOrNull;
                return Container(
                  color: done.contains(r.ref) ? const Color(0xFFE6F6E6) : (p == null ? const Color(0xFFFBE9E9) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                  child: Row(children: [
                    sakanCell(
                      Checkbox(
                        value: _sel.contains(r.ref),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sel.add(r.ref);
                          } else {
                            _sel.remove(r.ref);
                          }
                        }),
                      ),
                      50,
                    ),
                    sakanCell(Text(r.scaleNo), 80),
                    sakanCell(Text(r.invoiceNo), 90),
                    sakanCell(Text('${jFormat(r.date)} ${r.date.hour}:${r.date.minute.toString().padLeft(2, '0')}'), 130),
                    sakanCell(Text(r.code), 110),
                    sakanCell(Text(p?.name ?? 'ناشناخته', overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                    sakanCell(Text('${r.qty}'), 90),
                    sakanCell(Text(groupDigits(r.unitPrice)), 110),
                    sakanCell(Text(groupDigits(r.total)), 120),
                    sakanCell(Text(done.contains(r.ref) ? 'ثبت شده' : ''), 80),
                  ]),
                );
              },
            ),
          ),
          Text('جمع مبلغ فاکتور: ${groupDigits(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
