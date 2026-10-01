import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/store.dart';

/// Shared two-pane frame: brand panel + form card.
class _AuthFrame extends StatelessWidget {
  final Widget form;
  const _AuthFrame({required this.form});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final accent = th.colorScheme.primary;
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final showBrand = c.maxWidth >= 900;
        return Row(
          children: [
            if (showBrand)
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [accent, Color.lerp(accent, Colors.black, 0.45)!],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(child: CustomPaint(painter: _RingsPainter())),
                      Padding(
                        padding: const EdgeInsets.all(56),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const TarazLogo(size: 56, onDark: true),
                            const Spacer(),
                            const Text('تراز',
                                style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w700, height: 1.1)),
                            const SizedBox(height: 10),
                            Text('حسابداری شخصی برای کامپیوتر',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 20)),
                            const SizedBox(height: 36),
                            for (final f in const [
                              (Icons.receipt_long_outlined, 'ثبت سریع درآمد، هزینه و انتقال با صفحه‌کلید'),
                              (Icons.handshake_outlined, 'حساب بدهی و طلب اشخاص و پیگیری چک‌ها'),
                              (Icons.insights_outlined, 'گزارش ماهانه و سالانه با تاریخ شمسی'),
                              (Icons.lock_outline_rounded, 'اطلاعات فقط روی همین کامپیوتر، با رمز ورود'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(f.$1, color: Colors.white, size: 19),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(f.$2,
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 15)),
                                    ),
                                  ],
                                ),
                              ),
                            const Spacer(),
                            Text(Jalali.now().formatWithWeekday(),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              flex: 4,
              child: Container(
                color: th.colorScheme.surfaceContainerLowest,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: form,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1.5;
    final center = Offset(size.width * 0.05, size.height * 0.95);
    for (var i = 1; i <= 9; i++) {
      canvas.drawCircle(center, i * math.max(size.width, size.height) * 0.11, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// App mark: a balance-scale glyph inside a rounded square.
class TarazLogo extends StatelessWidget {
  final double size;
  final bool onDark;
  const TarazLogo({super.key, this.size = 36, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.16) : accent,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: onDark ? Border.all(color: Colors.white.withValues(alpha: 0.3)) : null,
      ),
      child: Icon(Icons.balance_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}

// ======================================================================= setup

class SetupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetupScreen({super.key, required this.onDone});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _name = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _hint = TextEditingController();
  bool _usePassword = true;
  bool _obscure = true;
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _pass, _pass2, _hint]) {
      c.dispose();
    }
    super.dispose();
  }

  void _finish() {
    final store = StoreScope.read(context);
    if (_usePassword) {
      if (_pass.text.length < 4) {
        setState(() => _err = 'رمز باید حداقل ۴ کاراکتر باشد');
        return;
      }
      if (_pass.text != _pass2.text) {
        setState(() => _err = 'رمز و تکرار آن یکسان نیستند');
        return;
      }
    }
    store.completeSetup(
      ownerName: _name.text.trim(),
      password: _usePassword ? _pass.text : null,
      hint: _hint.text.trim(),
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return _AuthFrame(
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('راه‌اندازی تراز', style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('چند ثانیه طول می‌کشد. اطلاعات شما فقط روی همین کامپیوتر ذخیره می‌شود.',
              style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
          const SizedBox(height: 28),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام شما', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _usePassword,
            onChanged: (v) => setState(() {
              _usePassword = v;
              _err = null;
            }),
            title: const Text('ورود با رمز'),
            subtitle: const Text('هنگام باز کردن برنامه رمز پرسیده شود'),
          ),
          if (_usePassword) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'رمز ورود',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass2,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'تکرار رمز', prefixIcon: Icon(Icons.lock_outline_rounded)),
              onSubmitted: (_) => _finish(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hint,
              decoration: const InputDecoration(labelText: 'راهنمای رمز (اختیاری)', prefixIcon: Icon(Icons.lightbulb_outline)),
            ),
          ],
          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!, style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _finish,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
            child: const Text('شروع کار'),
          ),
        ],
      ),
    );
  }
}

// ======================================================================= login

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pass = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _showHint = false;
  String? _err;
  int _fails = 0;

  @override
  void dispose() {
    _pass.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final store = StoreScope.read(context);
    if (store.checkPassword(_pass.text)) {
      widget.onSuccess();
      return;
    }
    setState(() {
      _fails++;
      _err = 'رمز اشتباه است';
      _pass.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final s = store.settings;
    final name = s.ownerName.trim();
    return _AuthFrame(
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: th.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              name.isEmpty ? '؟' : name.characters.first,
              style: TextStyle(fontSize: 28, color: th.colorScheme.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 18),
          Text(name.isEmpty ? 'خوش آمدید' : '$name، خوش آمدید',
              textAlign: TextAlign.center,
              style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('برای ورود رمز خود را وارد کنید',
              textAlign: TextAlign.center, style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
          const SizedBox(height: 28),
          TextField(
            controller: _pass,
            focusNode: _focus,
            autofocus: true,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'رمز ورود',
              errorText: _err,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
            child: const Text('ورود'),
          ),
          const SizedBox(height: 14),
          if (s.passwordHint.isNotEmpty && _fails > 0)
            TextButton(
              onPressed: () => setState(() => _showHint = !_showHint),
              child: Text(_showHint ? 'راهنما: ${s.passwordHint}' : 'نمایش راهنمای رمز'),
            ),
          if (_fails >= 3)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'رمز را فراموش کرده‌اید؟ برنامه را ببندید و در فایل data.json داخل پوشه\n'
                '${store.storage.dir.path}\n'
                'مقدار "passwordHash" را خالی کنید ("").',
                textAlign: TextAlign.center,
                style: th.textTheme.bodySmall?.copyWith(color: th.hintColor),
              ),
            ),
        ],
      ),
    );
  }
}
