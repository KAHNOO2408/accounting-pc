/// «زمانبندی ارسال پیامک»، یادآوری اقساط و فاکتورهای تسویه نشده، و
/// «یادسپار تقویم».
library;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _dt(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

class SmsAuto {
  bool overdueInstallments; // ارسال پیامک اقساط معوقه
  String installmentTemplate;
  bool unpaidInvoices; // ارسال پیامک فاکتورهای تسویه نشده
  int unpaidDays;
  String unpaidTemplate;
  SmsAuto({
    this.overdueInstallments = false,
    this.installmentTemplate = '{نام} گرامی، قسط {مبلغ قسط} با سررسید {سررسید} پرداخت نشده است. {فروشگاه}',
    this.unpaidInvoices = false,
    this.unpaidDays = 30,
    this.unpaidTemplate = '{نام} گرامی، مانده حساب شما {مانده} {واحد} است. لطفا نسبت به تسویه اقدام فرمایید. {فروشگاه}',
  });
  Map<String, dynamic> toJson() => {
        'overdueInstallments': overdueInstallments,
        'installmentTemplate': installmentTemplate,
        'unpaidInvoices': unpaidInvoices,
        'unpaidDays': unpaidDays,
        'unpaidTemplate': unpaidTemplate,
      };
  factory SmsAuto.fromJson(Map<String, dynamic> j) {
    final d = SmsAuto();
    return SmsAuto(
      overdueInstallments: j['overdueInstallments'] == true,
      installmentTemplate: _s(j['installmentTemplate']).isEmpty ? d.installmentTemplate : _s(j['installmentTemplate']),
      unpaidInvoices: j['unpaidInvoices'] == true,
      unpaidDays: j['unpaidDays'] == null ? 30 : _i(j['unpaidDays']),
      unpaidTemplate: _s(j['unpaidTemplate']).isEmpty ? d.unpaidTemplate : _s(j['unpaidTemplate']),
    );
  }
}

/// Who a scheduled message goes to.
enum SmsTarget { everyone, debtors, creditors, chosen }

extension SmsTargetX on SmsTarget {
  String get label => switch (this) {
        SmsTarget.everyone => 'همه اشخاص دارای موبایل',
        SmsTarget.debtors => 'بدهکاران',
        SmsTarget.creditors => 'بستانکاران',
        SmsTarget.chosen => 'اشخاص انتخابی',
      };
}

enum Repeat { none, daily, weekly, monthly, yearly }

extension RepeatX on Repeat {
  String get label => switch (this) {
        Repeat.none => 'یک بار',
        Repeat.daily => 'روزانه',
        Repeat.weekly => 'هفتگی',
        Repeat.monthly => 'ماهانه',
        Repeat.yearly => 'سالانه',
      };

  DateTime next(DateTime d) => switch (this) {
        Repeat.none => d,
        Repeat.daily => DateTime(d.year, d.month, d.day + 1, d.hour, d.minute),
        Repeat.weekly => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        Repeat.monthly => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
        Repeat.yearly => DateTime(d.year + 1, d.month, d.day, d.hour, d.minute),
      };
}

/// «زمانبندی ارسال پیامک».
class SmsSchedule {
  String id;
  String title;
  String text;
  SmsTarget target;
  List<String> personIds;
  DateTime at; // next run
  Repeat repeat;
  bool enabled;
  DateTime? lastRun;
  SmsSchedule({required this.id, this.title = '', this.text = '', this.target = SmsTarget.everyone, List<String>? personIds, required this.at, this.repeat = Repeat.none, this.enabled = true, this.lastRun})
      : personIds = personIds ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'target': target.name,
        'personIds': personIds,
        'at': at.toIso8601String(),
        'repeat': repeat.name,
        'enabled': enabled,
        'lastRun': lastRun?.toIso8601String(),
      };
  factory SmsSchedule.fromJson(Map<String, dynamic> j) => SmsSchedule(
        id: _s(j['id']),
        title: _s(j['title']),
        text: _s(j['text']),
        target: SmsTarget.values.firstWhere((t) => t.name == j['target'], orElse: () => SmsTarget.everyone),
        personIds: j['personIds'] is List ? [for (final x in j['personIds'] as List) '$x'] : null,
        at: _dt(j['at']) ?? DateTime.now(),
        repeat: Repeat.values.firstWhere((r) => r.name == j['repeat'], orElse: () => Repeat.none),
        enabled: j['enabled'] != false,
        lastRun: _dt(j['lastRun']),
      );
}

/// «یادسپار تقویم».
class Reminder {
  String id;
  DateTime at;
  String title;
  String note;
  Repeat repeat;
  bool done;
  Reminder({required this.id, required this.at, required this.title, this.note = '', this.repeat = Repeat.none, this.done = false});

  /// Whether the reminder falls on [day] (repeats included).
  bool on(DateTime day) {
    final d = DateTime(at.year, at.month, at.day);
    final x = DateTime(day.year, day.month, day.day);
    if (x.isBefore(d)) return false;
    return switch (repeat) {
      Repeat.none => x == d,
      Repeat.daily => true,
      Repeat.weekly => x.difference(d).inDays % 7 == 0,
      Repeat.monthly => x.day == d.day,
      Repeat.yearly => x.day == d.day && x.month == d.month,
    };
  }

  Map<String, dynamic> toJson() => {'id': id, 'at': at.toIso8601String(), 'title': title, 'note': note, 'repeat': repeat.name, 'done': done};
  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: _s(j['id']),
        at: _dt(j['at']) ?? DateTime.now(),
        title: _s(j['title']),
        note: _s(j['note']),
        repeat: Repeat.values.firstWhere((r) => r.name == j['repeat'], orElse: () => Repeat.none),
        done: j['done'] == true,
      );
}
