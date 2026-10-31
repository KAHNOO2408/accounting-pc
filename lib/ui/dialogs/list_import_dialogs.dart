import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/xlsx.dart';
import '../../data/list_import.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// Reads an .xlsx (any sheet) or a .csv/.txt file chosen by the user.
Future<(String, List<int>)?> _pickSheetFile() async {
  final f = await fs.openFile(acceptedTypeGroups: const [
    fs.XTypeGroup(label: 'Excel / CSV', extensions: ['xlsx', 'csv', 'txt']),
  ]);
  if (f == null) return null;
  return (f.path, await File(f.path).readAsBytes());
}

List<List<String>> _readCsv(List<int> bytes) {
  var t = utf8.decode(bytes, allowMalformed: true);
  if (t.startsWith('﻿')) t = t.substring(1);
  final sep = t.split('\n').first.contains('\t') ? '\t' : (t.split('\n').first.contains(';') && !t.split('\n').first.contains(',') ? ';' : ',');
  final out = <List<String>>[];
  for (final line in const LineSplitter().convert(t)) {
    final row = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if (c == sep && !q) {
        row.add(b.toString());
        b.clear();
      } else {
        b.write(c);
      }
    }
    row.add(b.toString());
    out.add(row);
  }
  return out;
}

/// «دریافت اطلاعات از فایل اکسل»: sheet, preview and «معادل سازی» of the
/// file's columns with [fields]. Returns the mapped rows.
Future<List<Map<String, String>>?> showExcelMapping(BuildContext context, List<ImportField> fields, {String title = 'دریافت اطلاعات از فایل اکسل'}) async {
  final picked = await _pickSheetFile();
  if (picked == null || !context.mounted) return null;
  final (path, bytes) = picked;
  final csv = !path.toLowerCase().endsWith('.xlsx');
  final sheets = csv ? const ['CSV'] : xlsxSheetNames(bytes);
  List<List<String>> read(int sheet) {
    try {
      return csv ? _readCsv(bytes) : readXlsx(bytes, sheet: sheet);
    } on FormatException catch (e) {
      toast(context, e.message, error: true);
      return const [];
    }
  }

  return showDialog<List<Map<String, String>>>(
    context: context,
    builder: (_) => _Mapping(title: title, fields: fields, sheets: sheets.isEmpty ? const ['Sheet1'] : sheets, read: read, path: path),
  );
}

class _Mapping extends StatefulWidget {
  final String title;
  final List<ImportField> fields;
  final List<String> sheets;
  final List<List<String>> Function(int) read;
  final String path;
  const _Mapping({required this.title, required this.fields, required this.sheets, required this.read, required this.path});
  @override
  State<_Mapping> createState() => _MappingState();
}

