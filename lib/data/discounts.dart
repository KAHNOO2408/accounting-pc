/// «مدل تخفیفات و اشانتیون»، «تخفیف های عمومی»، «تخصیص تخفیفات فردی» و
/// «گروه های یارانه» — Sakan's discount, gift and subsidy rules (docs/sakan/ui).
library;

import '../core/jalali.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? d);
double _dbl(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('$v') ?? d;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
String? _ds(DateTime? d) => d?.toIso8601String().substring(0, 10);
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

/// One step of a model's table («جدول اشانتیون ها و تخفیفات» / «رنج»).
class DiscountTier {
  double from; // از (تعداد به واحد مبنا، یا مبلغ)
  double to; // تا (0 = بدون سقف)
  double pct; // تخفیف درصدی
  int amount; // تخفیف ریالی برای هر واحد
  double freeQty; // تخفیف تعدادی (واحد رایگان)
  String? giftProductId; // اشانتیون
  double giftQty;

  DiscountTier({this.from = 0, this.to = 0, this.pct = 0, this.amount = 0, this.freeQty = 0, this.giftProductId, this.giftQty = 0});

  bool contains(double v) => v >= from && (to <= 0 || v <= to);

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'pct': pct,
        'amount': amount,
        'freeQty': freeQty,
        if (giftProductId != null) 'giftProductId': giftProductId,
        'giftQty': giftQty,
      };

  factory DiscountTier.fromJson(Map<String, dynamic> j) => DiscountTier(
        from: _dbl(j['from']),
        to: _dbl(j['to']),
        pct: _dbl(j['pct']),
        amount: _i(j['amount']),
        freeQty: _dbl(j['freeQty']),
        giftProductId: _sn(j['giftProductId']),
        giftQty: _dbl(j['giftQty']),
      );
}

/// «مبنای محاسبه»: quantity in unit 1..3, or the row amount (مبلغ).
enum DiscountBase { unit1, unit2, unit3, amount }

extension DiscountBaseX on DiscountBase {
  String get label => switch (this) {
        DiscountBase.unit1 => 'تعداد به واحد 1',
        DiscountBase.unit2 => 'تعداد به واحد 2',
        DiscountBase.unit3 => 'تعداد به واحد 3',
        DiscountBase.amount => 'مبلغ',
      };
}

class DiscountModel {
  String id;
  String name;
  String note;
  bool active;
  bool retail; // خرده فروشی
  bool wholesale; // عمده فروشی
  bool special; // ویژه

  /// The product the model applies to (null = every product).
  String? productId;

  /// «محاسبه تصاعدی»: the whole quantity is split over the tiers; otherwise
  /// («محاسبه ویژه») only the tier containing the quantity applies.
  bool progressive;
  DiscountBase base;
  List<DiscountTier> tiers;
  bool autoApply; // اعمال خودکار تخفیف در فروش

  // محدوده تاریخی و زمانی اعمال
  DateTime? fromDate;
  DateTime? toDate;
  int? fromMinute; // دقیقه از نیمه شب
  int? toMinute;
  Set<int> weekdays; // DateTime.weekday (1 = Monday … 7 = Sunday); empty = all
  int? monthDay; // ماهانه (روز)
  DateTime? specialDate; // تاریخ مشخص

  DiscountModel({
    required this.id,
    required this.name,
    this.note = '',
    this.active = true,
    this.retail = true,
    this.wholesale = true,
    this.special = true,
    this.productId,
    this.progressive = false,
    this.base = DiscountBase.unit1,
    List<DiscountTier>? tiers,
    this.autoApply = false,
    this.fromDate,
    this.toDate,
    this.fromMinute,
    this.toMinute,
    Set<int>? weekdays,
    this.monthDay,
    this.specialDate,
  })  : tiers = tiers ?? [],
        weekdays = weekdays ?? {};

  String get typeLabel => [if (retail) 'خرده فروشی', if (wholesale) 'عمده فروشی', if (special) 'ویژه'].join('، ');

  /// Whether the model is in effect at [t] for a buyer of [priceType] (1 retail, 2 wholesale, 3 special; 0 = any).
  bool appliesAt(DateTime t, {int priceType = 0}) {
    if (!active) return false;
    if (priceType == 1 && !retail || priceType == 2 && !wholesale || priceType == 3 && !special) return false;
    final d = DateTime(t.year, t.month, t.day);
    if (fromDate != null && d.isBefore(fromDate!)) return false;
    if (toDate != null && d.isAfter(toDate!)) return false;
    if (specialDate != null && d != DateTime(specialDate!.year, specialDate!.month, specialDate!.day)) return false;
    if (weekdays.isNotEmpty && !weekdays.contains(t.weekday)) return false;
    if (monthDay != null && monthDay! > 0 && Jalali.fromDateTime(t).day != monthDay) return false;
    final m = t.hour * 60 + t.minute;
    if (fromMinute != null && m < fromMinute!) return false;
    if (toMinute != null && m > toMinute!) return false;
    return true;
  }

