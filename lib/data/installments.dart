/// «دفترچه اقساط» with «گزارش مطالبات» (receivable) and «گزارش تعهدات»
/// (payable) — Sakan DaftarcheAghsat / MFull / TFull / TAll.
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
String? _ds(DateTime? d) => d?.toIso8601String().substring(0, 10);
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class Installment {
  DateTime due;
  int amount;
  DateTime? paidOn;
  int paid;
  Installment({required this.due, required this.amount, this.paidOn, this.paid = 0});
  bool get settled => paid >= amount;
  int get remaining => amount - paid;
  Map<String, dynamic> toJson() => {'due': _ds(due), 'amount': amount, 'paidOn': _ds(paidOn), 'paid': paid};
  factory Installment.fromJson(Map<String, dynamic> j) =>
      Installment(due: _dt(j['due']) ?? DateTime.now(), amount: _i(j['amount']), paidOn: _dt(j['paidOn']), paid: _i(j['paid']));
}

class InstallmentPlan {
  String id;
  String? personId;
  bool receivable; // مطالبات (true) / تعهدات (false)
  int principal; // کل مبلغ
  int count; // تعداد اقساط
  DateTime interestFrom; // تاریخ شروع محاسبه سود
  DateTime firstDue; // تاریخ شروع پرداخت اقساط
  int everyMonths;
  double interestPct; // درصد سود (سالانه)
  double penaltyPct; // درصد جریمه (ماهانه، روی قسط معوق)
  String babat;
  List<Installment> items;
  int createdAt;

  /// «اطلاعات ضامن».
  String guarantorName = '';
  String guarantorPhone = '';
  String guarantorId = ''; // کد ملی

  InstallmentPlan({
    required this.id,
    this.personId,
    this.receivable = true,
    this.principal = 0,
    this.count = 1,
    required this.interestFrom,
    required this.firstDue,
    this.everyMonths = 1,
    this.interestPct = 0,
    this.penaltyPct = 0,
    this.babat = '',
    List<Installment>? items,
    int? createdAt,
  })  : items = items ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// «سود متعلقه»: simple annual interest from [interestFrom] to each due date.
  int get interest => items.fold(0, (a, i) => a + i.amount) - principal;
  int get total => items.fold(0, (a, i) => a + i.amount);
  int get paid => items.fold(0, (a, i) => a + i.paid);
  int get remaining => total - paid;

  /// Builds the schedule: equal principal shares plus interest of each share.
  void generate() {
    items = [];
    if (count <= 0) return;
    final share = principal ~/ count;
    for (var k = 0; k < count; k++) {
      final due = DateTime(firstDue.year, firstDue.month + k * everyMonths, firstDue.day);
      final p = k == count - 1 ? principal - share * (count - 1) : share;
      final days = due.difference(interestFrom).inDays.clamp(0, 1 << 30);
      final intr = (p * interestPct / 100 * days / 365).round();
      items.add(Installment(due: due, amount: p + intr));
    }
  }

  /// Penalty of an overdue installment at [at].
  int penaltyOf(Installment i, DateTime at) {
    if (i.settled || penaltyPct <= 0 || !at.isAfter(i.due)) return 0;
    final days = at.difference(i.due).inDays;
    return (i.remaining * penaltyPct / 100 * days / 30).round();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'personId': personId,
        'receivable': receivable,
        'principal': principal,
        'count': count,
        'interestFrom': _ds(interestFrom),
        'firstDue': _ds(firstDue),
        'everyMonths': everyMonths,
        'interestPct': interestPct,
        'penaltyPct': penaltyPct,
        'babat': babat,
        'items': items.map((e) => e.toJson()).toList(),
        'createdAt': createdAt,
        if (guarantorName.isNotEmpty) 'guarantorName': guarantorName,
        if (guarantorPhone.isNotEmpty) 'guarantorPhone': guarantorPhone,
        if (guarantorId.isNotEmpty) 'guarantorId': guarantorId,
      };

  factory InstallmentPlan.fromJson(Map<String, dynamic> j) => InstallmentPlan(
        id: _s(j['id']),
        personId: j['personId'] is String && (j['personId'] as String).isNotEmpty ? j['personId'] as String : null,
        receivable: j['receivable'] != false,
        principal: _i(j['principal']),
        count: _i(j['count']),
        interestFrom: _dt(j['interestFrom']) ?? DateTime.now(),
        firstDue: _dt(j['firstDue']) ?? DateTime.now(),
        everyMonths: j['everyMonths'] == null ? 1 : _i(j['everyMonths']),
        interestPct: _d(j['interestPct']),
        penaltyPct: _d(j['penaltyPct']),
        babat: _s(j['babat']),
        items: _list(j['items']).map(Installment.fromJson).toList(),
        createdAt: _i(j['createdAt']),
      )
        ..guarantorName = _s(j['guarantorName'])
        ..guarantorPhone = _s(j['guarantorPhone'])
        ..guarantorId = _s(j['guarantorId']);
}