class _MappingState extends State<_Mapping> {
  int _sheet = 0;
  bool _header = true;
  List<List<String>> _rows = const [];
  Map<String, int> _map = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _rows = widget.read(_sheet);
    _map = _rows.isEmpty ? {} : autoMapFields(widget.fields, _rows.first);
    // no recognised header → map columns in order
    if (_map.isEmpty && _rows.isNotEmpty) {
      _header = false;
      for (var i = 0; i < widget.fields.length && i < _rows.first.length; i++) {
        _map[widget.fields[i].key] = i;
      }
    } else {
      _header = true;
    }
  }

  int get _cols => _rows.fold(0, (m, r) => r.length > m ? r.length : m);

  String _colName(int i) {
    var n = i, s = '';
    do {
      s = String.fromCharCode(65 + n % 26) + s;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    final h = _header && _rows.isNotEmpty && i < _rows.first.length ? _rows.first[i] : '';
    return h.isEmpty ? 'ستون $s' : '$s : $h';
  }

  @override
  Widget build(BuildContext context) {
    final cols = _cols;
    final preview = _rows.take(9).toList();
    return SakanWindow(
      title: widget.title,
      width: 1000,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('فایل: ${widget.path}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            const Text('شیت منتخب: '),
            DropdownButton<int>(
              value: _sheet,
              items: [for (var i = 0; i < widget.sheets.length; i++) DropdownMenuItem(value: i, child: Text(widget.sheets[i]))],
              onChanged: (v) => setState(() {
                _sheet = v ?? 0;
                _load();
              }),
            ),
            const SizedBox(width: 16),
            Checkbox(value: _header, onChanged: (v) => setState(() => _header = v ?? true)),
            const Text('سطر اول عنوان ستون هاست'),
            const Spacer(),
            Text('${(_rows.length - (_header ? 1 : 0)).clamp(0, 1 << 30)} ردیف'),
          ]),
          const SizedBox(height: 6),
          sakanGroup(
            'پیش نمایش فایل',
            SizedBox(
              height: 190,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: Table(
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    border: TableBorder.all(color: Colors.black12),
                    children: [
                      TableRow(decoration: const BoxDecoration(color: Color(0xFFEFF5FC)), children: [
                        for (var c = 0; c < cols; c++) Padding(padding: const EdgeInsets.all(4), child: Text(_colName(c).split(' : ').first, style: const TextStyle(fontWeight: FontWeight.w800))),
                      ]),
                      for (final r in preview)
                        TableRow(children: [
                          for (var c = 0; c < cols; c++)
                            Padding(padding: const EdgeInsets.all(4), child: Text(c < r.length ? r[c] : '', maxLines: 1, style: const TextStyle(fontSize: 12))),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('معادل سازی ستون های فایل با اطلاعات', style: TextStyle(fontWeight: FontWeight.w800)),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 320,
              childAspectRatio: 6.5,
              children: [
                for (final f in widget.fields)
                  Row(children: [
                    SizedBox(width: 130, child: Text('${f.label}${f.required ? ' *' : ''}', overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _map[f.key] != null && _map[f.key]! < cols ? _map[f.key] : -1,
                        items: [
                          const DropdownMenuItem(value: -1, child: Text('— ندارد —')),
                          for (var c = 0; c < cols; c++) DropdownMenuItem(value: c, child: Text(_colName(c), overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => v == null || v < 0 ? _map.remove(f.key) : _map[f.key] = v),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final miss = widget.fields.where((f) => f.required && !_map.containsKey(f.key)).map((f) => f.label);
                if (miss.isNotEmpty) return toast(context, 'ستون «${miss.join('، ')}» معادل سازی نشده', error: true);
                Navigator.pop(context, mapRows(_rows, _map, header: _header));
              },
              child: const Text('دریافت اطلاعات'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// «ورود لیستی اطلاعات»: editable list, Excel read, check, show errors,
/// confirm & insert, remove inserted rows.
Future<void> showListImport(BuildContext context, {ImportKind kind = ImportKind.people}) =>
    showDialog<void>(context: context, builder: (_) => _ListImport(kind));

class _ListImport extends StatefulWidget {
  final ImportKind kind;
  const _ListImport(this.kind);
  @override
  State<_ListImport> createState() => _ListImportState();
}

class _ListImportState extends State<_ListImport> {
  late ImportKind _kind = widget.kind;
  final List<Map<String, String>> _rows = [];
  final List<String> _status = []; // '' unchecked, 'ok', 'done', or error text
  int? _sel;
  bool _errorsOnly = false;
  int _gen = 0; // rebuilds the text fields after bulk changes

  List<ImportField> get _fields => importFields(_kind);

  void _add([Map<String, String>? r]) {
    _rows.add(r ?? {});
    _status.add('');
  }

  void _check(AppStore s) {
    final e = s.checkImport(_kind, _rows);
    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        if (_status[i] != 'done') _status[i] = e[i].isEmpty ? 'ok' : e[i];
      }
    });
    final bad = e.where((x) => x.isNotEmpty).length;
    toast(context, bad == 0 ? 'اطلاعات بدون خطاست' : '$bad ردیف دارای خطاست', error: bad > 0);
  }

  void _apply(AppStore s) {
    final idx = [for (var i = 0; i < _rows.length; i++) if (_status[i] != 'done') i];
    final rows = [for (final i in idx) _rows[i]];
    final errs = s.checkImport(_kind, rows);
    final (ins, upd) = s.applyImport(_kind, rows);
    setState(() {
      for (var j = 0; j < idx.length; j++) {
        _status[idx[j]] = errs[j].isEmpty ? 'done' : errs[j];
      }
    });
    toast(context, '$ins مورد جدید درج و $upd مورد بروزرسانی شد${errs.any((e) => e.isNotEmpty) ? ' — ردیف های دارای خطا درج نشدند' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final fields = _fields;
    const w = 130.0;
    final shown = [for (var i = 0; i < _rows.length; i++) if (!_errorsOnly || (_status[i].isNotEmpty && _status[i] != 'ok' && _status[i] != 'done')) i];
    return SakanWindow(
      title: 'ورود لیستی اطلاعات',
      width: 1150,
      height: 720,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('نوع اطلاعات: '),
            DropdownButton<ImportKind>(
              value: _kind,
              items: [for (final k in ImportKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: _rows.isNotEmpty
                  ? null
                  : (k) => setState(() => _kind = k ?? _kind),
            ),
            sakanBtn('خواندن از فایل اکسل', () async {
              final r = await showExcelMapping(context, fields);
              if (r == null || !mounted) return;
              setState(() {
                for (final x in r) {
                  _add(x);
                }
                _gen++;
              });
            }, icon: Icons.table_view_rounded),
            sakanBtn('افزودن ردیف', () => setState(() {
                  _add();
                  _sel = _rows.length - 1;
                }), icon: Icons.add_rounded),
            sakanBtn('حذف ردیف', _sel == null
                ? null
                : () => setState(() {
                      _rows.removeAt(_sel!);
                      _status.removeAt(_sel!);
                      _sel = null;
                      _gen++;
                    }), icon: Icons.close_rounded),
            sakanBtn('1- بررسی اطلاعات', _rows.isEmpty ? null : () => _check(s), color: const Color(0xFFFFF8E1)),
            sakanBtn(_errorsOnly ? 'نمایش همه' : '2- نمایش خطاها', _rows.isEmpty ? null : () => setState(() => _errorsOnly = !_errorsOnly), color: const Color(0xFFFFEBEE)),
            sakanBtn('3- تایید و درج اطلاعات', _rows.isEmpty ? null : () => _apply(s), color: const Color(0xFFE8F5E9)),
            sakanBtn('حذف اطلاعات ثبت شده از لیست', !_status.contains('done')
                ? null
                : () => setState(() {
                      for (var i = _rows.length - 1; i >= 0; i--) {
                        if (_status[i] == 'done') {
                          _rows.removeAt(i);
                          _status.removeAt(i);
                        }
                      }
                      _sel = null;
                      _gen++;
                    })),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(builder: (ctx, box) {
              final total = 40 + 200 + fields.length * w;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: total < box.maxWidth ? box.maxWidth : total,
                  child: SakanGrid(
                    header: [
                      sakanHead('ردیف', 40),
                      for (final f in fields) sakanHead(f.label, w, fg: f.required ? const Color(0xFFC62828) : null),
                      sakanHead('وضعیت', 0),
                    ],
                    count: shown.length,
                    empty: 'ردیفی وارد نشده — «خواندن از فایل اکسل» یا «افزودن ردیف»',
                    row: (_, n) {
                      final i = shown[n];
                      final st = _status[i];
                      final done = st == 'done';
                      return Material(
                        color: _sel == i ? const Color(0xFFDDEBFA) : (done ? const Color(0xFFE8F5E9) : (st.isNotEmpty && st != 'ok' ? const Color(0xFFFFEBEE) : Colors.white)),
                        child: InkWell(
                          onTap: () => setState(() => _sel = i),
                          child: Row(children: [
                            sakanCell(Text('${i + 1}'), 40),
                            for (final f in fields)
                              sakanCell(
                                TextFormField(
                                  key: ValueKey('$_gen-$i-${f.key}'),
                                  initialValue: _rows[i][f.key] ?? '',
                                  readOnly: done,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                                  onTap: () => setState(() => _sel = i),
                                  onChanged: (v) {
                                    _rows[i][f.key] = v;
                                    if (_status[i] != '') setState(() => _status[i] = '');
                                  },
                                ),
                                w,
                              ),
                            sakanCell(
                              Text(
                                switch (st) { '' => '', 'ok' => 'صحیح', 'done' => 'ثبت شد', _ => st },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: done || st == 'ok' ? Colors.green.shade800 : Colors.red.shade800),
                              ),
                              0,
                              align: AlignmentDirectional.centerStart.resolve(TextDirection.rtl),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            _kind == ImportKind.balances
                ? 'دفتر با کد یا نام شناسایی می شود (اشخاص، بانک و صندوق، کالا یا کد معین). مبلغ مثبت = بدهکار؛ یا ستون های بدهکار/بستانکار.'
                : 'رکوردی که کد (یا نام) آن قبلاً ثبت شده باشد بروزرسانی می شود. فایل های خروجی اکسل سکان هم قابل خواندن است.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ]),
      ),
    );
  }
}

/// «دریافت اطلاعات از اکسل» inside an invoice: rows with «شناسایی کالا».
Future<List<InvoiceLine>?> showInvoiceRowsImport(BuildContext context) async {
  var by = 'name';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('دریافت ردیف های فاکتور از اکسل'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('شناسایی کالا بر اساس:'),
          for (final (k, t) in const [('name', 'نام کالا'), ('barcode', 'بارکد'), ('techNo', 'شماره فنی'), ('code', 'کد کالا')])
            RadioListTile<String>(dense: true, value: k, groupValue: by, title: Text(t), onChanged: (v) => set(() => by = v ?? by)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('انتخاب فایل')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final rows = await showExcelMapping(context, invoiceRowFields, title: 'دریافت ردیف های فاکتور از فایل اکسل');
  if (rows == null || !context.mounted) return null;
  final (lines, missing) = StoreScope.read(context).importInvoiceRows(rows, by: by);
  if (missing.isNotEmpty) toast(context, '${missing.length} کالا پیدا نشد: ${missing.take(5).join('، ')}', error: true);
  return lines;
}

class _TransferFile {
  final String path;
  final List<List<String>> rows;
  ImportKind? kind;
  String result = '';
  _TransferFile(this.path, this.rows, this.kind);
}

/// «انتقال اطلاعات از سکان»: Excel lists exported from Sakan (اشخاص، کالا،
/// پرسنل، اموال، تراز / مانده دفاتر) are recognised and inserted in order.
Future<void> showSakanTransfer(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _Transfer());

class _Transfer extends StatefulWidget {
  const _Transfer();
  @override
  State<_Transfer> createState() => _TransferState();
}

class _TransferState extends State<_Transfer> {
  final List<_TransferFile> _files = [];

  Future<void> _pick() async {
    final fl = await fs.openFiles(acceptedTypeGroups: const [
      fs.XTypeGroup(label: 'Excel / CSV', extensions: ['xlsx', 'csv', 'txt']),
    ]);
    for (final f in fl) {
      final bytes = await File(f.path).readAsBytes();
      final csv = !f.path.toLowerCase().endsWith('.xlsx');
      final sheets = csv ? 1 : xlsxSheetNames(bytes).length.clamp(1, 50);
      for (var i = 0; i < sheets; i++) {
        List<List<String>> rows;
        try {
          rows = csv ? _readCsv(bytes) : readXlsx(bytes, sheet: i);
        } on FormatException {
          rows = const [];
        }
        // skip title lines above the real header (Sakan exports can have one)
        var h = 0;
        while (h < rows.length - 1 && h < 5 && detectKind(rows[h]) == null) {
          h++;
        }
        final body = rows.skip(h).toList();
        if (body.isEmpty) continue;
        _files.add(_TransferFile(sheets > 1 ? '${f.path} [${i + 1}]' : f.path, body, detectKind(body.first)));
      }
    }
    if (mounted) setState(() {});
  }

  void _run(AppStore s) {
    for (final k in ImportKind.values) {
      for (final f in _files.where((f) => f.kind == k && f.result.isEmpty)) {
        final rows = mapRows(f.rows, autoMap(k, f.rows.first));
        final errs = s.checkImport(k, rows);
        final (ins, upd) = s.applyImport(k, rows);
        final bad = errs.where((e) => e.isNotEmpty).length;
        f.result = '$ins جدید، $upd بروزرسانی${bad > 0 ? '، $bad خطا' : ''}';
      }
    }
    setState(() {});
    toast(context, 'انتقال اطلاعات انجام شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return SakanWindow(
      title: 'انتقال اطلاعات از سکان',
      width: 980,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'در نرم افزار سکان از جدول اشخاص، کالاها، پرسنل، اموال و تراز آزمایشی (سطح تفصیلی) «خروجی به اکسل» بگیرید و فایل ها را اینجا انتخاب کنید. '
            'نوع هر فایل از روی عنوان ستون ها تشخیص داده می شود و به ترتیب اشخاص، کالا، پرسنل، اموال و مانده دفاتر درج می گردد.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Row(children: [
            sakanBtn('انتخاب فایل های اکسل سکان', _pick, icon: Icons.folder_open_rounded),
            const SizedBox(width: 6),
            sakanBtn('پاک کردن لیست', _files.isEmpty ? null : () => setState(_files.clear)),
            const Spacer(),
            sakanBtn('شروع انتقال', _files.any((f) => f.kind != null && f.result.isEmpty) ? () => _run(s) : null, color: const Color(0xFFE8F5E9), icon: Icons.play_arrow_rounded),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [sakanHead('فایل', 0), sakanHead('ردیف ها', 80), sakanHead('نوع اطلاعات', 190), sakanHead('نتیجه', 220)],
              count: _files.length,
              empty: 'فایلی انتخاب نشده',
              row: (_, i) {
                final f = _files[i];
                return Row(children: [
                  sakanCell(Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr), 0),
                  sakanCell(Text('${f.rows.length - 1}'), 80),
                  sakanCell(
                    DropdownButton<ImportKind?>(
                      isDense: true,
                      isExpanded: true,
                      value: f.kind,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('تشخیص داده نشد / رد شود')),
                        for (final k in ImportKind.values) DropdownMenuItem(value: k, child: Text(k.label)),
                      ],
                      onChanged: f.result.isNotEmpty ? null : (k) => setState(() => f.kind = k),
                    ),
                    190,
                  ),
                  sakanCell(Text(f.result, style: const TextStyle(fontSize: 12)), 220),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
