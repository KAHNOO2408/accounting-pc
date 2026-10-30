/// «حضور و غیاب»: shifts, clock records («تردد»), imports from the clock's
/// Excel/CSV export and the monthly result («عملکرد ماهانه پرسنل»).
library;

import '../core/jalali.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class Shift {
  String id;
  String name;
  int start; // minutes from midnight
  int end;
  int breakMinutes;
  int graceMinutes; // تاخیر مجاز
  bool thursdayHalf; // پنجشنبه نیمه وقت
  Shift({required this.id, required this.name, this.start = 8 * 60, this.end = 16 * 60, this.breakMinutes = 30, this.graceMinutes = 0, this.thursdayHalf = false});

  int lengthOn(DateTime d) {
    final full = end - start - breakMinutes;
    if (d.weekday == DateTime.thursday && thursdayHalf) return full ~/ 2;
    return full;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'start': start, 'end': end, 'breakMinutes': breakMinutes, 'graceMinutes': graceMinutes, 'thursdayHalf': thursdayHalf};
  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        id: _s(j['id']),
        name: _s(j['name']),
        start: j['start'] == null ? 480 : _i(j['start']),
        end: j['end'] == null ? 960 : _i(j['end']),
        breakMinutes: _i(j['breakMinutes']),
        graceMinutes: _i(j['graceMinutes']),
        thursdayHalf: j['thursdayHalf'] == true,
      );
}

/// One day of an employee: first entry and last exit (minutes from midnight).
class ClockRecord {
  String employeeId;
  DateTime date;
  int? inMin;
  int? outMin;
  String note;
  bool edited; // «اصلاح تردد»
  ClockRecord({required this.employeeId, required this.date, this.inMin, this.outMin, this.note = '', this.edited = false});

  int get worked => inMin == null || outMin == null || outMin! <= inMin! ? 0 : outMin! - inMin!;

  Map<String, dynamic> toJson() => {'e': employeeId, 'd': date.toIso8601String().substring(0, 10), 'i': inMin, 'o': outMin, if (note.isNotEmpty) 'n': note, if (edited) 'x': true};
  factory ClockRecord.fromJson(Map<String, dynamic> j) => ClockRecord(
        employeeId: _s(j['e']),
        date: DateTime.tryParse(_s(j['d'])) ?? DateTime(2000),
        inMin: j['i'] is num ? (j['i'] as num).toInt() : null,
        outMin: j['o'] is num ? (j['o'] as num).toInt() : null,
        note: _s(j['n']),
        edited: j['x'] == true,
      );
}

String hm(int? m) => m == null ? '' : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

int? parseHm(String t) {
  final m = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(normalizeDigits(t));
  if (m == null) return null;
  final h = int.parse(m[1]!), mi = int.parse(m[2]!);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

/// Parses a date cell: Jalali «1405/08/08», Gregorian «2026-10-30», or an Excel serial.
DateTime? parseClockDate(String t) {
  final v = normalizeDigits(t.trim());
  final serial = double.tryParse(v);
  if (serial != null && serial > 20000 && serial < 80000) return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
  final m = RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (y < 1700) return Jalali(y, mo, d).toDateTime();
  return DateTime(y, mo, d);
}

/// Reads clock rows. Recognised layouts (header row optional):
/// code, date, in, out — or code, date, time (one punch per row) — or
/// code, «date time» (one punch per row). Returns (code, date, minutes) punches.
List<(String, DateTime, int)> parseClockRows(List<List<String>> rows) {
  final out = <(String, DateTime, int)>[];
  for (final r in rows) {
    final cells = r.map((c) => c.trim()).toList();
    if (cells.length < 2) continue;
    final code = normalizeDigits(cells[0]);
    if (code.isEmpty || !RegExp(r'^\d+$').hasMatch(code)) continue; // header or blank
    final d = parseClockDate(cells[1]);
    if (d == null) continue;
    final day = DateTime(d.year, d.month, d.day);
    final times = <int>[];
    final inline = parseHm(cells[1].contains(' ') ? cells[1].split(' ').last : '');
    if (inline != null) times.add(inline);
    for (final c in cells.skip(2)) {
      final t = parseHm(c);
      if (t != null) times.add(t);
    }
    for (final t in times) {
      out.add((code, day, t));
    }
  }
  return out;
}

/// Monthly result of one employee.
class AttendanceResult {
  int presentDays = 0;
  int absentDays = 0;
  int workedMinutes = 0;
  int overtimeMinutes = 0;
  int shortMinutes = 0; // تاخیر + تعجیل
  int lateCount = 0;
  int incomplete = 0; // روزهای ناقص (فقط ورود یا فقط خروج)
}

AttendanceResult attendanceOf(List<ClockRecord> records, Shift shift, DateTime from, DateTime to, {Set<DateTime> holidays = const {}}) {
  final r = AttendanceResult();
  final byDay = {for (final c in records) DateTime(c.date.year, c.date.month, c.date.day): c};
  for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final off = d.weekday == DateTime.friday || holidays.contains(d);
    final c = byDay[d];
    if (c == null || (c.inMin == null && c.outMin == null)) {
      if (!off) r.absentDays++;
      continue;
    }
    if (c.inMin == null || c.outMin == null) {
      r.incomplete++;
      r.presentDays++;
      continue;
    }
    r.presentDays++;
    final w = c.worked - (c.worked > 6 * 60 ? shift.breakMinutes : 0);
    r.workedMinutes += w;
    if (off) {
      r.overtimeMinutes += w;
      continue;
    }
    final need = shift.lengthOn(d);
    if (c.inMin! > shift.start + shift.graceMinutes) r.lateCount++;
    if (w > need) {
      r.overtimeMinutes += w - need;
    } else {
      r.shortMinutes += need - w;
    }
  }
  return r;
}
