import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/sms.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/sakan.dart';

/// «ارسال پیام» (Ctrl+F11): SMS to people, cheque due reminders, the sent
/// messages and the SMS panel settings.
Future<void> showSmsWindow(BuildContext context, {int tab = 0}) =>
    showDialog<void>(context: context, builder: (_) => _SmsWindow(initialTab: tab));

/// Sends the SMS of one invoice (editable text, the buyer's mobile).
Future<void> showInvoiceSms(BuildContext context, Invoice inv) {
  final s = StoreScope.read(context);
  final p = s.person(inv.personId);
  return _showSendOne(
    context,
    title: 'ارسال پیامک ${inv.proforma ? 'پیش فاکتور' : inv.kind.label} ${inv.number}',
    to: p?.phone ?? '',
    name: p?.name ?? (inv.info['buyerName'] ?? ''),
    text: invoiceSmsText(s, inv),
    ref: 'inv:${inv.id}',
  );
}

/// Sends a message to one person (balance text by default).
Future<void> showPersonSms(BuildContext context, Person p) {
  final s = StoreScope.read(context);
  return _showSendOne(context, title: 'ارسال پیامک به ${p.name}', to: p.phone, name: p.name, text: debtSmsText(s, p));
}

Future<void> _showSendOne(BuildContext context,
    {required String title, required String to, required String name, required String text, String ref = ''}) async {
  final s = StoreScope.read(context);
  if (!s.settings.sms.configured) {
    final go = await confirm(context, 'پنل پیامک', 'پنل پیامک هنوز تنظیم نشده است. تنظیمات پنل باز شود؟', ok: 'تنظیمات', danger: false);
    if (go && context.mounted) await showSmsWindow(context, tab: 3);
    return;
  }
  if (!context.mounted) return;
  final toC = TextEditingController(text: to);
  final textC = TextEditingController(text: text);
  var sending = false;
  final sent = s.smsSentFor(ref) && ref.isNotEmpty;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Future<void> send() async {
          if (normalizeMobile(toC.text).isEmpty) {
            toast(ctx, 'شماره موبایل معتبر نیست', error: true);
            return;
          }
          set(() => sending = true);
          final ok = await sendSmsBatch(s, [SmsJob(to: toC.text, name: name, text: textC.text.trim(), ref: ref)]);
          if (!ctx.mounted) return;
          set(() => sending = false);
          if (ok == 1) {
            Navigator.pop(ctx);
            toast(context, 'پیامک ارسال شد');
          } else {
            toast(ctx, s.smsLog.isEmpty ? 'ارسال ناموفق' : s.smsLog.first.result, error: true);
          }
        }

        return FormDialog(
          title: title,
          width: 520,
          actions: [
            TextButton(onPressed: sending ? null : () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton.icon(
              onPressed: sending ? null : send,
              icon: sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('ارسال'),
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (sent)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('این پیام قبلاً یک بار ارسال شده است.', style: TextStyle(color: Colors.orange.shade800)),
              ),
            TextField(
              controller: toC,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: 'شماره موبایل${name.isEmpty ? '' : ' — $name'}', prefixIcon: const Icon(Icons.phone_android_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textC,
              minLines: 5,
              maxLines: 9,
              onChanged: (_) => set(() {}),
              decoration: const InputDecoration(labelText: 'متن پیام', alignLabelWithHint: true),
            ),
            const SizedBox(height: 6),
            Text('${textC.text.runes.length} نویسه — ${smsParts(textC.text)} پیامک',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).hintColor)),
          ]),
        );
      },
    ),
  );
  toC.dispose();
  textC.dispose();
}

// =========================================================================== window

class _SmsWindow extends StatefulWidget {
  final int initialTab;
  const _SmsWindow({this.initialTab = 0});

  @override
  State<_SmsWindow> createState() => _SmsWindowState();
}

class _SmsWindowState extends State<_SmsWindow> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SakanWindow(
        title: 'ارسال پیام',
        width: 1040,
        height: 720,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Material(
            color: Colors.white.withValues(alpha: 0.6),
            child: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
              Tab(icon: Icon(Icons.groups_outlined, size: 18), text: 'ارسال به اشخاص'),
              Tab(icon: Icon(Icons.event_note_outlined, size: 18), text: 'یادآوری سررسید چک'),
              Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'پیام‌های ارسالی'),
              Tab(icon: Icon(Icons.settings_outlined, size: 18), text: 'تنظیمات پنل پیامک'),
            ]),
          ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _PeopleTab(onSettings: () => _tabs.animateTo(3)),
              _ChequeTab(onSettings: () => _tabs.animateTo(3)),
              const _LogTab(),
              const _SettingsTab(),
            ]),
          ),
        ]),
      );
}

