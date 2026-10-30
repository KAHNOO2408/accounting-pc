/// «فرمول های تولید»، «تولید حرفه ای»، «سالن های تولید» و «برآورد قیمت تمام
/// شده کالای تولیدی» — Sakan's production module (docs/sakan/ui).
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// Default credit side of production overhead: Sakan «سربار جذبی».
const mAbsorbedOverhead = '2050';

class ProductionHall {
  String id;
  String name;
  String note;
  ProductionHall({required this.id, required this.name, this.note = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'note': note};
  factory ProductionHall.fromJson(Map<String, dynamic> j) => ProductionHall(id: _s(j['id']), name: _s(j['name']), note: _s(j['note']));
}

/// A material row; [cost] is frozen when a production is saved.
class ProductionLine {
  String productId;
  double qty;
  int cost; // total cost of this row
  ProductionLine({required this.productId, this.qty = 0, this.cost = 0});
  Map<String, dynamic> toJson() => {'productId': productId, 'qty': qty, 'cost': cost};
  factory ProductionLine.fromJson(Map<String, dynamic> j) => ProductionLine(productId: _s(j['productId']), qty: _d(j['qty']), cost: _i(j['cost']));
}

/// «فرمول تولید»: materials for [yieldQty] units of [productId].
class ProductionFormula {
  String id;
  String name;
  String productId;
  double yieldQty;
  List<ProductionLine> lines;
  int overhead; // سربار (دستمزد، انرژی…) for one batch
  String? hallId;
  String note;
  ProductionFormula({required this.id, required this.name, required this.productId, this.yieldQty = 1, List<ProductionLine>? lines, this.overhead = 0, this.hallId, this.note = ''})
      : lines = lines ?? [];

  /// Materials for producing [qty] units.
  List<ProductionLine> scaled(double qty) =>
      [for (final l in lines) ProductionLine(productId: l.productId, qty: yieldQty <= 0 ? l.qty : l.qty * qty / yieldQty)];
  int overheadFor(double qty) => yieldQty <= 0 ? overhead : (overhead * qty / yieldQty).round();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'productId': productId,
        'yieldQty': yieldQty,
        'lines': lines.map((e) => {'productId': e.productId, 'qty': e.qty}).toList(),
        'overhead': overhead,
        'hallId': hallId,
        'note': note,
      };
  factory ProductionFormula.fromJson(Map<String, dynamic> j) => ProductionFormula(
        id: _s(j['id']),
        name: _s(j['name']),
        productId: _s(j['productId']),
        yieldQty: j['yieldQty'] == null ? 1 : _d(j['yieldQty']),
        lines: _list(j['lines']).map(ProductionLine.fromJson).toList(),
        overhead: _i(j['overhead']),
        hallId: _sn(j['hallId']),
        note: _s(j['note']),
      );
}

/// «تولید»: consumes materials and adds [qty] of [productId] at their cost plus overhead.
class Production {
  String id;
  int number;
  DateTime date;
  String productId;
  double qty;
  String? formulaId;
  String? hallId;
  String? warehouseId;
  List<ProductionLine> lines;
  int overhead;
  String overheadAcc;
  String note;
  int createdAt;

  Production({
    required this.id,
    required this.number,
    required this.date,
    required this.productId,
    required this.qty,
    this.formulaId,
    this.hallId,
    this.warehouseId,
    List<ProductionLine>? lines,
    this.overhead = 0,
    this.overheadAcc = mAbsorbedOverhead,
    this.note = '',
    int? createdAt,
  })  : lines = lines ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  int get materialCost => lines.fold(0, (a, l) => a + l.cost);
  int get totalCost => materialCost + overhead;
  int get unitCost => qty <= 0 ? 0 : (totalCost / qty).round();

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'date': date.toIso8601String().substring(0, 10),
        'productId': productId,
        'qty': qty,
        'formulaId': formulaId,
        'hallId': hallId,
        'warehouseId': warehouseId,
        'lines': lines.map((e) => e.toJson()).toList(),
        'overhead': overhead,
        'overheadAcc': overheadAcc,
        'note': note,
        'createdAt': createdAt,
      };
  factory Production.fromJson(Map<String, dynamic> j) => Production(
        id: _s(j['id']),
        number: _i(j['number']),
        date: DateTime.tryParse(_s(j['date'])) ?? DateTime.now(),
        productId: _s(j['productId']),
        qty: _d(j['qty']),
        formulaId: _sn(j['formulaId']),
        hallId: _sn(j['hallId']),
        warehouseId: _sn(j['warehouseId']),
        lines: _list(j['lines']).map(ProductionLine.fromJson).toList(),
        overhead: _i(j['overhead']),
        overheadAcc: _sn(j['overheadAcc']) ?? mAbsorbedOverhead,
        note: _s(j['note']),
        createdAt: _i(j['createdAt']),
      );
}
