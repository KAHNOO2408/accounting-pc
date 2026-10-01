import 'dart:io';

import 'package:taraz/core/format.dart';
import 'package:taraz/core/hash.dart';
import 'package:taraz/core/jalali.dart';
import 'package:taraz/data/models.dart';
import 'package:taraz/data/storage.dart';
import 'package:taraz/data/store.dart';
import 'package:taraz/main.dart';
import 'package:taraz/ui/shell.dart';
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

  test('invoices, stock, profit and loans', () {
    final s = _tempStore();
    final cash = s.accounts.first.id;
    final today = DateTime(2026, 10, 1);
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final phone = Product(id: newId(), name: 'Headphone', openingQty: 2);
    s.upsertProduct(phone);

    // buy 10 @ 100 on credit (pay 400 now)
    s.saveInvoice(Invoice(
      id: newId(),
      kind: InvoiceKind.purchase,
      number: s.nextInvoiceNumber(InvoiceKind.purchase),
      date: today,
      personId: ali.id,
      lines: [InvoiceLine(productId: phone.id, qty: 10, unitPrice: 100)],
      paid: 400,
      accountId: cash,
    ));
    expect(s.stock(phone.id), 12);
    expect(s.avgCost(phone.id), 100);
    expect(s.balance(cash), -400);
    expect(s.personBalance(ali.id), -600);

    // sell 3 @ 150 + a free-text service line, cash customer, fully paid
    s.saveInvoice(Invoice(
      id: newId(),
      kind: InvoiceKind.sale,
      number: s.nextInvoiceNumber(InvoiceKind.sale),
      date: today,
      lines: [
        InvoiceLine(productId: phone.id, qty: 3, unitPrice: 150),
        InvoiceLine(title: 'Install', qty: 1, unitPrice: 50),
      ],
      paid: 500,
      accountId: cash,
    ));
    expect(s.stock(phone.id), 9);
    expect(s.balance(cash), 100);
    final p = s.profit(today, today);
    expect(p.sales, 500);
    expect(p.cogs, 300);
    expect(p.grossProfit, 200);

    // purchase discount from supplier reduces what I owe
    s.upsertTxn(Txn(id: newId(), type: TxnType.purchaseDiscount, amount: 100, date: today, personId: ali.id));
    expect(s.personBalance(ali.id), -500);
    expect(s.profit(today, today).netProfit, 300);

    // return 1 to supplier
    s.saveInvoice(Invoice(
      id: newId(),
      kind: InvoiceKind.purchaseReturn,
      number: 1,
      date: today,
      personId: ali.id,
      lines: [InvoiceLine(productId: phone.id, qty: 1, unitPrice: 100)],
    ));
    expect(s.stock(phone.id), 8);
    expect(s.personBalance(ali.id), -400);

    // loan: receive 1000, 4 installments of 300
    final loan = Loan(
        id: newId(), title: 'Bank', principal: 1000, installmentAmount: 300, installments: 4, firstDue: today, accountId: cash);
    s.saveLoan(loan, recordReceive: true, receiveDate: today);
    expect(s.balance(cash), 1100);
    expect(s.totalLoanRemaining, 1200);
    s.payInstallment(loan, accountId: cash, amount: 300, date: today);
    expect(s.loanPaidCount(loan.id), 1);
    expect(s.totalLoanRemaining, 900);
    expect(s.balance(cash), 800);

    // round trip
    final again = AppStore.open(s.storage);
    expect(again.invoices.length, 3);
    expect(again.stock(phone.id), 8);
    expect(again.loanPaidCount(loan.id), 1);

    // deleting an invoice removes its ledger rows and stock effect
    final sale = s.invoices.firstWhere((i) => i.kind == InvoiceKind.sale);
    s.removeInvoice(sale.id);
    expect(s.stock(phone.id), 11);
    expect(s.txns.where((t) => t.invoiceId == sale.id), isEmpty);
  });

  test('pro-forma, stock adjustments and cheque operations', () {
    final s = _tempStore();
    final cash = s.accounts.first.id;
    final today = DateTime(2026, 10, 1);
    final a = Product(id: newId(), name: 'Box', openingQty: 10);
    final b = Product(id: newId(), name: 'Piece');
    s.upsertProduct(a);
    s.upsertProduct(b);

    final pf = Invoice(
      id: newId(),
      kind: InvoiceKind.sale,
      number: 1,
      date: today,
      proforma: true,
      lines: [InvoiceLine(productId: a.id, qty: 2, unitPrice: 100)],
    );
    s.saveInvoice(pf);
    expect(s.stock(a.id), 10);
    expect(s.txns.where((t) => t.invoiceId == pf.id), isEmpty);
    final sale = s.convertProforma(pf);
    expect(sale.proforma, isFalse);
    expect(s.stock(a.id), 8);
    expect(s.invoices.where((i) => i.proforma), isEmpty);

    s.addAdjusts([StockAdjust(id: newId(), date: today, productId: a.id, qty: -1, reason: AdjustReason.waste)]);
    expect(s.stock(a.id), 7);
    final g = newId();
    s.addAdjusts([
      StockAdjust(id: newId(), date: today, productId: a.id, qty: -1, reason: AdjustReason.convertOut, groupId: g),
      StockAdjust(id: newId(), date: today, productId: b.id, qty: 20, reason: AdjustReason.convertIn, groupId: g),
    ]);
    expect(s.stock(a.id), 6);
    expect(s.stock(b.id), 20);
    expect(s.applyCount({a.id: 5, b.id: 20}, today), 1);
    expect(s.stock(a.id), 5);
    s.removeAdjust(s.adjusts.firstWhere((x) => x.groupId == g));
    expect(s.stock(b.id), 0);

    // cheques: deposit -> clear, endorse -> take back
    final ali = Person(id: newId(), name: 'Ali');
    final reza = Person(id: newId(), name: 'Reza');
    s.upsertPerson(ali);
    s.upsertPerson(reza);
    s.upsertTxn(Txn(id: newId(), type: TxnType.lend, amount: 500, date: today, personId: ali.id));
    s.upsertTxn(Txn(id: newId(), type: TxnType.borrow, amount: 500, date: today, personId: reza.id));
    final c1 = Cheque(id: newId(), direction: ChequeDirection.received, amount: 500, dueDate: today, issueDate: today, personId: ali.id);
    s.upsertCheque(c1);
    s.endorseCheque(c1, toPersonId: reza.id, date: today);
    expect(s.personBalance(ali.id), 0);
    expect(s.personBalance(reza.id), 0);
    s.setChequeStatus(c1, ChequeStatus.pending);
    expect(s.personBalance(ali.id), 500);
    expect(s.personBalance(reza.id), -500);
    s.depositCheque(c1, cash);
    expect(c1.status, ChequeStatus.deposited);
    s.clearCheque(c1, accountId: cash, asType: TxnType.collect, date: today);
    expect(s.personBalance(ali.id), 0);
    final c2 = Cheque(
        id: newId(), direction: ChequeDirection.received, amount: 100, dueDate: today.add(const Duration(days: 30)), issueDate: today);
    final c3 = Cheque(
        id: newId(), direction: ChequeDirection.received, amount: 300, dueDate: today.add(const Duration(days: 70)), issueDate: today);
    final avg = s.averageDue([c2, c3])!;
    expect(avg.difference(dateOnly(DateTime.now())).inDays,
        ((100 * c2.dueDate.difference(dateOnly(DateTime.now())).inDays + 300 * c3.dueDate.difference(dateOnly(DateTime.now())).inDays) / 400).round());
  });

  testWidgets('all pages render', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Ali');
    s.upsertPerson(p);
    final prod = Product(id: newId(), name: 'Cable', sellPrice: 50, openingQty: 5);
    s.upsertProduct(prod);
    s.upsertTxn(Txn(
        id: newId(), type: TxnType.lend, amount: 300, date: DateTime.now(), accountId: s.accounts.first.id, personId: p.id,
        dueDate: DateTime.now().add(const Duration(days: 3))));
    s.upsertTxn(Txn(id: newId(), type: TxnType.expense, amount: 120, date: DateTime.now(), accountId: s.accounts.first.id));
    s.upsertCheque(Cheque(
        id: newId(), direction: ChequeDirection.issued, amount: 999, dueDate: DateTime.now(), issueDate: DateTime.now()));
    s.saveInvoice(Invoice(
      id: newId(),
      kind: InvoiceKind.sale,
      number: 1001,
      date: DateTime.now(),
      personId: p.id,
      lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 50)],
    ));
    s.saveLoan(Loan(id: newId(), title: 'Loan', installmentAmount: 10, installments: 3, firstDue: DateTime.now()));
    s.upsertAccount(Account(id: newId(), name: 'Car', type: AccountType.savings, goal: 1000));

    for (final page in AppPage.values) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(TarazApp(store: s, initialPage: page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page.name);
    }

    for (final tab in ['اسناد', 'عملیات کالا', 'مالی', 'مالی ویژه', 'هزینه و درآمد', 'گزارشات', 'متفرقه', 'کنترل اسناد', 'خروج و پشتیبان']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    // open the sales tab of the ribbon and start a sale invoice
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خرید و فروش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاکتور فروش').first);
    await tester.pumpAndSettle();
    expect(find.text('ذخیره فاکتور (Ctrl+S)'), findsOneWidget);
    // type a product and quantity
    final fields = find.byType(TextField);
    await tester.enterText(find.descendant(of: find.byType(RawAutocomplete<Product>), matching: find.byType(TextField)), 'Cable');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fields, findsWidgets);
    await tester.tap(find.text('تسویه کامل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره فاکتور (Ctrl+S)'));
    await tester.pumpAndSettle();
    expect(s.invoices.length, 2);
    expect(s.stock(prod.id), 2);

    // new transaction from the home tab
    await tester.tap(find.text('خانه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تراکنش جدید').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25000');
    await tester.tap(find.text('ذخیره (Ctrl+S)'));
    await tester.pumpAndSettle();
    expect(s.txns.where((t) => t.amount == 25000).length, 1);
  });
}
