import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Minimal Excel (.xlsx / Office Open XML) writer and reader — «خروجی به اکسل»
/// and «خواندن از فایل اکسل» without CSV. Sheets are right-to-left, the header
/// row is bold with a grey fill and frozen, numbers keep thousands separators.

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // characters that are not allowed in XML 1.0
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

const _faDigits = '۰۱۲۳۴۵۶۷۸۹';
const _arDigits = '٠١٢٣٤٥٦٧٨٩';

String _latin(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    var i = _faDigits.indexOf(ch);
    if (i < 0) i = _arDigits.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b.toString();
}

/// Returns the numeric value of a cell text like "1,250,000" or "-۳۵۰", or null
/// when the text should stay text (codes with leading zeros, phone numbers…).
num? xlsxNumber(String text) {
  final t = _latin(text.trim()).replaceAll('٬', ',');
  if (t.isEmpty || t.length > 18) return null;
  if (!RegExp(r'^-?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$').hasMatch(t)) return null;
  final digits = t.replaceAll(',', '').replaceFirst('-', '');
  if (digits.length > 1 && digits.startsWith('0') && !digits.startsWith('0.')) return null;
  return num.tryParse(t.replaceAll(',', ''));
}

String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int _colIndex(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// One worksheet.
class XlsxSheet {
  final String name;
  final List<String> headers;
  final List<List<String>> rows;

  /// Optional title rows printed above the table (e.g. report name, date range).
  final List<String> titleLines;

  XlsxSheet(this.name, this.headers, this.rows, {this.titleLines = const []});
}

/// Builds an .xlsx file with one or more sheets.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final a = Archive();
  void add(String name, String xml) => a.addFile(ArchiveFile.string(name, xml));

  final names = <String>[];
  for (var i = 0; i < sheets.length; i++) {
    var n = sheets[i].name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (n.isEmpty) n = 'Sheet${i + 1}';
    if (n.length > 31) n = n.substring(0, 31);
    var u = n;
    var k = 2;
    while (names.contains(u)) {
      u = '${n.length > 27 ? n.substring(0, 27) : n} ($k)';
      k++;
    }
    names.add(u);
  }

  add('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''');

  add('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''');

  final now = DateTime.now().toUtc().toIso8601String().split('.').first;
  add('docProps/core.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:creator>Taraz</dc:creator>
<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created>
</cp:coreProperties>''');
  add('docProps/app.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Taraz</Application></Properties>''');

  add('xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<bookViews><workbookView/></bookViews>
<sheets>
${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_x(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets>
</workbook>''');

  add('xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join('\n')}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');

  // styles: 0 normal, 1 header (bold, grey fill, border), 2 number #,##0 (border),
  // 3 text (border), 4 title (bold, larger)
  add('xl/styles.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3">
<font><sz val="11"/><name val="Tahoma"/></font>
<font><b/><sz val="11"/><name val="Tahoma"/></font>
<font><b/><sz val="13"/><name val="Tahoma"/></font>
</fonts>
<fills count="3">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE5E7EB"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left style="thin"><color rgb="FFA3A3A3"/></left><right style="thin"><color rgb="FFA3A3A3"/></right><top style="thin"><color rgb="FFA3A3A3"/></top><bottom style="thin"><color rgb="FFA3A3A3"/></bottom><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="5">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="3" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''');

  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
  }
  return ZipEncoder().encodeBytes(a);
}

String _sheetXml(XlsxSheet s) {
  final cols = s.headers.length;
  final b = StringBuffer();
  var r = 0;

  String textCell(int c, String v, int style) =>
      '<c r="${_col(c)}${r + 1}" t="inlineStr" s="$style"><is><t xml:space="preserve">${_x(v)}</t></is></c>';

  for (final line in s.titleLines) {
    b.write('<row r="${r + 1}">${textCell(0, line, 4)}</row>');
    r++;
  }
  if (s.titleLines.isNotEmpty) r++; // blank row
  final headerRow = r;

  b.write('<row r="${r + 1}">');
  for (var c = 0; c < cols; c++) {
    b.write(textCell(c, s.headers[c], 1));
  }
  b.write('</row>');
  r++;

  // column widths from content length
  final widths = [for (final h in s.headers) h.length.toDouble() + 4];
  for (final row in s.rows) {
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < cols; c++) {
      final v = c < row.length ? row[c] : '';
      if (v.length + 3 > widths[c]) widths[c] = v.length + 3.0;
      final n = xlsxNumber(v);
      if (n != null) {
        b.write('<c r="${_col(c)}${r + 1}" s="2"><v>$n</v></c>');
      } else {
        b.write(textCell(c, v, 3));
      }
    }
    b.write('</row>');
    r++;
  }

  final lastCol = _col(cols == 0 ? 0 : cols - 1);
  final pane = '<pane ySplit="${headerRow + 1}" topLeftCell="A${headerRow + 2}" activePane="bottomLeft" state="frozen"/>';
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetViews><sheetView rightToLeft="1" workbookViewId="0">$pane</sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="18"/>
${cols == 0 ? '' : '<cols>${[for (var c = 0; c < cols; c++) '<col min="${c + 1}" max="${c + 1}" width="${widths[c].clamp(6, 60).toStringAsFixed(1)}" customWidth="1"/>'].join()}</cols>'}
<sheetData>${b.toString()}</sheetData>
${s.rows.isEmpty || cols == 0 ? '' : '<autoFilter ref="A${headerRow + 1}:$lastCol${headerRow + 1 + s.rows.length}"/>'}
<pageSetup paperSize="9" orientation="${cols > 7 ? 'landscape' : 'portrait'}"/>
</worksheet>''';
}

// ---------------------------------------------------------------------------- reading

String _unx(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16)))
    .replaceAll('&amp;', '&');

String _texts(String xml) =>
    RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>').allMatches(xml).map((m) => _unx(m[1]!)).join();

/// Reads the first worksheet of an .xlsx file as rows of cell text.
/// Throws [FormatException] when the file is not a valid workbook.
List<List<String>> readXlsx(List<int> bytes) {
  final Archive a;
  try {
    a = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('فایل اکسل معتبر نیست');
  }
  String? read(String name) {
    final f = a.findFile(name);
    return f == null ? null : utf8.decode(f.content, allowMalformed: true);
  }

  final shared = <String>[];
  final ss = read('xl/sharedStrings.xml');
  if (ss != null) {
    for (final m in RegExp(r'<si>([\s\S]*?)</si>').allMatches(ss)) {
      shared.add(_texts(m[1]!));
    }
  }

  // first sheet in workbook order
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final wb = read('xl/workbook.xml');
  final rels = read('xl/_rels/workbook.xml.rels');
  if (wb != null && rels != null) {
    final first = RegExp(r'<sheet\b[^>]*\br:id="([^"]+)"').firstMatch(wb)?[1];
    if (first != null) {
      final rel = RegExp('<Relationship\\b[^>]*Id="${RegExp.escape(first)}"[^>]*>').firstMatch(rels)?[0] ??
          '';
      final target = RegExp(r'Target="([^"]+)"').firstMatch(rel)?[1];
      if (target != null) {
        sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
  }
  final sheet = read(sheetPath) ?? read('xl/worksheets/sheet1.xml');
  if (sheet == null) throw const FormatException('برگه‌ای در فایل اکسل پیدا نشد');

  final out = <List<String>>[];
  for (final rm in RegExp(r'<row\b([^>]*?)(?:/>|>([\s\S]*?)</row>)').allMatches(sheet)) {
    final rowNo = int.tryParse(RegExp(r'\br="(\d+)"').firstMatch(rm[1]!)?[1] ?? '');
    if (rowNo != null) {
      while (out.length < rowNo - 1) {
        out.add(<String>[]);
      }
    }
    final body = rm[2];
    final row = <String>[];
    if (body != null) {
      for (final cm in RegExp(r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)').allMatches(body)) {
        final attrs = cm[1]!;
        final inner = cm[2] ?? '';
        final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attrs)?[1];
        final type = RegExp(r'\bt="([^"]+)"').firstMatch(attrs)?[1];
        final v = RegExp(r'<v>([\s\S]*?)</v>').firstMatch(inner)?[1];
        String text;
        if (type == 's') {
          final i = int.tryParse(v ?? '') ?? -1;
          text = i >= 0 && i < shared.length ? shared[i] : '';
        } else if (type == 'inlineStr') {
          text = _texts(inner);
        } else {
          text = _unx(v ?? '');
          // 1250000.0 → 1250000
          if (RegExp(r'^-?\d+\.0+$').hasMatch(text)) text = text.substring(0, text.indexOf('.'));
        }
        final idx = ref == null ? row.length : _colIndex(ref);
        while (row.length < idx) {
          row.add('');
        }
        if (idx < row.length) {
          row[idx] = text;
        } else {
          row.add(text);
        }
      }
    }
    out.add(row);
  }
  return out;
}
