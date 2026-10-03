/// Chart of accounts (کل / معین) used by manual vouchers and the opening voucher.
/// Group names follow the Sakan opening-voucher screen.

enum Side { asset, liability, equity, income, expense }

/// What kind of detail (تفصیلی) a ledger (معین) is linked to.
enum TafsiliKind { none, cash, bank, person, product, incomeCat, expenseCat }

class Moeen {
  final String code;
  final String name;
  final TafsiliKind kind;
  const Moeen(this.code, this.name, [this.kind = TafsiliKind.none]);

  String get kolCode => code.substring(0, 3);
  Kol get kol => kolOf(code);
  Side get side => kol.side;

  /// Debit-natured accounts grow with debit.
  bool get debitNature => side == Side.asset || side == Side.expense;

  /// Linked to an entity (cash box, bank, person…) whose own balance tracks it.
  bool get hasEntity => kind != TafsiliKind.none;
}

class Kol {
  final String code;
  final String name;
  final Side side;
  final List<Moeen> moeens;
  const Kol(this.code, this.name, this.side, this.moeens);

  /// Built-in ledgers plus the ones made in «کدبندی دفاتر کل و معین».
  List<Moeen> get ledgers => [...moeens, ...extraMoeens.where((m) => m.kolCode == code)];
}

// Codes used by app logic.
const mCash = '10102';
const mPettyCash = '10101';
const mCashFx = '10103';
const mBank = '10201';
const mBankFx = '10202';
const mChequesAtCash = '10301';
const mChequesAtBank = '10302';
const mStock = '10401';
const mStockConsign = '10402';
const mAssets = '10501';
const mDebtorsTrade = '10601';
const mDebtorsFx = '10602';
const mDebtorsOther = '10603';
const mOtherPersonsDr = '10604';
const mChequesPayable = '20101';
const mCreditorsTrade = '20201';
const mCreditorsFx = '20202';
const mCreditorsOther = '20203';
const mOtherPersonsCr = '20204';
const mCapital = '30101';
const mRetained = '30103';
const mPartners = '30104';
const mIncome = '40101';
const mSales = '40103';
const mSalesReturn = '40104';
const mPurchaseDiscount = '40105';
const mExpense = '50101';
const mCogs = '50103';
const mSaleDiscount = '50104';
const mStockLoss = '50105';
const mLoanCost = '50106';
const mDepreciation = '50107';
const mAccDepreciation = '20302';
const mOtherIncome = '40102';
const mOtherExpense = '50102';
const mLoans = '20601';
const mOtherLiab = '20603';

