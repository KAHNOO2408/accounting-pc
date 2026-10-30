import 'dart:io';

import 'package:taraz/core/format.dart';
import 'package:taraz/core/hash.dart';
import 'package:taraz/core/jalali.dart';
import 'package:taraz/core/qr.dart';
import 'package:taraz/core/xlsx.dart';
import 'package:taraz/core/zip_backup.dart';
import 'package:taraz/data/sms.dart';
import 'package:taraz/ui/dialogs/sms_dialogs.dart';
import 'package:taraz/data/books.dart';
import 'package:taraz/data/mrt_import.dart';
import 'package:taraz/data/chart.dart';
import 'package:taraz/data/journal.dart';
import 'package:taraz/data/kardex.dart';
import 'package:taraz/data/discounts.dart';
import 'package:taraz/data/marketing.dart';
import 'package:taraz/data/payroll.dart';
import 'package:taraz/data/woo.dart';
import 'package:taraz/data/serials.dart';
import 'package:taraz/data/custom_reports.dart';
import 'package:taraz/data/scale.dart';
import 'package:taraz/data/tax_report.dart';
import 'package:taraz/data/tools.dart';
import 'package:taraz/data/insurance_disk.dart';
import 'package:taraz/core/iran_system.dart';
import 'package:taraz/ui/dialogs/payroll_dialogs.dart';
import 'package:taraz/ui/dialogs/orders_centers_dialogs.dart';
import 'package:taraz/ui/dialogs/extra_reports.dart';
import 'package:taraz/data/models.dart';
import 'package:taraz/data/report_layout.dart';
import 'package:taraz/data/storage.dart';
import 'package:taraz/data/store.dart';
import 'package:taraz/main.dart';
import 'package:taraz/ui/dialogs/bank_dialogs.dart';
import 'package:taraz/ui/dialogs/books_dialogs.dart';
import 'package:taraz/ui/dialogs/composite_dialogs.dart';
import 'package:taraz/ui/dialogs/invoice_editor.dart';
import 'package:taraz/ui/dialogs/ledger_dialogs.dart';
import 'package:taraz/ui/dialogs/price_dialog.dart';
import 'package:taraz/ui/dialogs/sakan_tools.dart';
import 'package:taraz/ui/pages/ledger_reports.dart';
import 'package:taraz/ui/print_designer.dart';
import 'package:taraz/ui/report/report_render.dart';
import 'package:taraz/ui/shell.dart';
import 'package:taraz/ui/widgets/common.dart';
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
      other: {'1220': 2000, '2110': 500},
    );
    expect(s.balance(cash), 1000);
    expect(s.personBalance(ali.id), 300);
    expect(s.stock(pr.id), 10);
    expect(s.avgCost(pr.id), 50);
    expect(s.ledgerBalance('1220'), 2000);
    expect(s.ledgerBalance('2110'), 500);

    // cash 200 to Ali (he now owes more) and a manual expense
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: 1, date: DateTime(2026, 10, 1), lines: [
      VoucherLine(moeen: mDebtorsTrade, tafsiliId: ali.id, debit: 200),
      VoucherLine(moeen: mCash, tafsiliId: cash, credit: 200),
    ]));
    expect(s.balance(cash), 800);
    expect(s.personBalance(ali.id), 500);
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: 2, date: DateTime(2026, 10, 1), lines: [
      VoucherLine(moeen: '5007', debit: 120),
      VoucherLine(moeen: '2110', credit: 120),
    ]));
    expect(s.nextVoucherNumber(), 3);
    expect(s.ledgerBalance('2110'), 620);
    expect(s.profit(DateTime(2026, 10, 1), DateTime(2026, 10, 1)).expenses, 120);

    final again = AppStore.open(s.storage);
    expect(again.vouchers.length, 2);
    expect(again.personBalance(ali.id), 500);
    expect(again.settings.openingOther['1220'], 2000);
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
      other: {'1220': 1000},
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
    expect(kolTb.any((r) => r.code == '10'), isTrue);

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

  test('Sakan reports: 6-column trial balance, seller shipping and «نحوه تسویه»', () {
    final s = _tempStore();
    final cash = s.accounts.firstWhere((a) => a.type == AccountType.cash);
    cash.opening = 5000;
    s.upsertAccount(cash);
    final bank = Account(id: newId(), name: 'Bank', type: AccountType.bank);
    s.upsertAccount(bank);
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final d = DateTime(2026, 10, 1);

    // sale with shipping: 300 paid by the buyer, 200 paid by us from the cash box
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: d, personId: ali.id, lines: [
      InvoiceLine(title: 'Cable', qty: 2, unitPrice: 1000),
    ], extra: 300, info: {'shipSeller': '200', 'shipAcc': cash.id});
    s.saveInvoice(inv);
    expect(inv.total, 2300);
    expect(inv.shipBySeller, 200);
    expect(s.balance(cash.id), 4800);
    expect(s.personBalance(ali.id), 2300);
    expect(s.categories.any((c) => c.name == 'هزینه حمل'), isTrue);

    // settlement: 1000 cash, 800 bank, 500 cheque
    saveInvoiceSettlement(s, inv, [
      PayItem(PayMethod.cashIn, amount: 1000, accountId: cash.id),
      PayItem(PayMethod.bankIn, amount: 800, accountId: bank.id),
      PayItem(PayMethod.chequeReceive, amount: 500, due: d, serial: '9'),
    ]);
    final sum = s.settlementSummary(inv);
    expect(sum['دریافت نقدی'], 1000);
    expect(sum['واریز به بانک'], 800);
    expect(sum['دریافت چک'], 500);
    final data = invoiceReportData(s, inv);
    expect(data.fields['مبلغ دریافت نقدی'], '1,000');
    expect(data.fields['مبلغ حواله بانکی'], '800');
    expect(data.fields['مبلغ دریافت چک'], '500');
    expect(data.fields['هزینه حمل بعهده فروشنده'], '200');
    expect(data.fields['نحوه تسویه'], contains('دریافت چک'));

    // trial balance: the opening goes to «ابتدای دوره», documents to «طی دوره»
    final j = buildJournal(s);
    final rows = trialBalance(s, j, ReportFilter()..level = TbLevel.moeen, TbOptions());
    final cashRow = rows.firstWhere((r) => r.code == mCash);
    expect(cashRow.startDr, 5000);
    expect(cashRow.turnDr, 1000);
    expect(cashRow.turnCr, 200);
    expect(cashRow.balDr, 5800);
    expect(rows.fold<int>(0, (a, r) => a + r.balDr), rows.fold<int>(0, (a, r) => a + r.balCr));
    // a row without a product is a service: Sakan's «فروش خدمات» (4050)
    expect(rows.firstWhere((r) => r.code == mServiceSales).isPl, isTrue);
    expect(cashRow.isPl, isFalse);
    expect(j.where((p) => p.docKey == 'inv:${inv.id}').fold<int>(0, (a, p) => a + p.debit),
        j.where((p) => p.docKey == 'inv:${inv.id}').fold<int>(0, (a, p) => a + p.credit));
  });

  testWidgets('6-column trial balance and the shipping dialog render', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final cash = s.accounts.firstWhere((a) => a.type == AccountType.cash);
    cash.opening = 7000;
    s.upsertAccount(cash);
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('خرید و فروش').first);
    showDialog<void>(context: ctx, builder: (_) => TrialBalanceView(filter: ReportFilter()..level = TbLevel.moeen, options: TbOptions()));
    await tester.pumpAndSettle();
    expect(find.text('بدهکار ابتدای دوره'), findsOneWidget);
    expect(find.text('مانده دفاتر سود و زیانی'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('بدهکار ابتدای دوره'))).pop();
    await tester.pumpAndSettle();

    final f = showShippingDialog(ctx, buy: false);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('shipSeller')), matching: find.byType(TextFormField)), '400');
    await tester.tap(find.text('تایید (F9)'));
    await tester.pumpAndSettle();
    expect(find.text('حساب پرداخت هزینه حمل را انتخاب کنید'), findsOneWidget);
    await tester.tap(find.text('انصراف').last);
    await tester.pumpAndSettle();
    expect(await f, isNull);
  });

  test('cheque books and moving cheques between boxes', () {
    final s = _tempStore();
    final box1 = s.accounts.firstWhere((a) => a.type == AccountType.cash).id;
    final box2 = Account(id: newId(), name: 'Box 2', type: AccountType.cash);
    final bank = Account(id: newId(), name: 'Mellat', type: AccountType.bank);
    s.upsertAccount(box2);
    s.upsertAccount(bank);
    final book = ChequeBook(id: newId(), accountId: bank.id, prefix: 'A', start: 100, count: 5);
    s.saveChequeBook(book);
    expect(s.leavesOf(bank.id).length, 5);
    expect(s.freeSerials(bank.id).first, 'A100');

    final d = DateTime(2026, 10, 1);
    applyPayItems(s, null, [PayItem(PayMethod.chequeIssue, amount: 70, due: d, serial: 'A100', accountId: bank.id)], d, 'x');
    expect(s.cheques.single.bankAccountId, bank.id);
    s.setLeafVoid(book, 101, true, note: 'torn');
    final states = s.leavesOf(bank.id).map((l) => l.state).toList();
    expect(states.take(3), [LeafState.used, LeafState.voided, LeafState.free]);
    expect(s.freeSerials(bank.id), ['A102', 'A103', 'A104']);
    expect(s.removeChequeBook(book.id), isFalse);
    s.setLeafVoid(book, 101, false);
    expect(s.freeSerials(bank.id).length, 4);

    final c1 = Cheque(id: newId(), direction: ChequeDirection.received, amount: 10, dueDate: d, issueDate: d);
    final c2 = Cheque(id: newId(), direction: ChequeDirection.received, amount: 20, dueDate: d, issueDate: d);
    s.upsertCheque(c1);
    s.upsertCheque(c2);
    expect(s.chequesInBox(box1).length, 2);
    final v = s.moveCheques(fromId: box1, toId: box2.id, chequeIds: [c1.id], date: d);
    expect(v.kind, 'chequeMove');
    expect(s.chequesInBox(box1).map((c) => c.id), [c2.id]);
    expect(s.chequesInBox(box2.id).map((c) => c.id), [c1.id]);
    final again = AppStore.open(s.storage);
    expect(again.chequesInBox(box2.id).length, 1);
    expect(again.chequeBooks.single.count, 5);
    s.removeVoucher(v.id);
    expect(s.chequesInBox(box1).length, 2);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
  });

  test('closing document and transfer to opening', () {
    final s = _tempStore();
    final cash = s.accounts.firstWhere((a) => a.type == AccountType.cash).id;
    final d = DateTime(2026, 3, 10);
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final prod = Product(id: newId(), name: 'Cable', buyPrice: 30, sellPrice: 50, openingQty: 10);
    s.upsertProduct(prod);
    s.upsertTxn(Txn(id: newId(), type: TxnType.income, amount: 500, date: d, accountId: cash));
    s.upsertTxn(Txn(id: newId(), type: TxnType.expense, amount: 200, date: d, accountId: cash));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: d, personId: ali.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 50)]));
    final cashBefore = s.balance(cash);
    final aliBefore = s.personBalance(ali.id);
    final costBefore = s.avgCost(prod.id);
    final profitBefore = s.profit(DateTime(2026, 1, 1), DateTime(2026, 12, 31));

    final end = DateTime(2026, 3, 20);
    expect(closingIssues(s, end), isEmpty);
    final lines = closingLines(s, end);
    expect(lines, isNotEmpty);
    expect(lines.fold<int>(0, (a, l) => a + l.debit), lines.fold<int>(0, (a, l) => a + l.credit));
    final closing = Voucher(id: newId(), number: 1, fixedNumber: 1, date: end, lines: lines, kind: 'closing');
    s.saveVoucher(closing);
    expect(s.balance(cash), 0);
    expect(s.personBalance(ali.id), 0);
    expect(s.avgCost(prod.id), costBefore);
    expect(s.profit(DateTime(2026, 1, 1), DateTime(2026, 12, 31)).netProfit, profitBefore.netProfit);
    expect(s.pendingClosing?.id, closing.id);
    expect(closingIssues(s, end), isNotEmpty);

    final re = s.transferClosing(closing, date: DateTime(2026, 3, 21));
    expect(s.pendingClosing, isNull);
    expect(s.balance(cash), cashBefore);
    expect(s.personBalance(ali.id), aliBefore);
    expect(re.totalDebit, re.totalCredit);
    expect(re.lines.where((l) => l.moeen == mRetained).length, 1);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    s.removeVoucher(re.id);
    expect(s.pendingClosing?.id, closing.id);
  });

  test('invoice settlement, unit price helpers and print templates', () {
    final s = _tempStore();
    final cash = s.accounts.firstWhere((a) => a.type == AccountType.cash).id;
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final prod = Product(id: newId(), name: 'Glass', code: 'G-1', sellPrice: 750, sellPrice2: 700, openingQty: 5);
    s.upsertProduct(prod);
    final d = DateTime(2026, 10, 1);
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 7, date: d, personId: ali.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 750)]);
    s.saveInvoice(inv);
    expect(s.personBalance(ali.id), 1500);
    final v = saveInvoiceSettlement(s, inv, [
      PayItem(PayMethod.cashIn, amount: 1000, accountId: cash),
      PayItem(PayMethod.saleDiscount, amount: 100),
    ])!;
    expect(v.kind, 'settle');
    expect(s.personBalance(ali.id), 400);
    expect(s.personBalance(ali.id, excludeInvoiceId: inv.id), -1100);
    expect(s.balance(cash), 1000);
    expect(s.settlementsOf(inv.id).length, 1);

    // walk-in customer
    final inv2 = Invoice(id: newId(), kind: InvoiceKind.sale, number: 8, date: d,
        lines: [InvoiceLine(productId: prod.id, qty: 1, unitPrice: 700)]);
    s.saveInvoice(inv2);
    saveInvoiceSettlement(s, inv2, [PayItem(PayMethod.cashIn, amount: 700, accountId: cash)]);
    expect(s.balance(cash), 1700);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    s.removeInvoice(inv2.id);
    expect(s.balance(cash), 1000);

    expect(roundPrice(12345, 1000), 12000);
    expect(roundPrice(12345, 1000, up: true), 13000);
    expect(roundPrice(12000, 1000, up: true), 12000);
    expect(lastBuyPrice(s, prod), 0);

    // print templates
    final t = s.defaultTemplate(PrintDocType.invoice);
    final doc = buildPrintDoc(s, inv, t);
    expect(doc.title, 'فاکتور فروش');
    expect(doc.rows.single.contains('Glass'), isTrue);
    expect(doc.totals.any((x) => x.$1.startsWith('کل مانده حساب')), isTrue);
    final wh = buildPrintDoc(s, inv, s.defaultTemplate(PrintDocType.warehouse));
    expect(wh.headers.contains('فی'), isFalse);
    expect(wh.signatures.first, 'امضاء تحویل دهنده');
    final bc = buildPrintDoc(s, inv, s.defaultTemplate(PrintDocType.barcode));
    expect(bc.labels.length, 2);
    expect(bc.labels.first.code, 'G-1');
    expect(code128('G-1').length, (3 + 2) * 11 + 13);
    expect(printDocHtml(doc, t), contains('فاکتور فروش'));
    final mine = t.copy()
      ..id = newId()
      ..name = 'طرح ۲'
      ..paper = '80mm'
      ..columns = ['name', 'qty', 'total'];
    s.saveTemplate(mine);
    s.setDefaultTemplate(mine);
    final again = AppStore.open(s.storage);
    expect(again.defaultTemplate(PrintDocType.invoice).name, 'طرح ۲');
    expect(buildPrintDoc(again, inv, again.defaultTemplate(PrintDocType.invoice)).headers, ['شرح کالا', 'تعداد', 'مبلغ کل']);
    expect(again.product(prod.id)!.sellPrice2, 700);
  });

  test('warehouses, transfers and fixed assets', () {
    final s = _tempStore();
    final cash = s.accounts.firstWhere((a) => a.type == AccountType.cash).id;
    final d = DateTime(2026, 10, 1);
    expect(s.warehouses.length, 1);
    final main = s.mainWarehouseId;
    final w2 = Warehouse(id: newId(), code: s.nextWarehouseCode(), name: 'مرجوعی');
    s.saveWarehouse(w2);
    final prod = Product(id: newId(), name: 'Cable', buyPrice: 10, openingQty: 10);
    s.upsertProduct(prod);
    s.saveTransfer(WarehouseTransfer(id: newId(), number: 1, date: d, fromId: main, lines: [
      TransferLine(productId: prod.id, toId: w2.id, qty: 4),
    ]));
    expect(s.stock(prod.id), 10);
    expect(s.stock(prod.id, warehouseId: main), 6);
    expect(s.stock(prod.id, warehouseId: w2.id), 4);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: d,
        lines: [InvoiceLine(productId: prod.id, qty: 1, unitPrice: 20, warehouseId: w2.id)]));
    s.addAdjusts([StockAdjust(id: newId(), date: d, productId: prod.id, qty: -1, reason: AdjustReason.waste, warehouseId: w2.id)]);
    expect(s.stock(prod.id, warehouseId: w2.id), 2);
    expect(s.stock(prod.id), 8);
    expect(s.removeWarehouse(w2.id), isFalse);
    expect(s.removeWarehouse(main), isFalse);
    final again = AppStore.open(s.storage);
    expect(again.warehouses.length, 2);
    expect(again.stock(prod.id, warehouseId: w2.id), 2);

    // assets
    final ali = Person(id: newId(), name: 'Ali');
    s.upsertPerson(ali);
    final buy = s.buyAssets(
      date: d,
      personId: ali.id,
      items: [Asset(id: newId(), code: 0, name: 'Laptop', cost: 1000), Asset(id: newId(), code: 0, name: 'Desk', cost: 300)],
      payLines: applyPayItems(s, ali.id, [PayItem(PayMethod.cashOut, amount: 500, accountId: cash)], d, 'x'),
    );
    expect(buy.totalDebit, buy.totalCredit);
    expect(s.assets.length, 2);
    expect(s.assets.map((a) => a.code).toSet().length, 2);
    expect(s.personBalance(ali.id), -800);
    final laptop = s.assets.firstWhere((a) => a.name == 'Laptop');
    laptop.depreciation = 200;
    s.saveAsset(laptop);
    expect(s.vouchers.where((v) => v.kind == 'depreciation').length, 1);
    final sell = s.sellAssets(date: d, sales: [(laptop, 900)],
        payLines: applyPayItems(s, null, [PayItem(PayMethod.cashIn, amount: 900, accountId: cash)], d, 'y'));
    expect(sell.totalDebit, sell.totalCredit);
    expect(laptop.sold, isTrue);
    final pr = s.profit(DateTime(2000), DateTime(2100));
    expect(pr.otherIncome, 100);
    expect(pr.expenses, 200);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    s.removeVoucher(sell.id);
    expect(laptop.sold, isFalse);
    expect(s.removeAsset(laptop.id), isFalse);
    s.removeVoucher(buy.id);
    expect(s.assets, isEmpty);
    expect(s.vouchers.where((v) => v.kind == 'depreciation'), isEmpty);
  });

  test('users, audit trail and document centers', () {
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali', password: '1234');
    expect(s.login('admin', 'bad'), isNull);
    expect(s.login('admin', '1234')?.id, 'owner');
    final u = AppUser(id: newId(), code: s.nextUserCode(), name: 'Tayeb', login: 'tayeb', denied: {'فاکتور خرید'});
    expect(s.saveUser(u, password: 'x1'), isNull);
    expect(s.saveUser(AppUser(id: newId(), code: 9, name: 'Dup', login: 'TAYEB')), isNotNull);
    expect(s.multiUser, isTrue);
    expect(s.login('tayeb', 'nope'), isNull);
    expect(s.login('tayeb', 'x1')?.name, 'Tayeb');
    expect(s.canUse('فاکتور خرید'), isFalse);
    expect(s.canUse('فاکتور فروش'), isTrue);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 5, date: DateTime(2026, 10, 1), lines: [InvoiceLine(title: 'x', unitPrice: 10)]));
    final last = s.audit.last;
    expect(last.userId, u.id);
    expect(last.docNo, 5);
    expect(s.audit.where((e) => e.action == 'ورود').length, 2);
    final again = AppStore.open(s.storage);
    expect(again.users.single.login, 'tayeb');
    expect(again.audit.length, s.audit.length);

    expect(s.saveCenter('شعبه ۲'), isNull);
    expect(s.saveCenter('شعبه ۲'), isNotNull);
    s.saveVoucher(Voucher(id: newId(), number: 1, fixedNumber: 1, date: DateTime(2026, 10, 1), center: 'شعبه ۲'));
    expect(s.removeCenter('شعبه ۲'), isNotNull);
    expect(s.saveCenter('شعبه دو', old: 'شعبه ۲'), isNull);
    expect(s.vouchers.single.center, 'شعبه دو');
    expect(s.removeCenter('اصلی'), isNull);
    expect(s.removeCenter('شعبه دو'), isNotNull);
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
      expect(tester.takeException(), isNull, reason: 'page: ${page.name}');
    }

    for (final tab in ['خرید و فروش', 'عملیات کالا', 'مالی', 'مالی ویژه', 'هزینه و درآمد', 'حقوق و دستمزد', 'گزارشات', 'متفرقه', 'کنترل اسناد', 'خروج و پشتیبان']) {
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
    await tester.tap(find.text('دارایی های جاری نقدی'));
    await tester.pumpAndSettle();
    expect(find.text('لیست دفاتر موجود در گروه دارایی های جاری نقدی'), findsOneWidget);
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

    // cheque books window and cheque move dialog
    await tester.tap(find.text('مالی').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('معرفی دسته چک').first);
    await tester.pumpAndSettle();
    expect(find.text('نام بانک'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('بازگشت (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مالی ویژه').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('جا به جایی چک').first);
    await tester.pumpAndSettle();
    expect(find.text('صندوق دریافت کننده چک'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('اسناد').first);
    await tester.pumpAndSettle();

    // warehouses list → new warehouse, transfer window, assets
    await tester.tap(find.text('متفرقه').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('لیست انبارها').first);
    await tester.pumpAndSettle();
    expect(find.text('لیست انبار های سیستم'), findsOneWidget);
    await tester.tap(find.text('معرفی انبار'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'نام انبار'), 'انبار مرجوعی');
    await tester.tap(find.text('تایید (F9)').last);
    await tester.pumpAndSettle();
    expect(s.warehouses.length, 2);
    await tester.tap(find.text('بازگشت (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('عملیات کالا').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتقال بین انبارها').first);
    await tester.pumpAndSettle();
    expect(find.text('انتقال بین انبار'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خرید و فروش').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('جدول اموال').first);
    await tester.pumpAndSettle();
    expect(find.text('همه موارد'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خرید اموال و تجهیزات').first);
    await tester.pumpAndSettle();
    expect(find.text('تایید و تسویه (F9)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('اسناد').first);
    await tester.pumpAndSettle();

    // closing dialog opens
    await tester.tap(find.text('سند اختتامیه').first);
    await tester.pumpAndSettle();
    expect(find.text('تراز اختتامیه - حسابهای ترازنامه ای'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();

    // document centers, profit split, users and audit
    await tester.tap(find.text('مرکز اسناد').first);
    await tester.pumpAndSettle();
    expect(find.text('مراکز اسناد'), findsOneWidget);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تقسیم سود و زیان صاحبان سهام').first);
    await tester.pumpAndSettle();
    expect(find.text('عنوان معین صاحبان سهام'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تقسیم سود و زیان سال مالی').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('متفرقه').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('کاربران').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('کاربران').first);
    await tester.pumpAndSettle();
    expect(find.text('لیست کاربران'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('بازگشت (F10)').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ردپای کاربران').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ردپای کاربران').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشاهده پویا'));
    await tester.pumpAndSettle();
    expect(find.text('گزارش پویا — ردپای کاربران'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('بستن').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف (F10)').last);
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
    expect(find.text('تعیین نوع چاپ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // type a product → «تعیین تعداد» → price window
    await tester.enterText(find.descendant(of: find.byType(RawAutocomplete<Product>), matching: find.byType(TextField)).first, 'Cable');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('تعیین تعداد'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('تایید F9').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('تایید F9').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // print type menu → warehouse slip → report builder → new layout in the band designer
    await tester.tap(find.text('تعیین نوع چاپ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('چاپ حواله انبار').last);
    await tester.pumpAndSettle();
    expect(find.text('گزارش سازی — چاپ حواله انبار'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ساخت گزارش'));
    await tester.pumpAndSettle();
    expect(find.text('Header1'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ذخیره طرح (F9)').last);
    await tester.pumpAndSettle();
    expect(s.reportLayouts.length, 1);
    await tester.tap(find.text('انصراف (F10)').last);
    await tester.pumpAndSettle();
    expect(s.invoices.length, 2);

    // settle in cash from the «نحوه دریافت» window
    final cashBefore = s.balance(s.accounts.first.id);
    await tester.tap(find.text('تایید').first);
    await tester.pumpAndSettle();
    expect(find.text('بدهی قبلی'), findsOneWidget);
    await tester.tap(find.text('دریافت نقدی').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(MoneyField), matching: find.byType(TextField)).last, '50');
    await tester.tap(find.text('افزودن').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تایید (F9)').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(s.invoices.length, 2);
    expect(s.stock(prod.id), 2);
    expect(s.vouchers.where((v) => v.kind == 'settle').length, 1);
    expect(s.balance(s.accounts.first.id), cashBefore + 50);

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

  test('kardex: moving average, negative control and contra nature', () {
    final s = _tempStore();
    final p = Person(id: newId(), name: 'Buyer');
    s.upsertPerson(p);
    final prod = Product(id: newId(), name: 'Holder', code: '7020', sellPrice: 300, weight: 0.5);
    s.upsertProduct(prod);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2025, 1, 1), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 100)]));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 2, date: DateTime(2025, 1, 2), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 200)]));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2025, 1, 3), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 3, unitPrice: 300)]));
    final k = buildKardex(s, prod.id);
    expect(k.length, 3);
    expect(k[2].fi, 150);
    expect(k[2].total, -450);
    expect(k.last.balance, 1);
    expect(k.last.value, 150);
    expect(negativeKardexes(s), isEmpty);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 2, date: DateTime(2025, 1, 4), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 5, unitPrice: 300)]));
    expect(negativeKardexes(s).length, 1);
    expect(checkKardex(s, all: true), isNotEmpty);
    expect(contraNature(s, includeStock: true).any((r) => r.tafsiliId == prod.id), isTrue);
    expect(contraNature(s, includeStock: false).any((r) => r.tafsiliId == prod.id), isFalse);
    // product extra info round-trips
    prod.info['barcode'] = '6260001';
    final back = Product.fromJson(prod.toJson());
    expect(back.weight, 0.5);
    expect(back.info['barcode'], '6260001');
  });

  testWidgets('stock list, kardex, product form and document controls', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final prod = Product(id: newId(), name: 'Cable', code: '7001', sellPrice: 50, openingQty: 5);
    s.upsertProduct(prod);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime.now(),
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 50)]));
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خرید و فروش').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('جدول کالا').first);
    await tester.pumpAndSettle();
    expect(find.text('لیست اقلام موجودی'), findsOneWidget);
    expect(find.text('7001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('رویت کاردکس'));
    await tester.pumpAndSettle();
    expect(find.text('کاردکس کالا — Cable'), findsOneWidget);
    expect(find.text('میانگین_متحرک'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('بازگشت').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('اطلاعات کالا').last);
    await tester.pumpAndSettle();
    expect(find.text('اطلاعات دفتر تفصیلی موجودی کالا'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('کنترل اسناد').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('کنترل کاردکس').first);
    await tester.pumpAndSettle();
    expect(find.text('مایل به کنترل کاردکس های منفی هستید؟'), findsOneWidget);
    await tester.tap(find.text('بله'));
    await tester.pumpAndSettle();
    expect(find.text('کاردکس منفی وجود ندارد'), findsOneWidget);
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('چک کاردکس').first);
    await tester.pumpAndSettle();
    expect(find.text('شماره مبنا در سند'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('برگشت').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('گزارش خلاف ماهیت').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('بله'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('لیست دفاتری که ماهیت غیر مجاز دارند'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('نمایش اخطارهای ورودی').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نمایش اخطارهای ورودی').first);
    await tester.pumpAndSettle();
    expect(find.text('گزارش پویا — اخطارهای ورودی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F5 in the invoice form saves and prints without the financial window', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Reza');
    s.upsertPerson(p);
    final prod = Product(id: newId(), name: 'Cable', sellPrice: 50, openingQty: 5);
    s.upsertProduct(prod);
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 7, date: DateTime.now(), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 1, unitPrice: 50)]);
    s.saveInvoice(inv);
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('خرید و فروش').first);
    showInvoiceEditor(ctx, edit: inv);
    await tester.pumpAndSettle();
    expect(find.text('تعیین نوع چاپ'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('بدهی قبلی'), findsNothing);
    expect(find.text('تعیین نوع چاپ'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(s.invoices.length, 1);

    // a متفرقه invoice is not opened in the financial window either
    final misc = Invoice(id: newId(), kind: InvoiceKind.sale, number: 8, date: DateTime.now(),
        lines: [InvoiceLine(productId: prod.id, qty: 1, unitPrice: 50)]);
    s.saveInvoice(misc);
    showInvoiceEditor(tester.element(find.text('خرید و فروش').first), edit: misc);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('بدهی قبلی'), findsNothing);
    expect(find.textContaining('فاکتور متفرقه باید کامل تسویه شود'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('account table rows: persons share codes and keep their balance side', () {
    final s = _tempStore();
    final ali = Person(id: newId(), name: 'Ali');
    final reza = Person(id: newId(), name: 'Reza');
    final zero = Person(id: newId(), name: 'Zero');
    for (final p in [ali, reza, zero]) {
      s.upsertPerson(p);
    }
    expect(ali.code, 7001);
    expect(zero.code, 7003);
    s.upsertProduct(Product(id: newId(), name: 'Item', code: '${s.nextTafsiliCode()}', sellPrice: 10));
    expect(s.products.first.code, '7004');
    final prod = s.products.first;
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2025, 1, 1), personId: ali.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 100)]));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2025, 1, 2), personId: reza.id,
        lines: [InvoiceLine(productId: prod.id, qty: 3, unitPrice: 50)]));
    final people = accCategories.expand((r) => r).firstWhere((c) => c.label == 'اشخاص');
    final j = buildJournal(s);
    expect(j.where((p) => p.docKey != null && p.docKey!.startsWith('inv:')), isNotEmpty);
    final bal = <String, int>{};
    for (final p in j) {
      final k = '${p.moeen}|${p.tafsiliId ?? ''}';
      bal[k] = (bal[k] ?? 0) + p.debit - p.credit;
      bal[p.moeen] = (bal[p.moeen] ?? 0) + p.debit - p.credit;
    }
    final rows = {for (final r in accountRows(s, people, bal)) r.name: r};
    expect(rows['Ali']!.balance, 200);
    expect(rows['Reza']!.balance, -150);
    expect(rows['Zero']!.balance, 0);
    expect(balanceColor(200), debtorBlue);
    expect(balanceColor(-150), creditorRed);
    expect(balanceColor(0), isNull);
    expect(defaultLayoutFor(PrintDocType.ledger).itemsOf(BandKind.data).length, 7);
    expect(s.layoutsOf(PrintDocType.ledger).first.id, 'builtin-ledger');
    expect(const DateFilter(from: null, to: null).isEmpty, isTrue);
    expect(DateFilter(from: DateTime(2025, 1, 2)).hasDate(DateTime(2025, 1, 1)), isFalse);
  });

  testWidgets('accounts selector and account ledger windows', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Reza');
    s.upsertPerson(p);
    final prod = Product(id: newId(), name: 'Cable', sellPrice: 50, openingQty: 5);
    s.upsertProduct(prod);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 3, date: DateTime.now(), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 50)]));
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    showAccountSelector(tester.element(find.text('خرید و فروش').first));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب دفتر تفصیلی'), findsOneWidget);
    expect(find.text('Reza'), findsOneWidget);
    expect(find.text(groupDigits(100)), findsWidgets); // جمع کل بدهی on the blue bar
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Reza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('رویت حساب'));
    await tester.pumpAndSettle();
    expect(find.textContaining('مشاهده اسناد'), findsOneWidget);
    expect(find.text('بد'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('محدوده تاریخی'));
    await tester.pumpAndSettle();
    expect(find.text('فیلتر تاریخ سند'), findsOneWidget);
    await tester.tap(find.text('از ابتدا تا انتها'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('گزینه های جستجو'));
    await tester.pumpAndSettle();
    expect(find.text('جستجو بر اساس:'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'فاکتور');
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // مشخصه filter and cost centers
    await tester.tap(find.text('فیلتر مرکز هزینه(رکورد)'));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب مرکز هزینه(رکورد)'), findsOneWidget);
    await tester.tap(find.text('بازگشت').last);
    await tester.pumpAndSettle();
    // چاپ ▸ نمایش ▸ پرینت حساب opens the band report preview
    await tester.tap(find.text('چاپ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نمایش  ◂'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('پرینت حساب با منقول جدیداز قبل'));
    await tester.pumpAndSettle();
    expect(find.text('Report-Preview'), findsOneWidget);
    expect(find.textContaining('منقول از قبل'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بازگشت').last);
    await tester.pumpAndSettle();
    // other groups render too
    await tester.tap(find.text('صندوق').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('سایر کل ها F8'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('recycle bin keeps deleted documents and restores them', () {
    final s = _tempStore();
    final p = Person(id: newId(), name: 'Ali');
    s.upsertPerson(p);
    final prod = Product(id: newId(), name: 'Cable', sellPrice: 50, openingQty: 5);
    s.upsertProduct(prod);
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 9, date: DateTime(2025, 2, 2), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 2, unitPrice: 50)]);
    s.saveInvoice(inv);
    s.removeInvoice(inv.id);
    expect(s.invoices, isEmpty);
    expect(s.recycle.length, 1);
    expect(s.restoreRecycled(s.recycle.first.id), isNull);
    expect(s.invoices.length, 1);
    expect(s.recycle, isEmpty);
    expect(s.stock(prod.id), 3);
    // permanent delete
    s.removeInvoice(inv.id);
    s.clearRecycle();
    expect(s.recycle, isEmpty);
    // user ledgers
    final code = s.addMoeen('11', 'وام کارکنان');
    expect(code, '1101');
    expect(findMoeen(code)?.name, 'وام کارکنان');
    expect(s.editMoeen(mCash, name: 'x'), isNotNull);
    expect(s.editMoeen(code, remove: true), isNull);
    expect(findMoeen(code), isNull);
  });

  test('financial books: create, copy master data and carry balances', () {
    final dir = Directory.systemTemp.createTempSync('books');
    final reg = BookRegistry(dir);
    expect(reg.active.length, 1);
    final main = reg.open('main');
    main.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Reza');
    main.upsertPerson(p);
    final prod = Product(id: newId(), name: 'Cable', sellPrice: 50, buyPrice: 30, openingQty: 4);
    main.upsertProduct(prod);
    main.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime.now(), personId: p.id,
        lines: [InvoiceLine(productId: prod.id, qty: 1, unitPrice: 50)]));
    final b = reg.create(BookInfo(id: '', title: 'دفتر مالی ۱۴۰۶'), main, copyOf: main);
    expect(reg.active.length, 2);
    final nb = reg.open(b.id);
    expect(nb.people.length, 1);
    expect(nb.invoices, isEmpty);
    reg.transferBalances(main, b.id);
    final after = reg.open(b.id);
    expect(after.personBalance(p.id), 50);
    expect(after.stock(prod.id), 3);
    expect(BookRegistry.idOf(after.storage.dir), b.id);
    expect(BookRegistry.baseOf(after.storage.dir).path, dir.path);
  });

  testWidgets('books, reports files, center report, recycle bin and chart coding windows open', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Reza');
    s.upsertPerson(p);
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 4, date: DateTime.now(), personId: p.id,
        lines: [InvoiceLine(title: 'خدمت', qty: 1, unitPrice: 70)]);
    s.saveInvoice(inv);
    s.removeInvoice(inv.id);
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('خرید و فروش').first);
    for (final (open, title) in [
      (() => showTransferToBook(ctx), 'انتقال حسابهای دفتر به دفتر جدید'),
      (() => showBooksManager(ctx), 'مدیریت دفاتر مالی'),
      (() => showReportFiles(ctx), 'مدیریت فایل های گزارش'),
      (() => showCenterGroupReport(ctx), 'تهیه گزارش از گروه مراکز دفتر'),
      (() => showRecycleBin(ctx), 'سطل بازیافت'),
      (() => showChartCoding(ctx), 'کدبندی دفاتر کل و معین'),
    ]) {
      open();
      await tester.pumpAndSettle();
      expect(find.text(title), findsWidgets, reason: 'page: $title');
      expect(tester.takeException(), isNull, reason: 'page: $title');
      Navigator.of(tester.element(find.text(title).last)).pop();
      await tester.pumpAndSettle();
    }
    expect(s.recycle.length, 1);
  });

  test('each invoice kind keeps its own print layouts', () {
    final s = _tempStore();
    expect(s.defaultLayout(PrintDocType.invoice, variant: 'sale').id, 'builtin-invoice-sale');
    expect(s.defaultLayout(PrintDocType.invoice, variant: 'purchase').id, 'builtin-invoice-purchase');
    final buy = s.defaultLayout(PrintDocType.invoice, variant: 'purchase');
    expect(buy.items.any((i) => i.text.contains('نام فروشنده')), isTrue);
    final mine = buy.copy()
      ..id = newId()
      ..name = 'خرید من';
    s.saveLayout(mine);
    s.setDefaultLayout(mine);
    expect(s.defaultLayout(PrintDocType.invoice, variant: 'purchase').name, 'خرید من');
    expect(s.defaultLayout(PrintDocType.invoice, variant: 'sale').id, 'builtin-invoice-sale');
    expect(s.layoutsOf(PrintDocType.invoice, variant: 'proforma').length, 1);
    expect(s.layoutsOf(PrintDocType.invoice, variant: 'purchase').length, 2);
    // old shared layouts become the sale invoice's
    final legacy = defaultLayoutFor(PrintDocType.invoice)
      ..id = 'old'
      ..variant = ''
      ..name = 'قدیمی';
    final j = s.toJson();
    (j['reportLayouts'] as List).add(legacy.toJson());
    j['defaultLayouts'] = {...(j['defaultLayouts'] as Map), 'invoice': 'old'};
    final dir = Directory.systemTemp.createTempSync('lay');
    final st = Storage(dir)..save(j);
    final re = AppStore.open(st);
    expect(re.defaultLayout(PrintDocType.invoice, variant: 'sale').name, 'قدیمی');
    expect(re.defaultLayout(PrintDocType.invoice, variant: 'purchase').name, 'خرید من');
  });

  testWidgets('print forms window opens a designer per document', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    showPrintForms(tester.element(find.text('خرید و فروش').first));
    await tester.pumpAndSettle();
    expect(find.text('طراحی فرم های چاپ'), findsWidgets);
    for (final (label, title) in [
      ('فاکتور خرید', 'گزارش سازی — چاپ فاکتور (فاکتور خرید)'),
      ('پیش فاکتور', 'گزارش سازی — چاپ فاکتور (پیش فاکتور)'),
      ('گزارش حساب', 'گزارش سازی — پرینت حساب'),
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: 'page: $title');
      expect(tester.takeException(), isNull, reason: 'page: $title');
      await tester.tap(find.text('انصراف (F10)').last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('bank windows: deposit, withdraw with fee, between accounts and bank form', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final cash = s.accounts.firstWhere((a) => a.type == AccountType.cash);
    s.upsertPerson(Person(id: newId(), name: 'Reza'));
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('خرید و فروش').first);

    // bank form
    showBankDialog(ctx);
    await tester.pumpAndSettle();
    expect(find.text('اطلاعات دفتر تفصیلی بانک ها'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'ملت');
    await tester.enterText(fields.at(2), '5196043677');
    await tester.enterText(fields.at(4), 'جاری');
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    final bank = s.accounts.firstWhere((a) => a.number == '5196043677');
    expect(bank.name, 'جاری 5196043677 ملت');
    expect(int.parse(bank.info['code']!), greaterThan(7000));

    // واریز به بانک: a voucher moves the money
    showBankOpsDialog(ctx, BankOp.deposit);
    await tester.pumpAndSettle();
    expect(find.text('بانک دریافت کننده'), findsOneWidget);
    expect(find.text('خواندن از فایل اکسل'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('انصراف').last);
    await tester.pumpAndSettle();

    final before = s.balance(bank.id);
    final cashBefore = s.balance(cash.id);
    final v = Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: s.nextFixedNumber(), date: DateTime.now(), kind: 'bankDeposit', lines: [
      VoucherLine(moeen: mBank, tafsiliId: bank.id, debit: 1000),
      VoucherLine(moeen: mCash, tafsiliId: cash.id, credit: 1000),
    ], meta: {
      'babat': '',
      'rows': [
        {'to': bank.id, 'from': cash.id, 'amount': 1000, 'ref': '12', 'babat': '', 'feeCat': null, 'fee': 0},
      ],
    });
    s.saveVoucher(v);
    expect(s.balance(bank.id), before + 1000);
    expect(s.balance(cash.id), cashBefore - 1000);
    // re-open from the documents list
    showBankOpsDialog(ctx, BankOp.deposit, edit: v);
    await tester.pumpAndSettle();
    expect(find.text('1,000'), findsWidgets);
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    expect(s.vouchers.where((x) => x.kind == 'bankDeposit').length, 1);
    expect(s.balance(bank.id), before + 1000);

    // اصلاح موجودی: the wrongly entered balance is corrected from the bank form
    showBankDialog(ctx, edit: bank);
    await tester.pumpAndSettle();
    expect(find.text('موجودی اول دوره:'), findsOneWidget);
    await tester.tap(find.text('اصلاح موجودی'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('realBalance')), '5000');
    await tester.pump();
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    expect(s.balance(bank.id), 5000);
    expect(bank.opening, 4000);
    // editing the opening directly
    showBankDialog(ctx, edit: bank);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bankOpening')), '0');
    await tester.tap(find.text('تایید').last);
    await tester.pumpAndSettle();
    expect(bank.opening, 0);
    expect(s.balance(bank.id), 1000);

    for (final (op, col) in [(BankOp.withdraw, 'سرفصل هزینه کارمزد'), (BankOp.between, 'حساب پرداخت کننده')]) {
      showBankOpsDialog(ctx, op);
      await tester.pumpAndSettle();
      expect(find.text(col), findsOneWidget, reason: 'page: ${op.title}');
      expect(tester.takeException(), isNull, reason: 'page: ${op.title}');
      // the account columns pick a person in «انتخاب دفتر تفصیلی»
      await tester.tap(find.text('انتخاب شخص').first);
      await tester.pumpAndSettle();
      expect(find.text('انتخاب دفتر تفصیلی'), findsOneWidget);
      await tester.tap(find.text('Reza'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تایید').last);
      await tester.pumpAndSettle();
      expect(find.text('Reza'), findsOneWidget, reason: 'page: ${op.title}');
      await tester.tap(find.text('انصراف').last);
      await tester.pumpAndSettle();
    }
  });
  // ------------------------------------------------------------ Sakan libraries

  test('xlsx export round-trips through the reader', () {
    final bytes = buildXlsx([
      XlsxSheet('گزارش', ['نام', 'مبلغ', 'کد'], [
        ['علی & <رضا>', '1,250,000', '0912'],
        ['مریم', '-۳۵۰', '7001'],
      ], titleLines: ['عنوان گزارش']),
    ]);
    final rows = readXlsx(bytes);
    expect(rows[0], ['عنوان گزارش']);
    expect(rows[2], ['نام', 'مبلغ', 'کد']);
    expect(rows[3], ['علی & <رضا>', '1250000', '0912']);
    expect(rows[4], ['مریم', '-350', '7001']);
    expect(xlsxNumber('0912'), isNull);
    expect(xlsxNumber('12,500'), 12500);
  });

  test('store writes .xlsx exports', () {
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final path = s.exportTableXlsx(['a', 'b'], [
      ['x', '10'],
    ], name: 'unit-test');
    expect(path.endsWith('.xlsx'), isTrue);
    final rows = readXlsx(File(path).readAsBytesSync());
    expect(rows.last, ['x', '10']);
    File(path).deleteSync();
  });

  test('QR codes are generated for Persian text', () {
    final m = qrMatrix('فاکتور ۱۲ — 1,250,000');
    expect(m, isNotNull);
    expect(m!.length, greaterThanOrEqualTo(21));
    expect(qrSvg('abc'), contains('<svg'));
    expect(qrSvg(''), isEmpty);
    final it = RItem(id: 'q', kind: 'qr', band: BandKind.header, x: 1, y: 1, w: 20, h: 20, text: '{شماره فاکتور}');
    final back = RItem.fromJson(it.toJson());
    expect(back.isQr, isTrue);
  });

  test('zip backups: plain, with password, wrong password', () {
    final plain = zipBackup('{"a":1}');
    expect(zipIsEncrypted(plain), isFalse);
    expect(unzipBackup(plain), '{"a":1}');
    final locked = zipBackup('{"a":2}', password: 'secret');
    expect(zipIsEncrypted(locked), isTrue);
    expect(() => unzipBackup(locked), throwsA(isA<BackupPasswordException>()));
    expect(() => unzipBackup(locked, password: 'nope'), throwsA(isA<BackupPasswordException>()));
    expect(unzipBackup(locked, password: 'secret'), '{"a":2}');
  });

  test('store backup is a zip and restores', () {
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    s.upsertPerson(Person(id: newId(), name: 'Reza'));
    s.settings.backupPassword = 'p1';
    final path = s.exportBackup();
    expect(path.endsWith('.zip'), isTrue);
    final t = _tempStore();
    t.completeSetup(ownerName: 'Other');
    expect(() => t.importBackup(path), throwsA(isA<BackupPasswordException>()));
    t.importBackup(path, password: 'p1');
    expect(t.people.any((p) => p.name == 'Reza'), isTrue);
    expect(s.availableBackups().any((f) => f.path == path), isTrue);
    File(path).deleteSync();
  });

  test('sms helpers: mobile numbers, templates and parts', () {
    expect(normalizeMobile('+98 912 123 4567'), '09121234567');
    expect(normalizeMobile('۰۹۱۲۱۲۳۴۵۶۷'), '09121234567');
    expect(normalizeMobile('9121234567'), '09121234567');
    expect(normalizeMobile('021-88776655'), '');
    expect(fillSms('{نام} - {مانده} {x}', {'نام': 'علی', 'مانده': '10'}), 'علی - 10 {x}');
    expect(smsParts('سلام'), 1);
    expect(smsParts('س' * 71), 2);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final p = Person(id: newId(), name: 'Reza', phone: '09121234567');
    s.upsertPerson(p);
    final txt = debtSmsText(s, p);
    expect(txt, contains('Reza'));
    expect(s.settings.sms.configured, isFalse);
    final cfg = SmsConfig.fromJson((SmsConfig()
          ..provider = SmsProvider.melipayamak
          ..username = 'u'
          ..password = 'p'
          ..sender = '3000')
        .toJson());
    expect(cfg.configured, isTrue);
    expect(cfg.provider, SmsProvider.melipayamak);
  });

  testWidgets('SMS window opens with all tabs', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    s.upsertPerson(Person(id: newId(), name: 'Reza', phone: '09121234567'));
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('خرید و فروش').first);
    showSmsWindow(ctx);
    await tester.pumpAndSettle();
    expect(find.text('Reza'), findsWidgets);
    for (final t in ['یادآوری سررسید چک', 'پیام‌های ارسالی', 'تنظیمات پنل پیامک']) {
      await tester.tap(find.text(t));
      await tester.pumpAndSettle();
    }
    expect(find.text('متن پیامک فاکتور'), findsOneWidget);
    await tester.tap(find.text('ذخیره تنظیمات (Ctrl+S)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('report preview renders a QR element', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    final l = defaultInvoiceLayout()
      ..items.add(RItem(id: 'qr1', kind: 'qr', band: BandKind.header, x: 20, y: 7, w: 20, h: 20, text: '{شماره فاکتور}'));
    const d = ReportData(fields: {'شماره فاکتور': '12'}, rows: [], title: 't');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: reportPages(l, d, 3))))));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is QrPainter), findsOneWidget);
    expect(reportHtml(l, d), contains('<svg'));
  });
  test('Sakan .mrt report files import as band layouts', () {
    String text(String name, String rect, String t, {String extra = ''}) =>
        '<$name Ref="9" type="Text" isKey="true"><Border>All;Black;1;Solid;False;4;Black</Border><Brush>Gainsboro</Brush>'
        '<ClientRectangle>$rect</ClientRectangle><Font>David,12,Bold</Font><Text>$t</Text>$extra</$name>';
    String band(String name, String type, String rect, String comps) =>
        '<$name Ref="5" type="$type" isKey="true"><ClientRectangle>$rect</ClientRectangle>'
        '<Components isList="true" count="1">$comps</Components></$name>';
    final xml = '﻿<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
        '<StiSerializer version="1.0" application="StiReport"><Pages isList="true" count="1"><Page1 Ref="2" type="Page" isKey="true">'
        '<Components isList="true" count="6">'
        '${band('ReportTitle1', 'ReportTitleBand', '0,0.4,19,2', text('T1', '5,0.5,8,1', 'فاکتور {PrintInfoFrosh.ShFactor} &amp; {PrintInfoFrosh.Foo}', extra: '<HorAlignment>Center</HorAlignment>'))}'
        '${band('Header1', 'HeaderBand', '0,3,19,0.8', text('T2', '0,0,19,0.8', 'شرح'))}'
        '${band('Data1', 'DataBand', '0,4.2,19,0.6', text('T3', '17,0,2,0.6', '{Line}') + text('T4', '0,0,4,0.6', '{PrintKalaFrosh.Jam1System}', extra: '<TextOptions>RightToLeft=True, Angle=0</TextOptions>'))}'
        '${band('Footer1', 'FooterBand', '0,5.2,19,1', text('T5', '0,0,19,1', '{Farsi.BeHorof(PrintInfoFrosh.JamFator_system)}'))}'
        '${band('PageFooter1', 'PageFooterBand', '0,27,19,0.8', text('T6', '0,0,3,0.8', '{PageNofM}'))}'
        '<Rectangle1 Ref="20" type="Stimulsoft.Report.Components.StiRectanglePrimitive" isKey="true"><ClientRectangle>0,0.4,19,1.5</ClientRectangle></Rectangle1>'
        '</Components><Margins>1,1,1,1</Margins><PageHeight>29.7</PageHeight><PageWidth>21</PageWidth></Page1></Pages>'
        '<ReportUnit>Centimeters</ReportUnit></StiSerializer>';
    final r = importMrt(xml, type: PrintDocType.invoice, variant: 'sale', name: 'فروش');
    final l = r.layout;
    expect(l.pageW, closeTo(210, 0.01));
    expect(l.margin, closeTo(10, 0.01));
    expect(l.heightOf(BandKind.header), closeTo(20, 0.01));
    expect(l.heightOf(BandKind.columns), closeTo(8, 0.01));
    expect(l.heightOf(BandKind.data), closeTo(6, 0.01));
    expect(l.heightOf(BandKind.footer1), closeTo(10, 0.01));
    expect(l.heightOf(BandKind.footer2), closeTo(8, 0.01));
    final title = l.itemsOf(BandKind.header).firstWhere((i) => i.text.contains('فاکتور'));
    expect(title.text, 'فاکتور {شماره فاکتور} &');
    expect(title.x, closeTo(50, 0.01));
    expect(title.align, 'center');
    expect(title.bold, isTrue);
    expect(title.border, Sides.all);
    expect(title.fill, isNot(0));
    expect(l.itemsOf(BandKind.data).map((i) => i.text), containsAll(['{ردیف}', '{جمع بدون تخفیف}']));
    expect(l.itemsOf(BandKind.data).firstWhere((i) => i.text == '{جمع بدون تخفیف}').align, 'right');
    expect(l.itemsOf(BandKind.footer1).single.text, '{مبلغ به حروف}');
    expect(l.itemsOf(BandKind.footer2).single.text, '{صفحه}');
    // the page-level frame lands in the header band
    expect(l.itemsOf(BandKind.header).where((i) => i.text.isEmpty && i.border == Sides.all), hasLength(1));
    expect(r.unknownFields, ['PrintInfoFrosh.Foo']);
    expect(mapSakanExpression('Sum(PrintKalaFrosh.TedadVahed1)', PrintDocType.invoice), '{جمع اقلام}');
    expect(mapSakanExpression('BookMoein.Bed', PrintDocType.ledger), '{بدهکار}');
    expect(() => importMrt('<html/>', type: PrintDocType.invoice), throwsFormatException);
    // round trip through JSON
    expect(ReportLayout.fromJson(l.toJson()).items.length, l.items.length);
  });

  test('old 5-digit ledger codes are converted to Sakan codes on load', () {
    final dir = Directory.systemTemp.createTempSync('taraz_mig');
    final st = Storage(dir);
    st.save({
      'app': 'taraz',
      'version': 1,
      'accounts': [],
      'txns': [],
      'customMoeens': {'10704': 'وام کارکنان'},
      'hiddenMoeens': ['50107'],
      'vouchers': [
        {
          'id': 'v1',
          'number': 1,
          'date': '2026-10-01',
          'lines': [
            {'moeen': '10102', 'debit': 100, 'credit': 0},
            {'moeen': '20201', 'debit': 0, 'credit': 60},
            {'moeen': '10704', 'debit': 0, 'credit': 40},
          ],
        },
      ],
      'settings': {
        'openingOther': {'20601': 500, '40104': 30},
      },
    });
    final s = AppStore.open(st);
    final codes = s.vouchers.single.lines.map((l) => l.moeen).toList();
    expect(codes.take(2), [mCash, mDebtorsTrade]);
    expect(findMoeen(codes[2])?.name, 'وام کارکنان');
    expect(codes[2], '1101');
    expect(s.hiddenMoeens, {mDepreciation});
    expect(s.settings.openingOther[mLoans], 500);
    // «برگشت از فروش» moved from the income side to Sakan's 5055 (debit nature)
    expect(s.settings.openingOther[mSalesReturn], -30);
    expect(File('${dir.path}${Storage.sep}backups${Storage.sep}before-sakan-codes.json').existsSync(), isTrue);
    expect(AppStore.open(st).vouchers.single.lines.first.moeen, mCash);
  });

  test('Sakan invoice type codes', () {
    expect(InvoiceKind.sale.sakanCode, 2);
    expect(InvoiceKind.purchase.sakanCode, 4);
    expect(InvoiceKind.purchaseReturn.sakanCode, 6);
    expect(InvoiceKind.saleReturn.sakanCode, 8);
    final pro = Invoice(id: 'x', kind: InvoiceKind.sale, number: 1, date: DateTime(2026), proforma: true);
    expect(pro.sakanType, 7);
    expect(pro.sakanTypeName, 'پیش فاکتور');
  });

  test('Sakan counting units: rows in unit 2, stock in unit 1', () {
    final s = _tempStore();
    final pr = Product(id: newId(), name: 'Cable', unit: 'عدد', unit2: 'کارتن', ratio2: 24, unit3: 'متر', ratio3: 2, defaultUnit: 2);
    s.upsertProduct(pr);
    expect(pr.unitFactor(2), 24);
    expect(pr.unitFactor(3), 0.5);
    expect(s.units.map((u) => u.name), containsAll(['عدد', 'کارتن', 'متر']));

    // 2 cartons at 240,000 per carton = 48 pieces at 10,000
    final l = InvoiceLine.inUnit(productId: pr.id, unit: 2, factor: 24, qty: 2, fi: 240000);
    expect(l.qty, 48);
    expect(l.unitPrice, 10000);
    expect(l.total, 480000);
    expect(l.shownQty, 2);
    expect(l.shownFi, 240000);
    final back = InvoiceLine.fromJson(l.toJson());
    expect(back.unitNo, 2);
    expect(back.total, 480000);

    // a price that does not divide evenly keeps the exact total
    final odd = InvoiceLine.inUnit(productId: pr.id, unit: 2, factor: 24, qty: 1, fi: 1000000);
    expect(odd.total, 1000000);

    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 9, 1), lines: [l]));
    expect(s.stock(pr.id), 48);
    expect(fmtStock(pr, 48), '48 عدد (2 کارتن)');

    // renaming a unit renames it on products; used units are not removed
    final carton = s.units.firstWhere((u) => u.name == 'کارتن');
    expect(s.saveUnit(CountUnit(id: carton.id, name: 'جعبه'), oldName: 'کارتن'), isNull);
    expect(s.product(pr.id)!.unit2, 'جعبه');
    expect(s.removeUnit(s.units.firstWhere((u) => u.name == 'جعبه')), isNotNull);
    expect(s.saveUnit(CountUnit(id: newId(), name: 'عدد')), isNotNull);
  });

  test('امانی: receive on consignment, return part, settle the rest by purchase', () {
    final s = _tempStore();
    final sup = Person(id: newId(), name: 'Supplier');
    s.upsertPerson(sup);
    final pr = Product(id: newId(), name: 'Headset');
    s.upsertProduct(pr);
    final line = ConsignLine(id: newId(), productId: pr.id, qty: 10, fi: 100);
    final c = Consignment(id: newId(), dir: ConsignDir.received, number: s.nextConsignNumber(ConsignDir.received), date: DateTime(2026, 9, 1), personId: sup.id, lines: [line]);
    expect(s.saveConsignment(c), isNull);
    // ownership does not change
    expect(s.stock(pr.id), 0);
    expect(s.consignOpen(pr.id, ConsignDir.received), 10);

    // «تسویه انبار»: 3 returned
    expect(s.addConsignReturn(line.id, 20, DateTime(2026, 9, 5)), isNotNull);
    expect(s.addConsignReturn(line.id, 3, DateTime(2026, 9, 5)), isNull);
    expect(s.consignRemaining(c, line), 7);

    // «تسویه کل»: 5 bought through a purchase invoice
    final inv = Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 9, 10), personId: sup.id,
        lines: [InvoiceLine(productId: pr.id, qty: 5, unitPrice: 100, consignRef: line.id)]);
    s.saveInvoice(inv);
    expect(s.stock(pr.id), 5);
    expect(s.consignRemaining(c, line), 2);
    expect(InvoiceLine.fromJson(inv.lines.first.toJson()).consignRef, line.id);

    // memo accounts hold the open value (2 × 100) and the journal balances
    final j = buildJournal(s);
    int bal(String m) => j.where((p) => p.moeen == m).fold<int>(0, (a, p) => a + p.debit - p.credit);
    expect(bal('1250'), 200);
    expect(bal('1260'), -200);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));

    // settled documents are protected; deleting the invoice re-opens them
    expect(s.removeConsignment(c.id), isNotNull);
    expect(s.saveConsignment(Consignment(id: c.id, dir: c.dir, number: c.number, date: c.date, personId: sup.id,
        lines: [ConsignLine(id: line.id, productId: pr.id, qty: 6, fi: 100)])), isNotNull);
    s.removeInvoice(inv.id);
    expect(s.consignRemaining(c, line), 7);

    final again = AppStore.open(s.storage);
    expect(again.consignments.single.returns.single.qty, 3);
  });

  test('بازاریابان: commission by percent, amount and product percent', () {
    final s = _tempStore();
    final buyer = Person(id: newId(), name: 'Buyer');
    final m1 = Person(id: newId(), name: 'Reza', marketer: true, marketerPct: 5);
    final m2 = Person(id: newId(), name: 'Sara', marketer: true);
    for (final p in [buyer, m1, m2]) {
      s.upsertPerson(p);
    }
    final pr = Product(id: newId(), name: 'Phone', info: {'marketingPct': '2'});
    s.upsertProduct(pr);
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 10, 1), personId: buyer.id,
        lines: [InvoiceLine(productId: pr.id, qty: 2, unitPrice: 50000)],
        marketers: [MarketerShare(personId: m1.id, pct: 5), MarketerShare(personId: m2.id)]);
    s.saveInvoice(inv);
    final c = s.commissions(inv);
    expect(c[0].$3, 5000); // 5% of 100,000
    expect(c[1].$3, 2000); // product «درصد بازاریابی» 2%
    expect(s.commissionTotal(inv), 7000);
    expect(s.marketers.length, 2);
    // the marketers are owed their shares; the journal agrees and balances
    expect(s.personBalance(m1.id), -5000);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    expect(j.where((p) => p.moeen == mDebtorsTrade && p.tafsiliId == m1.id).fold<int>(0, (a, p) => a + p.debit - p.credit), -5000);
    expect(j.where((p) => p.moeen == '5010').fold<int>(0, (a, p) => a + p.debit), 7000);
    expect(s.commissionReport(DateTime(2026), DateTime(2027)).length, 2);
    expect(s.salesByMarketer(DateTime(2026), DateTime(2027), monthly: true).first.net, 100000);
    expect(Invoice.fromJson(inv.toJson()).marketers.length, 2);
    // without «پورسانت بعنوان هزینه» nothing is posted
    s.updateSettings((x) => x.commissionExpense = false);
    expect(s.personBalance(m1.id), 0);
  });

  test('حقوق و دستمزد: payslip, insurance, tax, loan and the payroll voucher', () {
    final rules = PayrollRules();
    expect(rules.tax(24000000), 0);
    expect(rules.tax(30000000), 600000); // 6M × 10%
    expect(rules.tax(40000000), 600000 + 1200000 + 400000); // 10% of 6M, 15% of 8M, 20% of 2M

    final s = _tempStore();
    final cash = s.accounts.first;
    final e = Employee(id: newId(), personId: '', firstName: 'Ali', lastName: 'Rezaei', personnelCode: '1001', monthlyWage: 30000000,
        benefits: [PayItem2(name: 'حق مسکن', amount: 3000000), PayItem2(name: 'بن', amount: 2000000, insured: false)]);
    expect(s.saveEmployee(e), isNull);
    expect(s.person(e.personId)?.name, 'Ali Rezaei');
    final p = s.addPayPeriod(1405, 7); // مهر — 30 days
    expect(p.days, 30);
    expect(s.employeesIn(p).length, 1);

    s.saveStaffLoan(StaffLoan(id: newId(), employeeId: e.id, date: p.start.subtract(const Duration(days: 5)), amount: 3000000, installments: 3, accountId: cash.id));
    final slip = s.payslipOf(p, e)
      ..overtimeHours = 10
      ..advance = 1000000;
    s.savePayslip(slip);
    s.saveLeave(Leave(id: newId(), employeeId: e.id, kind: LeaveKind.unpaid, start: p.start.add(const Duration(days: 3)), end: p.start.add(const Duration(days: 3)), days: 2));

    final r = s.payResult(p, e);
    expect(r.workDays, 28);
    expect(r.hoghoghMahiane, 28000000);
    expect(r.ezafeKari, (10 * 30000000 / 220 * 1.4).round());
    expect(r.dastmozdMashmoolBime, 28000000 + 2800000 + r.ezafeKari); // بن is not insured
    expect(r.bimeSahmBimeShode, (r.dastmozdMashmoolBime * 0.07).round());
    expect(r.vam, 1000000);
    expect(r.mosaede, 1000000);
    expect(r.khales, r.jamKol - r.bimeSahmBimeShode - r.maliat - r.vam - r.mosaede);

    final v = s.postPayroll(p);
    expect(v.totalDebit, v.totalCredit);
    expect(s.postPayroll(p).id, v.id); // re-posting replaces
    expect(s.vouchers.where((x) => x.kind == 'payroll').length, 1);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, x) => a + x.debit), j.fold<int>(0, (a, x) => a + x.credit));
    // employee: loan 3M owed, then salary credited (net + advance) and 1M installment repaid
    expect(s.personBalance(e.personId), 3000000 - (r.khales + r.mosaede) - r.vam);
    expect(s.loanRemaining(e), 2000000);
    expect(s.leaveBalance(e, 1405).$1, 26);
    expect(s.removePayPeriod(p.id), isNotNull);

    final again = AppStore.open(s.storage);
    expect(again.employees.single.benefits.length, 2);
    expect(again.payResult(again.payPeriods.single, again.employees.single).khales, r.khales);
  });

  testWidgets('payroll window tabs render', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _tempStore();
    s.completeSetup(ownerName: 'Ali');
    s.saveEmployee(Employee(id: newId(), personId: '', firstName: 'Sara', lastName: 'K', monthlyWage: 20000000));
    s.addPayPeriod(1405, 8);
    await tester.pumpWidget(TarazApp(store: s));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('خرید و فروش').first);
    showPayrollWindow(ctx);
    await tester.pumpAndSettle();
    for (final t in ['کارکرد و فیش حقوقی', 'مرخصی', 'ماموریت', 'وام پرسنل', 'گزارشات', 'تنظیمات', 'پرسنل']) {
      await tester.tap(find.widgetWithText(ChoiceChip, t));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: t);
    }
  });

  test('عوارض و مالیات بر اقلام: VAT in totals, journal and profit', () {
    final s = _tempStore();
    final buyer = Person(id: newId(), name: 'Buyer');
    s.upsertPerson(buyer);
    final pr = Product(id: newId(), name: 'Speaker', info: {'taxPct': '9', 'dutyPct': '1'});
    s.upsertProduct(pr);
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 10, 1), personId: buyer.id, discount: 1000,
        lines: [InvoiceLine(productId: pr.id, qty: 1, unitPrice: 11000, taxPct: 9, dutyPct: 1)]);
    s.saveInvoice(inv);
    expect(inv.netOf(inv.lines.first), 10000);
    expect(inv.taxTotal, 900);
    expect(inv.dutyTotal, 100);
    expect(inv.total, 11000);
    expect(s.personBalance(buyer.id), 11000);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    expect(j.where((p) => p.moeen == mVatPayable).fold<int>(0, (a, p) => a + p.credit - p.debit), 1000);
    expect(s.profit(DateTime(2026), DateTime(2027)).sales, 10000);
    expect(InvoiceLine.fromJson(inv.lines.first.toJson()).taxPct, 9);
  });

  test('تنظیمات فاکتور: options round-trip and price range', () {
    final o = InvoiceOptions(priceRange: true, minPct: 10, maxPct: 20, allowNegative: false);
    final b = InvoiceOptions.fromJson(o.toJson());
    expect(b.allowNegative, isFalse);
    expect(b.range(1000), (900, 1200));
    expect(InvoiceOptions().range(1000), isNull);
    final s = _tempStore();
    s.updateSettings((x) => x.saleOptions = o);
    expect(AppStore.open(s.storage).settings.saleOptions.minPct, 10);
  });

  test('ارز: currencies, foreign entries, revaluation', () {
    final s = _tempStore();
    final usd = Currency(id: newId(), name: 'دلار', sign: r'$', rate: 60000);
    expect(s.saveCurrency(usd), isNull);
    expect(s.saveCurrency(Currency(id: newId(), name: 'دلار')), isNotNull);
    final p = Person(id: newId(), name: 'Supplier', currencyId: usd.id);
    s.upsertPerson(p);
    s.saveVoucher(Voucher(id: newId(), number: 1, fixedNumber: 1, date: DateTime(2026, 9, 1), kind: 'fx', lines: [
      VoucherLine(moeen: mDebtorsFx, tafsiliId: p.id, debit: 6000000, currencyId: usd.id, fx: 100),
      VoucherLine(moeen: mCapital, credit: 6000000),
    ]));
    expect(s.fxBalances().values.single, (100.0, 6000000));
    final v = s.revalue(DateTime(2026, 10, 1), {usd.id: 70000})!;
    expect(v.totalDebit, v.totalCredit);
    expect(v.lines.firstWhere((l) => l.moeen == mFxGain).credit, 1000000);
    expect(s.fxBalances().values.single, (100.0, 7000000));
    expect(s.currency(usd.id)!.rate, 70000);
    expect(s.removeCurrency(usd.id), isNotNull);
    final again = AppStore.open(s.storage);
    expect(again.person(p.id)!.currencyId, usd.id);
    expect(again.vouchers.first.lines.first.fx, 100);
  });

  test('مدل تخفیفات، تخفیف عمومی و یارانه', () {
    final s = _tempStore();
    final pr = Product(id: newId(), name: 'Cable', sellPrice: 1000);
    final gift = Product(id: newId(), name: 'Sticker');
    s.upsertProduct(pr);
    s.upsertProduct(gift);
    // 10+ units: 5% off; 20+: 10% off and a gift
    final m = DiscountModel(id: newId(), name: 'Tiered', productId: pr.id, tiers: [
      DiscountTier(from: 10, to: 19, pct: 5),
      DiscountTier(from: 20, pct: 10, giftProductId: gift.id, giftQty: 1),
    ]);
    s.saveDiscountModel(m);
    final t = DateTime(2026, 10, 30, 12);
    expect(s.bestModel(InvoiceLine(productId: pr.id, qty: 5, unitPrice: 1000), t), isNull);
    expect(s.bestModel(InvoiceLine(productId: pr.id, qty: 12, unitPrice: 1000), t)!.$2, 600);
    final r = s.bestModel(InvoiceLine(productId: pr.id, qty: 20, unitPrice: 1000), t)!;
    expect(r.$2, 2000);
    expect(r.$4, gift.id);
    // progressive: 10% on the 10 units above 10
    m.progressive = true;
    m.tiers = [DiscountTier(from: 10, pct: 10)];
    expect(s.bestModel(InvoiceLine(productId: pr.id, qty: 20, unitPrice: 1000), t)!.$2, 1000);
    // weekday / date limits
    m.weekdays = {DateTime.monday};
    expect(s.bestModel(InvoiceLine(productId: pr.id, qty: 20, unitPrice: 1000), t), isNull); // 30 Oct 2026 is a Friday
    expect(DiscountModel.fromJson(m.toJson()).weekdays, {DateTime.monday});

    s.saveAmountDiscounts([AmountDiscount(id: newId(), name: 'Big', fromAmount: 100000, pct: 3)]);
    expect(s.amountDiscountFor(50000, null), isNull);
    expect(s.amountDiscountFor(200000, null)!.$1, 3);

    // subsidy: 40% of the row is paid by the insurer
    final buyer = Person(id: newId(), name: 'Buyer');
    final ins = Person(id: newId(), name: 'Insurer');
    s.upsertPerson(buyer);
    s.upsertPerson(ins);
    s.saveSubsidyGroup(SubsidyGroup(id: newId(), name: 'Drugs', pct: 40, personId: ins.id));
    final inv = Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: t, personId: buyer.id, info: {'subsidyAcc': ins.id},
        lines: [InvoiceLine(productId: pr.id, qty: 10, unitPrice: 1000, subsidyPct: 40)]);
    s.saveInvoice(inv);
    expect(inv.subsidyTotal, 4000);
    expect(s.personBalance(buyer.id), 6000);
    expect(s.personBalance(ins.id), 4000);
    s.saveInvoice(inv);
    expect(s.vouchers.where((v) => v.kind == 'subsidy').length, 1);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    s.removeInvoice(inv.id);
    expect(s.vouchers.where((v) => v.kind == 'subsidy'), isEmpty);
  });

  test('orders quota, cost adjust, book centers and hidden buttons', () {
    final s = _tempStore();
    final pr = Product(id: newId(), name: 'Rice', info: {'dailyQuota': '10', 'dailyQuotaControl': '1'});
    s.upsertProduct(pr);
    final t = DateTime(2026, 10, 30);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: t, lines: [InvoiceLine(productId: pr.id, qty: 10, unitPrice: 1000)]));
    expect(s.avgCost(pr.id), 1000);

    // «تعیین سفارش روزانه»
    final o1 = Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: t, proforma: true, lines: [InvoiceLine(productId: pr.id, qty: 7, unitPrice: 1500)]);
    s.saveInvoice(o1);
    expect(checkDailyQuota(s, t, null, [(pr.id, 3)]), isNull);
    expect(checkDailyQuota(s, t, null, [(pr.id, 4)]), isNotNull);
    expect(checkDailyQuota(s, t, o1.id, [(pr.id, 10)]), isNull); // editing the same order
    expect(checkDailyQuota(s, t.add(const Duration(days: 1)), null, [(pr.id, 10)]), isNull);

    // «اعمال افزایش در قیمت تمام شده کالا»: +5000 over 10 units → 1500
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: s.nextFixedNumber(), date: t, kind: 'costAdjust', lines: [
      VoucherLine(moeen: mStock, tafsiliId: pr.id, debit: 5000),
      VoucherLine(moeen: mOtherExpense, credit: 5000),
    ]));
    expect(s.avgCost(pr.id), 1500);

    // «مرکز دفاتر»
    final c = BookCenter(id: newId(), name: 'Shop', members: ['$mStock|${pr.id}']);
    s.bookCenters.add(c);
    s.centerGroups.add(CenterGroup(id: newId(), name: 'All', centerIds: [c.id]));
    s.updateSettings((_) {});
    expect(centerBalance(s, c, buildJournal(s)), 15000);
    final again = AppStore.open(s.storage);
    expect(again.bookCenters.single.members, c.members);
    expect(again.centerGroups.single.centerIds, [c.id]);

    // «تنظیم دکمه‌ها»
    expect(s.canUse('سفارشات'), isTrue);
    s.setHiddenButtons({'سفارشات'});
    expect(s.canUse('سفارشات'), isFalse);
    expect(AppStore.open(s.storage).hiddenButtons, {'سفارشات'});
  });

  test('woocommerce orders become sale invoices', () {
    final s = _tempStore();
    final acc = s.activeAccounts.first;
    final pr = Product(id: newId(), name: 'Mug', code: 'MUG-1');
    s.upsertProduct(pr);
    final old = Person(id: newId(), name: 'Old name', phone: '0912 123 4567');
    s.upsertPerson(old);
    s.woo = WooConfig(url: 'shop.test/', key: 'ck', secret: 'cs', factor: 10, payAccounts: {'zarinpal': acc.id});
    expect(wooUri(s.woo, 'orders', {'page': '1'}).toString(), 'https://shop.test/wp-json/wc/v3/orders?page=1');
    final api = {
      'id': 77,
      'number': '77',
      'status': 'processing',
      'date_created': '2026-10-29T10:00:00',
      'total': '23000',
      'shipping_total': '5000',
      'discount_total': '2000',
      'total_tax': '0',
      'payment_method': 'zarinpal',
      'payment_method_title': 'زرین پال',
      'billing': {'first_name': 'Ali', 'last_name': 'R', 'phone': '+98۹۱۲۱۲۳۴۵۶۷', 'city': 'Tehran', 'address_1': 'St 1'},
      'shipping': {'first_name': '', 'last_name': ''},
      'line_items': [
        {'name': 'Mug', 'sku': 'MUG-1', 'quantity': 2, 'price': 5000, 'subtotal': '10000', 'total': '9000'},
        {'name': 'Gift wrap', 'sku': '', 'quantity': 1, 'price': 10000, 'subtotal': '10000', 'total': '9000'},
      ],
    };
    final o = WooOrder.fromApi(api);
    expect(o.items.length, 2);
    expect(o.recipient, 'Ali R');
    expect(mergeWooOrders(s, [o]), 1);
    expect(mergeWooOrders(s, [WooOrder.fromApi(api)]), 0);
    final inv = wooToInvoice(s, s.wooOrders.single);
    expect(inv.personId, old.id); // matched by phone
    expect(inv.lines.first.productId, pr.id);
    expect(inv.lines.last.productId, isNull);
    expect(inv.total, 230000); // toman ×10
    expect(inv.extra, 50000);
    expect(inv.discount, 20000);
    expect(s.personBalance(old.id), 0); // paid through the mapped account
    expect(s.wooOrders.single.invoiceId, inv.id);
    expect(AppStore.open(s.storage).wooOrders.single.invoiceId, inv.id);
    s.removeInvoice(inv.id);
    expect(s.wooOrders.single.invoiceId, isNull);
  });

  test('production consumes materials and builds cost', () {
    final s = _tempStore();
    final flour = Product(id: newId(), name: 'Flour', unit: 'kg');
    final sugar = Product(id: newId(), name: 'Sugar', unit: 'kg');
    final cake = Product(id: newId(), name: 'Cake');
    for (final p in [flour, sugar, cake]) {
      s.upsertProduct(p);
    }
    final t = DateTime(2026, 10, 1);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: t, lines: [
      InvoiceLine(productId: flour.id, qty: 10, unitPrice: 2000),
      InvoiceLine(productId: sugar.id, qty: 5, unitPrice: 4000),
    ]));
    final f = ProductionFormula(id: newId(), name: 'Cake', productId: cake.id, yieldQty: 2, overhead: 1000, lines: [
      ProductionLine(productId: flour.id, qty: 1),
      ProductionLine(productId: sugar.id, qty: 0.5),
    ]);
    s.saveFormula(f);
    expect(s.estimateProduction(f, 4), (8000, 2000)); // 2kg flour + 1kg sugar
    final pr = Production(id: newId(), number: s.nextProductionNumber(), date: t, productId: cake.id, qty: 4, lines: f.scaled(4), overhead: f.overheadFor(4));
    s.saveProduction(pr);
    expect(s.stock(flour.id), 8);
    expect(s.stock(sugar.id), 4);
    expect(s.stock(cake.id), 4);
    expect(s.avgCost(cake.id), 2500);
    expect(s.avgCost(flour.id), 2000);
    final j = buildJournal(s);
    expect(j.fold<int>(0, (a, p) => a + p.debit), j.fold<int>(0, (a, p) => a + p.credit));
    int bal(String? t) => j.where((p) => p.moeen == mStock && p.tafsiliId == t).fold(0, (a, p) => a + p.debit - p.credit);
    expect(bal(cake.id), 10000);
    expect(bal(flour.id), 16000);
    expect(j.where((p) => p.moeen == mAbsorbedOverhead).fold<int>(0, (a, p) => a + p.credit), 2000);
    // re-saving does not duplicate stock movements
    s.saveProduction(pr);
    expect(s.stock(cake.id), 4);
    expect(AppStore.open(s.storage).productions.single.totalCost, 10000);
    s.removeProduction(pr.id);
    expect(s.stock(flour.id), 10);
    expect(s.stock(cake.id), 0);
  });

  test('guarantee documents post to memo accounts until returned', () {
    final s = _tempStore();
    final p = Person(id: newId(), name: 'Contractor');
    s.upsertPerson(p);
    final it1 = GuaranteeItem(id: newId(), kind: GuaranteeKind.safte, serial: '123', amount: 5000000);
    final it2 = GuaranteeItem(id: newId(), kind: GuaranteeKind.zemanat, serial: 'Z9', amount: 2000000);
    s.saveGuarantee(GuaranteeDoc(id: newId(), number: s.nextGuaranteeNumber(), date: DateTime(2026, 10, 1), personId: p.id, items: [it1, it2]));
    int memo() => buildJournal(s).where((x) => x.moeen == '1250').fold(0, (a, x) => a + x.debit - x.credit);
    expect(memo(), 7000000);
    s.returnGuarantee(it1, DateTime(2026, 10, 20));
    expect(memo(), 2000000);
    expect(s.personBalance(p.id), 0);
    final again = AppStore.open(s.storage);
    expect(again.guarantees.single.items.first.returnedOn, DateTime(2026, 10, 20));
    expect(again.guarantees.single.openTotal, 2000000);
    expect(s.nextGuaranteeNumber(), 2);
  });

  test('warranty and repair reception', () {
    final s = _tempStore();
    final c = Person(id: newId(), name: 'Customer');
    s.upsertPerson(c);
    final w = Warranty(id: newId(), code: s.nextWarrantyCode(), productName: 'Phone', serial: 'SN1', start: DateTime(2026, 1, 1), end: DateTime(2026, 12, 31), personId: c.id);
    s.saveWarranty(w);
    expect(w.activeAt(DateTime(2026, 10, 30)), isTrue);
    expect(w.activeAt(DateTime(2027, 1, 1)), isFalse);
    w.events.add(WarrantyEvent(date: DateTime(2026, 5, 1), kind: 'تعویض', newSerial: 'SN2'));
    s.saveWarranty(w);
    expect(s.findWarranty('SN2')?.id, w.id);
    expect(s.findWarranty('SN1')?.id, w.id);
    expect(s.findWarranty('${w.code}')?.id, w.id);

    final r = Reception(id: newId(), number: s.nextReceptionNumber(), date: DateTime(2026, 10, 30), personId: c.id, productName: 'Phone', serial: 'SN2', warrantyCode: w.code, problem: 'Screen', cost: 500000);
    s.saveReception(r);
    final inv = s.receptionInvoice(r);
    expect(inv.total, 500000);
    expect(s.personBalance(c.id), 500000);
    r.cost = 600000;
    expect(s.receptionInvoice(r).id, inv.id); // re-issuing updates the same invoice
    expect(s.personBalance(c.id), 600000);
    final again = AppStore.open(s.storage);
    expect(again.receptions.single.invoiceId, inv.id);
    expect(again.warranties.single.currentSerial, 'SN2');
    s.removeInvoice(inv.id);
    expect(s.receptions.single.invoiceId, isNull);
  });

  test('restaurant tab: kitchen rows, settle with service, recipe assembly', () {
    final s = _tempStore();
    final bread = Product(id: newId(), name: 'Bread');
    final burger = Product(id: newId(), name: 'Burger', sellPrice: 100000, info: {'restaurant': '1'});
    s.upsertProduct(bread);
    s.upsertProduct(burger);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 10, 1), lines: [InvoiceLine(productId: bread.id, qty: 10, unitPrice: 5000)]));
    s.saveFormula(ProductionFormula(id: newId(), name: 'Burger', productId: burger.id, lines: [ProductionLine(productId: bread.id, qty: 1)]));
    final table = RestTable(id: newId(), number: s.nextTableNumber());
    s.restTables.add(table);
    s.restConfig = RestConfig(servicePct: 10, accountId: s.activeAccounts.first.id);
    final tab = RestTab(id: newId(), tableId: table.id, opened: DateTime.now(), lines: [TabLine(productId: burger.id, qty: 2, price: 100000)]);
    s.saveTab(tab);
    expect(s.tabOfTable(table.id)?.id, tab.id);
    expect(s.takeKitchenRows(tab).single.$2, 2);
    expect(s.takeKitchenRows(tab), isEmpty);
    tab.lines.single.qty = 3;
    expect(s.takeKitchenRows(tab).single.$2, 1);
    final inv = s.settleTab(tab);
    expect(inv.total, 330000);
    expect(inv.paid, 330000);
    expect(inv.info['desk'], '1');
    expect(s.tabOfTable(table.id), isNull);
    expect(s.stock(bread.id), 7);
    expect(s.stock(burger.id), 0);
    expect(AppStore.open(s.storage).restConfig.servicePct, 10);
  });

  test('iran system encoding and insurance disk layout', () {
    expect(encodeIranSystem('حسین'), [0xF6, 0xFE, 0xA8, 0x9F]);
    expect(encodeIranSystem('سردار نژاد'), [0xA2, 0x90, 0xA6, 0xF7, 0x20, 0xA4, 0x90, 0xA2, 0xA4, 0xA8]);
    expect(encodeIranSystem('محمد هادی'), [0xFD, 0xA2, 0x91, 0xFB, 0x20, 0xA2, 0xF5, 0x9F, 0xF5]);
    expect(encodeIranSystem('علی 12'), [0x31, 0x32, 0x20, 0xFC, 0xF3, 0xE4]);
    expect(encodeIranSystem('کلاس'), [0xA7, 0xF2, 0xEE]);
    final kar = buildDbf(dskKarFields, [{}]);
    final wor = buildDbf(dskWorFields, [{}, {}]);
    // header and record lengths of the official templates
    expect(kar[8] | kar[9] << 8, 769);
    expect(kar[10] | kar[11] << 8, 287);
    expect(wor[8] | wor[9] << 8, 897);
    expect(wor[10] | wor[11] << 8, 332);
    expect(wor.length, 897 + 2 * 332 + 1);
    final w = buildDbf(dskWorFields, [{'DSW_FNAME': 'حسین', 'DSW_DD': 31, 'DSW_ID': '1234567890'}], persian: {'DSW_FNAME'});
    final rec = w.sublist(897);
    expect(String.fromCharCodes(rec.sublist(1, 11)), '1234567890');
    final fname = 1 + 10 + 2 + 2 + 12 + 8;
    expect(rec.sublist(fname, fname + 4), [0xF6, 0xFE, 0xA8, 0x9F]);
  });

  test('balance purchase posts buyer, seller and brokerage income', () {
    final s = _tempStore();
    final seller = Person(id: newId(), name: 'Seller');
    final buyer = Person(id: newId(), name: 'Buyer');
    s.upsertPerson(seller);
    s.upsertPerson(buyer);
    final d = BalanceDeal(id: newId(), number: s.nextBalanceNumber(false), date: DateTime(2026, 10, 2), sellerId: seller.id, buyerId: buyer.id,
        lines: [BalanceLine(title: 'Cement', qty: 10, buyPrice: 1000, sellPrice: 1200)], sellerDiscount: 500);
    s.saveBalanceDeal(d);
    expect(d.margin, 2500);
    expect(s.personBalance(buyer.id), 12000);
    expect(s.personBalance(seller.id), -9500);
    final j = buildJournal(s);
    expect(j.where((p) => p.moeen == '4025').fold<int>(0, (a, p) => a + p.credit - p.debit), 2500);
    // editing keeps one voucher
    d.lines.first.qty = 20;
    s.saveBalanceDeal(d);
    expect(s.vouchers.where((v) => v.kind == 'balance').length, 1);
    expect(s.personBalance(buyer.id), 24000);
    final r = BalanceDeal(id: newId(), number: s.nextBalanceNumber(true), date: DateTime(2026, 10, 3), isReturn: true, sellerId: seller.id, buyerId: buyer.id,
        lines: [BalanceLine(title: 'Cement', qty: 5, buyPrice: 1000, sellPrice: 1200)]);
    s.saveBalanceDeal(r);
    expect(s.personBalance(buyer.id), 18000);
    expect(s.personBalance(seller.id), -19500 + 5000);
    s.removeBalanceDeal(r.id);
    expect(s.personBalance(buyer.id), 24000);
    expect(AppStore.open(s.storage).balanceDeals.single.lines.first.qty, 20);
  });

  test('account status report and monthly profit', () {
    final s = _tempStore();
    final p = Person(id: newId(), name: 'Ali');
    s.upsertPerson(p);
    final now = DateTime(2026, 10, 30);
    s.cheques.add(Cheque(id: newId(), direction: ChequeDirection.received, amount: 1000, dueDate: DateTime(2026, 10, 1), issueDate: now, personId: p.id));
    s.cheques.add(Cheque(id: newId(), direction: ChequeDirection.received, amount: 2000, dueDate: DateTime(2026, 12, 1), issueDate: now, personId: p.id));
    s.cheques.add(Cheque(id: newId(), direction: ChequeDirection.issued, amount: 500, dueDate: DateTime(2026, 12, 1), issueDate: now, personId: p.id));
    final r = accountStatus(s, at: now).single;
    expect((r.recvDue, r.recvNotDue, r.paidDue, r.paidNotDue), (1000, 2000, 0, 500));
    final pr = Product(id: newId(), name: 'X');
    s.upsertProduct(pr);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 4, 1), lines: [InvoiceLine(productId: pr.id, qty: 10, unitPrice: 100)]));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 5, 1), lines: [InvoiceLine(productId: pr.id, qty: 5, unitPrice: 300)]));
    final m = monthlyProfit(s, 1405);
    expect(m.length, 12);
    expect(m[1].$2, 1000); // 11 Ordibehesht 1405 = 1 May 2026
  });

  test('installment plan schedule, interest and penalty', () {
    final s = _tempStore();
    final p = InstallmentPlan(id: newId(), principal: 1200000, count: 12, interestFrom: DateTime(2026, 1, 1), firstDue: DateTime(2026, 2, 1), interestPct: 0);
    p.generate();
    expect(p.items.length, 12);
    expect(p.total, 1200000);
    expect(p.items[11].due, DateTime(2027, 1, 1));
    p.interestPct = 36.5;
    p.generate();
    expect(p.items.first.amount, 100000 + 3100); // 31 days at 36.5% → 0.1% a day
    expect(p.interest, greaterThan(0));
    p.penaltyPct = 3;
    expect(p.penaltyOf(p.items.first, DateTime(2026, 3, 3)), ((p.items.first.amount) * 0.03 * 30 / 30).round());
    p.items.first
      ..paid = p.items.first.amount
      ..paidOn = DateTime(2026, 2, 1);
    expect(p.penaltyOf(p.items.first, DateTime(2026, 3, 3)), 0);
    s.saveInstallmentPlan(p);
    final again = AppStore.open(s.storage).installmentPlans.single;
    expect(again.remaining, p.total - p.items.first.amount);
    expect(again.items.first.paidOn, DateTime(2026, 2, 1));
  });

  test('serial tracking and product variants', () {
    final s = _tempStore();
    final phone = Product(id: newId(), name: 'Phone', info: {'serial': '1', 'openSerials': 'A0'});
    final shirt = Product(id: newId(), name: 'Shirt', info: {'attrs': 'رنگ=قرمز,آبی;سایز=S,M'});
    s.upsertProduct(phone);
    s.upsertProduct(shirt);
    expect(productVariants(shirt), ['قرمز / S', 'قرمز / M', 'آبی / S', 'آبی / M']);
    final buy = Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 10, 1), lines: [
      InvoiceLine(productId: phone.id, qty: 2, unitPrice: 100, serials: ['A1', 'A2']),
      InvoiceLine(productId: shirt.id, qty: 5, unitPrice: 10, variant: 'آبی / M'),
    ]);
    expect(s.checkSerials(buy), isNull);
    s.saveInvoice(buy);
    expect(s.serialsInStock(productId: phone.id).keys.toSet(), {'A0', 'A1', 'A2'});
    expect(s.variantStock(shirt.id, 'آبی / M'), 5);
    expect(s.variantStock(shirt.id, 'قرمز / S'), 0);
    // buying an in-stock serial again, or selling one not in stock, is refused
    expect(s.checkSerials(Invoice(id: 'x', kind: InvoiceKind.purchase, number: 2, date: DateTime(2026, 10, 2), lines: [InvoiceLine(productId: phone.id, qty: 1, serials: ['A1'])])), isNotNull);
    expect(s.checkSerials(Invoice(id: 'x', kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 10, 2), lines: [InvoiceLine(productId: phone.id, qty: 1, serials: ['Z9'])])), isNotNull);
    expect(s.checkSerials(Invoice(id: 'x', kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 10, 2), lines: [InvoiceLine(productId: phone.id, qty: 2, serials: ['A1'])])), isNotNull);
    final sale = Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 10, 3), lines: [InvoiceLine(productId: phone.id, qty: 1, unitPrice: 200, serials: ['A1'])]);
    expect(s.checkSerials(sale), isNull);
    s.saveInvoice(sale);
    expect(s.serialsInStock(productId: phone.id).keys.toSet(), {'A0', 'A2'});
    expect(s.serialMoves(serial: 'A1').length, 2);
    // «انتقال بین سریال»
    expect(s.swapSerial(sale.id, 'A1', 'A2'), isTrue);
    expect(s.serialsInStock(productId: phone.id).keys.toSet(), {'A0', 'A1'});
    expect(AppStore.open(s.storage).invoices.firstWhere((i) => i.id == sale.id).lines.single.serials, ['A2']);
    expect(InvoiceLine.fromJson(buy.lines.last.toJson()).variant, 'آبی / M');
  });

  test('cost centers collect expense txns and voucher rows', () {
    final s = _tempStore();
    final c = CostCenter(id: newId(), code: s.nextCostCenterCode(), name: 'Shop');
    s.costCenters.add(c);
    s.upsertTxn(Txn(id: newId(), type: TxnType.expense, amount: 700, date: DateTime(2026, 10, 1), accountId: s.activeAccounts.first.id)..costCenterId = c.id);
    s.upsertTxn(Txn(id: newId(), type: TxnType.income, amount: 200, date: DateTime(2026, 10, 2), accountId: s.activeAccounts.first.id)..costCenterId = c.id);
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: s.nextFixedNumber(), date: DateTime(2026, 10, 3), lines: [
      VoucherLine(moeen: '5005', debit: 50, costCenterId: c.id),
      VoucherLine(moeen: '1010', credit: 50),
    ]));
    final rows = s.costCenterRows();
    expect(rows.length, 3);
    expect(rows.fold<int>(0, (a, r) => a + r.$4), 750);
    expect(rows.fold<int>(0, (a, r) => a + r.$5), 200);
    expect(s.costCenterRows(from: DateTime(2026, 10, 2)).length, 2);
    final again = AppStore.open(s.storage);
    expect(again.costCenterRows().length, 3);
    expect(again.costCenters.single.code, 1);
  });

  test('payroll extras: non-cash, tax exemption, reserve, groups, attendance', () {
    final s = _tempStore();
    final person = Person(id: newId(), name: 'Reza');
    s.upsertPerson(person);
    final e = Employee(id: newId(), personId: person.id, personnelCode: '7', firstName: 'Reza', lastName: 'K', monthlyWage: 30000000);
    s.employees.add(e);
    final g = PayGroup(id: newId(), name: 'Workers', monthlyWage: 36500000, benefits: [PayItem2(name: 'Food', amount: 1000000, nonCash: true)]);
    s.payGroups.add(g);
    g.applyTo(e);
    expect(e.monthlyWage, 36500000);
    final period = PayPeriod(id: newId(), year: 1405, month: 7, days: 30, start: DateTime(2026, 9, 23), end: DateTime(2026, 10, 22));
    s.payPeriods.add(period);
    s.addEmployeesToPeriod(period);
    final r = s.payResult(period, e);
    expect(r.gheirNaghdi, 1000000);
    expect(r.khales, r.jamKol - r.jamKosorat - 1000000);
    final taxBefore = r.mashmoolMaliat;
    e.taxExemptMonthly = 500000;
    expect(s.payResult(period, e).mashmoolMaliat, taxBefore - 500000);
    expect(serviceReserve(e, r), ((36500000 + 1000000) * 30 / 365).round());
    final v = s.postPayroll(period);
    expect(v.lines.fold<int>(0, (a, l) => a + l.debit), v.lines.fold<int>(0, (a, l) => a + l.credit));
    expect(s.postServiceReserve(period)!.lines.first.debit, serviceReserve(e, r));
    // attendance
    expect(parseClockDate('1405/07/01'), DateTime(2026, 9, 23));
    final punches = parseClockRows([
      ['کد', 'تاریخ', 'ورود', 'خروج'],
      ['7', '1405/07/01', '08:10', '17:40'],
      ['7', '2026-09-24 07:55'],
      ['7', '2026-09-24 16:00'],
      ['99', '1405/07/01', '08:00', '16:00'],
    ]);
    final (n, unknown) = s.importPunches(punches);
    expect(n, 2);
    expect(unknown, {'99'});
    expect(s.clockOf(e.id, DateTime(2026, 9, 24))!.inMin, 7 * 60 + 55);
    final a = s.attendance(e, period);
    expect(a.presentDays, 2);
    expect(a.lateCount, 1);
    expect(a.overtimeMinutes, 95); // 570−30 = 540 vs 450 → 90; 485−30 = 455 vs 450 → 5
    expect(s.applyAttendance(period), 1);
    expect(s.payslipOf(period, e).workDays, 30 - a.absentDays);
  });

  test('automatic sms jobs, reminders and custom statements', () {
    final s = _tempStore();
    final p = Person(id: newId(), name: 'Ali', phone: '09121234567');
    s.upsertPerson(p);
    final plan = InstallmentPlan(id: newId(), personId: p.id, principal: 1000, count: 2, interestFrom: DateTime(2026, 1, 1), firstDue: DateTime(2026, 2, 1));
    plan.generate();
    s.saveInstallmentPlan(plan);
    final now = DateTime(2026, 10, 30, 12);
    expect(dueAutoSms(s, now: now), isEmpty);
    s.smsAuto.overdueInstallments = true;
    expect(dueAutoSms(s, now: now).length, 2);
    s.smsSchedules.add(SmsSchedule(id: newId(), text: 'سلام {نام}', at: DateTime(2026, 10, 30, 9), target: SmsTarget.chosen, personIds: [p.id]));
    final jobs = dueAutoSms(s, now: now);
    expect(jobs.length, 3);
    expect(jobs.first.text, 'سلام Ali');
    expect(Repeat.monthly.next(DateTime(2026, 1, 31, 9)).month, 3); // Dart rolls Feb 31 forward
    final r = Reminder(id: newId(), at: DateTime(2026, 10, 1), title: 'Rent', repeat: Repeat.monthly);
    expect(r.on(DateTime(2026, 11, 1)), isTrue);
    expect(r.on(DateTime(2026, 11, 2)), isFalse);
    expect(r.on(DateTime(2026, 9, 1)), isFalse);

    final pr = Product(id: newId(), name: 'X');
    s.upsertProduct(pr);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 4, 1), lines: [InvoiceLine(productId: pr.id, qty: 10, unitPrice: 100)]));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 5, 1), lines: [InvoiceLine(productId: pr.id, qty: 5, unitPrice: 300)]));
    final pl = evaluateStatement(s, CustomStatement.sampleProfit(), from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
    expect(pl[0], 1500);
    expect(pl[1], -500);
    expect(pl[2], 1000);
    final bs = CustomStatement.sampleBalanceSheet();
    final b = evaluateStatement(s, bs, to: DateTime(2026, 12, 31));
    expect(b[3], b[9]); // assets = liabilities + equity
    final dyn = dynamicSeries(s, DynMetric.sales, DynGroup.product, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
    expect(dyn.single, ('X', 1500));
    expect(consolidatedProfit(s, DateTime(2026, 1, 1), DateTime(2026, 12, 31)).first.$2.netSales, 1500);
  });

  test('loyalty, draws, messages, cleanup and overhead variance', () {
    final s = _tempStore();
    final p = Person(id: newId(), name: 'Fan');
    final idle = Person(id: newId(), name: 'Idle');
    s.upsertPerson(p);
    s.upsertPerson(idle);
    final pr = Product(id: newId(), name: 'X');
    final unused = Product(id: newId(), name: 'Unused');
    s.upsertProduct(pr);
    s.upsertProduct(unused);
    final card = LoyaltyCard(number: '1001', personId: p.id, issued: DateTime(2026, 10, 1));
    s.loyaltyCards.add(card);
    s.loyalty = LoyaltyConfig(amountPerPoint: 1000, gifts: [GiftRow(points: 3, title: 'Mug', amount: 500)]);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 5, date: DateTime(2026, 10, 2), personId: p.id, lines: [InvoiceLine(productId: pr.id, qty: 5, unitPrice: 1000)]));
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 4, date: DateTime(2026, 9, 2), personId: p.id, lines: [InvoiceLine(productId: pr.id, qty: 9, unitPrice: 1000)]));
    expect(s.loyaltyPoints(card), 5);
    expect(s.redeem(card, s.loyalty.gifts.first), isTrue);
    expect(s.loyaltyPoints(card), 2);
    expect(s.redeem(card, s.loyalty.gifts.first), isFalse);
    final d = DrawCampaign(id: newId(), name: 'Nowruz', prefix: 'N', from: DateTime(2026, 9, 1), to: DateTime(2026, 10, 30), minAmount: 4000);
    expect(s.drawCodes(d).map((c) => c.$1).toList(), ['N4-1', 'N4-2', 'N5']);
    s.sendMessage('*', 'hello');
    expect(s.inbox(s.currentUser.id), isEmpty); // own broadcast
    expect(s.unusedPeople().map((x) => x.name), ['Idle']);
    expect(s.unusedProducts().map((x) => x.name), ['Unused']);
    expect(s.removeUnused(persons: true, items: true), 2);
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: s.nextFixedNumber(), date: DateTime(2026, 10, 3), lines: [
      VoucherLine(moeen: '1170', debit: 1200),
      VoucherLine(moeen: '1010', credit: 1200),
    ]));
    s.saveVoucher(Voucher(id: newId(), number: s.nextVoucherNumber(), fixedNumber: s.nextFixedNumber(), date: DateTime(2026, 10, 3), lines: [
      VoucherLine(moeen: '1150', debit: 1000),
      VoucherLine(moeen: '2050', credit: 1000),
    ]));
    expect(s.overheadVariance(DateTime(2026, 10, 1), DateTime(2026, 10, 30)), (1000, 1200));
    final v = s.postOverheadVariance(DateTime(2026, 10, 1), DateTime(2026, 10, 30))!;
    expect(v.lines.firstWhere((l) => l.moeen == '5030').debit, 200);
    expect(s.overheadVariance(DateTime(2026, 10, 1), DateTime(2026, 10, 30)), (0, 0));
  });

  test('weighted barcodes, caller lookup and seasonal tax rows', () {
    final s = _tempStore();
    final cheese = Product(id: newId(), name: 'Cheese', code: '123', sellPrice: 500000, info: {'plu': '42', 'scale': '1', 'barcode': '6260000000017'});
    s.upsertProduct(cheese);
    expect(ean13Check('400638133393'), 1); // 4006381333931
    final code = makeWeighted('21', '42', 1250, s.scale);
    expect(code.length, 13);
    expect(parseWeighted(code, s.scale), ('00042', 1250));
    final hit = s.matchScan(code)!;
    expect(hit.$1.id, cheese.id);
    expect(hit.$2, 1.25);
    expect(s.matchScan('6260000000017')!.$2, isNull);
    expect(s.matchScan('123')!.$1.id, cheese.id);
    expect(s.scaleFile(), contains('42,Cheese,500000'));

    final p = Person(id: newId(), name: 'Caller', phone: '0912 111 2233', info: {'nationalId': '0012345678'});
    s.upsertPerson(p);
    expect(s.whoCalls('+989121112233').$1?.id, p.id);
    expect(s.logCall('09121112233').personId, p.id);

    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.sale, number: 1, date: DateTime(2026, 10, 1), personId: p.id, lines: [InvoiceLine(productId: cheese.id, qty: 2, unitPrice: 1000)]));
    final (from, to) = seasonRange(1405, 3);
    expect(from, DateTime(2026, 9, 23));
    expect(to, DateTime(2026, 12, 21));
    final rows = seasonRows(s, 1405, 3, sales: true);
    expect(rows.single.amount, 2000);
    expect(seasonTable(rows).single[2], '0012345678');
    expect(missingTaxInfo(rows), isEmpty);
    expect(AppStore.open(s.storage).person(p.id)!.info['nationalId'], '0012345678');
  });

  test('network mode: a save from another computer is detected and loaded', () {
    final dir = Directory.systemTemp.createTempSync('taraz_net');
    final a = AppStore.open(Storage(dir));
    final b = AppStore.open(Storage(dir));
    a.upsertPerson(Person(id: newId(), name: 'From A'));
    expect(b.storage.changedExternally(), isTrue);
    expect(b.syncFromDisk(), isTrue);
    expect(b.people.any((p) => p.name == 'From A'), isTrue);
    expect(b.syncFromDisk(), isFalse);
    // A saves again; B's next change is refused and B reloads A's data
    a.upsertPerson(Person(id: newId(), name: 'A2'));
    b.upsertPerson(Person(id: newId(), name: 'From B'));
    expect(b.lastError, isNotNull);
    expect(b.people.any((p) => p.name == 'A2'), isTrue);
    expect(b.people.any((p) => p.name == 'From B'), isFalse);
    b.upsertPerson(Person(id: newId(), name: 'From B'));
    expect(b.lastError, isNull);
    expect(a.syncFromDisk(), isTrue);
    expect(a.people.any((p) => p.name == 'From B'), isTrue);
  });

  test('price formulas, standard barcodes, combined voucher, guarantor', () {
    final s = _tempStore();
    final a = Product(id: newId(), name: 'A', code: '7', buyPrice: 1000, sellPrice: 1500);
    final b = Product(id: newId(), name: 'B', code: '8', buyPrice: 2000, sellPrice: 2500, info: {'barcode': '6261234567890'});
    s.upsertProduct(a);
    s.upsertProduct(b);
    expect(formulaPrice(s, a, PriceField.sell1, PriceMode.percent, 10), 1650);
    expect(formulaPrice(s, a, PriceField.sell1, PriceMode.marginOnBuy, 30, round: 1000), 2000);
    expect(s.applyPriceFormula([a, b], PriceField.sell1, PriceMode.amount, 100), 2);
    expect(b.sellPrice, 2600);
    expect(s.makeStandardBarcodes(), 1);
    expect(a.info['barcode'], startsWith('200000000007'));
    expect(a.info['barcode']!.length, 13);
    expect(s.matchScan(a.info['barcode']!)!.$1.id, a.id);
    s.saveInvoice(Invoice(id: newId(), kind: InvoiceKind.purchase, number: 1, date: DateTime(2026, 10, 5), lines: [InvoiceLine(productId: a.id, qty: 2, unitPrice: 1000)]));
    final rows = combinedVoucher(s, DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    expect(rows.fold<int>(0, (x, r) => x + r.$3), rows.fold<int>(0, (x, r) => x + r.$4));
    expect(rows.any((r) => r.$1 == '1150' && r.$3 == 2000), isTrue);
    final plan = InstallmentPlan(id: newId(), interestFrom: DateTime(2026), firstDue: DateTime(2026, 2))..guarantorName = 'Zamen';
    expect(InstallmentPlan.fromJson(plan.toJson()).guarantorName, 'Zamen');
  });
}
