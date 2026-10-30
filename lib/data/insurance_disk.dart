/// «دیسک بیمه» — the monthly social-security list as DSKKAR00.DBF (workshop)
/// and DSKWOR00.DBF (workers), dBase III with Iran System text, the format
/// accepted by the تامین اجتماعی portal (field layout as in Sakan's templates).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/iran_system.dart';
import '../core/jalali.dart';
import 'payroll.dart';
import 'store.dart';

class DbfField {
  final String name;
  final String type; // C or N
  final int len;
  const DbfField(this.name, this.type, this.len);
}

const dskKarFields = [
  DbfField('DSK_ID', 'C', 10), DbfField('DSK_NAME', 'C', 30), DbfField('DSK_FARM', 'C', 30), DbfField('DSK_ADRS', 'C', 40), //
  DbfField('DSK_KIND', 'N', 1), DbfField('DSK_YY', 'N', 2), DbfField('DSK_MM', 'N', 2), DbfField('DSK_LISTNO', 'C', 12),
  DbfField('DSK_DISC', 'C', 30), DbfField('DSK_NUM', 'N', 5), DbfField('DSK_TDD', 'N', 6), DbfField('DSK_TROOZ', 'N', 12),
  DbfField('DSK_TMAH', 'N', 12), DbfField('DSK_TMAZ', 'N', 12), DbfField('DSK_TMASH', 'N', 12), DbfField('DSK_TTOTL', 'N', 12),
  DbfField('DSK_TBIME', 'N', 12), DbfField('DSK_TKOSO', 'N', 12), DbfField('DSK_BIC', 'N', 12), DbfField('DSK_RATE', 'N', 5),
  DbfField('DSK_PRATE', 'N', 2), DbfField('DSK_BIMH', 'N', 12), DbfField('MON_PYM', 'C', 3),
];

const dskWorFields = [
  DbfField('DSW_ID', 'C', 10), DbfField('DSW_YY', 'N', 2), DbfField('DSW_MM', 'N', 2), DbfField('DSW_LISTNO', 'C', 12), //
  DbfField('DSW_ID1', 'C', 8), DbfField('DSW_FNAME', 'C', 20), DbfField('DSW_LNAME', 'C', 25), DbfField('DSW_DNAME', 'C', 20),
  DbfField('DSW_IDNO', 'C', 15), DbfField('DSW_IDPLC', 'C', 30), DbfField('DSW_IDATE', 'C', 8), DbfField('DSW_BDATE', 'C', 8),
  DbfField('DSW_SEX', 'C', 3), DbfField('DSW_NAT', 'C', 10), DbfField('DSW_OCP', 'C', 50), DbfField('DSW_SDATE', 'C', 8),
  DbfField('DSW_EDATE', 'C', 8), DbfField('DSW_DD', 'N', 2), DbfField('DSW_ROOZ', 'N', 12), DbfField('DSW_MAH', 'N', 12),
  DbfField('DSW_MAZ', 'N', 12), DbfField('DSW_MASH', 'N', 12), DbfField('DSW_TOTL', 'N', 12), DbfField('DSW_BIME', 'N', 12),
  DbfField('DSW_PRATE', 'N', 2), DbfField('DSW_JOB', 'C', 6), DbfField('PER_NATCOD', 'C', 10),
];

/// Builds a dBase III file. Values: String (C, already-encoded via [persian]) or num (N).
Uint8List buildDbf(List<DbfField> fields, List<Map<String, Object>> records, {Set<String> persian = const {}, DateTime? now}) {
  final d = now ?? DateTime.now();
  final recLen = 1 + fields.fold<int>(0, (a, f) => a + f.len);
  final hdrLen = 32 + 32 * fields.length + 1;
  final b = BytesBuilder();
  final h = ByteData(32)
    ..setUint8(0, 0x03)
    ..setUint8(1, d.year - 1900)
    ..setUint8(2, d.month)
    ..setUint8(3, d.day)
    ..setUint32(4, records.length, Endian.little)
    ..setUint16(8, hdrLen, Endian.little)
    ..setUint16(10, recLen, Endian.little);
  b.add(h.buffer.asUint8List());
  for (final f in fields) {
    final fd = Uint8List(32);
    final n = ascii.encode(f.name);
    fd.setRange(0, n.length, n);
    fd[11] = f.type.codeUnitAt(0);
    fd[16] = f.len;
    b.add(fd);
  }
  b.addByte(0x0D);
  for (final r in records) {
    b.addByte(0x20);
    for (final f in fields) {
      final v = r[f.name];
      final cell = Uint8List(f.len)..fillRange(0, f.len, 0x20);
      if (f.type == 'N') {
        final t = v is num ? (v is double ? v.round() : v).toString() : '${v ?? ''}';
        final bytes = ascii.encode(t.length > f.len ? t.substring(t.length - f.len) : t);
        cell.setRange(f.len - bytes.length, f.len, bytes);
      } else {
        final s = '${v ?? ''}';
        final bytes = persian.contains(f.name) ? encodeIranSystem(s) : ascii.encode(normalizeDigits(s).replaceAll(RegExp(r'[^\x20-\x7E]'), ''));
        cell.setRange(0, bytes.length > f.len ? f.len : bytes.length, bytes);
      }
      b.add(cell);
    }
  }
  b.addByte(0x1A);
  return b.toBytes();
}

