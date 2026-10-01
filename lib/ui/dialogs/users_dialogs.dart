import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../print.dart';
import '../shell.dart' show ribbonCatalog;
import '../theme.dart';
import '../widgets/common.dart';

Widget _head(BuildContext context, List<Widget> cells) {
  final th = Theme.of(context);
  return Container(
    color: Brand.of(context).accent.withValues(alpha: 0.10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: DefaultTextStyle(
      style: th.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w800, color: th.colorScheme.onSurface),
      child: Row(children: cells),
    ),
  );
}

class _Win extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget body;
  final Widget footer;
  final double width;
  const _Win({required this.title, required this.icon, required this.body, required this.footer, this.width = 900});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: (size.height * 0.88).clamp(400.0, 760.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HeaderBand(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
            child: Row(children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(child: body),
          const Divider(),
          Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 12), child: footer),
        ]),
      ),
    );
  }
}

// ================================================================ لیست کاربران

Future<void> showUsersWindow(BuildContext context) async {
  if (!StoreScope.read(context).currentUser.admin) {
    toast(context, 'فقط مدیر سیستم به بخش کاربران دسترسی دارد', error: true);
    return;
  }
  await showDialog<void>(context: context, builder: (_) => const _UsersWindow());
}

class _UsersWindow extends StatefulWidget {
  const _UsersWindow();

  @override
  State<_UsersWindow> createState() => _UsersWindowState();
}

class _UsersWindowState extends State<_UsersWindow> {
  String? _sel;

  AppUser? _selected(AppStore s) => s.users.where((u) => u.id == _sel).firstOrNull;

  bool _needUser(AppStore s) {
    if (_sel == 'owner') {
      toast(context, 'این عملیات برای مدیر اصلی برنامه از «تنظیمات» انجام می‌شود', error: true);
      return false;
    }
    if (_selected(s) == null) {
      toast(context, 'کاربر را انتخاب کنید', error: true);
      return false;
    }
    return true;
  }

  Future<void> _form({AppUser? edit, AppUser? copyOf}) async {
    await showDialog<void>(context: context, builder: (_) => _UserForm(edit: edit, copyOf: copyOf));
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final s = StoreScope.read(context);
    if (!_needUser(s)) return;
    final u = _selected(s)!;
    if (u.id == s.currentUserId) return toast(context, 'کاربر فعلی قابل حذف نیست', error: true);
    final ok = await confirm(context, 'حذف کاربر', 'کاربر «${u.name}» حذف شود؟');
    if (!ok || !mounted) return;
    s.removeUser(u.id);
    setState(() => _sel = null);
  }

  Future<void> _resetPassword() async {
    final s = StoreScope.read(context);
    if (_sel == 'owner') {
      return toast(context, 'رمز مدیر اصلی را از «تنظیمات» تغییر دهید', error: true);
    }
    if (!_needUser(s)) return;
    final u = _selected(s)!;
    final p = await _askPassword(context, 'بازنشانی رمز عبور — ${u.name}');
    if (p == null || !mounted) return;
    s.saveUser(u, password: p);
    toast(context, 'رمز عبور ${u.name} تغییر کرد');
  }

  Future<void> _permissions() async {
    final s = StoreScope.read(context);
    if (!_needUser(s)) return;
    await showDialog<void>(context: context, builder: (_) => _Permissions(user: _selected(s)!));
    if (mounted) setState(() {});
  }

