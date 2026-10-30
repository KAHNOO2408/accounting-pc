import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../data/woo.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';
import 'invoice_editor.dart' show fmtQty, showInvoiceEditor;

/// «لیست فاکتورهای ثبت شده در وبسایت ووکامرس».
Future<void> showWooOrders(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _WooOrders());

class _WooOrders extends StatefulWidget {
  const _WooOrders();

  @override
  State<_WooOrders> createState() => _WooOrdersState();
}

class _WooOrdersState extends State<_WooOrders> {
  int? _sel;
  int _filter = 1; // 0 همه، 1 سند نشده، 2 سند شده
  DateTime? _from, _to;
  bool _busy = false;
  String? _msg;

  Future<void> _fetch(AppStore s, {bool all = false}) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final after = all ? _from : (s.woo.lastFetch == null ? _from : s.woo.lastFetch!.subtract(const Duration(days: 2)));
      final list = await fetchWooOrders(s.woo, after: after);
      final n = mergeWooOrders(s, list);
      _msg = '${list.length} سفارش دریافت شد ($n سفارش جدید)';
    } catch (e) {
      _msg = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toInvoice(AppStore s, List<WooOrder> orders) async {
    var n = 0;
    for (final o in orders.where((o) => o.invoiceId == null)) {
      wooToInvoice(s, o);
      n++;
    }
    if (mounted) {
      toast(context, '$n فاکتور فروش صادر شد');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.wooOrders.where((o) {
      if (_filter == 1 && o.invoiceId != null) return false;
      if (_filter == 2 && o.invoiceId == null) return false;
      final d = dateOnly(o.date);
      if (_from != null && d.isBefore(_from!)) return false;
      if (_to != null && d.isAfter(_to!)) return false;
      return true;
    }).toList();
    final sel = list.where((o) => o.id == _sel).firstOrNull;
    final f = s.woo.factor <= 0 ? 1 : s.woo.factor;
    return SakanWindow(
      title: 'لیست فاکتورهای ثبت شده در وبسایت ووکامرس',
      width: 1180,
      height: 680,
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            sakanBtn('دریافت سفارش‌های جدید', _busy ? null : () => _fetch(s), icon: Icons.cloud_download_outlined),
            sakanBtn('دریافت مجدد بازه', _busy ? null : () => _fetch(s, all: true), icon: Icons.refresh_rounded),
            sakanBtn('صدور فاکتور', sel == null || sel.invoiceId != null ? null : () => _toInvoice(s, [sel]), key: 'F2', icon: Icons.receipt_long_outlined),
            sakanBtn('صدور فاکتور همه سند نشده‌ها', list.any((o) => o.invoiceId == null) ? () => _toInvoice(s, list) : null, icon: Icons.playlist_add_check_rounded),
            sakanBtn('نمایش فاکتور', sel?.invoiceId == null
                ? null
                : () {
                    final inv = s.invoices.where((i) => i.id == sel!.invoiceId).firstOrNull;
                    if (inv != null) showInvoiceEditor(context, edit: inv);
                  }, icon: Icons.visibility_outlined),
            sakanBtn('اقلام', sel == null ? null : () => _items(context, sel, f), icon: Icons.list_alt_rounded),
            sakanBtn('گیرنده', sel == null ? null : () => _recipient(context, sel), icon: Icons.local_shipping_outlined),
            sakanBtn('حذف از لیست', sel == null
                ? null
                : () {
                    s.wooOrders.removeWhere((o) => o.id == sel.id);
                    s.updateSettings((_) {});
                    setState(() => _sel = null);
                  }, icon: Icons.delete_outline_rounded),
            sakanBtn('تنظیمات', () => showWooSettings(context), icon: Icons.settings_outlined),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 0, label: Text('همه')), ButtonSegment(value: 1, label: Text('سند نشده')), ButtonSegment(value: 2, label: Text('سند شده'))],
              selected: {_filter},
              onSelectionChanged: (v) => setState(() => _filter = v.first),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 170, child: DateField(label: 'از تاریخ', value: _from, clearable: true, onChanged: (d) => setState(() => _from = d))),
            const SizedBox(width: 8),
            SizedBox(width: 170, child: DateField(label: 'تا تاریخ', value: _to, clearable: true, onChanged: (d) => setState(() => _to = d))),
            const SizedBox(width: 12),
            if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            if (_msg != null) Expanded(child: Text(_msg!, overflow: TextOverflow.ellipsis)),
            if (_msg == null && s.woo.lastFetch != null) Text('آخرین دریافت: ${jFormat(s.woo.lastFetch!)}'),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SakanGrid(
              header: [
                sakanHead('شماره سفارش', 90),
                sakanHead('تاریخ', 95),
                sakanHead('نام خریدار', 0),
                sakanHead('تلفن', 120),
                sakanHead('روش پرداخت', 150),
                sakanHead('وضعیت', 120),
                sakanHead('هزینه ارسال', 100),
                sakanHead('مبلغ کل', 120),
                sakanHead('سند', 90),
              ],
              count: list.length,
              empty: s.woo.configured ? 'سفارشی نیست — «دریافت سفارش‌های جدید» را بزنید' : 'ابتدا «تنظیمات» ووکامرس را انجام دهید',
              row: (ctx, i) {
                final o = list[i];
                final on = o.id == _sel;
                final st = TextStyle(color: on ? Colors.white : null, fontSize: 12.5);
                final inv = o.invoiceId == null ? null : s.invoices.where((x) => x.id == o.invoiceId).firstOrNull;
                return InkWell(
                  onTap: () => setState(() => _sel = o.id),
                  onDoubleTap: () => _items(context, o, f),
                  child: Container(
                    color: on ? sakanSel : (o.invoiceId != null ? const Color(0xFFE6F6E6) : (i.isOdd ? const Color(0xFFF3F7FC) : null)),
                    child: Row(children: [
                      sakanCell(Text(o.number, style: st), 90),
                      sakanCell(Text(jFormat(o.date), style: st), 95),
                      sakanCell(Text(o.customer, style: st, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                      sakanCell(Text(o.phone, style: st, textDirection: TextDirection.ltr), 120),
                      sakanCell(Text(o.payTitle, style: st, overflow: TextOverflow.ellipsis), 150),
                      sakanCell(Text(o.statusName, style: st), 120),
                      sakanCell(Text(groupDigits(o.shipping * f), style: st), 100),
                      sakanCell(Text(groupDigits(o.total * f), style: st.copyWith(fontWeight: FontWeight.w700)), 120),
                      sakanCell(Text(inv == null ? 'سند نشده' : 'فاکتور ${inv.number}', style: st), 90),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text('${list.length} سفارش — جمع ${groupDigits(list.fold<int>(0, (a, o) => a + o.total * f))}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Future<void> _items(BuildContext context, WooOrder o, int f) {
    final s = StoreScope.read(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'اقلام سفارش ${o.number}',
        width: 720,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final it in o.items)
            ListTile(
              dense: true,
              title: Text(it.name),
              subtitle: Text([
                if (it.sku.isNotEmpty) 'SKU: ${it.sku}',
                wooProduct(s, it) == null ? 'کالای متناظر در تراز پیدا نشد' : 'کالای تراز: ${wooProduct(s, it)!.name}',
              ].join(' — ')),
              trailing: Text('${fmtQty(it.qty)} × ${groupDigits(it.price * f)} = ${groupDigits(it.total * f)}'),
            ),
          const Divider(),
          Text('هزینه ارسال: ${groupDigits(o.shipping * f)}    تخفیف: ${groupDigits(o.discount * f)}    مالیات: ${groupDigits(o.tax * f)}'),
          Text('مبلغ کل: ${groupDigits(o.total * f)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (o.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('یادداشت خریدار: ${o.note}')),
        ]),
      ),
    );
  }

  Future<void> _recipient(BuildContext context, WooOrder o) => showDialog<void>(
        context: context,
        builder: (ctx) => FormDialog(
          title: 'مشخصات گیرنده سفارش ${o.number}',
          width: 520,
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectableText('خریدار: ${o.customer}'),
            SelectableText('تلفن: ${o.phone}'),
            if (o.email.isNotEmpty) SelectableText('ایمیل: ${o.email}'),
            SelectableText('آدرس خریدار: ${o.address}'),
            const Divider(),
            SelectableText('گیرنده: ${o.recipient}'),
            SelectableText('آدرس ارسال: ${o.recipientAddress}'),
          ]),
        ),
      );
}

/// Connection settings: site, API keys, amount factor and payment accounts.
Future<void> showWooSettings(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _WooSettings());

class _WooSettings extends StatefulWidget {
  const _WooSettings();

  @override
  State<_WooSettings> createState() => _WooSettingsState();
}

class _WooSettingsState extends State<_WooSettings> {
  late final AppStore _s = StoreScope.read(context);
  late final _url = TextEditingController(text: _s.woo.url);
  late final _key = TextEditingController(text: _s.woo.key);
  late final _secret = TextEditingController(text: _s.woo.secret);
  late int _factor = _s.woo.factor;
  late bool _create = _s.woo.createProducts;
  late final Map<String, String> _pay = {..._s.woo.payAccounts};
  late final Set<String> _paid = {..._s.woo.paidStatuses};
  final _method = TextEditingController();
  String? _test;

  @override
  void dispose() {
    for (final c in [_url, _key, _secret, _method]) {
      c.dispose();
    }
    super.dispose();
  }

  WooConfig get _cfg => WooConfig(
        url: _url.text.trim(),
        key: _key.text.trim(),
        secret: _secret.text.trim(),
        factor: _factor,
        payAccounts: _pay,
        paidStatuses: _paid,
        createProducts: _create,
        lastFetch: _s.woo.lastFetch,
      );

  @override
  Widget build(BuildContext context) {
    final methods = {..._pay.keys, for (final o in _s.wooOrders) if (o.payMethod.isNotEmpty) o.payMethod};
    final accounts = _s.activeAccounts;
    return FormDialog(
      title: 'تنظیمات اتصال به ووکامرس',
      width: 680,
      leading: TextButton.icon(
        onPressed: () async {
          setState(() => _test = 'در حال آزمایش…');
          try {
            final l = await fetchWooOrders(_cfg, after: DateTime.now().subtract(const Duration(days: 7)), maxPages: 1);
            _test = 'اتصال برقرار شد — ${l.length} سفارش در ۷ روز اخیر';
          } catch (e) {
            _test = '$e';
          }
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.wifi_tethering_rounded),
        label: const Text('آزمایش اتصال'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف F10')),
        FilledButton(
          onPressed: () {
            _s.woo = _cfg;
            _s.updateSettings((_) {});
            Navigator.pop(context);
          },
          child: const Text('تایید F9'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'آدرس سایت', hintText: 'https://shop.example.com')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _key, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Consumer key', hintText: 'ck_…'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _secret, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Consumer secret', hintText: 'cs_…'))),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('کلید را در پیشخوان وردپرس ← ووکامرس ← پیکربندی ← پیشرفته ← REST API با دسترسی «خواندن» بسازید.', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Text('واحد مبالغ سایت: '),
          const SizedBox(width: 8),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 1, label: Text('مثل تراز')), ButtonSegment(value: 10, label: Text('تومان (×۱۰)')), ButtonSegment(value: 0, label: Text('سفارشی'))],
            selected: {_factor == 1 || _factor == 10 ? _factor : 0},
            onSelectionChanged: (v) => setState(() => _factor = v.first == 0 ? 1000 : v.first),
          ),
          if (_factor != 1 && _factor != 10) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: '$_factor',
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'ضریب', isDense: true),
                onChanged: (v) => _factor = int.tryParse(normalizeDigits(v)) ?? _factor,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _create,
          onChanged: (v) => setState(() => _create = v ?? false),
          title: const Text('کالاهایی که در تراز نیستند هنگام صدور فاکتور تعریف شوند (کد کالا = SKU)'),
        ),
        const Divider(),
        const Text('وضعیت‌هایی که پرداخت شده حساب می‌شوند', style: TextStyle(fontWeight: FontWeight.w800)),
        Wrap(spacing: 4, children: [
          for (final e in wooStatusNames.entries)
            FilterChip(label: Text(e.value), selected: _paid.contains(e.key), onSelected: (v) => setState(() {
                  if (v) {
                    _paid.add(e.key);
                  } else {
                    _paid.remove(e.key);
                  }
                })),
        ]),
        const SizedBox(height: 8),
        const Text('حساب دریافت هر روش پرداخت', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final m in ['*', ...methods.where((m) => m != '*')])
          Row(children: [
            SizedBox(width: 170, child: Text(m == '*' ? 'سایر روش‌ها' : m, textDirection: TextDirection.ltr)),
            Expanded(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: accounts.any((a) => a.id == _pay[m]) ? _pay[m] : null,
                hint: const Text('بدون دریافت (نسیه)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('بدون دریافت (نسیه)')),
                  for (final a in accounts) DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() {
                  if (v == null) {
                    _pay.remove(m);
                  } else {
                    _pay[m] = v;
                  }
                }),
              ),
            ),
          ]),
        Row(children: [
          SizedBox(width: 220, child: TextField(controller: _method, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'افزودن روش (مثلا bacs یا cod)', isDense: true))),
          IconButton(
            onPressed: () {
              final m = _method.text.trim();
              if (m.isEmpty || accounts.isEmpty) return;
              setState(() => _pay[m] = accounts.first.id);
              _method.clear();
            },
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
        if (_test != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_test!, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