String _jd(DateTime? d) {
  if (d == null) return '';
  final j = Jalali.fromDateTime(d);
  return '${j.year.toString().padLeft(4, '0')}${j.month.toString().padLeft(2, '0')}${j.day.toString().padLeft(2, '0')}';
}

/// (DSKKAR00.DBF, DSKWOR00.DBF) for a pay period.
(Uint8List, Uint8List) insuranceDisk(AppStore s, PayPeriod p, {String listNo = '01', String description = '', String contract = '000'}) {
  final w = s.workshop;
  final yy = p.year % 100;
  final workers = <Map<String, Object>>[];
  var tdd = 0, trooz = 0, tmah = 0, tmaz = 0, tmash = 0, ttotl = 0, tbime = 0, tkoso = 0, tbic = 0, thard = 0;
  for (final e in s.employeesIn(p)) {
    final r = s.payResult(p, e);
    final days = r.workDays.round();
    final maz = r.dastmozdMashmoolBime - r.hoghoghMahiane;
    workers.add({
      'DSW_ID': w.code,
      'DSW_YY': yy,
      'DSW_MM': p.month,
      'DSW_LISTNO': listNo,
      'DSW_ID1': e.insuranceNo,
      'DSW_FNAME': e.firstName,
      'DSW_LNAME': e.lastName,
      'DSW_DNAME': e.fatherName,
      'DSW_IDNO': e.idNo,
      'DSW_IDPLC': e.issuePlace,
      'DSW_IDATE': '',
      'DSW_BDATE': _jd(e.birthDate),
      'DSW_SEX': e.male ? 'مرد' : 'زن',
      'DSW_NAT': e.nationality.isEmpty ? 'ایرانی' : e.nationality,
      'DSW_OCP': e.jobName,
      'DSW_SDATE': e.hireDate != null && !e.hireDate!.isBefore(p.start) ? _jd(e.hireDate) : '',
      'DSW_EDATE': e.endDate != null && !e.endDate!.isAfter(p.end) ? _jd(e.endDate) : '',
      'DSW_DD': days,
      'DSW_ROOZ': r.dailyWage,
      'DSW_MAH': r.hoghoghMahiane,
      'DSW_MAZ': maz,
      'DSW_MASH': r.dastmozdMashmoolBime,
      'DSW_TOTL': r.jamKol,
      'DSW_BIME': r.bimeSahmBimeShode,
      'DSW_PRATE': 0,
      'DSW_JOB': e.jobCode,
      'PER_NATCOD': e.nationalId,
    });
    tdd += days;
    trooz += r.dailyWage;
    tmah += r.hoghoghMahiane;
    tmaz += maz;
    tmash += r.dastmozdMashmoolBime;
    ttotl += r.jamKol;
    tbime += r.bimeSahmBimeShode;
    tkoso += r.bimeSahmKarfarma;
    tbic += r.bimeBikari;
    thard += r.bimeMashagheleSakht;
  }
  final kar = buildDbf(dskKarFields, [
    {
      'DSK_ID': w.code,
      'DSK_NAME': w.name,
      'DSK_FARM': w.employer,
      'DSK_ADRS': w.address,
      'DSK_KIND': 0,
      'DSK_YY': yy,
      'DSK_MM': p.month,
      'DSK_LISTNO': listNo,
      'DSK_DISC': description.isEmpty ? 'لیست ماه ${p.month} سال ${p.year}' : description,
      'DSK_NUM': workers.length,
      'DSK_TDD': tdd,
      'DSK_TROOZ': trooz,
      'DSK_TMAH': tmah,
      'DSK_TMAZ': tmaz,
      'DSK_TMASH': tmash,
      'DSK_TTOTL': ttotl,
      'DSK_TBIME': tbime,
      'DSK_TKOSO': tkoso,
      'DSK_BIC': tbic,
      'DSK_RATE': (s.payrollRules.employerPct + s.payrollRules.unemploymentPct).round(),
      'DSK_PRATE': 0,
      'DSK_BIMH': thard,
      'MON_PYM': contract,
    },
  ], persian: const {'DSK_NAME', 'DSK_FARM', 'DSK_ADRS', 'DSK_DISC'});
  final wor = buildDbf(dskWorFields, workers, persian: const {'DSW_FNAME', 'DSW_LNAME', 'DSW_DNAME', 'DSW_IDPLC', 'DSW_SEX', 'DSW_NAT', 'DSW_OCP'});
  return (kar, wor);
}
