import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/format.dart';
import '../core/jalali.dart';
import 'models.dart';
import 'store.dart';

/// «ارسال پیام» — sends SMS through a web panel (کاوه‌نگار، ملی پیامک،
/// SMS.ir or any panel with a send URL) and builds the message texts.

/// Result of one send request.
class SmsResult {
  final bool ok;
  final String message;
  const SmsResult(this.ok, this.message);
}

/// Normalises an Iranian mobile number to 09xxxxxxxxx, or returns '' when it
/// is not a mobile number.
String normalizeMobile(String input) {
  var d = normalizeDigits(input).replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('+')) d = d.substring(1);
  if (d.startsWith('0098')) d = d.substring(4);
  if (d.startsWith('98') && d.length == 12) d = d.substring(2);
  if (d.length == 10 && d.startsWith('9')) d = '0$d';
  return RegExp(r'^09\d{9}$').hasMatch(d) ? d : '';
}

/// Number of SMS parts the text takes (Persian / Unicode: 70, then 67 per part).
int smsParts(String text) {
  if (text.isEmpty) return 0;
  final unicode = text.runes.any((r) => r > 127);
  final single = unicode ? 70 : 160;
  final multi = unicode ? 67 : 153;
  final n = text.runes.length;
  return n <= single ? 1 : (n / multi).ceil();
}

/// Replaces {placeholders} in [template].
String fillSms(String template, Map<String, String> values) =>
    template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) => values[m.group(1)!.trim()] ?? m.group(0)!);

String _shop(AppStore s) {
  final st = s.settings;
  final sig = st.sms.signature.trim();
  if (sig.isNotEmpty) return sig;
  return st.businessName.isNotEmpty ? st.businessName : st.ownerName;
}

/// Balance text of a person: «۱۲۰,۰۰۰ بدهکار».
String _balanceText(AppStore s, Person p) {
  final b = s.personBalance(p.id);
  if (b == 0) return '0 (تسویه)';
  return '${groupDigits(b.abs())} ${b > 0 ? 'بدهکار' : 'بستانکار'}';
}

/// Common values for any message to [p].
Map<String, String> smsValues(AppStore s, Person? p) => {
      'نام': p?.name ?? '',
      'مانده': p == null ? '' : _balanceText(s, p),
      'واحد': s.settings.currency,
      'فروشگاه': _shop(s),
      'تلفن فروشگاه': s.settings.businessPhone,
      'امروز': jFormat(DateTime.now()),
    };

/// Fields usable in each template (for the «درج فیلد» chips).
const smsCommonFields = ['نام', 'مانده', 'واحد', 'فروشگاه', 'تلفن فروشگاه', 'امروز'];
const smsInvoiceFields = ['عنوان', 'شماره فاکتور', 'تاریخ', 'مبلغ فاکتور', 'تعداد اقلام', 'اقلام', 'دریافتی', 'مانده فاکتور'];
const smsChequeFields = ['شماره چک', 'مبلغ چک', 'سررسید', 'بانک'];

String invoiceSmsText(AppStore s, Invoice inv) {
  final p = s.person(inv.personId);
  final title = inv.proforma ? 'پیش فاکتور' : inv.kind.label;
  final names = <String>[];
  for (final l in inv.lines) {
    final n = s.product(l.productId)?.name ?? l.title;
    if (n.isNotEmpty) names.add(n);
  }
  return fillSms(s.settings.sms.invoiceTemplate, {
    ...smsValues(s, p),
    if (p == null) 'نام': inv.info['buyerName'] ?? 'مشتری',
    'عنوان': title,
    'شماره فاکتور': '${inv.number}',
    'تاریخ': jFormat(inv.date),
    'مبلغ فاکتور': groupDigits(inv.total),
    'تعداد اقلام': '${inv.lines.length}',
    'اقلام': names.length <= 3 ? names.join('، ') : '${names.take(3).join('، ')} و ${names.length - 3} قلم دیگر',
    'دریافتی': groupDigits(inv.total - inv.remaining),
    'مانده فاکتور': groupDigits(inv.remaining),
  });
}

