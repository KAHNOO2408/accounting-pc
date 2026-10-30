/// «خرید بالانس» / «برگشت از خرید بالانس» — goods bought from a seller and
/// delivered straight to a buyer (no stock movement); the margin is
/// «درآمد واسطه گری». Posted as a voucher of kind 'balance'.
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class BalanceLine {
  String? productId;
  String title;
  double qty;
  int buyPrice; // فی خرید (فروشنده)
  int sellPrice; // فی فروش (خریدار)
  BalanceLine({this.productId, this.title = '', this.qty = 1, this.buyPrice = 0, this.sellPrice = 0});
  int get buyTotal => (qty * buyPrice).round();
  int get sellTotal => (qty * sellPrice).round();
  Map<String, dynamic> toJson() => {'productId': productId, 'title': title, 'qty': qty, 'buyPrice': buyPrice, 'sellPrice': sellPrice};
  factory BalanceLine.fromJson(Map<String, dynamic> j) =>
      BalanceLine(productId: _sn(j['productId']), title: _s(j['title']), qty: _d(j['qty']), buyPrice: _i(j['buyPrice']), sellPrice: _i(j['sellPrice']));
}

class BalanceDeal {
  String id;
  int number;
  DateTime date;
  bool isReturn; // برگشت از خرید بالانس
  String? sellerId;
  String? buyerId;
  List<BalanceLine> lines;
  int sellerDiscount; // تخفیف فروشنده
  int buyerDiscount; // تخفیف به خریدار
  String incomeAcc; // حساب درآمد واسطه گری
  // حمل
  String vehicle;
  String plate;
  String waybill; // شماره بارنامه
  String carrier; // شرکت باربری
  String origin;
  String destination;
  String note;
  String? voucherId;
  int createdAt;

  BalanceDeal({
    required this.id,
    required this.number,
    required this.date,
    this.isReturn = false,
    this.sellerId,
    this.buyerId,
    List<BalanceLine>? lines,
    this.sellerDiscount = 0,
    this.buyerDiscount = 0,
    this.incomeAcc = '4025',
    this.vehicle = '',
    this.plate = '',
    this.waybill = '',
    this.carrier = '',
    this.origin = '',
    this.destination = '',
    this.note = '',
    this.voucherId,
    int? createdAt,
  })  : lines = lines ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  String get label => isReturn ? 'برگشت از خرید بالانس' : 'خرید بالانس';
  int get buyTotal => lines.fold(0, (a, l) => a + l.buyTotal) - sellerDiscount; // owed to seller
  int get sellTotal => lines.fold(0, (a, l) => a + l.sellTotal) - buyerDiscount; // owed by buyer
  int get margin => sellTotal - buyTotal; // درآمد واسطه گری

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'date': date.toIso8601String().substring(0, 10),
        'isReturn': isReturn,
        'sellerId': sellerId,
        'buyerId': buyerId,
        'lines': lines.map((e) => e.toJson()).toList(),
        'sellerDiscount': sellerDiscount,
        'buyerDiscount': buyerDiscount,
        'incomeAcc': incomeAcc,
        'vehicle': vehicle,
        'plate': plate,
        'waybill': waybill,
        'carrier': carrier,
        'origin': origin,
        'destination': destination,
        'note': note,
        'voucherId': voucherId,
        'createdAt': createdAt,
      };

  factory BalanceDeal.fromJson(Map<String, dynamic> j) => BalanceDeal(
        id: _s(j['id']),
        number: _i(j['number']),
        date: DateTime.tryParse(_s(j['date'])) ?? DateTime.now(),
        isReturn: j['isReturn'] == true,
        sellerId: _sn(j['sellerId']),
        buyerId: _sn(j['buyerId']),
        lines: _list(j['lines']).map(BalanceLine.fromJson).toList(),
        sellerDiscount: _i(j['sellerDiscount']),
        buyerDiscount: _i(j['buyerDiscount']),
        incomeAcc: _sn(j['incomeAcc']) ?? '4025',
        vehicle: _s(j['vehicle']),
        plate: _s(j['plate']),
        waybill: _s(j['waybill']),
        carrier: _s(j['carrier']),
        origin: _s(j['origin']),
        destination: _s(j['destination']),
        note: _s(j['note']),
        voucherId: _sn(j['voucherId']),
        createdAt: _i(j['createdAt']),
      );
}