  /// Discount of a row: (amount off, free units, gift product, gift qty).
  /// [measure] is the quantity in the model's unit, or the row amount.
  (int, double, String?, double) evaluate({required double measure, required double baseQty, required int unitPrice, required int gross}) {
    if (tiers.isEmpty || measure <= 0) return (0, 0, null, 0);
    final sorted = [...tiers]..sort((a, b) => a.from.compareTo(b.from));
    if (!progressive) {
      final t = sorted.lastWhere((x) => x.contains(measure), orElse: () => DiscountTier(from: -1));
      if (t.from < 0) return (0, 0, null, 0);
      final off = (gross * t.pct / 100).round() + (t.amount * baseQty).round();
      return (off, t.freeQty, t.giftProductId, t.giftQty);
    }
    // «محاسبه تصاعدی»: each tier's percent on the part of the quantity inside it
    var off = 0.0, free = 0.0, gift = 0.0;
    String? giftId;
    final perMeasure = measure == 0 ? 0 : gross / measure;
    for (final t in sorted) {
      final lo = t.from, hi = t.to <= 0 ? measure : (t.to < measure ? t.to : measure);
      if (hi <= lo) continue;
      final part = hi - lo;
      off += part * perMeasure * t.pct / 100 + t.amount * part * (baseQty / measure);
      free += t.freeQty;
      if (t.giftProductId != null) {
        giftId = t.giftProductId;
        gift += t.giftQty;
      }
    }
    return (off.round(), free, giftId, gift);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'active': active,
        'retail': retail,
        'wholesale': wholesale,
        'special': special,
        'productId': productId,
        'progressive': progressive,
        'base': base.name,
        'tiers': tiers.map((t) => t.toJson()).toList(),
        'autoApply': autoApply,
        'fromDate': _ds(fromDate),
        'toDate': _ds(toDate),
        'fromMinute': fromMinute,
        'toMinute': toMinute,
        'weekdays': weekdays.toList(),
        'monthDay': monthDay,
        'specialDate': _ds(specialDate),
      };

  factory DiscountModel.fromJson(Map<String, dynamic> j) => DiscountModel(
        id: _s(j['id']),
        name: _s(j['name']),
        note: _s(j['note']),
        active: j['active'] != false,
        retail: j['retail'] != false,
        wholesale: j['wholesale'] != false,
        special: j['special'] != false,
        productId: _sn(j['productId']),
        progressive: j['progressive'] == true,
        base: DiscountBase.values.firstWhere((b) => b.name == j['base'], orElse: () => DiscountBase.unit1),
        tiers: _list(j['tiers']).map(DiscountTier.fromJson).toList(),
        autoApply: j['autoApply'] == true,
        fromDate: _dt(j['fromDate']),
        toDate: _dt(j['toDate']),
        fromMinute: j['fromMinute'] is num ? (j['fromMinute'] as num).toInt() : null,
        toMinute: j['toMinute'] is num ? (j['toMinute'] as num).toInt() : null,
        weekdays: j['weekdays'] is List ? {for (final x in j['weekdays'] as List) _i(x)} : null,
        monthDay: j['monthDay'] is num ? (j['monthDay'] as num).toInt() : null,
        specialDate: _dt(j['specialDate']),
      );
}

/// «تخفیف های عمومی» (invoice amount range → percent) and, with [personId],
/// «تخصیص تخفیفات فردی».
class AmountDiscount {
  String id;
  String name;
  int fromAmount;
  int toAmount; // 0 = بدون سقف
  double pct;
  String note;
  String? personId;
  AmountDiscount({required this.id, this.name = '', this.fromAmount = 0, this.toAmount = 0, this.pct = 0, this.note = '', this.personId});

  bool contains(int v) => v >= fromAmount && (toAmount <= 0 || v <= toAmount);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'fromAmount': fromAmount, 'toAmount': toAmount, 'pct': pct, 'note': note, 'personId': personId};

  factory AmountDiscount.fromJson(Map<String, dynamic> j) => AmountDiscount(
        id: _s(j['id']),
        name: _s(j['name']),
        fromAmount: _i(j['fromAmount']),
        toAmount: _i(j['toAmount']),
        pct: _dbl(j['pct']),
        note: _s(j['note']),
        personId: _sn(j['personId']),
      );
}

/// «گروه های یارانه»: the subsidy percent of a group of products, paid by
/// the subsidy account («حساب یارانه», e.g. an insurer).
class SubsidyGroup {
  String id;
  String name;
  double pct;
  String note;
  bool isDefault;
  String? personId; // حساب یارانه
  SubsidyGroup({required this.id, required this.name, this.pct = 0, this.note = '', this.isDefault = false, this.personId});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pct': pct, 'note': note, 'isDefault': isDefault, 'personId': personId};

  factory SubsidyGroup.fromJson(Map<String, dynamic> j) =>
      SubsidyGroup(id: _s(j['id']), name: _s(j['name']), pct: _dbl(j['pct']), note: _s(j['note']), isDefault: j['isDefault'] == true, personId: _sn(j['personId']));
}

