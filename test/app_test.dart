import 'dart:io';

import 'package:taraz/core/format.dart';
import 'package:taraz/core/hash.dart';
import 'package:taraz/core/jalali.dart';
import 'package:taraz/data/models.dart';
import 'package:taraz/data/storage.dart';
import 'package:taraz/data/store.dart';
import 'package:taraz/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _tempStore() => AppStore.open(Storage(Directory.systemTemp.createTempSync('taraz_test')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Render with the real Persian font so layout widths match the app.
    final loader = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-FD-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-FD-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-FD-Bold.ttf'));
    await loader.load();
  });

  group('Jalali', () {
    test('known dates', () {
      expect(Jalali.fromDateTime(DateTime(2026, 10, 1)).format(), '1405/07/09');
      expect(Jalali.fromDateTime(DateTime(2026, 3, 21)).format(), '1405/01/01');
      expect(Jalali.fromDateTime(DateTime(2025, 3, 20)).format(), '1403/12/30');
      expect(Jalali.fromDateTime(DateTime(1979, 2, 11)).format(), '1357/11/22');
    });

    test('round trip 20 years', () {
      var d = DateTime(2010, 1, 1);
      for (var i = 0; i < 7300; i++) {
        final j = Jalali.fromDateTime(d);
        expect(j.toDateTime(), d);
        d = DateTime(d.year, d.month, d.day + 1);
      }
    });

    test('leap years and parsing', () {
      expect(Jalali.isLeapYear(1403), isTrue);
      expect(Jalali.isLeapYear(1404), isFalse);
      expect(Jalali.monthLength(1404, 12), 29);
      expect(Jalali.tryParse('۱۴۰۵/۰۷/۰۹'), const Jalali(1405, 7, 9));
      expect(Jalali.tryParse('1404/12/30'), isNull);
    });
  });

  group('format', () {
    test('groupDigits / parseMoney', () {
      expect(groupDigits(1234567), '1,234,567');
      expect(groupDigits(-1000), '-1,000');
      expect(groupDigits(999), '999');
      expect(parseMoney('۱,۲۵۰,۰۰۰'), 1250000);
    });

    test('words', () {
      expect(amountInWords(1500000), 'یک میلیون و پانصد هزار');
    });
  });

  group('store', () {
    test('balances, debts and cheques', () {
      final s = _tempStore();
      final cash = s.accounts.first.id;
      final bank = Account(id: newId(), name: 'Bank', opening: 1000);
      s.upsertAccount(bank);
      final p = Person(id: newId(), name: 'Ali');
      s.upsertPerson(p);
      final today = DateTime(2026, 10, 1);

      s.upsertTxn(Txn(id: newId(), type: TxnType.income, amount: 500, date: today, accountId: cash));
      s.upsertTxn(Txn(id: newId(), type: TxnType.expense, amount: 200, date: today, accountId: cash));
      s.upsertTxn(Txn(id: newId(), type: TxnType.transfer, amount: 100, date: today, accountId: bank.id, toAccountId: cash));
      s.upsertTxn(Txn(id: newId(), type: TxnType.lend, amount: 300, date: today, accountId: cash, personId: p.id));
      s.upsertTxn(Txn(id: newId(), type: TxnType.collect, amount: 50, date: today, accountId: cash, personId: p.id));

      expect(s.balance(cash), 500 - 200 + 100 - 300 + 50);
      expect(s.balance(bank.id), 900);
      expect(s.personBalance(p.id), 250);
      expect(s.totalReceivable, 250);

      final c = Cheque(
        id: newId(),
        direction: ChequeDirection.received,
        amount: 250,
        dueDate: today,
        issueDate: today,
        personId: p.id,
      );
      s.upsertCheque(c);
      s.clearCheque(c, accountId: bank.id, asType: TxnType.collect, date: today);
      expect(s.personBalance(p.id), 0);
      expect(s.balance(bank.id), 1150);
      s.setChequeStatus(c, ChequeStatus.bounced);
      expect(s.personBalance(p.id), 250);
      expect(s.balance(bank.id), 900);

      // persistence round trip
      final again = AppStore.open(s.storage);
      expect(again.txns.length, s.txns.length);
      expect(again.balance(cash), s.balance(cash));
    });
  });

  test('password hashing', () {
    expect(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    final s = _tempStore();
    s.completeSetup(ownerName: 'Benjamin', password: 'secret1');
    expect(s.checkPassword('secret1'), isTrue);
    expect(s.checkPassword('wrong'), isFalse);
    final again = AppStore.open(s.storage);
    expect(again.checkPassword('secret1'), isTrue);
    again.removePassword();
    expect(again.settings.hasPassword, isFalse);
  });

  testWidgets('setup screen then login', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = _tempStore();
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('راه‌اندازی تراز'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'بنیامین');
    await tester.enterText(fields.at(1), '1234');
    await tester.enterText(fields.at(2), '1234');
    await tester.tap(find.text('شروع کار'));
    await tester.pumpAndSettle();
    expect(s.settings.setupDone, isTrue);
    expect(s.settings.hasPassword, isTrue);
    expect(find.text('پیشخوان'), findsWidgets);

    // a fresh launch asks for the password
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('ورود'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '0000');
    await tester.tap(find.text('ورود'));
    await tester.pumpAndSettle();
    expect(find.text('رمز اشتباه است'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('ورود'));
    await tester.pumpAndSettle();
    expect(find.text('پیشخوان'), findsWidgets);
  });

  testWidgets('all pages render', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Ali');
    s.upsertPerson(p);
    s.upsertTxn(Txn(
        id: newId(), type: TxnType.lend, amount: 300, date: DateTime.now(), accountId: s.accounts.first.id, personId: p.id,
        dueDate: DateTime.now().add(const Duration(days: 3))));
    s.upsertTxn(Txn(id: newId(), type: TxnType.expense, amount: 120, date: DateTime.now(), accountId: s.accounts.first.id));
    s.upsertCheque(Cheque(
        id: newId(), direction: ChequeDirection.issued, amount: 999, dueDate: DateTime.now(), issueDate: DateTime.now()));

    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('پیشخوان'), findsWidgets);

    for (final label in ['تراکنش‌ها', 'حساب‌ها', 'اشخاص', 'چک‌ها', 'دسته‌ها', 'گزارش‌ها']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }

    // settings via Ctrl+8
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('کاربر و رمز ورود'), findsOneWidget);

    // new transaction dialog
    await tester.tap(find.text('ثبت تراکنش').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25000');
    await tester.tap(find.text('ذخیره (Ctrl+S)'));
    await tester.pumpAndSettle();
    expect(s.txns.where((t) => t.amount == 25000).length, 1);
  });
}
