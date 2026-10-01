import 'dart:io';

import 'package:taraz/core/format.dart';
import 'package:taraz/core/hash.dart';
import 'package:taraz/core/jalali.dart';
import 'package:taraz/data/chart.dart';
import 'package:taraz/data/journal.dart';
import 'package:taraz/data/models.dart';
import 'package:taraz/data/storage.dart';
import 'package:taraz/data/store.dart';
import 'package:taraz/main.dart';
import 'package:taraz/ui/dialogs/composite_dialogs.dart';
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
    expect(find.text('خرید و فروش'), findsWidgets);

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
    expect(find.text('خرید و فروش'), findsWidgets);
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

  test('manual vouchers and opening voucher', () {
    final s = _tempStore();
    final cash = s.accounts.first.id;
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final pr = Product(id: newId(), name: 'Cable', buyPrice: 70);
    s.upsertProduct(pr);

    s.applyOpening(
      date: DateTime(2026, 3, 21),
      accountOpenings: {cash: 1000},
      personOpenings: {ali.id: 300},
      productQty: {pr.id: 10},
      productCost: {pr.id: 50},
      other: {'10501': 2000, '20601': 500},
    );
    expect(s.balance(cash), 1000);
    expect(s.personBalance(ali.id), 300);
    expect(s.stock(pr.id), 10);
    expect(s.avgCost(pr.id), 50);
    expect(s.ledgerBalance('10501'), 2000);
    expect(s.ledgerBalance('20601'), 500);

    // cash 200 to Ali (he now owes more) and a manual expense
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: 1, date: DateTime(2026, 10, 1), lines: [
      VoucherLine(moeen: mDebtorsTrade, tafsiliId: ali.id, debit: 200),
      VoucherLine(moeen: mCash, tafsiliId: cash, credit: 200),
    ]));
    expect(s.balance(cash), 800);
    expect(s.personBalance(ali.id), 500);
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: 2, date: DateTime(2026, 10, 1), lines: [
      VoucherLine(moeen: '50102', debit: 120),
      VoucherLine(moeen: '20601', credit: 120),
    ]));
    expect(s.nextVoucherNumber(), 3);
    expect(s.ledgerBalance('20601'), 620);
    expect(s.profit(DateTime(2026, 10, 1), DateTime(2026, 10, 1)).expenses, 120);

    final again = AppStore.open(s.storage);
    expect(again.vouchers.length, 2);
    expect(again.personBalance(ali.id), 500);
    expect(again.settings.openingOther['10501'], 2000);
  });

  test('journal is balanced and trial balance matches balances', () {
    final s = _tempStore();
    final cash = s.accounts.first.id;
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final pr = Product(id: newId(), name: 'Cable');
    s.upsertProduct(pr);
    s.applyOpening(
      date: DateTime(2026, 3, 21),
      accountOpenings: {cash: 5000},
      personOpenings: {ali.id: -800},
      productQty: {pr.id: 4},
      productCost: {pr.id: 100},
      other: {'10501': 1000},
    );
    final d = DateTime(2026, 9, 1);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: d, personId: ali.id,
        lines: [InvoiceLine(productId: pr.id, qty: 6, unitPrice: 100)], paid: 200, accountId: cash));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: d,
        lines: [InvoiceLine(productId: pr.id, qty: 3, unitPrice: 180), InvoiceLine(title: 'Service', qty: 1, unitPrice: 60)],
        discount: 20, extra: 10, paid: 590, accountId: cash));
    s.upsertTxn(Txn(id: newId(), type: TxnType.expense, amount: 70, date: d, accountId: cash));
    s.upsertTxn(Txn(id: newId(), type: TxnType.purchaseDiscount, amount: 50, date: d, personId: ali.id));
    s.addAdjusts([StockAdjust(id: newId(), date: d, productId: pr.id, qty: -1, reason: AdjustReason.waste)]);
    s.saveVoucher(Voucher(id: newId(), number: 1, fixedNumber: 1, date: d, lines: [
      VoucherLine(moeen: mDebtorsTrade, tafsiliId: ali.id, debit: 300),
      VoucherLine(moeen: mCash, tafsiliId: cash, credit: 300),
    ]));

    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));

    final f = ReportFilter()..level = TbLevel.tafsili;
    final tb = trialBalance(s, j, f, TbOptions());
    int bal(String moeen, String? id) => tb.firstWhere((r) => r.key == '$moeen|${id ?? ''}').bal;
    expect(bal(mCash, cash), s.balance(cash));
    expect(bal(mDebtorsTrade, ali.id), s.personBalance(ali.id));
    expect(tb.fold<int>(0, (a, r) => a + r.balDr), tb.fold<int>(0, (a, r) => a + r.balCr));

    final kolTb = trialBalance(s, j, ReportFilter(), TbOptions());
    expect(kolTb.any((r) => r.code == '101'), isTrue);

    final led = generalLedger(s, j, ReportFilter()..level = TbLevel.tafsili ..pathMoeen = mCash ..linkTafsili = cash);
    expect(led.length, 1);
    expect(led.first.end, s.balance(cash));
    final period = generalLedger(s, j, ReportFilter()..level = TbLevel.moeen ..pathMoeen = mCash ..from = DateTime(2026, 6, 1));
    expect(period.first.before, 5000);
  });

  test('composite receive/pay and composite expense', () {
    final s = _tempStore();
    final cash = s.accounts.first.id;
    final bank = Account(id: newId(), name: 'Bank', type: AccountType.bank);
    s.upsertAccount(bank);
    final ali = Person(id: newId(), name: 'Ali', opening: 1000);
    final reza = Person(id: newId(), name: 'Reza');
    s.upsertPerson(ali);
    s.upsertPerson(reza);
    final d = DateTime(2026, 10, 1);

    final lines = applyPayItems(s, ali.id, [
      PayItem(PayMethod.cashIn, amount: 300, accountId: cash),
      PayItem(PayMethod.bankIn, amount: 200, accountId: bank.id),
      PayItem(PayMethod.saleDiscount, amount: 50),
      PayItem(PayMethod.toOtherPerson, amount: 100, otherPersonId: reza.id),
      PayItem(PayMethod.chequeReceive, amount: 250, due: d, serial: '77'),
    ], d, 'test');
    s.saveVoucher(Voucher(id: newId(), number: 1, fixedNumber: 1, date: d, lines: lines, kind: 'composite'));
    expect(lines.fold<int>(0, (a, l) => a + l.debit), lines.fold<int>(0, (a, l) => a + l.credit));
    expect(s.balance(cash), 300);
    expect(s.balance(bank.id), 200);
    expect(s.personBalance(ali.id), 1000 - 650);
    expect(s.personBalance(reza.id), 100);
    expect(s.cheques.where((c) => c.personId == ali.id && c.amount == 250).length, 1);

    final cat = s.categoriesOf(CategoryKind.expense).first;
    final exp = [
      VoucherLine(moeen: mExpense, tafsiliId: cat.id, debit: 400),
      VoucherLine(moeen: mDebtorsTrade, tafsiliId: reza.id, credit: 400),
      ...applyPayItems(s, reza.id, [PayItem(PayMethod.cashOut, amount: 400, accountId: cash)], d, 'exp'),
    ];
    s.saveVoucher(Voucher(id: newId(), number: 2, fixedNumber: 2, date: d, lines: exp, kind: 'expense'));
    expect(s.balance(cash), -100);
    expect(s.personBalance(reza.id), 100);
    expect(s.profit(d, d).expenses, 400);
    expect(s.profit(d, d).discountsGiven, 50);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
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

    for (final tab in ['خرید و فروش', 'عملیات کالا', 'مالی', 'مالی ویژه', 'هزینه و درآمد', 'گزارشات', 'متفرقه', 'کنترل اسناد', 'خروج و پشتیبان']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    // opening voucher: decline the backup prompt and check the form
    await tester.tap(find.text('اسناد').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('سند افتتاحیه').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خیر'));
    await tester.pumpAndSettle();
    expect(find.text('جمع دارایی ها'), findsOneWidget);
    await tester.tap(find.text('صندوق و تنخواه'));
    await tester.pumpAndSettle();
    expect(find.text('لیست دفاتر موجود در گروه صندوق و تنخواه'), findsOneWidget);
    await tester.tap(find.text('تایید (F9)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تایید (F9)').last);
    await tester.pumpAndSettle();
    expect(s.settings.openingDate, isNotNull);

    // trial balance and general ledger
    await tester.tap(find.text('گزارشات').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تراز آزمایشی').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشاهده تراز'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تراز آزمایشی —'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف (F10)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دفتر کل').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نمایش'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بازگشت (F10)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اسناد').first);
    await tester.pumpAndSettle();

    // composite receive/pay and composite expense forms open
    await tester.tap(find.text('مالی ویژه').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('دریافت پرداخت مرکب').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نحوه دریافت و پرداخت'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لطفاً شخص را تعیین کنید'), findsOneWidget);
    await tester.tap(find.text('انصراف (F10)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('هزینه و درآمد').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('پرداخت هزینه های مرکب').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('کالا ها'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اسناد').first);
    await tester.pumpAndSettle();

    // manual voucher dialog opens
    await tester.tap(find.text('سند حسابداری دستی').first);
    await tester.pumpAndSettle();
    expect(find.text('جمع بدهکاری: '), findsOneWidget);
    await tester.tap(find.text('خروج'));
    await tester.pumpAndSettle();

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

    // cash payment from the finance tab
    await tester.tap(find.text('مالی').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('پرداخت نقدی').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25000');
    await tester.tap(find.text('ذخیره (Ctrl+S)'));
    await tester.pumpAndSettle();
    expect(s.txns.where((t) => t.amount == 25000).length, 1);
  });
}
