/// «لیست فاکتورهای ثبت شده در وبسایت ووکامرس» — WooCommerce orders fetched
/// through the REST API (/wp-json/wc/v3/orders) and turned into sale invoices.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/jalali.dart' show normalizeDigits;
import 'models.dart';
import 'store.dart';

String _s(Object? v) => v == null ? '' : '$v';
int _money(Object? v) => (double.tryParse(_s(v)) ?? 0).round();
double _d(Object? v) => double.tryParse(_s(v)) ?? 0;

class WooConfig {
  String url; // https://example.com
  String key; // consumer key (ck_…)
  String secret; // consumer secret (cs_…)
  /// Site amounts × factor = Taraz amounts (10 when the site is in toman and Taraz in rial).
  int factor;

  /// Payment method id (bacs, cod, zarinpal…) → cash box / bank account id.
  Map<String, String> payAccounts;

  /// Statuses that count as paid.
  Set<String> paidStatuses;
  bool createProducts; // unknown SKUs become new products
  DateTime? lastFetch;

  WooConfig({this.url = '', this.key = '', this.secret = '', this.factor = 1, Map<String, String>? payAccounts, Set<String>? paidStatuses, this.createProducts = false, this.lastFetch})
      : payAccounts = payAccounts ?? {},
        paidStatuses = paidStatuses ?? {'processing', 'completed'};

  bool get configured => url.trim().isNotEmpty && key.trim().isNotEmpty && secret.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'url': url,
        'key': key,
        'secret': secret,
        'factor': factor,
        'payAccounts': payAccounts,
        'paidStatuses': paidStatuses.toList(),
        'createProducts': createProducts,
        'lastFetch': lastFetch?.toIso8601String(),
      };

  factory WooConfig.fromJson(Map<String, dynamic> j) => WooConfig(
        url: _s(j['url']),
        key: _s(j['key']),
        secret: _s(j['secret']),
        factor: j['factor'] is num ? (j['factor'] as num).toInt() : 1,
        payAccounts: j['payAccounts'] is Map ? {for (final e in (j['payAccounts'] as Map).entries) '${e.key}': '${e.value}'} : null,
        paidStatuses: j['paidStatuses'] is List ? {for (final x in j['paidStatuses'] as List) '$x'} : null,
        createProducts: j['createProducts'] == true,
        lastFetch: j['lastFetch'] is String ? DateTime.tryParse(j['lastFetch'] as String) : null,
      );
}

class WooItem {
  String name;
  String sku;
  double qty;
  int price; // site unit price (before factor)
  int total; // site row total after coupon (before factor)
  WooItem({required this.name, this.sku = '', this.qty = 1, this.price = 0, this.total = 0});
  Map<String, dynamic> toJson() => {'name': name, 'sku': sku, 'qty': qty, 'price': price, 'total': total};
  factory WooItem.fromJson(Map<String, dynamic> j) => WooItem(name: _s(j['name']), sku: _s(j['sku']), qty: _d(j['qty']), price: _money(j['price']), total: _money(j['total']));
}

const wooStatusNames = {
  'pending': 'در انتظار پرداخت',
  'processing': 'در حال انجام',
  'on-hold': 'در انتظار بررسی',
  'completed': 'تکمیل شده',
  'cancelled': 'لغو شده',
  'refunded': 'مسترد شده',
  'failed': 'ناموفق',
  'checkout-draft': 'پیش‌نویس',
};

class WooOrder {
  int id;
  String number;
  String status;
  DateTime date;
  int total;
  int shipping;
  int discount;
  int tax;
  String payMethod;
  String payTitle;
  String customer;
  String phone;
  String email;
  String address;
  String recipient; // گیرنده (shipping name)
  String recipientAddress;
  String note;
  List<WooItem> items;
  String? invoiceId; // set once «سند شده»

  WooOrder({
    required this.id,
    this.number = '',
    this.status = '',
    required this.date,
    this.total = 0,
    this.shipping = 0,
    this.discount = 0,
    this.tax = 0,
    this.payMethod = '',
    this.payTitle = '',
    this.customer = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.recipient = '',
    this.recipientAddress = '',
    this.note = '',
    List<WooItem>? items,
    this.invoiceId,
  }) : items = items ?? [];

  String get statusName => wooStatusNames[status] ?? status;

