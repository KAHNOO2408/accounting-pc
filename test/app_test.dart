import 'dart:io';

import 'package:taraz/core/format.dart';
import 'package:taraz/core/hash.dart';
import 'package:taraz/core/jalali.dart';
import 'package:taraz/data/books.dart';
import 'package:taraz/data/chart.dart';
import 'package:taraz/data/journal.dart';
import 'package:taraz/data/kardex.dart';
import 'package:taraz/data/models.dart';
import 'package:taraz/data/report_layout.dart';
import 'package:taraz/data/storage.dart';
import 'package:taraz/data/store.dart';
import 'package:taraz/main.dart';
import 'package:taraz/ui/dialogs/books_dialogs.dart';
import 'package:taraz/ui/dialogs/composite_dialogs.dart';
import 'package:taraz/ui/dialogs/invoice_editor.dart';
import 'package:taraz/ui/dialogs/ledger_dialogs.dart';
import 'package:taraz/ui/dialogs/price_dialog.dart';
import 'package:taraz/ui/dialogs/sakan_tools.dart';
import 'package:taraz/ui/print_designer.dart';
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
    final code = s.addMoeen('107', 'وام کارکنان');
    expect(code, '10704');
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
}