String chequeSmsText(AppStore s, Cheque c) => fillSms(s.settings.sms.chequeTemplate, {
      ...smsValues(s, s.person(c.personId)),
      'شماره چک': c.serial,
      'مبلغ چک': groupDigits(c.amount),
      'سررسید': jFormat(c.dueDate),
      'بانک': c.bank,
    });

String debtSmsText(AppStore s, Person p, [String? template]) =>
    fillSms(template ?? s.settings.sms.debtTemplate, smsValues(s, p));

// ------------------------------------------------------------------ sending

Future<(int, String)> _http(String method, Uri url,
    {Map<String, String> headers = const {}, String? body, String contentType = 'application/x-www-form-urlencoded'}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.openUrl(method, url).timeout(const Duration(seconds: 25));
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.parse('$contentType; charset=utf-8');
      req.add(utf8.encode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    return (res.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

String _form(Map<String, String> m) =>
    m.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

/// Sends [text] to [to] (one number). Never throws.
Future<SmsResult> sendSms(SmsConfig c, String to, String text) async {
  final mobile = normalizeMobile(to);
  if (mobile.isEmpty) return const SmsResult(false, 'شماره موبایل معتبر نیست');
  if (!c.configured) return const SmsResult(false, 'پنل پیامک تنظیم نشده است');
  try {
    switch (c.provider) {
      case SmsProvider.kavenegar:
        // https://api.kavenegar.com/v1/{API-KEY}/sms/send.json
        final (code, body) = await _http(
          'POST',
          Uri.parse('https://api.kavenegar.com/v1/${Uri.encodeComponent(c.apiKey.trim())}/sms/send.json'),
          body: _form({'receptor': mobile, 'message': text, if (c.sender.trim().isNotEmpty) 'sender': c.sender.trim()}),
        );
        final j = _json(body);
        final ret = j is Map ? j['return'] : null;
        final status = ret is Map ? ret['status'] : null;
        if (status == 200) return const SmsResult(true, 'ارسال شد');
        final msg = ret is Map ? '${ret['message'] ?? ''}' : '';
        return SmsResult(false, 'خطای کاوه‌نگار ${status ?? code}: ${msg.isEmpty ? _short(body) : msg}');

      case SmsProvider.melipayamak:
        // https://rest.payamak-panel.com/api/SendSMS/SendSMS
        final (code, body) = await _http(
          'POST',
          Uri.parse('https://rest.payamak-panel.com/api/SendSMS/SendSMS'),
          body: _form({
            'username': c.username.trim(),
            'password': c.password,
            'to': mobile,
            'from': c.sender.trim(),
            'text': text,
            'isFlash': 'false',
          }),
        );
        final j = _json(body);
        if (j is Map && '${j['RetStatus']}' == '1') return const SmsResult(true, 'ارسال شد');
        final msg = j is Map ? '${j['StrRetStatus'] ?? j['Value'] ?? ''}' : _short(body);
        return SmsResult(false, 'خطای ملی پیامک ($code): $msg');

      case SmsProvider.smsir:
        // https://api.sms.ir/v1/send/bulk
        final (code, body) = await _http(
          'POST',
          Uri.parse('https://api.sms.ir/v1/send/bulk'),
          headers: {'X-API-KEY': c.apiKey.trim(), 'Accept': 'application/json'},
          contentType: 'application/json',
          body: jsonEncode({
            'lineNumber': int.tryParse(normalizeDigits(c.sender.trim())) ?? c.sender.trim(),
            'messageText': text,
            'mobiles': [mobile],
          }),
        );
        final j = _json(body);
        if (j is Map && '${j['status']}' == '1') return const SmsResult(true, 'ارسال شد');
        final msg = j is Map ? '${j['message'] ?? ''}' : _short(body);
        return SmsResult(false, 'خطای SMS.ir ($code): $msg');

      case SmsProvider.custom:
        final url = fillSms(c.customUrl.trim(), {
          'to': Uri.encodeQueryComponent(mobile),
          'text': Uri.encodeQueryComponent(text),
          'from': Uri.encodeQueryComponent(c.sender.trim()),
          'user': Uri.encodeQueryComponent(c.username.trim()),
          'pass': Uri.encodeQueryComponent(c.password),
          'key': Uri.encodeQueryComponent(c.apiKey.trim()),
        });
        final (code, body) = await _http('GET', Uri.parse(url));
        if (code >= 200 && code < 300) return SmsResult(true, 'ارسال شد — پاسخ پنل: ${_short(body.trim())}');
        return SmsResult(false, 'خطای پنل ($code): ${_short(body)}');
    }
  } on TimeoutException {
    return const SmsResult(false, 'پاسخی از پنل پیامک دریافت نشد (اتصال اینترنت را بررسی کنید)');
  } on SocketException catch (e) {
    return SmsResult(false, 'اتصال به پنل پیامک برقرار نشد: ${e.message}');
  } catch (e) {
    return SmsResult(false, 'خطا: $e');
  }
}

Object? _json(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

/// One message of a batch.
class SmsJob {
  final String to;
  final String name;
  final String text;
  final String ref;
  const SmsJob({required this.to, required this.name, required this.text, this.ref = ''});
}

/// Sends [jobs] one by one, records them in «گزارش پیام‌های ارسالی» and
/// returns how many succeeded. [onProgress] gets (done, total).
Future<int> sendSmsBatch(AppStore s, List<SmsJob> jobs, {void Function(int done, int total)? onProgress}) async {
  final log = <SmsLogEntry>[];
  var ok = 0;
  for (var i = 0; i < jobs.length; i++) {
    final j = jobs[i];
    final r = await sendSms(s.settings.sms, j.to, j.text);
    if (r.ok) ok++;
    log.add(SmsLogEntry(
      id: newId(),
      date: DateTime.now(),
      to: normalizeMobile(j.to).isEmpty ? j.to : normalizeMobile(j.to),
      name: j.name,
      text: j.text,
      ok: r.ok,
      result: r.message,
      ref: j.ref,
    ));
    onProgress?.call(i + 1, jobs.length);
  }
  if (log.isNotEmpty) s.logSms(log.reversed);
  return ok;
}

/// Sends the invoice SMS automatically after a sale invoice is saved
/// (when «ارسال خودکار» is on). Runs in the background; never throws.
void autoInvoiceSms(AppStore s, Invoice inv) {
  final c = s.settings.sms;
  if (!c.autoInvoice || !c.configured || inv.proforma || inv.kind.buySide) return;
  final p = s.person(inv.personId);
  if (p == null || normalizeMobile(p.phone).isEmpty) return;
  final ref = 'inv:${inv.id}';
  if (s.smsSentFor(ref)) return;
  unawaited(sendSmsBatch(s, [SmsJob(to: p.phone, name: p.name, text: invoiceSmsText(s, inv), ref: ref)]));
}

/// Received cheques that are pending and fall due between today and [days] days later.
List<Cheque> dueCheques(AppStore s, {int days = 3}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final until = today.add(Duration(days: days + 1));
  return s.cheques
      .where((c) =>
          c.direction == ChequeDirection.received &&
          (c.status == ChequeStatus.pending || c.status == ChequeStatus.deposited) &&
          !c.dueDate.isBefore(today) &&
          c.dueDate.isBefore(until))
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
}

/// «یادآوری سررسید چک»: when the app opens, reminds the drawers of received
/// cheques due today (once per cheque). Runs in the background.
void autoChequeReminders(AppStore s) {
  final c = s.settings.sms;
  if (!c.autoCheque || !c.configured) return;
  final jobs = <SmsJob>[];
  for (final ch in dueCheques(s, days: 0)) {
    final p = s.person(ch.personId);
    if (p == null || normalizeMobile(p.phone).isEmpty) continue;
    final ref = 'chq:${ch.id}';
    if (s.smsSentFor(ref)) continue;
    jobs.add(SmsJob(to: p.phone, name: p.name, text: chequeSmsText(s, ch), ref: ref));
  }
  if (jobs.isNotEmpty) unawaited(sendSmsBatch(s, jobs));
}
