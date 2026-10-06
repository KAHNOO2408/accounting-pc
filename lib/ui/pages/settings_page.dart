import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../core/zip_backup.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _path = TextEditingController();
  late final _bpass = TextEditingController(text: StoreScope.read(context).settings.backupPassword);
  bool _showBpass = false;

  @override
  void dispose() {
    _path.dispose();
    _bpass.dispose();
    super.dispose();
  }

  Future<void> _restore(AppStore store, String path) async {
    final ok = await confirm(
      context,
      'بازیابی پشتیبان',
      'همه اطلاعات فعلی با محتوای این فایل جایگزین می‌شود.\n(یک نسخه از اطلاعات فعلی به‌صورت خودکار نگه داشته می‌شود.)\n\n$path',
      ok: 'بازیابی',
    );
    if (!ok || !mounted) return;
    String? password;
    while (true) {
      try {
        store.importBackup(path, password: password);
        if (mounted) toast(context, 'اطلاعات با موفقیت بازیابی شد');
        return;
      } on BackupPasswordException catch (e) {
        if (!mounted) return;
        password = await _askPassword(e.wrong ? 'رمز اشتباه است؛ دوباره وارد کنید' : 'این فایل پشتیبان رمز دارد');
        if (password == null || !mounted) return;
      } catch (e) {
        if (mounted) toast(context, 'بازیابی ناموفق: $e', error: true);
        return;
      }
    }
  }

  Future<String?> _askPassword(String message) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رمز فایل پشتیبان'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رمز'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('تایید')),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _pickBackup(AppStore store) async {
    final f = await fs.openFile(acceptedTypeGroups: const [
      fs.XTypeGroup(label: 'پشتیبان تراز', extensions: ['zip', 'json']),
    ]);
    if (f == null || !mounted) return;
    _path.text = f.path;
    await _restore(store, f.path);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final s = store.settings;
    List<File> backups;
    try {
      backups = store.availableBackups();
    } catch (_) {
      backups = [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'تنظیمات و پشتیبان', subtitle: 'ظاهر برنامه، واحد پول و نگهداری اطلاعات'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ProfilePanel(),
                      const SizedBox(height: 16),
                      const _BusinessPanel(),
                      const SizedBox(height: 16),
                      Panel(
                        title: 'ظاهر',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('حالت نمایش', style: th.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 'light', label: Text('روشن'), icon: Icon(Icons.light_mode_outlined, size: 16)),
                                ButtonSegment(value: 'dark', label: Text('تیره'), icon: Icon(Icons.dark_mode_outlined, size: 16)),
                                ButtonSegment(value: 'system', label: Text('مطابق ویندوز'), icon: Icon(Icons.computer_rounded, size: 16)),
                              ],
                              selected: {s.themeMode},
                              onSelectionChanged: (v) => store.updateSettings((x) => x.themeMode = v.first),
                            ),
                            const SizedBox(height: 18),
                            Text('رنگ اصلی', style: th.textTheme.labelLarge),
                            const SizedBox(height: 8),
                            ColorPickerRow(value: s.accent, onChanged: (c) => store.updateSettings((x) => x.accent = c)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        title: 'واحد پول',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 'تومان', label: Text('تومان')),
                                ButtonSegment(value: 'ریال', label: Text('ریال')),
                              ],
                              selected: {s.currency},
                              onSelectionChanged: (v) => store.updateSettings((x) => x.currency = v.first),
                            ),
                            const SizedBox(height: 8),
                            Text('فقط برچسب نمایش عوض می‌شود؛ مبالغ ثبت‌شده تبدیل نمی‌شوند.',
                                style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        title: 'میانبرهای صفحه‌کلید',
                        child: Column(
                          children: [
                            for (final e in const [
                              ('F6', 'فاکتور فروش'),
                              ('F5', 'فاکتور خرید'),
                              ('F7', 'پیش‌فاکتور'),
                              ('F1 / F2', 'دریافت / پرداخت نقدی'),
                              ('F3 / F4', 'دریافت / پرداخت چک'),
                              ('Ctrl+A', 'جدول و مشاهده حساب‌ها'),
                              ('F11', 'تهیه نسخه پشتیبان'),
                              ('Insert', 'افزودن ردیف در فاکتور'),
                              ('Ctrl+F', 'جستجو در تراکنش‌ها'),
                              ('Ctrl+P', 'چاپ فاکتور (داخل فاکتور)'),
                              ('Ctrl+S', 'ذخیره فرم (داخل پنجره تراکنش)'),
                              ('Ctrl+Enter', 'ثبت و تراکنش بعدی'),
                              ('Ctrl+L', 'قفل برنامه (اگر رمز دارد)'),
                              ('Esc', 'بستن پنجره'),
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(e.$2)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: th.colorScheme.outlineVariant),
                                        color: th.colorScheme.surfaceContainerLow,
                                      ),
                                      child: Text(e.$1,
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Panel(
                        title: 'پشتیبان‌گیری',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'اطلاعات به‌صورت خودکار ذخیره می‌شود و هر روز یک نسخه پشتیبان خودکار هم گرفته می‌شود. '
                              'برای انتقال به کامپیوتر دیگر، یک فایل پشتیبان بسازید (فایل فشرده zip).',
                              style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
                            ),
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                child: TextField(
                                  controller: _bpass,
                                  obscureText: !_showBpass,
                                  textDirection: TextDirection.ltr,
                                  decoration: InputDecoration(
                                    labelText: 'رمز فایل پشتیبان (اختیاری)',
                                    helperText: 'با رمز، فایل پشتیبان رمزنگاری می‌شود (AES-256) و بدون رمز باز نمی‌شود',
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: Icon(_showBpass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                                      onPressed: () => setState(() => _showBpass = !_showBpass),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  store.settings.backupPassword = _bpass.text;
                                  store.saveNow();
                                  toast(context, _bpass.text.isEmpty ? 'رمز پشتیبان برداشته شد' : 'رمز پشتیبان ذخیره شد');
                                },
                                child: const Text('ثبت رمز'),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    try {
                                      final p = store.exportBackup();
                                      toast(context, 'پشتیبان ساخته شد: $p');
                                      setState(() {});
                                    } catch (e) {
                                      toast(context, 'خطا: $e', error: true);
                                    }
                                  },
                                  icon: const Icon(Icons.backup_outlined, size: 18),
                                  label: const Text('ساخت فایل پشتیبان'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => Storage.openFolder(Storage.userFolder.path),
                                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                                  label: const Text('پوشه پشتیبان‌ها'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => Storage.openFolder(store.storage.dir.path),
                                  icon: const Icon(Icons.storage_rounded, size: 18),
                                  label: const Text('پوشه داده‌ها'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SelectableText('محل فایل‌های پشتیبان: ${Storage.userFolder.path}',
                                style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        title: 'بازیابی',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _path,
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                      labelText: 'مسیر فایل پشتیبان (یا از فهرست زیر انتخاب کنید)',
                                      hintText: r'C:\Users\...\taraz-backup.zip',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'انتخاب فایل',
                                  onPressed: () => _pickBackup(store),
                                  icon: const Icon(Icons.folder_open_outlined),
                                ),
                                const SizedBox(width: 4),
                                FilledButton.tonal(
                                  onPressed: () {
                                    final p = _path.text.trim().replaceAll('"', '');
                                    if (p.isEmpty) return;
                                    if (!File(p).existsSync()) {
                                      toast(context, 'فایل پیدا نشد', error: true);
                                      return;
                                    }
                                    _restore(store, p);
                                  },
                                  child: const Text('بازیابی'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (backups.isEmpty)
                              Text('فایل پشتیبانی پیدا نشد', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor))
                            else
                              for (final f in backups.take(12))
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    f.path.split(Storage.sep).last.startsWith('auto-')
                                        ? Icons.history_rounded
                                        : (f.path.toLowerCase().endsWith('.zip') ? Icons.folder_zip_outlined : Icons.description_outlined),
                                    size: 20,
                                  ),
                                  title: Text(f.path.split(Storage.sep).last, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                                  subtitle: Text(_fileInfo(f)),
                                  trailing: TextButton(onPressed: () => _restore(store, f.path), child: const Text('بازیابی')),
                                ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        title: 'درباره',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('تراز — حسابداری شخصی ویندوز، نسخه ۱.۰', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('طراحی و توسعه: بنیامین قاسمی', style: th.textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              '${store.accounts.length} حساب · ${store.txns.length} تراکنش · ${store.people.length} شخص · ${store.cheques.length} چک',
                              style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fileInfo(File f) {
    try {
      final m = f.lastModifiedSync();
      final kb = (f.lengthSync() / 1024).toStringAsFixed(1);
      return '${Jalali.fromDateTime(m).format()}  ${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}  ·  $kb KB';
    } catch (_) {
      return '';
    }
  }
}


class _ProfilePanel extends StatefulWidget {
  const _ProfilePanel();

  @override
  State<_ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<_ProfilePanel> {
  late final TextEditingController _name;
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  final _hint = TextEditingController();
  bool _editingPass = false;
  String? _err;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _name = TextEditingController(text: StoreScope.read(context).settings.ownerName);
  }

  @override
  void dispose() {
    for (final c in [_name, _old, _new, _new2, _hint]) {
      c.dispose();
    }
    super.dispose();
  }

  void _savePass(AppStore store) {
    if (store.settings.hasPassword && !store.checkPassword(_old.text)) {
      setState(() => _err = 'رمز فعلی درست نیست');
      return;
    }
    if (_new.text.length < 4) {
      setState(() => _err = 'رمز جدید باید حداقل ۴ کاراکتر باشد');
      return;
    }
    if (_new.text != _new2.text) {
      setState(() => _err = 'رمز جدید و تکرار آن یکسان نیستند');
      return;
    }
    store.setPassword(_new.text, hint: _hint.text.trim());
    for (final c in [_old, _new, _new2, _hint]) {
      c.clear();
    }
    setState(() {
      _editingPass = false;
      _err = null;
    });
    toast(context, 'رمز ورود ذخیره شد');
  }

  Future<void> _removePass(AppStore store) async {
    if (!store.checkPassword(_old.text)) {
      setState(() => _err = 'برای حذف رمز، رمز فعلی را در کادر «رمز فعلی» وارد کنید');
      return;
    }
    final ok = await confirm(context, 'حذف رمز ورود', 'برنامه بدون رمز باز می‌شود. ادامه می‌دهید؟', ok: 'حذف رمز');
    if (!ok || !mounted) return;
    store.removePassword();
    _old.clear();
    setState(() {
      _editingPass = false;
      _err = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final has = store.settings.hasPassword;
    return Panel(
      title: 'کاربر و رمز ورود',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'نام نمایشی', prefixIcon: Icon(Icons.person_outline_rounded)),
                  onSubmitted: (v) => store.updateSettings((s) => s.ownerName = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  store.updateSettings((s) => s.ownerName = _name.text.trim());
                  toast(context, 'ذخیره شد');
                },
                child: const Text('ذخیره نام'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(has ? Icons.verified_user_outlined : Icons.lock_open_rounded,
                  color: has ? th.colorScheme.primary : th.hintColor, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(has ? 'ورود با رمز فعال است' : 'برنامه بدون رمز باز می‌شود')),
              if (!_editingPass)
                OutlinedButton(
                  onPressed: () => setState(() => _editingPass = true),
                  child: Text(has ? 'تغییر یا حذف رمز' : 'تعریف رمز'),
                ),
            ],
          ),
          if (_editingPass) ...[
            const SizedBox(height: 14),
            if (has) ...[
              TextField(controller: _old, obscureText: true, decoration: const InputDecoration(labelText: 'رمز فعلی')),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'رمز جدید')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(controller: _new2, obscureText: true, decoration: const InputDecoration(labelText: 'تکرار رمز جدید')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(controller: _hint, decoration: const InputDecoration(labelText: 'راهنمای رمز (اختیاری)')),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!, style: TextStyle(color: th.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (has)
                  TextButton(
                    onPressed: () => _removePass(store),
                    child: Text('حذف رمز', style: TextStyle(color: th.colorScheme.error)),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _editingPass = false;
                    _err = null;
                  }),
                  child: const Text('انصراف'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => _savePass(store), child: const Text('ذخیره رمز')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _BusinessPanel extends StatefulWidget {
  const _BusinessPanel();

  @override
  State<_BusinessPanel> createState() => _BusinessPanelState();
}

class _BusinessPanelState extends State<_BusinessPanel> {
  TextEditingController? _name, _phone, _address;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name != null) return;
    final s = StoreScope.read(context).settings;
    _name = TextEditingController(text: s.businessName);
    _phone = TextEditingController(text: s.businessPhone);
    _address = TextEditingController(text: s.businessAddress);
  }

  @override
  void dispose() {
    _name?.dispose();
    _phone?.dispose();
    _address?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Panel(
      title: 'مشخصات فروشگاه (سربرگ فاکتور)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام فروشگاه / شرکت')),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'تلفن'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'آدرس')),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: () {
                store.updateSettings((s) => s
                  ..businessName = _name!.text.trim()
                  ..businessPhone = _phone!.text.trim()
                  ..businessAddress = _address!.text.trim());
                toast(context, 'مشخصات فروشگاه ذخیره شد');
              },
              child: const Text('ذخیره'),
            ),
          ),
        ],
      ),
    );
  }
}