  Future<void> _copyPermissions() async {
    final s = StoreScope.read(context);
    if (!_needUser(s)) return;
    final target = _selected(s)!;
    final from = await showDialog<AppUser>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'کپی دسترسی از کاربر دیگر به «${target.name}»',
        width: 460,
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))],
        child: Column(children: [
          for (final u in s.users.where((u) => u.id != target.id))
            ListTile(leading: const Icon(Icons.person_outline), title: Text(u.name), subtitle: Text(u.login), onTap: () => Navigator.pop(ctx, u)),
          if (s.users.length < 2) const Padding(padding: EdgeInsets.all(16), child: Text('کاربر دیگری وجود ندارد')),
        ]),
      ),
    );
    if (from == null || !mounted) return;
    target
      ..denied = {...from.denied}
      ..admin = from.admin;
    s.saveUser(target);
    toast(context, 'دسترسی‌های ${from.name} به ${target.name} کپی شد');
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    Widget btn(String label, IconData icon, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () {
          final u = _selected(s);
          if (u != null) _form(copyOf: u);
        },
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: _Win(
          title: 'لیست کاربران',
          icon: Icons.manage_accounts_outlined,
          width: 980,
          footer: Row(children: [
            Text('کاربر فعلی: ${s.currentUser.name}', style: th.textTheme.bodySmall),
            const Spacer(),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('بازگشت (F10)')),
          ]),
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _head(context, const [
                      SizedBox(width: 70, child: Text('شناسه')),
                      Expanded(child: Text('نام کاربر')),
                      Expanded(child: Text('نام ورود کاربر')),
                      SizedBox(width: 120, child: Text('نقش')),
                    ]),
                    Expanded(
                      child: ListView(children: [
                        for (final u in s.allUsers)
                          Material(
                            color: u.id == _sel ? th.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _sel = u.id),
                              onDoubleTap: () {
                                setState(() => _sel = u.id);
                                if (u.id != 'owner') _form(edit: s.users.firstWhere((x) => x.id == u.id));
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                child: Row(children: [
                                  SizedBox(width: 70, child: Text('${u.code}')),
                                  Expanded(child: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  Expanded(child: Text(u.login, textDirection: TextDirection.ltr, textAlign: TextAlign.right)),
                                  SizedBox(
                                    width: 120,
                                    child: Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: Pill(u.admin ? 'مدیر سیستم' : 'کاربر (${u.denied.length} محدودیت)',
                                          color: u.admin ? AppColors.income : AppColors.loan),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 230,
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    btn('معرفی کاربر', Icons.person_add_alt_1_outlined, () => _form()),
                    btn('ویرایش کاربر', Icons.edit_outlined, () {
                      if (_needUser(s)) _form(edit: _selected(s));
                    }),
                    btn('حذف کاربر', Icons.person_remove_outlined, _delete),
                    btn('بازنشانی رمز عبور', Icons.key_rounded, _resetPassword),
                    btn('دسترسی دکمه ها', Icons.touch_app_outlined, _permissions),
                    btn('کپی دسترسی از کاربر دیگر', Icons.copy_all_outlined, _copyPermissions),
                    btn('کپی کاربر (F2)', Icons.content_copy_rounded, () {
                      if (_needUser(s)) _form(copyOf: _selected(s));
                    }),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<String?> _askPassword(BuildContext context, String title) async {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => FormDialog(
        title: title,
        width: 440,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              if (a.text != b.text) return set(() => err = 'تکرار رمز یکسان نیست');
              Navigator.pop(ctx, a.text);
            },
            child: const Text('تایید'),
          ),
        ],
        child: Column(children: [
          TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'رمز عبور جدید')),
          const SizedBox(height: 10),
          TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: 'تکرار رمز عبور', errorText: err)),
          const SizedBox(height: 6),
          Text('رمز خالی یعنی ورود بدون رمز', style: Theme.of(ctx).textTheme.bodySmall),
        ]),
      ),
    ),
  );
  a.dispose();
  b.dispose();
  return r;
}

class _UserForm extends StatefulWidget {
  final AppUser? edit;
  final AppUser? copyOf;
  const _UserForm({this.edit, this.copyOf});

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _login = TextEditingController(text: widget.edit?.login ?? '');
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  late bool _admin = widget.edit?.admin ?? widget.copyOf?.admin ?? false;
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _login, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = StoreScope.read(context);
    final isNew = widget.edit == null;
    if (isNew && _pass.text != _pass2.text) return setState(() => _err = 'تکرار رمز یکسان نیست');
    final u = widget.edit ??
        AppUser(id: newId(), code: s.nextUserCode(), name: '', login: '', denied: {...?widget.copyOf?.denied});
    final backup = u.toJson();
    u
      ..name = _name.text
      ..login = _login.text
      ..admin = _admin;
    final e = s.saveUser(u, password: isNew ? _pass.text : null);
    if (e != null) {
      final old = AppUser.fromJson(backup);
      u
        ..name = old.name
        ..login = old.login
        ..admin = old.admin;
      return setState(() => _err = e);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final isNew = widget.edit == null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: isNew ? (widget.copyOf == null ? 'معرفی کاربر' : 'کپی کاربر ${widget.copyOf!.name}') : 'ویرایش کاربر',
        width: 480,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          FilledButton(onPressed: _save, child: const Text('تایید (F9)')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'نام کاربر')),
          const SizedBox(height: 12),
          TextField(controller: _login, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'نام ورود کاربر')),
          if (isNew) ...[
            const SizedBox(height: 12),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'رمز عبور')),
            const SizedBox(height: 12),
            TextField(controller: _pass2, obscureText: true, decoration: const InputDecoration(labelText: 'تکرار رمز عبور')),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _admin,
            onChanged: (v) => setState(() => _admin = v ?? false),
            title: const Text('مدیر سیستم (دسترسی کامل)'),
          ),
          if (_err != null) Text(_err!, style: TextStyle(color: th.colorScheme.error)),
        ]),
      ),
    );
  }
}

