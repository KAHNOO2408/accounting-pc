/// «لیست گارانتی»، «اعمال گارانتی» و «پذیرش» (رسید مشتری / برچسب تعمیر) —
/// Sakan's warranty and repair-service module (docs/sakan/forms/Garanti*, Paziresh_*).
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
String? _ds(DateTime? d) => d?.toIso8601String().substring(0, 10);
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// One «اعمال گارانتی» record: تعویض / جایگزین / تعمیر.
class WarrantyEvent {
  DateTime date;
  String kind; // تعویض، جایگزین، تعمیر
  String newSerial;
  String note;
  WarrantyEvent({required this.date, this.kind = 'تعمیر', this.newSerial = '', this.note = ''});
  Map<String, dynamic> toJson() => {'date': _ds(date), 'kind': kind, 'newSerial': newSerial, 'note': note};
  factory WarrantyEvent.fromJson(Map<String, dynamic> j) =>
      WarrantyEvent(date: _dt(j['date']) ?? DateTime.now(), kind: _s(j['kind']), newSerial: _s(j['newSerial']), note: _s(j['note']));
}

class Warranty {
  String id;
  int code; // کد گارانتی
  String? productId;
  String productName;
  String serial;
  DateTime start;
  DateTime end;
  String? personId; // مشتری
  String receiver; // نام دریافت کننده
  int invoiceNo;
  String contractNo;
  String note;
  List<WarrantyEvent> events;

  Warranty({
    required this.id,
    required this.code,
    this.productId,
    this.productName = '',
    this.serial = '',
    required this.start,
    required this.end,
    this.personId,
    this.receiver = '',
    this.invoiceNo = 0,
    this.contractNo = '',
    this.note = '',
    List<WarrantyEvent>? events,
  }) : events = events ?? [];

  bool activeAt(DateTime d) => !d.isBefore(DateTime(start.year, start.month, start.day)) && !d.isAfter(DateTime(end.year, end.month, end.day, 23, 59));

  /// Current serial (after the last replacement).
  String get currentSerial => events.lastWhere((e) => e.newSerial.isNotEmpty, orElse: () => WarrantyEvent(date: start, newSerial: serial)).newSerial;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'productId': productId,
        'productName': productName,
        'serial': serial,
        'start': _ds(start),
        'end': _ds(end),
        'personId': personId,
        'receiver': receiver,
        'invoiceNo': invoiceNo,
        'contractNo': contractNo,
        'note': note,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory Warranty.fromJson(Map<String, dynamic> j) => Warranty(
        id: _s(j['id']),
        code: _i(j['code']),
        productId: _sn(j['productId']),
        productName: _s(j['productName']),
        serial: _s(j['serial']),
        start: _dt(j['start']) ?? DateTime.now(),
        end: _dt(j['end']) ?? DateTime.now(),
        personId: _sn(j['personId']),
        receiver: _s(j['receiver']),
        invoiceNo: _i(j['invoiceNo']),
        contractNo: _s(j['contractNo']),
        note: _s(j['note']),
        events: _list(j['events']).map(WarrantyEvent.fromJson).toList(),
      );
}

const receptionStatuses = ['پذیرش شده', 'در حال تعمیر', 'منتظر قطعه', 'آماده تحویل', 'تحویل شده', 'غیر قابل تعمیر'];

/// «پذیرش»: a device received from a customer for repair.
class Reception {
  String id;
  int number; // شماره پذیرش
  DateTime date; // تاریخ و ساعت تحویل از مشتری
  String? personId;
  String? productId;
  String productName;
  String serial;
  int warrantyCode; // 0 = بدون گارانتی
  String location; // مکان پذیرش
  String problem; // ایراد اعلام شده
  String accessories; // لوازم همراه
  int estimate; // هزینه تقریبی
  DateTime? promised; // تاریخ تحویل احتمالی
  String status;
  String repairNote; // شرح تعمیرات
  int cost; // هزینه نهایی
  DateTime? deliveredOn;
  String? invoiceId;
  String user;

  Reception({
    required this.id,
    required this.number,
    required this.date,
    this.personId,
    this.productId,
    this.productName = '',
    this.serial = '',
    this.warrantyCode = 0,
    this.location = '',
    this.problem = '',
    this.accessories = '',
    this.estimate = 0,
    this.promised,
    this.status = 'پذیرش شده',
    this.repairNote = '',
    this.cost = 0,
    this.deliveredOn,
    this.invoiceId,
    this.user = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'date': date.toIso8601String(),
        'personId': personId,
        'productId': productId,
        'productName': productName,
        'serial': serial,
        'warrantyCode': warrantyCode,
        'location': location,
        'problem': problem,
        'accessories': accessories,
        'estimate': estimate,
        'promised': _ds(promised),
        'status': status,
        'repairNote': repairNote,
        'cost': cost,
        'deliveredOn': _ds(deliveredOn),
        'invoiceId': invoiceId,
        'user': user,
      };

  factory Reception.fromJson(Map<String, dynamic> j) => Reception(
        id: _s(j['id']),
        number: _i(j['number']),
        date: _dt(j['date']) ?? DateTime.now(),
        personId: _sn(j['personId']),
        productId: _sn(j['productId']),
        productName: _s(j['productName']),
        serial: _s(j['serial']),
        warrantyCode: _i(j['warrantyCode']),
        location: _s(j['location']),
        problem: _s(j['problem']),
        accessories: _s(j['accessories']),
        estimate: _i(j['estimate']),
        promised: _dt(j['promised']),
        status: _sn(j['status']) ?? receptionStatuses.first,
        repairNote: _s(j['repairNote']),
        cost: _i(j['cost']),
        deliveredOn: _dt(j['deliveredOn']),
        invoiceId: _sn(j['invoiceId']),
        user: _s(j['user']),
      );
}
