import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taraz/data/models.dart';
import 'package:taraz/data/storage.dart';
import 'package:taraz/data/store.dart';
import 'package:taraz/main.dart';
import 'package:taraz/ui/shell.dart';

/// Renders a few screens to PNG files (uploaded by CI) so the look can be reviewed.
void main() {
  setUpAll(() async {
    final vaz = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-FD-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-FD-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-FD-Bold.ttf'));
    await vaz.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> shot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('screenshots')..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  testWidgets('screenshots', (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = AppStore.open(Storage(Directory.systemTemp.createTempSync('shots')));
    s.completeSetup(ownerName: 'بنیامین');
    s.updateSettings((x) => x.businessName = 'فروشگاه نمونه');
    final p = Person(id: newId(), name: 'علی رضایی');
    s.upsertPerson(p);
    s.upsertProduct(Product(id: newId(), name: 'هندزفری بلوتوثی', sellPrice: 850000, buyPrice: 600000, openingQty: 12));

    Future<void> open(AppPage page, String name, {String? tab}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: TarazApp(store: s, initialPage: page)));
      await tester.pumpAndSettle();
      if (tab != null) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
      }
      await shot(tester, name);
    }

    await open(AppPage.home, '01-home');
    await open(AppPage.home, '02-sales-tab', tab: 'خرید و فروش');
    await open(AppPage.home, '03-finance-tab', tab: 'مالی');
    await open(AppPage.vouchers, '04-vouchers');
    await open(AppPage.products, '05-products', tab: 'عملیات کالا');

    await tester.tap(find.text('خرید و فروش').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاکتور فروش').first);
    await tester.pumpAndSettle();
    await shot(tester, '06-sale-invoice');

    await open(AppPage.home, '07-finance-tab', tab: 'مالی');
    await tester.tap(find.text('جدول و مشاهده حسابها').first);
    await tester.pumpAndSettle();
    await shot(tester, '08-accounts-selector');
    await tester.tap(find.text('رویت حساب'));
    await tester.pumpAndSettle();
    await shot(tester, '09-account-ledger');

    Future<void> win(String tab, String item, String name) async {
      await open(AppPage.home, name, tab: tab);
      await tester.ensureVisible(find.text(item).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).first);
      await tester.pumpAndSettle();
      await shot(tester, name);
    }

    await win('متفرقه', 'کدبندی دفاتر کل و معین', '10-chart-coding');
    await win('متفرقه', 'سطل بازیافت', '11-recycle-bin');
    await win('متفرقه', 'معرفی دفاتر مالی', '12-books');
    await win('گزارشات', 'مدیریت گزارشات', '13-report-files');
    await win('گزارشات', 'گزارش از گروه مراکز دفتر', '14-center-report');
  });
}