class _Permissions extends StatefulWidget {
  final AppUser user;
  const _Permissions({required this.user});

  @override
  State<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends State<_Permissions> {
  late final Set<String> _denied = {...widget.user.denied};

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final cat = ribbonCatalog();
    return FormDialog(
      title: 'دسترسی دکمه ها — ${widget.user.name}',
      width: 760,
      leading: Text(widget.user.admin ? 'این کاربر مدیر سیستم است و همه دسترسی‌ها را دارد' : '${_denied.length} دکمه غیرفعال',
          style: th.textTheme.bodySmall),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: () {
            widget.user.denied = _denied;
            StoreScope.read(context).saveUser(widget.user);
            Navigator.pop(context);
          },
          child: const Text('تایید'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (tab, items) in cat) ...[
          Row(children: [
            Text(tab, style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _denied.removeAll(items)), child: const Text('همه')),
            TextButton(onPressed: () => setState(() => _denied.addAll(items)), child: const Text('هیچ')),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final i in items)
              FilterChip(
                label: Text(i),
                selected: !_denied.contains(i),
                onSelected: (v) => setState(() => v ? _denied.remove(i) : _denied.add(i)),
              ),
          ]),
          const Divider(height: 22),
        ],
      ]),
    );
  }
}

// ================================================================ ردپای کاربران

Future<void> showAuditReport(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _AuditFilter());

class _AuditFilter extends StatefulWidget {
  const _AuditFilter();

  @override
  State<_AuditFilter> createState() => _AuditFilterState();
}

