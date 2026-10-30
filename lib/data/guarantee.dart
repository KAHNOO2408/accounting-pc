/// «اسناد انتظامی»: سفته، وثیقه، ضمانت‌نامه… received from or issued to a
/// person («دریافت انتظامی» / «صدور انتظامی») and their return («عودت»).
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
String? _ds(DateTime? d) => d?.toIso8601String().substring(0, 10);
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

enum GuaranteeKind { safte, vasighe, zemanat, cheque, other }

extension GuaranteeKindX on GuaranteeKind {
  String get label => switch (this) {
        GuaranteeKind.safte => 'سفته',
        GuaranteeKind.vasighe => 'وثیقه',
        GuaranteeKind.zemanat => 'ضمانت نامه',
        GuaranteeKind.cheque => 'چک تضمین',
        GuaranteeKind.other => 'سایر',
      };
}

class GuaranteeItem {
  String id;
  GuaranteeKind kind;
  String serial; // شماره سریال
  int amount;
  DateTime? dueDate; // تاریخ سررسید
  String bank;
  String place; // مکان نگهداری
  String owner; // متعلق به
  DateTime? returnedOn; // عودت
  String returnNote;

  GuaranteeItem({required this.id, this.kind = GuaranteeKind.safte, this.serial = '', this.amount = 0, this.dueDate, this.bank = '', this.place = '', this.owner = '', this.returnedOn, this.returnNote = ''});

  bool get open => returnedOn == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'serial': serial,
        'amount': amount,
        'dueDate': _ds(dueDate),
        'bank': bank,
        'place': place,
        'owner': owner,
        'returnedOn': _ds(returnedOn),
        'returnNote': returnNote,
      };

  factory GuaranteeItem.fromJson(Map<String, dynamic> j) => GuaranteeItem(
        id: _s(j['id']),
        kind: GuaranteeKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => GuaranteeKind.other),
        serial: _s(j['serial']),
        amount: _i(j['amount']),
        dueDate: _dt(j['dueDate']),
        bank: _s(j['bank']),
        place: _s(j['place']),
        owner: _s(j['owner']),
        returnedOn: _dt(j['returnedOn']),
        returnNote: _s(j['returnNote']),
      );
}

class GuaranteeDoc {
  String id;
  int number;
  DateTime date;
  bool received; // دریافت انتظامی (true) / صدور انتظامی (false)
  String? personId;
  String babat; // بابت
  List<GuaranteeItem> items;
  int createdAt;

  GuaranteeDoc({required this.id, required this.number, required this.date, this.received = true, this.personId, this.babat = '', List<GuaranteeItem>? items, int? createdAt})
      : items = items ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  String get label => received ? 'دریافت انتظامی' : 'صدور انتظامی';
  int get total => items.fold(0, (a, i) => a + i.amount);
  int get openTotal => items.where((i) => i.open).fold(0, (a, i) => a + i.amount);

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'date': _ds(date),
        'received': received,
        'personId': personId,
        'babat': babat,
        'items': items.map((e) => e.toJson()).toList(),
        'createdAt': createdAt,
      };

  factory GuaranteeDoc.fromJson(Map<String, dynamic> j) => GuaranteeDoc(
        id: _s(j['id']),
        number: _i(j['number']),
        date: _dt(j['date']) ?? DateTime.now(),
        received: j['received'] != false,
        personId: j['personId'] is String && (j['personId'] as String).isNotEmpty ? j['personId'] as String : null,
        babat: _s(j['babat']),
        items: _list(j['items']).map(GuaranteeItem.fromJson).toList(),
        createdAt: _i(j['createdAt']),
      );
}
