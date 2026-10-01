import 'package:flutter/services.dart';

import 'jalali.dart';

/// Groups digits by thousands: 1234567 -> 1,234,567
String groupDigits(int value) {
  final neg = value < 0;
  final s = value.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    b.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) b.write(',');
  }
  return neg ? '-${b.toString()}' : b.toString();
}

/// Parses user input (may contain separators or Persian digits).
int parseMoney(String input) {
  final s = normalizeDigits(input).replaceAll(RegExp(r'[^0-9]'), '');
  if (s.isEmpty) return 0;
  return int.tryParse(s) ?? 0;
}

/// Converts a number to a short Persian reading, e.g. 2,500,000 -> "۲.۵ میلیون"
String compactMoney(int value) {
  final v = value.abs();
  String out;
  if (v >= 1000000000) {
    out = '${_trim(v / 1000000000)} میلیارد';
  } else if (v >= 1000000) {
    out = '${_trim(v / 1000000)} میلیون';
  } else if (v >= 1000) {
    out = '${_trim(v / 1000)} هزار';
  } else {
    out = v.toString();
  }
  return value < 0 ? '-$out' : out;
}

String _trim(double d) {
  final s = d.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Formatter that keeps digits only and inserts thousands separators.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = normalizeDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed.length > 15) return oldValue;
    final formatted = groupDigits(int.parse(trimmed));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Simple words for amounts (Persian), used under money fields.
String amountInWords(int n) {
  if (n == 0) return 'صفر';
  if (n < 0) return 'منفی ${amountInWords(-n)}';
  const ones = ['', 'یک', 'دو', 'سه', 'چهار', 'پنج', 'شش', 'هفت', 'هشت', 'نه'];
  const teens = [
    'ده', 'یازده', 'دوازده', 'سیزده', 'چهارده', 'پانزده', 'شانزده', 'هفده', 'هجده', 'نوزده'
  ];
  const tens = ['', '', 'بیست', 'سی', 'چهل', 'پنجاه', 'شصت', 'هفتاد', 'هشتاد', 'نود'];
  const hundreds = [
    '', 'صد', 'دویست', 'سیصد', 'چهارصد', 'پانصد', 'ششصد', 'هفتصد', 'هشتصد', 'نهصد'
  ];
  const scales = ['', 'هزار', 'میلیون', 'میلیارد', 'هزار میلیارد'];

  String three(int x) {
    final parts = <String>[];
    final h = x ~/ 100;
    final r = x % 100;
    if (h > 0) parts.add(hundreds[h]);
    if (r >= 10 && r < 20) {
      parts.add(teens[r - 10]);
    } else {
      final t = r ~/ 10;
      final o = r % 10;
      if (t > 0) parts.add(tens[t]);
      if (o > 0) parts.add(ones[o]);
    }
    return parts.join(' و ');
  }

  final groups = <String>[];
  var x = n;
  var i = 0;
  while (x > 0 && i < scales.length) {
    final g = x % 1000;
    if (g > 0) {
      final w = three(g);
      groups.insert(0, scales[i].isEmpty ? w : '$w ${scales[i]}');
    }
    x ~/= 1000;
    i++;
  }
  return groups.join(' و ');
}
