/// «کارت هواداری» و «جدول هدیه»، «قرعه کشی»، «پیام های داخلی» و
/// «تسویه فاکتور به فاکتور».
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class LoyaltyCard {
  String number;
  String personId;
  DateTime issued;
  bool active;
  LoyaltyCard({required this.number, required this.personId, required this.issued, this.active = true});
  Map<String, dynamic> toJson() => {'number': number, 'personId': personId, 'issued': issued.toIso8601String(), 'active': active};
  factory LoyaltyCard.fromJson(Map<String, dynamic> j) =>
      LoyaltyCard(number: _s(j['number']), personId: _s(j['personId']), issued: _dt(j['issued']) ?? DateTime.now(), active: j['active'] != false);
}

/// A row of «جدول هدیه»: [points] buy a gift worth [amount].
class GiftRow {
  int points;
  String title;
  int amount;
  GiftRow({this.points = 0, this.title = '', this.amount = 0});
  Map<String, dynamic> toJson() => {'points': points, 'title': title, 'amount': amount};
  factory GiftRow.fromJson(Map<String, dynamic> j) => GiftRow(points: _i(j['points']), title: _s(j['title']), amount: _i(j['amount']));
}

class LoyaltyConfig {
  int amountPerPoint; // هر چند ریال/تومان خرید = یک امتیاز
  List<GiftRow> gifts;
  LoyaltyConfig({this.amountPerPoint = 100000, List<GiftRow>? gifts}) : gifts = gifts ?? [];
  Map<String, dynamic> toJson() => {'amountPerPoint': amountPerPoint, 'gifts': gifts.map((g) => g.toJson()).toList()};
  factory LoyaltyConfig.fromJson(Map<String, dynamic> j) =>
      LoyaltyConfig(amountPerPoint: j['amountPerPoint'] == null ? 100000 : _i(j['amountPerPoint']), gifts: _list(j['gifts']).map(GiftRow.fromJson).toList());
}

/// «لیست کارت های هواداری استفاده شده در عملیات».
class Redemption {
  String id;
  String card;
  DateTime date;
  int points;
  String title;
  int amount;
  Redemption({required this.id, required this.card, required this.date, this.points = 0, this.title = '', this.amount = 0});
  Map<String, dynamic> toJson() => {'id': id, 'card': card, 'date': date.toIso8601String(), 'points': points, 'title': title, 'amount': amount};
  factory Redemption.fromJson(Map<String, dynamic> j) =>
      Redemption(id: _s(j['id']), card: _s(j['card']), date: _dt(j['date']) ?? DateTime.now(), points: _i(j['points']), title: _s(j['title']), amount: _i(j['amount']));
}

/// «تعریف کد قرعه کشی»: every sale of at least [minAmount] in the range gets
/// one code per [minAmount] (a chance per step).
class DrawCampaign {
  String id;
  String name;
  String prefix;
  DateTime from;
  DateTime to;
  int minAmount;
  String note;
  String? winner; // کد برنده
  DrawCampaign({required this.id, required this.name, this.prefix = 'Q', required this.from, required this.to, this.minAmount = 0, this.note = '', this.winner});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'prefix': prefix, 'from': from.toIso8601String(), 'to': to.toIso8601String(), 'minAmount': minAmount, 'note': note, 'winner': winner};
  factory DrawCampaign.fromJson(Map<String, dynamic> j) => DrawCampaign(
        id: _s(j['id']),
        name: _s(j['name']),
        prefix: _s(j['prefix']),
        from: _dt(j['from']) ?? DateTime.now(),
        to: _dt(j['to']) ?? DateTime.now(),
        minAmount: _i(j['minAmount']),
        note: _s(j['note']),
        winner: j['winner'] is String ? j['winner'] as String : null,
      );
}

/// «مدیریت پیام های داخلی» between users.
class InternalMessage {
  String id;
  String from; // user id
  String to; // user id ('*' = همه)
  DateTime date;
  String text;
  Set<String> readBy;
  InternalMessage({required this.id, required this.from, required this.to, required this.date, required this.text, Set<String>? readBy}) : readBy = readBy ?? {};
  Map<String, dynamic> toJson() => {'id': id, 'from': from, 'to': to, 'date': date.toIso8601String(), 'text': text, 'readBy': readBy.toList()};
  factory InternalMessage.fromJson(Map<String, dynamic> j) => InternalMessage(
        id: _s(j['id']),
        from: _s(j['from']),
        to: _s(j['to']),
        date: _dt(j['date']) ?? DateTime.now(),
        text: _s(j['text']),
        readBy: j['readBy'] is List ? {for (final x in j['readBy'] as List) '$x'} : null,
      );
}

/// «تسویه فاکتور به فاکتور»: a sale settled against a purchase of the same person.
class InvoiceOffset {
  String id;
  String saleId;
  String purchaseId;
  int amount;
  DateTime date;
  InvoiceOffset({required this.id, required this.saleId, required this.purchaseId, required this.amount, required this.date});
  Map<String, dynamic> toJson() => {'id': id, 'saleId': saleId, 'purchaseId': purchaseId, 'amount': amount, 'date': date.toIso8601String()};
  factory InvoiceOffset.fromJson(Map<String, dynamic> j) =>
      InvoiceOffset(id: _s(j['id']), saleId: _s(j['saleId']), purchaseId: _s(j['purchaseId']), amount: _i(j['amount']), date: _dt(j['date']) ?? DateTime.now());
}

/// «دفترچه تلفن»: a contact that is not an account.
class Contact {
  String id;
  String name;
  String phone;
  String note;
  Contact({required this.id, required this.name, this.phone = '', this.note = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'note': note};
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(id: _s(j['id']), name: _s(j['name']), phone: _s(j['phone']), note: _s(j['note']));
}

/// «لیست تماس های اخیر».
class CallLog {
  String number;
  DateTime date;
  String? personId;
  String note;
  CallLog({required this.number, required this.date, this.personId, this.note = ''});
  Map<String, dynamic> toJson() => {'number': number, 'date': date.toIso8601String(), 'personId': personId, 'note': note};
  factory CallLog.fromJson(Map<String, dynamic> j) =>
      CallLog(number: _s(j['number']), date: _dt(j['date']) ?? DateTime.now(), personId: j['personId'] is String ? j['personId'] as String : null, note: _s(j['note']));
}