Widget _notConfigured(VoidCallback onSettings) => Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFFF4D6), border: Border.all(color: const Color(0xFFE6C66A)), borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFFB7791F)),
        const SizedBox(width: 8),
        const Expanded(child: Text('برای ارسال پیامک، ابتدا مشخصات پنل پیامک خود را وارد کنید.')),
        sakanBtn('تنظیمات پنل', onSettings, icon: Icons.settings_outlined),
      ]),
    );

/// Shared send-with-progress for the list tabs.
Future<void> _sendJobs(BuildContext context, List<SmsJob> jobs) async {
  final s = StoreScope.read(context);
  if (jobs.isEmpty) {
    toast(context, 'گیرنده‌ای انتخاب نشده است', error: true);
    return;
  }
  final ok = await confirm(context, 'ارسال پیامک', '${jobs.length} پیامک ارسال شود؟', ok: 'ارسال', danger: false);
  if (!ok || !context.mounted) return;
  final progress = ValueNotifier<int>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: jobs.isEmpty ? null : v / jobs.length),
            const SizedBox(height: 12),
            Text('در حال ارسال… $v از ${jobs.length}'),
          ]),
        ),
      ),
    ),
  );
  final sent = await sendSmsBatch(s, jobs, onProgress: (d, _) => progress.value = d);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  final failed = jobs.length - sent;
  toast(context, failed == 0 ? '$sent پیامک ارسال شد' : '$sent پیامک ارسال شد، $failed مورد ناموفق (جزئیات در «پیام‌های ارسالی»)',
      error: failed > 0);
}

// --------------------------------------------------------------------- people tab