  /// Parses one order of the WooCommerce REST API.
  factory WooOrder.fromApi(Map<String, dynamic> j) {
    Map<String, dynamic> m(Object? v) => v is Map<String, dynamic> ? v : const {};
    final b = m(j['billing']), sh = m(j['shipping']);
    String join(Map<String, dynamic> a) =>
        [a['state'], a['city'], a['address_1'], a['address_2'], if (_s(a['postcode']).isNotEmpty) 'کدپستی ${a['postcode']}'].map(_s).where((x) => x.trim().isNotEmpty).join('، ');
    final name = '${_s(b['first_name'])} ${_s(b['last_name'])}'.trim();
    final rName = '${_s(sh['first_name'])} ${_s(sh['last_name'])}'.trim();
    return WooOrder(
      id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse(_s(j['id'])) ?? 0,
      number: _s(j['number']).isEmpty ? _s(j['id']) : _s(j['number']),
      status: _s(j['status']),
      date: DateTime.tryParse(_s(j['date_created'])) ?? DateTime.now(),
      total: _money(j['total']),
      shipping: _money(j['shipping_total']),
      discount: _money(j['discount_total']),
      tax: _money(j['total_tax']),
      payMethod: _s(j['payment_method']),
      payTitle: _s(j['payment_method_title']),
      customer: name.isEmpty ? _s(b['company']) : name,
      phone: normalizeDigits(_s(b['phone'])),
      email: _s(b['email']),
      address: join(b),
      recipient: rName.isEmpty ? name : rName,
      recipientAddress: join(sh).isEmpty ? join(b) : join(sh),
      note: _s(j['customer_note']),
      items: [
        for (final it in (j['line_items'] is List ? j['line_items'] as List : const []).whereType<Map<String, dynamic>>())
          WooItem(
            name: _s(it['name']),
            sku: _s(it['sku']),
            qty: _d(it['quantity']),
            price: _money(it['price'] ?? (_d(it['subtotal']) / (_d(it['quantity']) == 0 ? 1 : _d(it['quantity'])))),
            total: _money(it['total']),
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'status': status,
        'date': date.toIso8601String(),
        'total': total,
        'shipping': shipping,
        'discount': discount,
        'tax': tax,
        'payMethod': payMethod,
        'payTitle': payTitle,
        'customer': customer,
        'phone': phone,
        'email': email,
        'address': address,
        'recipient': recipient,
        'recipientAddress': recipientAddress,
        'note': note,
        'items': items.map((e) => e.toJson()).toList(),
        'invoiceId': invoiceId,
      };

  factory WooOrder.fromJson(Map<String, dynamic> j) => WooOrder(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        number: _s(j['number']),
        status: _s(j['status']),
        date: DateTime.tryParse(_s(j['date'])) ?? DateTime.now(),
        total: _money(j['total']),
        shipping: _money(j['shipping']),
        discount: _money(j['discount']),
        tax: _money(j['tax']),
        payMethod: _s(j['payMethod']),
        payTitle: _s(j['payTitle']),
        customer: _s(j['customer']),
        phone: _s(j['phone']),
        email: _s(j['email']),
        address: _s(j['address']),
        recipient: _s(j['recipient']),
        recipientAddress: _s(j['recipientAddress']),
        note: _s(j['note']),
        items: j['items'] is List ? (j['items'] as List).whereType<Map<String, dynamic>>().map(WooItem.fromJson).toList() : null,
        invoiceId: j['invoiceId'] is String ? j['invoiceId'] as String : null,
      );
}

Uri wooUri(WooConfig c, String path, [Map<String, String> q = const {}]) {
  var base = c.url.trim();
  if (!base.startsWith('http')) base = 'https://$base';
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return Uri.parse('$base/wp-json/wc/v3/$path').replace(queryParameters: q.isEmpty ? null : q);
}

/// Fetches orders created after [after] (all pages). Throws a Persian message on failure.
Future<List<WooOrder>> fetchWooOrders(WooConfig c, {DateTime? after, int maxPages = 20}) async {
  if (!c.configured) throw 'آدرس سایت و کلیدهای ووکامرس را در تنظیمات وارد کنید';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final auth = 'Basic ${base64.encode(utf8.encode('${c.key.trim()}:${c.secret.trim()}'))}';
  final out = <WooOrder>[];
  try {
    for (var page = 1; page <= maxPages; page++) {
      final uri = wooUri(c, 'orders', {
        'per_page': '50',
        'page': '$page',
        'orderby': 'date',
        'order': 'asc',
        if (after != null) 'after': after.toUtc().toIso8601String().split('.').first,
      });
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 25));
      req.headers.set(HttpHeaders.authorizationHeader, auth);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 40));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 40));
      if (res.statusCode == 401 || res.statusCode == 403) throw 'کلیدهای API ووکامرس پذیرفته نشد (${res.statusCode}) — دسترسی «خواندن» کلید را بررسی کنید';
      if (res.statusCode == 404) throw 'API ووکامرس در این آدرس پیدا نشد؛ پیوندهای یکتا (Permalinks) سایت را روی «نام نوشته» بگذارید';
      if (res.statusCode < 200 || res.statusCode >= 300) throw 'خطای سایت (${res.statusCode}): ${body.length > 200 ? body.substring(0, 200) : body}';
      final j = jsonDecode(body);
      if (j is! List) throw 'پاسخ سایت قابل خواندن نیست';
      out.addAll(j.whereType<Map<String, dynamic>>().map(WooOrder.fromApi));
      if (j.length < 50) break;
    }
  } on TimeoutException {
    throw 'سایت پاسخ نداد (اتصال اینترنت را بررسی کنید)';
  } on SocketException catch (e) {
    throw 'اتصال به سایت برقرار نشد: ${e.message}';
  } on FormatException {
    throw 'پاسخ سایت JSON معتبر نیست';
  } finally {
    client.close(force: true);
  }
  return out;
}