const List<Kol> chart = [
  Kol('101', 'صندوق و تنخواه', Side.asset, [
    Moeen(mPettyCash, 'موجودی تنخواه گردان'),
    Moeen(mCash, 'صندوق', TafsiliKind.cash),
    Moeen(mCashFx, 'صندوق ارزی'),
  ]),
  Kol('102', 'موجودی بانکها', Side.asset, [
    Moeen(mBank, 'موجودی بانکها', TafsiliKind.bank),
    Moeen(mBankFx, 'موجودی ارزی بانکها'),
  ]),
  Kol('103', 'اسناد دریافتنی', Side.asset, [
    Moeen(mChequesAtCash, 'اسناد وصولی نزد صندوق'),
    Moeen(mChequesAtBank, 'اسناد وصولی نزد بانک'),
  ]),
  Kol('104', 'موجودی کالا', Side.asset, [
    Moeen(mStock, 'موجودی کالا', TafsiliKind.product),
    Moeen(mStockConsign, 'موجودی کالای امانی'),
  ]),
  Kol('105', 'اموال و ماشین آلات', Side.asset, [
    Moeen(mAssets, 'اموال و ماشین آلات'),
  ]),
  Kol('106', 'حسابهای دریافتنی', Side.asset, [
    Moeen(mDebtorsTrade, 'بدهکاران تجاری', TafsiliKind.person),
    Moeen(mDebtorsFx, 'بدهکاران ارزی تجاری'),
    Moeen(mDebtorsOther, 'بدهکاران غیر تجاری'),
    Moeen(mOtherPersonsDr, 'سایر اشخاص'),
  ]),
  Kol('107', 'سایر حسابهای بدهکار', Side.asset, [
    Moeen('10701', 'پیش پرداخت ها'),
    Moeen('10702', 'سپرده ها'),
    Moeen('10703', 'سایر حسابهای بدهکار'),
  ]),
  Kol('201', 'اسناد پرداختنی', Side.liability, [
    Moeen(mChequesPayable, 'اسناد پرداختنی'),
  ]),
  Kol('202', 'حسابهای پرداختنی', Side.liability, [
    Moeen(mCreditorsTrade, 'بستانکاران تجاری', TafsiliKind.person),
    Moeen(mCreditorsFx, 'بستانکاران ارزی تجاری'),
    Moeen(mCreditorsOther, 'بستانکاران غیر تجاری'),
    Moeen(mOtherPersonsCr, 'سایر اشخاص'),
  ]),
  Kol('203', 'حسابهای کاهنده دارایی', Side.liability, [
    Moeen('20301', 'ذخیره مطالبات مشکوک الوصول'),
    Moeen(mAccDepreciation, 'استهلاک انباشته اموال و ماشین آلات'),
  ]),
  Kol('204', 'ذخایر', Side.liability, [
    Moeen('20401', 'ذخیره مزایای پایان خدمت'),
    Moeen('20402', 'ذخیره مالیات'),
    Moeen('20403', 'سایر ذخایر'),
  ]),
  Kol('205', 'حسابهای کنترلی بستانکار', Side.liability, [
    Moeen('20501', 'پیش دریافت ها'),
    Moeen('20502', 'سایر حسابهای کنترلی'),
  ]),
  Kol('206', 'سایر حسابهای بستانکار', Side.liability, [
    Moeen('20601', 'تسهیلات مالی دریافتنی و اوراق مشارکت'),
    Moeen('20602', 'تعهدات بلند مدت اجاره ای سرمایه ای'),
    Moeen('20603', 'سایر بدهی ها'),
    Moeen('20604', 'تعهدات پرداختنی'),
  ]),
  Kol('301', 'حقوق صاحبان سهام', Side.equity, [
    Moeen(mCapital, 'سرمایه'),
    Moeen('30102', 'برداشت'),
    Moeen(mRetained, 'سود و زیان انباشته'),
    Moeen(mPartners, 'حساب جاری صاحبان سهام', TafsiliKind.person),
  ]),
  Kol('401', 'درآمدها', Side.income, [
    Moeen(mIncome, 'درآمدهای عملیاتی', TafsiliKind.incomeCat),
    Moeen(mOtherIncome, 'سایر درآمدها'),
    Moeen(mSales, 'فروش کالا', TafsiliKind.product),
    Moeen(mSalesReturn, 'برگشت از فروش', TafsiliKind.product),
    Moeen(mPurchaseDiscount, 'تخفیفات خرید'),
  ]),
  Kol('501', 'هزینه ها', Side.expense, [
    Moeen(mExpense, 'هزینه های عمومی', TafsiliKind.expenseCat),
    Moeen(mOtherExpense, 'سایر هزینه ها'),
    Moeen(mCogs, 'بهای تمام شده کالای فروش رفته', TafsiliKind.product),
    Moeen(mSaleDiscount, 'تخفیفات فروش'),
    Moeen(mStockLoss, 'ضایعات و کسری انبار', TafsiliKind.product),
    Moeen(mLoanCost, 'هزینه تسهیلات'),
    Moeen(mDepreciation, 'هزینه استهلاک'),
  ]),
];

Kol kolOf(String moeenCode) => chart.firstWhere((k) => k.code == moeenCode.substring(0, 3));

Moeen? findMoeen(String? code) {
  if (code == null || code.length < 3) return null;
  for (final k in chart) {
    for (final m in k.ledgers) {
      if (m.code == code) return m;
    }
  }
  return null;
}

Iterable<Moeen> get allMoeens => chart.expand((k) => k.ledgers);

/// Ledgers (معین) the user added; loaded from the store.
List<Moeen> extraMoeens = [];
