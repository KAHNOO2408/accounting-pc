/// «میز»، «رزرو میز»، «فاکتور رستورانی»، «فیش آشپزخانه» و «ترکیب و مونتاژ
/// رستورانی» — Sakan's restaurant module (docs/sakan/forms/Resturant*).
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class RestTable {
  String id;
  int number; // شماره میز
  String name;
  int capacity;
  String hall; // سالن
  RestTable({required this.id, required this.number, this.name = '', this.capacity = 4, this.hall = ''});
  String get title => name.isEmpty ? 'میز $number' : name;
  Map<String, dynamic> toJson() => {'id': id, 'number': number, 'name': name, 'capacity': capacity, 'hall': hall};
  factory RestTable.fromJson(Map<String, dynamic> j) =>
      RestTable(id: _s(j['id']), number: _i(j['number']), name: _s(j['name']), capacity: j['capacity'] == null ? 4 : _i(j['capacity']), hall: _s(j['hall']));
}

class Reservation {
  String id;
  String tableId;
  DateTime at;
  String name;
  String phone;
  int people;
  String note;
  bool done; // حضور یافت / لغو
  Reservation({required this.id, required this.tableId, required this.at, this.name = '', this.phone = '', this.people = 2, this.note = '', this.done = false});
  Map<String, dynamic> toJson() => {'id': id, 'tableId': tableId, 'at': at.toIso8601String(), 'name': name, 'phone': phone, 'people': people, 'note': note, 'done': done};
  factory Reservation.fromJson(Map<String, dynamic> j) => Reservation(
        id: _s(j['id']),
        tableId: _s(j['tableId']),
        at: DateTime.tryParse(_s(j['at'])) ?? DateTime.now(),
        name: _s(j['name']),
        phone: _s(j['phone']),
        people: _i(j['people']),
        note: _s(j['note']),
        done: j['done'] == true,
      );
}

class TabLine {
  String productId;
  double qty;
  int price;
  String note; // توضیح برای آشپزخانه
  double sent; // already printed on a kitchen slip
  TabLine({required this.productId, this.qty = 1, this.price = 0, this.note = '', this.sent = 0});
  int get total => (qty * price).round();
  Map<String, dynamic> toJson() => {'productId': productId, 'qty': qty, 'price': price, 'note': note, 'sent': sent};
  factory TabLine.fromJson(Map<String, dynamic> j) => TabLine(productId: _s(j['productId']), qty: _d(j['qty']), price: _i(j['price']), note: _s(j['note']), sent: _d(j['sent']));
}

/// «نوع»: سالن / بیرون بر / پیک.
enum TabMode { dineIn, takeAway, delivery }

extension TabModeX on TabMode {
  String get label => switch (this) {
        TabMode.dineIn => 'سالن',
        TabMode.takeAway => 'بیرون بر',
        TabMode.delivery => 'ارسال با پیک',
      };
}

/// An open order (a table's running bill, or a take-away / delivery order).
class RestTab {
  String id;
  String? tableId;
  TabMode mode;
  DateTime opened;
  String? personId; // مشترک
  String? courierId; // پیک
  int guests;
  List<TabLine> lines;
  String note;
  RestTab({required this.id, this.tableId, this.mode = TabMode.dineIn, required this.opened, this.personId, this.courierId, this.guests = 0, List<TabLine>? lines, this.note = ''})
      : lines = lines ?? [];

  int get total => lines.fold(0, (a, l) => a + l.total);
  bool get hasUnsent => lines.any((l) => l.qty > l.sent + 1e-9);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tableId': tableId,
        'mode': mode.name,
        'opened': opened.toIso8601String(),
        'personId': personId,
        'courierId': courierId,
        'guests': guests,
        'lines': lines.map((e) => e.toJson()).toList(),
        'note': note,
      };
  factory RestTab.fromJson(Map<String, dynamic> j) => RestTab(
        id: _s(j['id']),
        tableId: _sn(j['tableId']),
        mode: TabMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => TabMode.dineIn),
        opened: DateTime.tryParse(_s(j['opened'])) ?? DateTime.now(),
        personId: _sn(j['personId']),
        courierId: _sn(j['courierId']),
        guests: _i(j['guests']),
        lines: _list(j['lines']).map(TabLine.fromJson).toList(),
        note: _s(j['note']),
      );
}

class RestConfig {
  /// «ترکیب و مونتاژ رستورانی»: selling a dish that has a production formula
  /// consumes its ingredients automatically.
  bool autoAssemble;
  double servicePct; // حق سرویس
  int deliveryFee; // هزینه پیک
  String? accountId; // صندوق پیش فرض
  int kitchenCopies;
  RestConfig({this.autoAssemble = true, this.servicePct = 0, this.deliveryFee = 0, this.accountId, this.kitchenCopies = 1});
  Map<String, dynamic> toJson() => {'autoAssemble': autoAssemble, 'servicePct': servicePct, 'deliveryFee': deliveryFee, 'accountId': accountId, 'kitchenCopies': kitchenCopies};
  factory RestConfig.fromJson(Map<String, dynamic> j) => RestConfig(
        autoAssemble: j['autoAssemble'] != false,
        servicePct: _d(j['servicePct']),
        deliveryFee: _i(j['deliveryFee']),
        accountId: _sn(j['accountId']),
        kitchenCopies: j['kitchenCopies'] == null ? 1 : _i(j['kitchenCopies']),
      );
}