/// Merges fetched orders into the store (keeps the «سند شده» link). Returns how many are new.
int mergeWooOrders(AppStore s, List<WooOrder> fetched) {
  var added = 0;
  for (final o in fetched) {
    final i = s.wooOrders.indexWhere((x) => x.id == o.id);
    if (i >= 0) {
      o.invoiceId = s.wooOrders[i].invoiceId;
      s.wooOrders[i] = o;
    } else {
      s.wooOrders.add(o);
      added++;
    }
  }
  s.wooOrders.sort((a, b) => b.date.compareTo(a.date));
  s.woo.lastFetch = DateTime.now();
  s.updateSettings((_) {});
  return added;
}

/// Finds (or creates) the customer of an order: by phone, then by name.
Person wooCustomer(AppStore s, WooOrder o) {
  final ph = o.phone.replaceAll(RegExp(r'\D'), '');
  String tail(String x) => x.length > 10 ? x.substring(x.length - 10) : x;
  if (ph.length >= 7) {
    final hit = s.people.where((p) => p.phone.isNotEmpty && tail(normalizeDigits(p.phone).replaceAll(RegExp(r'\D'), '')) == tail(ph)).firstOrNull;
    if (hit != null) return hit;
  }
  final name = o.customer.trim().isEmpty ? 'مشتری سایت ${o.number}' : o.customer.trim();
  final byName = s.people.where((p) => p.name.trim() == name).firstOrNull;
  if (byName != null) return byName;
  final p = Person(id: newId(), name: name, phone: o.phone, note: [o.email, o.address].where((x) => x.isNotEmpty).join(' — '));
  s.upsertPerson(p);
  return p;
}

/// Product of an order row: SKU → code / barcode, then exact name.
Product? wooProduct(AppStore s, WooItem it) {
  final sku = normalizeDigits(it.sku.trim());
  if (sku.isNotEmpty) {
    final p = s.products.where((p) => normalizeDigits(p.code) == sku || normalizeDigits(p.info['barcode'] ?? '') == sku).firstOrNull;
    if (p != null) return p;
  }
  return s.products.where((p) => p.name.trim() == it.name.trim()).firstOrNull;
}

/// «صدور فاکتور»: turns an order into a sale invoice (and its receipt, when paid).
Invoice wooToInvoice(AppStore s, WooOrder o) {
  final c = s.woo;
  final f = c.factor <= 0 ? 1 : c.factor;
  final person = wooCustomer(s, o);
  final lines = <InvoiceLine>[];
  var rowsGross = 0;
  for (final it in o.items) {
    var p = wooProduct(s, it);
    if (p == null && c.createProducts) {
      p = Product(id: newId(), name: it.name, code: it.sku.trim(), sellPrice: it.price * f);
      s.upsertProduct(p);
    }
    final qty = it.qty <= 0 ? 1.0 : it.qty;
    final unit = it.price * f;
    lines.add(InvoiceLine(productId: p?.id, title: p == null ? it.name : '', qty: qty, unitPrice: unit));
    rowsGross += (unit * qty).round();
  }
  final total = o.total * f;
  final ship = o.shipping * f;
  // the gap between rows + shipping and the order total is the coupon (−) or tax/fees (+)
  final diff = total - rowsGross - ship;
  final discount = diff < 0 ? -diff : 0;
  final extra = ship + (diff > 0 ? diff : 0);
  final paid = c.paidStatuses.contains(o.status);
  final acc = paid ? s.account(c.payAccounts[o.payMethod] ?? c.payAccounts['*']) : null;
  final inv = Invoice(
    id: newId(),
    kind: InvoiceKind.sale,
    number: s.nextInvoiceNumber(InvoiceKind.sale),
    date: o.date,
    personId: person.id,
    lines: lines,
    discount: discount,
    extra: extra,
    paid: acc == null ? 0 : total,
    accountId: acc?.id,
    note: 'سفارش سایت شماره ${o.number}${o.payTitle.isEmpty ? '' : ' — ${o.payTitle}'}${o.note.isEmpty ? '' : ' — ${o.note}'}',
    info: {'woo': '${o.id}', if (o.recipient.isNotEmpty) 'recipient': o.recipient, if (o.recipientAddress.isNotEmpty) 'address': o.recipientAddress},
  );
  s.saveInvoice(inv);
  o.invoiceId = inv.id;
  s.updateSettings((_) {});
  return inv;
}
