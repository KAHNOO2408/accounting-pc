import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/storage.dart';
import '../../data/store.dart';
import '../auth/auth_screens.dart';
import '../widgets/common.dart';

/// Built-in background gradients for the start screen.
const List<List<Color>> backgroundPresets = [
  [Color(0xFF1E3A8A), Color(0xFF6D28D9), Color(0xFFDB2777)], // شفق
  [Color(0xFF0F766E), Color(0xFF0891B2), Color(0xFF6366F1)], // دریا
  [Color(0xFF14532D), Color(0xFF15803D), Color(0xFFCA8A04)], // جنگل
  [Color(0xFF7C2D12), Color(0xFFEA580C), Color(0xFFFACC15)], // غروب
  [Color(0xFF0F172A), Color(0xFF334155), Color(0xFF0EA5E9)], // شب
  [Color(0xFF831843), Color(0xFFBE185D), Color(0xFFF97316)], // انار
];

const List<String> backgroundPresetNames = ['شفق', 'دریا', 'جنگل', 'غروب', 'شب', 'انار'];

/// Start screen shown behind the ribbon (like Sakan's desktop picture).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final th = Theme.of(context);
    final title = s.businessName.isNotEmpty ? s.businessName : 'تراز';
    final img = s.backgroundImage.isEmpty ? null : File(s.backgroundImage);
    final hasImg = img != null && img.existsSync();
    final colors = backgroundPresets[s.backgroundPreset.clamp(0, backgroundPresets.length - 1)];
    final now = Jalali.now();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImg)
          Image.file(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _Art(colors: colors))
        else
          _Art(colors: colors),
        // soft vignette for readability
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: hasImg ? 0.35 : 0.15)],
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                ),
                child: const TarazLogo(size: 76, onDark: true),
              ),
              const SizedBox(height: 18),
              Text(title,
                  style: th.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    shadows: const [Shadow(color: Colors.black38, blurRadius: 12)],
                  )),
              const SizedBox(height: 6),
              Text('دفتر مالی ${now.year}',
                  style: th.textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
            ],
          ),
        ),
        PositionedDirectional(
          end: 24,
          bottom: 24,
          child: _DateCard(now: now),
        ),
        PositionedDirectional(
          start: 24,
          bottom: 24,
          child: Tooltip(
            message: 'تصویر پس زمینه',
            child: Material(
              color: Colors.white.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => showBackgroundDialog(context),
                icon: const Icon(Icons.wallpaper_rounded, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateCard extends StatelessWidget {
  final Jalali now;
  const _DateCard({required this.now});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Vazirmatn', color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(jalaliWeekDays[now.weekDayIndex], style: const TextStyle(fontSize: 14, color: Colors.white70)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${now.day}', style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, height: 1.1)),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${now.monthName} ${now.year}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Decorative gradient with soft circles (used when no picture is chosen).
class _Art extends StatelessWidget {
  final List<Color> colors;
  const _Art({required this.colors});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
      ),
      child: CustomPaint(painter: _BubblesPainter()),
    );
  }
}

class _BubblesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final r = (0.05 + rnd.nextDouble() * 0.22) * size.shortestSide;
      final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(c, r, Paint()..color = Colors.white.withValues(alpha: 0.04 + rnd.nextDouble() * 0.05));
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.10);
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.92), i * size.shortestSide * 0.16, ring);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ================================================================ dialog

Future<void> showBackgroundDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _BackgroundDialog());

class _BackgroundDialog extends StatelessWidget {
  const _BackgroundDialog();

  Future<void> _pick(BuildContext context) async {
    final store = StoreScope.read(context);
    try {
      final f = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'تصاویر', extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp']),
      ]);
      if (f == null) return;
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'jpg';
      final dest = File('${store.storage.dir.path}${Storage.sep}background.$ext');
      await File(f.path).copy(dest.path);
      // remove an older picture with another extension
      for (final e in ['jpg', 'jpeg', 'png', 'bmp', 'webp']) {
        final old = File('${store.storage.dir.path}${Storage.sep}background.$e');
        if (e != ext && old.existsSync()) old.deleteSync();
      }
      PaintingBinding.instance.imageCache.clear();
      store.updateSettings((s) => s.backgroundImage = dest.path);
      if (context.mounted) toast(context, 'تصویر پس زمینه تنظیم شد');
    } catch (e) {
      if (context.mounted) toast(context, 'خطا در انتخاب تصویر: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final th = Theme.of(context);
    final hasImg = s.backgroundImage.isNotEmpty && File(s.backgroundImage).existsSync();
    return FormDialog(
      title: 'تصویر پس زمینه',
      width: 620,
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('طرح‌های آماده', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < backgroundPresets.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => store.updateSettings((x) {
                    x.backgroundPreset = i;
                    x.backgroundImage = '';
                  }),
                  child: Column(
                    children: [
                      Container(
                        width: 120,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: backgroundPresets[i]),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !hasImg && s.backgroundPreset == i ? th.colorScheme.onSurface : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: !hasImg && s.backgroundPreset == i
                            ? const Icon(Icons.check_circle_rounded, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(backgroundPresetNames[i], style: th.textTheme.labelMedium),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('عکس دلخواه', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (hasImg)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(s.backgroundImage), height: 150, fit: BoxFit.cover),
            ),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(
              onPressed: () => _pick(context),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('انتخاب عکس از کامپیوتر'),
            ),
            const SizedBox(width: 8),
            if (hasImg)
              OutlinedButton.icon(
                onPressed: () => store.updateSettings((x) => x.backgroundImage = ''),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف عکس'),
              ),
          ]),
          const SizedBox(height: 8),
          Text('عکس در پوشه‌ی اطلاعات برنامه کپی می‌شود.', style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
        ],
      ),
    );
  }
}
