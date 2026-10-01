// Jalali (Shamsi) calendar conversion.
// Port of the jalaali-js algorithm (MIT). Dart's ~/ truncates toward zero,
// which matches the original JS ~~(a / b) semantics.

const List<int> _breaks = [
  -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635, 2060, 2097,
  2192, 2262, 2324, 2394, 2456, 3178,
];

int _div(int a, int b) => a ~/ b;
int _mod(int a, int b) => a - (a ~/ b) * b;

class _JalCal {
  final int leap;
  final int gy;
  final int march;
  const _JalCal(this.leap, this.gy, this.march);
}

_JalCal _jalCal(int jy) {
  final bl = _breaks.length;
  final gy = jy + 621;
  var leapJ = -14;
  var jp = _breaks[0];
  var jump = 0;
  for (var i = 1; i < bl; i++) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    leapJ = leapJ + _div(jump, 33) * 8 + _div(_mod(jump, 33), 4);
    jp = jm;
  }
  var n = jy - jp;
  leapJ = leapJ + _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4);
  if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;
  final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
  final march = 20 + leapJ - leapG;
  if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
  var leap = _mod(_mod(n + 1, 33) - 1, 4);
  if (leap == -1) leap = 4;
  return _JalCal(leap, gy, march);
}

int _g2d(int gy, int gm, int gd) {
  var d = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4) +
      _div(153 * _mod(gm + 9, 12) + 2, 5) +
      gd -
      34840408;
  d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
  return d;
}

List<int> _d2g(int jdn) {
  var j = 4 * jdn + 139361631;
  j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908;
  final i = _div(_mod(j, 1461), 4) * 5 + 308;
  final gd = _div(_mod(i, 153), 5) + 1;
  final gm = _mod(_div(i, 153), 12) + 1;
  final gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
  return [gy, gm, gd];
}

int _j2d(int jy, int jm, int jd) {
  final r = _jalCal(jy);
  return _g2d(r.gy, 3, r.march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1;
}

List<int> _d2j(int jdn) {
  final gy = _d2g(jdn)[0];
  var jy = gy - 621;
  final r = _jalCal(jy);
  final jdn1f = _g2d(gy, 3, r.march);
  var k = jdn - jdn1f;
  if (k >= 0) {
    if (k <= 185) {
      return [jy, 1 + _div(k, 31), _mod(k, 31) + 1];
    } else {
      k -= 186;
    }
  } else {
    jy -= 1;
    k += 179;
    if (r.leap == 1) k += 1;
  }
  return [jy, 7 + _div(k, 30), _mod(k, 30) + 1];
}

const List<String> jalaliMonthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

/// Saturday-first week day names.
const List<String> jalaliWeekDays = [
  'شنبه',
  'یکشنبه',
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
];

const List<String> jalaliWeekDaysShort = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

class Jalali implements Comparable<Jalali> {
  final int year;
  final int month;
  final int day;

  const Jalali(this.year, this.month, this.day);

  factory Jalali.fromDateTime(DateTime dt) {
    final r = _d2j(_g2d(dt.year, dt.month, dt.day));
    return Jalali(r[0], r[1], r[2]);
  }

  factory Jalali.now() => Jalali.fromDateTime(DateTime.now());

  DateTime toDateTime() {
    final g = _d2g(_j2d(year, month, day));
    return DateTime(g[0], g[1], g[2]);
  }

  static bool isLeapYear(int jy) => _jalCal(jy).leap == 0;

  static int monthLength(int jy, int jm) {
    if (jm <= 6) return 31;
    if (jm <= 11) return 30;
    return isLeapYear(jy) ? 30 : 29;
  }

  int get monthLen => monthLength(year, month);

  /// 0 = Saturday ... 6 = Friday
  int get weekDayIndex => (toDateTime().weekday + 1) % 7;

  String get monthName => jalaliMonthNames[month - 1];

  Jalali addMonths(int n) {
    var total = (year * 12 + (month - 1)) + n;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final len = monthLength(y, m);
    return Jalali(y, m, day > len ? len : day);
  }

  Jalali get firstOfMonth => Jalali(year, month, 1);
  Jalali get lastOfMonth => Jalali(year, month, monthLen);

  /// Key like 140507 for grouping by month.
  int get monthKey => year * 100 + month;

  String format({String sep = '/'}) =>
      '$year$sep${month.toString().padLeft(2, '0')}$sep${day.toString().padLeft(2, '0')}';

  String formatLong() => '$day $monthName $year';

  String formatWithWeekday() => '${jalaliWeekDays[weekDayIndex]} ${formatLong()}';

  @override
  int compareTo(Jalali other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is Jalali && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => format();

  /// Parses "1405/07/09" or "1405-7-9" (Latin or Persian digits).
  static Jalali? tryParse(String input) {
    final s = normalizeDigits(input).trim();
    final parts = s.split(RegExp(r'[/\-\.\s]+'));
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (y < 1300 || y > 1600 || m < 1 || m > 12 || d < 1) return null;
    if (d > monthLength(y, m)) return null;
    return Jalali(y, m, d);
  }
}

/// Converts Persian/Arabic-Indic digits to Latin digits.
String normalizeDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
      continue;
    }
    final j = ar.indexOf(ch);
    if (j >= 0) {
      b.write(j);
      continue;
    }
    b.write(ch);
  }
  return b.toString();
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String jFormat(DateTime d) => Jalali.fromDateTime(d).format();
String jFormatLong(DateTime d) => Jalali.fromDateTime(d).formatLong();