class _AuditFilterState extends State<_AuditFilter> {
  bool _byUser = false;
  final Set<String> _users = {};
  bool _byDoc = false;
  bool _byOp = false;
  late DateTime _docFrom, _docTo, _opFrom, _opTo;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final first = Jalali(Jalali.now().year, Jalali.now().month, 1).toDateTime();
    _docFrom = first;
    _opFrom = first;
    _docTo = DateTime(n.year, n.month, n.day);
    _opTo = DateTime(n.year, n.month, n.day);
  }

  List<AuditEntry> _rows(AppStore s) {
    bool inR(DateTime? d, DateTime a, DateTime b) =>
        d != null && !d.isBefore(DateTime(a.year, a.month, a.day)) && d.isBefore(DateTime(b.year, b.month, b.day + 1));
    return s.audit.where((e) {
      if (_byUser && !_users.contains(e.userId)) return false;
      if (_byDoc && !inR(e.docDate, _docFrom, _docTo)) return false;
      if (_byOp && !inR(e.at, _opFrom, _opTo)) return false;
      return true;
    }).toList();
  }

  void _print() {
    final s = StoreScope.read(context);
    final rows = _rows(s);
    printTable(
      store: s,
      title: 'ردپای کاربران',
      headers: _auditCols,
      rows: [for (var i = 0; i < rows.length; i++) _auditCells(s, rows[i], i + 1)],
      fileName: 'audit',
    );
  }

  Widget _section(String title, bool value, ValueChanged<bool> on, Widget child) {
    final th = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Brand.of(context).accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: th.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(value: value, onChanged: (v) => setState(() => on(v ?? false))),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        Opacity(opacity: value ? 1 : 0.45, child: IgnorePointer(ignoring: !value, child: child)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f12): _print,
        const SingleActivator(LogicalKeyboardKey.f10): () => Navigator.pop(context),
      },
      child: FormDialog(
        title: 'گزارش سازی — ردپای کاربران',
        width: 620,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف (F10)')),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => _AuditResult(rows: _rows(s))),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('مشاهده پویا'),
          ),
          FilledButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('چاپ F12')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _section(
            'محدودیت کاربر',
            _byUser,
            (v) => _byUser = v,
            Wrap(spacing: 6, children: [
              for (final u in s.allUsers)
                FilterChip(
                  label: Text(u.name),
                  selected: _users.contains(u.id),
                  onSelected: (v) => setState(() => v ? _users.add(u.id) : _users.remove(u.id)),
                ),
            ]),
          ),
          _section(
            'محدودیت تاریخ سند',
            _byDoc,
            (v) => _byDoc = v,
            Row(children: [
              Expanded(child: DateField(label: 'از تاریخ', value: _docFrom, onChanged: (d) => setState(() => _docFrom = d ?? _docFrom))),
              const SizedBox(width: 8),
              Expanded(child: DateField(label: 'تا تاریخ', value: _docTo, onChanged: (d) => setState(() => _docTo = d ?? _docTo))),
            ]),
          ),
          _section(
            'محدودیت تاریخ عملیات',
            _byOp,
            (v) => _byOp = v,
            Row(children: [
              Expanded(child: DateField(label: 'از تاریخ', value: _opFrom, onChanged: (d) => setState(() => _opFrom = d ?? _opFrom))),
              const SizedBox(width: 8),
              Expanded(child: DateField(label: 'تا تاریخ', value: _opTo, onChanged: (d) => setState(() => _opTo = d ?? _opTo))),
            ]),
          ),
          Text('${_rows(s).length} مورد', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

const _auditCols = ['ردیف', 'کاربر', 'تاریخ سند', 'تاریخ انجام', 'ساعت', 'عملیات', 'شرح', 'کامپیوتر', 'شماره سند'];

List<String> _auditCells(AppStore s, AuditEntry e, int i) => [
      '$i',
      s.userName(e.userId),
      e.docDate == null ? '' : jFormat(e.docDate!),
      jFormat(e.at),
      '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}',
      e.action,
      e.desc,
      e.computer,
      e.docNo == null ? '' : '${e.docNo}',
    ];

class _AuditResult extends StatefulWidget {
  final List<AuditEntry> rows;
  const _AuditResult({required this.rows});

  @override
  State<_AuditResult> createState() => _AuditResultState();
}

class _AuditResultState extends State<_AuditResult> {
  int _col = 6;
  final _value = TextEditingController();
  String _filter = '';
  bool _desc = true;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final th = Theme.of(context);
    final q = normalizeDigits(_filter.trim()).toLowerCase();
    var list = [...widget.rows]..sort((a, b) => _desc ? b.at.compareTo(a.at) : a.at.compareTo(b.at));
    final cells = [for (var i = 0; i < list.length; i++) _auditCells(s, list[i], i + 1)];
    final shown = q.isEmpty ? cells : cells.where((c) => normalizeDigits(c[_col]).toLowerCase().contains(q)).toList();
    const widths = [50.0, 110.0, 95.0, 95.0, 60.0, 70.0, 0.0, 130.0, 80.0];
    Widget cell(int i, Widget child) => widths[i] == 0 ? Expanded(child: child) : SizedBox(width: widths[i], child: child);
    return _Win(
      title: 'گزارش پویا — ردپای کاربران',
      icon: Icons.history_toggle_off_rounded,
      width: 1180,
      footer: Row(children: [
        Text('${shown.length} مورد', style: th.textTheme.bodySmall),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => printTable(store: s, title: 'ردپای کاربران', headers: _auditCols, rows: shown, fileName: 'audit'),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('چاپ'),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 200,
              child: FieldDropdown<int>(
                label: 'ستون',
                value: _col,
                items: [for (var i = 0; i < _auditCols.length; i++) DropdownMenuItem(value: i, child: Text(_auditCols[i]))],
                onChanged: (v) => setState(() => _col = v ?? 6),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: TextField(controller: _value, decoration: const InputDecoration(labelText: 'مقدار'), onSubmitted: (v) => setState(() => _filter = v)),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: () => setState(() => _filter = _value.text), child: const Text('محدود')),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () => setState(() {
                _value.clear();
                _filter = '';
              }),
              child: const Text('همه موارد'),
            ),
            const SizedBox(width: 10),
            Checkbox(value: _desc, onChanged: (v) => setState(() => _desc = v ?? true)),
            const Text('نزولی مرتب شوند'),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _head(context, [for (var i = 0; i < _auditCols.length; i++) cell(i, Text(_auditCols[i]))]),
                Expanded(
                  child: shown.isEmpty
                      ? const EmptyState(icon: Icons.history_rounded, text: 'موردی یافت نشد')
                      : ListView.builder(
                          itemCount: shown.length,
                          itemExtent: 38,
                          itemBuilder: (context, r) => Container(
                            color: r.isOdd ? th.colorScheme.surfaceContainerLowest : null,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(children: [
                              for (var i = 0; i < shown[r].length; i++)
                                cell(
                                  i,
                                  Text(shown[r][i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: i == 6 ? FontWeight.w600 : null,
                                        color: i == 5
                                            ? switch (shown[r][i]) {
                                                'حذف' => AppColors.expense,
                                                'ثبت' => AppColors.income,
                                                'ورود' => AppColors.debt,
                                                _ => AppColors.loan,
                                              }
                                            : null,
                                      )),
                                ),
                            ]),
                          ),
                        ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
