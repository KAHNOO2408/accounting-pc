import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/storage.dart';
import '../../data/store.dart';
import '../auth/auth_screens.dart';
import '../widgets/common.dart';

/// Shown for menu items that are part of the plan but not built yet.
Future<void> showComingSoon(BuildContext context, String title) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final th = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(Icons.construction_rounded, color: th.colorScheme.primary, size: 36),
          title: Text(title),
          content: const SizedBox(
            width: 420,
            child: Text(
              'این بخش در منو قرار گرفته ولی هنوز ساخته نشده است.\n\n'
              'برای اینکه دقیقاً مطابق نیاز شما ساخته شود، از همین بخش در نرم‌افزار سکان '
              'عکس یا فیلم کوتاه بگیرید و بفرستید.',
              textAlign: TextAlign.center,
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
        );
      },
    );

Future<void> showAboutTaraz(BuildContext context, {bool license = false}) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final th = Theme.of(ctx);
        final store = StoreScope.read(ctx);
        return AlertDialog(
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TarazLogo(size: 64),
                const SizedBox(height: 14),
                Text('تراز', style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('حسابداری فروشگاهی و شخصی برای ویندوز', style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
                const SizedBox(height: 16),
                const Text('نسخه ۱.۲'),
                const SizedBox(height: 4),
                Text('طراحی و توسعه: بنیامین قاسمی', style: th.textTheme.bodySmall),
                if (license) ...[
                  const Divider(height: 28),
                  Text('نسخه کامل — بدون محدودیت تعداد کاربر و سند', style: th.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('محل داده‌ها: ${store.storage.dir.path}',
                      textDirection: TextDirection.ltr, style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                ],
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن'))],
        );
      },
    );

Future<void> confirmExit(BuildContext context) async {
  final ok = await confirm(context, 'خروج از برنامه', 'از تراز خارج می‌شوید؟ اطلاعات به‌صورت خودکار ذخیره شده است.',
      ok: 'خروج', danger: false);
  if (ok) exit(0);
}

void quickBackup(BuildContext context) {
  try {
    final p = StoreScope.read(context).exportBackup();
    toast(context, 'نسخه پشتیبان ساخته شد: $p');
    Storage.openFolder(Storage.userFolder.path);
  } catch (e) {
    toast(context, 'خطا در پشتیبان‌گیری: $e', error: true);
  }
}