class _PeopleTab extends StatefulWidget {
  final VoidCallback onSettings;
  const _PeopleTab({required this.onSettings});

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  final _text = TextEditingController();
  final _sel = <String>{};
  int _filter = 0; // 0 all, 1 debtors, 2 creditors
  bool _useTemplate = true;
  String? _focus;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _text.text = StoreScope.read(context).settings.sms.debtTemplate;
  }

  @override
  void dispose() {
    _q.dispose();
    _text.dispose();
    super.dispose();
  }

  List<(Person, int)> _rows(AppStore s) {
    final q = normalizeDigits(_q.text.trim());
    final out = <(Person, int)>[];
    for (final p in s.people) {
      final b = s.personBalance(p.id);
      if (_filter == 1 && b <= 0) continue;
      if (_filter == 2 && b >= 0) continue;
      if (q.isNotEmpty && !p.name.contains(q) && !normalizeDigits(p.phone).contains(q) && '${p.code}' != q) continue;
      out.add((p, b));
    }
    out.sort((a, b) => a.$1.name.compareTo(b.$1.name));
    return out;
  }

  String _messageFor(AppStore s, Person p) => fillSms(_text.text, smsValues(s, p));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = StoreScope.of(context);
    final rows = _rows(s);
    final valid = rows.where((r) => normalizeMobile(r.$1.phone).isNotEmpty).toList();
    final selected = valid.where((r) => _sel.contains(r.$1.id)).toList();
    final preview = _focus == null ? (selected.isNotEmpty ? selected.first.$1 : null) : s.person(_focus);
    final previewText = preview == null ? _text.text : _messageFor(s, preview);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!s.settings.sms.configured) _notConfigured(widget.onSettings),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Row(children: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجوی نام، کد یا شماره'),
            ),
          ),
          const SizedBox(width: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('همه')),
              ButtonSegment(value: 1, label: Text('بدهکاران')),
              ButtonSegment(value: 2, label: Text('بستانکاران')),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
          const Spacer(),
          sakanBtn('انتخاب همه', () => setState(() => _sel.addAll(valid.map((r) => r.$1.id)))),
          const SizedBox(width: 6),
          sakanBtn('حذف انتخاب', () => setState(_sel.clear)),
        ]),
      ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 10, 10),
              child: SakanGrid(
                header: [
                  sakanHead('', 40),
                  sakanHead('کد', 60),
                  sakanHead('نام شخص', 0),
                  sakanHead('موبایل', 130),
                  sakanHead('مانده حساب', 150),
                ],
                count: rows.length,
                empty: 'شخصی پیدا نشد',
                row: (_, i) {
                  final (p, b) = rows[i];
                  final mobile = normalizeMobile(p.phone);
                  final on = _sel.contains(p.id);
                  return InkWell(
                    onTap: mobile.isEmpty
                        ? null
                        : () => setState(() {
                              on ? _sel.remove(p.id) : _sel.add(p.id);
                              _focus = p.id;
                            }),
                    child: Container(
                      color: _focus == p.id ? const Color(0xFFE3EEFD) : (i.isOdd ? const Color(0xFFF8FBFF) : null),
                      child: Row(children: [
                        sakanCell(
                            Checkbox(
                              value: on,
                              visualDensity: VisualDensity.compact,
                              onChanged: mobile.isEmpty ? null : (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                            ),
                            40),
                        sakanCell(Text('${p.code}'), 60),
                        sakanCell(Text(p.name, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                        sakanCell(
                            Text(mobile.isEmpty ? (p.phone.isEmpty ? '—' : 'نامعتبر') : mobile,
                                textDirection: TextDirection.ltr, style: TextStyle(color: mobile.isEmpty ? Colors.black38 : null)),
                            130),
                        sakanCell(
                            Text(b == 0 ? '0' : '${groupDigits(b.abs())} ${b > 0 ? 'بد' : 'بس'}',
                                style: TextStyle(color: b > 0 ? const Color(0xFFC62828) : (b < 0 ? const Color(0xFF2E7D32) : null))),
                            150),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Text('متن پیام', style: TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'متن آماده',
                    onSelected: (v) => setState(() {
                      _useTemplate = true;
                      _text.text = v;
                    }),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: s.settings.sms.debtTemplate, child: const Text('اعلام مانده حساب')),
                      const PopupMenuItem(value: '{نام} عزیز\n\n{فروشگاه}', child: Text('متن آزاد با نام')),
                    ],
                    child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.text_snippet_outlined)),
                  ),
                ]),
                const SizedBox(height: 6),
                Expanded(
                  child: TextField(
                    controller: _text,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() => _useTemplate = true),
                    decoration: const InputDecoration(alignLabelWithHint: true, filled: true, fillColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                _FieldChips(fields: smsCommonFields, controller: _text, onInsert: () => setState(() {})),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minHeight: 70, maxHeight: 150),
                  decoration: BoxDecoration(color: const Color(0xFFEFFAEF), border: Border.all(color: const Color(0xFFA5D6A7)), borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(preview == null ? 'پیش‌نمایش' : 'پیش‌نمایش برای ${preview.name}',
                          style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      const SizedBox(height: 4),
                      Text(previewText),
                      const SizedBox(height: 4),
                      Text('${previewText.runes.length} نویسه — ${smsParts(previewText)} پیامک',
                          style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: !s.settings.sms.configured || selected.isEmpty || _text.text.trim().isEmpty
                        ? null
                        : () => _sendJobs(context, [
                              for (final (p, _) in selected)
                                SmsJob(to: p.phone, name: p.name, text: _useTemplate ? _messageFor(s, p) : _text.text.trim()),
                            ]),
                    icon: const Icon(Icons.send_rounded),
                    label: Text('ارسال به ${selected.length} نفر'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _FieldChips extends StatelessWidget {
  final List<String> fields;
  final TextEditingController controller;
  final VoidCallback onInsert;
  const _FieldChips({required this.fields, required this.controller, required this.onInsert});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, runSpacing: 4, children: [
        for (final f in fields)
          ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text(f, style: const TextStyle(fontSize: 11)),
            onPressed: () {
              final c = controller;
              final sel = c.selection;
              final t = '{$f}';
              final start = sel.isValid ? sel.start : c.text.length;
              final end = sel.isValid ? sel.end : c.text.length;
              c.text = c.text.replaceRange(start, end, t);
              c.selection = TextSelection.collapsed(offset: start + t.length);
              onInsert();
            },
          ),
      ]);
}

// --------------------------------------------------------------------- cheque tab

class _ChequeTab extends StatefulWidget {
  final VoidCallback onSettings;
  const _ChequeTab({required this.onSettings});

  @override
  State<_ChequeTab> createState() => _ChequeTabState();
}

class _ChequeTabState extends State<_ChequeTab> with AutomaticKeepAliveClientMixin {
  int _days = 3;
  final _sel = <String>{};
  bool _init = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = StoreScope.of(context);
    final list = dueCheques(s, days: _days);
    bool can(Cheque c) => normalizeMobile(s.person(c.personId)?.phone ?? '').isNotEmpty;
    if (!_init) {
      _init = true;
      _sel.addAll(list.where((c) => can(c) && !s.smsSentFor('chq:${c.id}')).map((c) => c.id));
    }
    final chosen = list.where((c) => _sel.contains(c.id) && can(c)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!s.settings.sms.configured) _notConfigured(widget.onSettings),
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          const Text('چک‌های دریافتی که تا '),
          SizedBox(
            width: 90,
            child: DropdownButton<int>(
              value: _days,
              isExpanded: true,
              items: [
                for (final d in const [0, 1, 2, 3, 7, 15, 30]) DropdownMenuItem(value: d, child: Text(d == 0 ? 'امروز' : '$d روز')),
              ],
              onChanged: (v) => setState(() => _days = v ?? _days),
            ),
          ),
          const Text(' آینده سررسید می‌شوند'),
          const Spacer(),
          sakanBtn('انتخاب همه', () => setState(() => _sel.addAll(list.where(can).map((c) => c.id)))),
          const SizedBox(width: 6),
          sakanBtn('حذف انتخاب', () => setState(_sel.clear)),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SakanGrid(
            header: [
              sakanHead('', 40),
              sakanHead('سررسید', 100),
              sakanHead('شماره چک', 110),
              sakanHead('بانک', 120),
              sakanHead('صادرکننده', 0),
              sakanHead('موبایل', 120),
              sakanHead('مبلغ', 130),
              sakanHead('یادآوری', 90),
            ],
            count: list.length,
            empty: 'چکی در این بازه سررسید نمی‌شود',
            row: (_, i) {
              final c = list[i];
              final p = s.person(c.personId);
              final mobile = normalizeMobile(p?.phone ?? '');
              final sent = s.smsSentFor('chq:${c.id}');
              return Container(
                color: i.isOdd ? const Color(0xFFF8FBFF) : null,
                child: Row(children: [
                  sakanCell(
                      Checkbox(
                        value: _sel.contains(c.id),
                        visualDensity: VisualDensity.compact,
                        onChanged: mobile.isEmpty ? null : (v) => setState(() => v == true ? _sel.add(c.id) : _sel.remove(c.id)),
                      ),
                      40),
                  sakanCell(Text(jFormat(c.dueDate)), 100),
                  sakanCell(Text(c.serial), 110),
                  sakanCell(Text(c.bank, overflow: TextOverflow.ellipsis), 120),
                  sakanCell(Text(p?.name ?? '—', overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                  sakanCell(Text(mobile.isEmpty ? '—' : mobile, textDirection: TextDirection.ltr), 120),
                  sakanCell(Text(groupDigits(c.amount)), 130),
                  sakanCell(
                      Text(sent ? 'ارسال شده' : '—', style: TextStyle(color: sent ? const Color(0xFF2E7D32) : Colors.black38)), 90),
                ]),
              );
            },
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(
            child: Text(
              'متن پیام از «تنظیمات پنل پیامک ← متن یادآوری چک» گرفته می‌شود.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ),
          SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: !s.settings.sms.configured || chosen.isEmpty
                  ? null
                  : () => _sendJobs(context, [
                        for (final c in chosen)
                          SmsJob(to: s.person(c.personId)!.phone, name: s.person(c.personId)!.name, text: chequeSmsText(s, c), ref: 'chq:${c.id}'),
                      ]),
              icon: const Icon(Icons.send_rounded),
              label: Text('ارسال یادآوری (${chosen.length})'),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// --------------------------------------------------------------------- log tab

class _LogTab extends StatefulWidget {
  const _LogTab();

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  bool _failedOnly = false;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final list = s.smsLog.where((e) => !_failedOnly || !e.ok).toList();
    final ok = s.smsLog.where((e) => e.ok).length;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('موفق: $ok   ناموفق: ${s.smsLog.length - ok}'),
          const SizedBox(width: 16),
          FilterChip(label: const Text('فقط ناموفق‌ها'), selected: _failedOnly, onSelected: (v) => setState(() => _failedOnly = v)),
          const Spacer(),
          sakanBtn('ارسال مجدد ناموفق‌ها', () {
            final failed = list.where((e) => !e.ok).toList();
            _sendJobs(context, [for (final e in failed) SmsJob(to: e.to, name: e.name, text: e.text, ref: e.ref)]);
          }, icon: Icons.replay_rounded),
          const SizedBox(width: 6),
          sakanBtn('پاک کردن گزارش', () async {
            final yes = await confirm(context, 'پاک کردن گزارش', 'همه سوابق پیام‌های ارسالی پاک شود؟', ok: 'پاک کن');
            if (yes) s.clearSmsLog();
          }, icon: Icons.delete_outline),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: SakanGrid(
            header: [
              sakanHead('تاریخ', 140),
              sakanHead('گیرنده', 160),
              sakanHead('موبایل', 115),
              sakanHead('متن پیام', 0),
              sakanHead('وضعیت', 220),
            ],
            count: list.length,
            empty: 'پیامی ارسال نشده است',
            row: (_, i) {
              final e = list[i];
              final d = e.date;
              return Tooltip(
                message: e.text,
                waitDuration: const Duration(milliseconds: 500),
                child: Container(
                  color: i.isOdd ? const Color(0xFFF8FBFF) : null,
                  child: Row(children: [
                    sakanCell(Text('${jFormat(d)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'), 140),
                    sakanCell(Text(e.name, overflow: TextOverflow.ellipsis), 160, align: Alignment.centerRight),
                    sakanCell(Text(e.to, textDirection: TextDirection.ltr), 115),
                    sakanCell(Text(e.text.replaceAll('\n', ' ⏎ '), maxLines: 1, overflow: TextOverflow.ellipsis), 0, align: Alignment.centerRight),
                    sakanCell(
                        Text(e.ok ? '✓ ارسال شد' : '✗ ${e.result}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: e.ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828))),
                        220,
                        align: Alignment.centerRight),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------------- settings tab

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> with AutomaticKeepAliveClientMixin {
  late SmsConfig c;
  late final _apiKey = TextEditingController(text: c.apiKey);
  late final _user = TextEditingController(text: c.username);
  late final _pass = TextEditingController(text: c.password);
  late final _sender = TextEditingController(text: c.sender);
  late final _url = TextEditingController(text: c.customUrl);
  late final _sig = TextEditingController(text: c.signature);
  late final _inv = TextEditingController(text: c.invoiceTemplate);
  late final _chq = TextEditingController(text: c.chequeTemplate);
  late final _debt = TextEditingController(text: c.debtTemplate);
  final _testTo = TextEditingController();
  bool _showPass = false;
  bool _testing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    c = SmsConfig.fromJson(StoreScope.read(context).settings.sms.toJson());
    _testTo.text = StoreScope.read(context).settings.businessPhone;
  }

  @override
  void dispose() {
    for (final x in [_apiKey, _user, _pass, _sender, _url, _sig, _inv, _chq, _debt, _testTo]) {
      x.dispose();
    }
    super.dispose();
  }

  SmsConfig _collect() => c
    ..apiKey = _apiKey.text.trim()
    ..username = _user.text.trim()
    ..password = _pass.text
    ..sender = normalizeDigits(_sender.text.trim())
    ..customUrl = _url.text.trim()
    ..signature = _sig.text.trim()
    ..invoiceTemplate = _inv.text.trim().isEmpty ? SmsConfig.defaultInvoiceSms : _inv.text.trim()
    ..chequeTemplate = _chq.text.trim().isEmpty ? SmsConfig.defaultChequeSms : _chq.text.trim()
    ..debtTemplate = _debt.text.trim().isEmpty ? SmsConfig.defaultDebtSms : _debt.text.trim();

  void _save() {
    final s = StoreScope.read(context);
    s.settings.sms = SmsConfig.fromJson(_collect().toJson());
    s.saveNow();
    toast(context, 'تنظیمات پیامک ذخیره شد');
  }

  Future<void> _test() async {
    final cfg = _collect();
    if (!cfg.configured) {
      toast(context, 'مشخصات پنل کامل نیست', error: true);
      return;
    }
    setState(() => _testing = true);
    final r = await sendSms(cfg, _testTo.text, 'پیام آزمایشی از نرم‌افزار حسابداری تراز');
    if (!mounted) return;
    setState(() => _testing = false);
    toast(context, r.ok ? 'پیام آزمایشی ارسال شد' : r.message, error: !r.ok);
  }

  Widget _tf(TextEditingController c, String label, {bool ltr = false, String? hint, bool obscure = false, Widget? suffix}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: obscure,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, suffixIcon: suffix),
        ),
      );

  Widget _template(String title, TextEditingController ctl, List<String> fields, String def) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => ctl.text = def), child: const Text('متن پیش‌فرض')),
          ]),
          TextField(controller: ctl, minLines: 3, maxLines: 6, decoration: const InputDecoration(filled: true, fillColor: Colors.white)),
          const SizedBox(height: 4),
          _FieldChips(fields: [...fields, ...smsCommonFields], controller: ctl, onInsert: () => setState(() {})),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final th = Theme.of(context);
    final p = c.provider;
    final eye = IconButton(
      icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
      onPressed: () => setState(() => _showPass = !_showPass),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save},
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: sakanGroup(
                  'مشخصات پنل پیامک',
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      FieldDropdown<SmsProvider>(
                        label: 'سرویس دهنده پیامک',
                        value: p,
                        items: [for (final x in SmsProvider.values) DropdownMenuItem(value: x, child: Text(x.label))],
                        onChanged: (v) => setState(() => c.provider = v ?? p),
                      ),
                      const SizedBox(height: 12),
                      if (p == SmsProvider.kavenegar || p == SmsProvider.smsir || p == SmsProvider.custom)
                        _tf(_apiKey, p == SmsProvider.custom ? 'کلید (API Key) — {key}' : 'کلید وب‌سرویس (API Key)',
                            ltr: true, obscure: !_showPass, suffix: eye),
                      if (p == SmsProvider.melipayamak || p == SmsProvider.custom) ...[
                        _tf(_user, p == SmsProvider.custom ? 'نام کاربری — {user}' : 'نام کاربری پنل', ltr: true),
                        _tf(_pass, p == SmsProvider.custom ? 'رمز عبور — {pass}' : 'رمز عبور پنل (یا کلید API)',
                            ltr: true, obscure: !_showPass, suffix: eye),
                      ],
                      _tf(_sender, p == SmsProvider.kavenegar ? 'شماره خط ارسال (اختیاری)' : 'شماره خط ارسال${p == SmsProvider.custom ? ' — {from}' : ''}',
                          ltr: true, hint: 'مثلاً 3000xxxx'),
                      if (p == SmsProvider.custom)
                        _tf(_url, 'آدرس ارسال (GET)',
                            ltr: true, hint: 'https://panel.example.ir/send?user={user}&pass={pass}&from={from}&to={to}&text={text}'),
                      Text(
                        switch (p) {
                          SmsProvider.kavenegar => 'کلید API را از پنل کاوه‌نگار ← تنظیمات حساب ← کلید API بردارید.',
                          SmsProvider.melipayamak => 'نام کاربری و رمز پنل ملی پیامک و شماره خط اختصاصی را وارد کنید.',
                          SmsProvider.smsir => 'کلید API را از پنل SMS.ir ← برنامه‌نویسان ← لیست کلیدها بسازید و شماره خط را وارد کنید.',
                          SmsProvider.custom => 'برای پنل‌های دیگر، آدرس وب‌سرویس ارسال را با جایگزین‌های {to} {text} {from} {user} {pass} {key} بنویسید.',
                        },
                        style: th.textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                      const Divider(height: 24),
                      _tf(_sig, 'امضای انتهای پیام {فروشگاه}', hint: 'خالی = نام فروشگاه از تنظیمات'),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: c.autoInvoice,
                        onChanged: (v) => setState(() => c.autoInvoice = v ?? false),
                        title: const Text('ارسال خودکار پیامک فاکتور فروش به خریدار پس از ثبت فاکتور'),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: c.autoCheque,
                        onChanged: (v) => setState(() => c.autoCheque = v ?? false),
                        title: const Text('ارسال خودکار یادآوری به صادرکننده چک‌های دریافتی در روز سررسید (هنگام باز کردن برنامه)'),
                      ),
                      const Divider(height: 24),
                      Row(children: [
                        Expanded(child: _tf(_testTo, 'شماره موبایل برای پیام آزمایشی', ltr: true)),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: sakanBtn(_testing ? 'در حال ارسال…' : 'ارسال آزمایشی', _testing ? null : _test, icon: Icons.send_outlined),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: sakanGroup(
                  'متن پیام‌ها',
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _template('متن پیامک فاکتور', _inv, smsInvoiceFields, SmsConfig.defaultInvoiceSms),
                      _template('متن یادآوری سررسید چک', _chq, smsChequeFields, SmsConfig.defaultChequeSms),
                      _template('متن اعلام مانده حساب', _debt, const [], SmsConfig.defaultDebtSms),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.white.withValues(alpha: 0.5),
          child: Row(children: [
            const Spacer(),
            SizedBox(
              height: 42,
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('ذخیره تنظیمات (Ctrl+S)')),
            ),
          ]),
        ),
      ]),
    );
  }
}
