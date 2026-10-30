/// «ایران سیستم» — the DOS-era Persian code page still required by the
/// social-security insurance disk (DSKKAR00 / DSKWOR00). Letters are stored
/// in their visual (shaped) form, left to right.
library;

import 'dart:typed_data';

// (isolated/final, initial/medial) for dual-joining letters
const _dual = <String, (int, int)>{
  'ب': (0x92, 0x93), 'پ': (0x94, 0x95), 'ت': (0x96, 0x97), 'ث': (0x98, 0x99), 'ج': (0x9A, 0x9B), 'چ': (0x9C, 0x9D), //
  'ح': (0x9E, 0x9F), 'خ': (0xA0, 0xA1), 'س': (0xA7, 0xA8), 'ش': (0xA9, 0xAA), 'ص': (0xAB, 0xAC), 'ض': (0xAD, 0xAE),
  'ط': (0xAF, 0xAF), 'ظ': (0xE0, 0xE0), 'ف': (0xE9, 0xEA), 'ق': (0xEB, 0xEC), 'ک': (0xED, 0xEE), 'گ': (0xEF, 0xF0),
  'ل': (0xF1, 0xF3), 'م': (0xF4, 0xF5), 'ن': (0xF6, 0xF7), 'ئ': (0xFE, 0x8E),
};

// right-joining letters: (isolated, final)
const _right = <String, (int, int)>{
  'ا': (0x90, 0x91), 'آ': (0x8D, 0x8D), 'د': (0xA2, 0xA2), 'ذ': (0xA3, 0xA3), 'ر': (0xA4, 0xA4), 'ز': (0xA5, 0xA5),
  'ژ': (0xA6, 0xA6), 'و': (0xF8, 0xF8),
};

const _fold = {'ك': 'ک', 'ي': 'ی', 'ى': 'ی', 'ة': 'ه', 'أ': 'ا', 'إ': 'ا', 'ٱ': 'ا', 'ؤ': 'و', 'ۀ': 'ه', 'ٔ': ''};

const _other = <String, int>{'،': 0x8A, 'ـ': 0x8B, '؟': 0x8C, 'ء': 0x8F, '؛': 0x3B, '٫': 0x2E};

bool _letter(String c) => _dual.containsKey(c) || _right.containsKey(c) || c == 'ع' || c == 'غ' || c == 'ه' || c == 'ی';
bool _joinsNext(String c) => _dual.containsKey(c) || c == 'ع' || c == 'غ' || c == 'ه' || c == 'ی';

/// Encodes [text] to Iran System bytes in visual order.
Uint8List encodeIranSystem(String text) {
  final chars = <String>[];
  for (final r in text.runes) {
    var c = String.fromCharCode(r);
    if (r >= 0x06F0 && r <= 0x06F9) c = String.fromCharCode(0x30 + r - 0x06F0); // Persian digits → ASCII
    if (r >= 0x0660 && r <= 0x0669) c = String.fromCharCode(0x30 + r - 0x0660);
    c = _fold[c] ?? c;
    if (c.isNotEmpty) chars.add(c);
  }
  // logical cells: (bytes, rtl)
  final cells = <(List<int>, bool)>[];
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    final prev = i > 0 ? chars[i - 1] : '';
    final next = i + 1 < chars.length ? chars[i + 1] : '';
    final fromPrev = _joinsNext(prev);
    final toNext = _joinsNext(c) && _letter(next);
    if (c == 'ل' && next == 'ا') {
      cells.add(([0xF2], true));
      i++;
      continue;
    }
    if (c == '‌') continue; // نیم فاصله: just breaks the joining
    int? b;
    if (_dual.containsKey(c)) {
      b = toNext ? _dual[c]!.$2 : _dual[c]!.$1;
    } else if (_right.containsKey(c)) {
      b = fromPrev ? _right[c]!.$2 : _right[c]!.$1;
    } else if (c == 'ع' || c == 'غ') {
      final base = c == 'ع' ? 0xE1 : 0xE5; // iso, final, medial, initial
      b = base + (fromPrev ? (toNext ? 2 : 1) : (toNext ? 3 : 0));
    } else if (c == 'ه') {
      b = toNext ? (fromPrev ? 0xFA : 0xFB) : 0xF9;
    } else if (c == 'ی') {
      b = toNext ? 0xFE : (fromPrev ? 0xFC : 0xFD);
    } else if (_other.containsKey(c)) {
      b = _other[c];
    }
    if (b != null) {
      cells.add(([b], true));
    } else {
      final code = c.codeUnitAt(0);
      cells.add(([code < 0x80 ? code : 0x3F], code < 0x80 && RegExp(r'[0-9A-Za-z]').hasMatch(c) ? false : true));
    }
  }
  // visual order: runs reversed; Persian runs reversed inside, latin/digit runs kept
  final runs = <(List<int>, bool)>[];
  for (final (b, rtl) in cells) {
    if (runs.isNotEmpty && runs.last.$2 == rtl) {
      runs.last.$1.addAll(b);
    } else {
      runs.add(([...b], rtl));
    }
  }
  final out = <int>[];
  for (final (b, rtl) in runs.reversed) {
    out.addAll(rtl ? b.reversed : b);
  }
  return Uint8List.fromList(out);
}
