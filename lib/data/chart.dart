/// Chart of accounts — Sakan's default coding («کدبندی دفاتر کل و معین»).
///
/// Codes, names and paths come from Sakan's initial database (see
/// docs/sakan/coding.json): each ledger has a 4-digit code (صندوق = 1010) and
/// a path (1010\100100\). The groups (کل) follow Sakan's group tree. Ledgers
/// marked «تراز» exist only in this app and use free codes in Sakan's ranges.

enum Side { asset, liability, equity, income, expense }

/// What kind of detail (تفصیلی) a ledger (معین) is linked to.
enum TafsiliKind { none, cash, bank, person, product, incomeCat, expenseCat }

class Moeen {
  final String code;
  final String name;
  final TafsiliKind kind;

  /// Sakan's 6-digit path segment (e.g. 100100 for صندوق); empty for ledgers
  /// that are not in Sakan's default coding.
  final String path;
  const Moeen(this.code, this.name, [this.kind = TafsiliKind.none, this.path = '']);

  String get kolCode => kolOf(code).code;
  Kol get kol => kolOf(code);
  Side get side => kol.side;

  /// Sakan-style path: «1010\100100\».
  String get sakanPath => path.isEmpty ? '$code\\' : '$code\\$path\\';

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
  List<Moeen> get ledgers => [...moeens, ...extraMoeens.where((m) => m.code.startsWith(code))];
}

// Codes used by app logic (Sakan codes).
const mCash = '1010'; // صندوق
const mPettyCash = '1040'; // تنخواه گردان
const mCashFx = '1030'; // صندوق ارزی
const mBank = '1020'; // بانکها
const mBankFx = '5080'; // بانکهای ارزی
const mChequesAtCash = '1120'; // اسناد وصولی نزد صندوق
const mChequesAtBank = '1115'; // اسناد وصولی نزد بانکها
const mStock = '1150'; // موجودی کالا
const mStockConsign = '1157'; // موجودی کالای امانی (تراز)
const mAssets = '1220'; // اموال و ماشین آلات
const mDebtorsTrade = '1125'; // اشخاص
const mDebtorsFx = '1130'; // اشخاص ارزی
const mDebtorsOther = '1145'; // سایر اشخاص
const mOtherPersonsDr = '1146'; // سایر حسابهای اشخاص (تراز)
const mChequesPayable = '2030'; // اسناد پرداختنی بانکها
// Sakan keeps every person in «اشخاص», whatever the side of the balance.
const mCreditorsTrade = mDebtorsTrade;
const mCreditorsFx = mDebtorsFx;
const mCreditorsOther = mDebtorsOther;
const mOtherPersonsCr = mOtherPersonsDr;
const mCapital = '3010'; // سرمایه
const mDrawings = '3015'; // برداشت (تراز)
const mRetained = '3030'; // سود و زیان سنواتی
const mPartners = '1140'; // صاحبان سهام
const mIncome = '4020'; // درآمدها
const mOtherIncome = '4025'; // سایر درآمدها (تراز)
const mSales = '4060'; // فروش موجودی کالا
const mServiceSales = '4050'; // فروش خدمات
const mSalesReturn = '5055'; // برگشت از فروش موجودی کالا
const mPurchaseDiscount = '4010'; // تخفیف از خرید
const mPurchaseReturn = '4070'; // برگشت از خرید موجودی کالا
const mExpense = '5005'; // هزینه ها
const mOtherExpense = '5007'; // سایر هزینه ها (تراز)
const mCogs = '5040'; // قیمت تمام شده کالای فروخته شده
const mSaleDiscount = '5050'; // تخفیف از فروش
const mStockLoss = '5065'; // ضایعات و کسری انبار (تراز)
const mLoanCost = '5070'; // هزینه تسهیلات (تراز)
const mDepreciation = '5075'; // هزینه استهلاک (تراز)
const mAccDepreciation = '2180'; // ذخیره استهلاک اموال و ماشین آلات
const mLoans = '2110'; // تسهیلات مالی دریافتنی و اوراق مشارکت
const mOtherLiab = '2150'; // سایر بدهی ها
const mPrepayments = '1165'; // پیش پرداختها
const mDeposits = '1245'; // سپرده ها (تراز)
const mAdvances = '2035'; // پیش دریافتها
const mOtherControl = '2057'; // سایر حسابهای کنترلی (تراز)
const mOtherIncomeExpense = mOtherExpense;
const mSalaryExpense = '5012'; // هزینه حقوق و دستمزد (تراز)
const mInsuranceExpense = '5013'; // هزینه بیمه سهم کارفرما (تراز)
const mInsurancePayable = '2041'; // بیمه پرداختنی (تراز)
const mSalaryTaxPayable = '2042'; // مالیات حقوق پرداختنی (تراز)
const mStaff = '1135'; // پرسنل

const List<Kol> chart = [
  Kol('10', 'دارایی های جاری نقدی', Side.asset, [
    Moeen(mCash, 'صندوق', TafsiliKind.cash, '100100'),
    Moeen(mBank, 'بانکها', TafsiliKind.bank, '100200'),
    Moeen(mCashFx, 'صندوق ارزی', TafsiliKind.none, '100300'),
    Moeen(mPettyCash, 'تنخواه گردان', TafsiliKind.none, '100400'),
    Moeen(mBankFx, 'بانکهای ارزی', TafsiliKind.none, '500800'),
  ]),
  Kol('11', 'دارایی های جاری غیر نقدی', Side.asset, [
    Moeen('1110', 'سرمایه گذاری جاری', TafsiliKind.none, '110100'),
    Moeen(mChequesAtBank, 'اسناد وصولی نزد بانکها', TafsiliKind.none, '110150'),
    Moeen(mChequesAtCash, 'اسناد وصولی نزد صندوق', TafsiliKind.none, '110200'),
    Moeen(mDebtorsTrade, 'اشخاص', TafsiliKind.person, '110250'),
    Moeen(mDebtorsFx, 'اشخاص ارزی', TafsiliKind.none, '110300'),
    Moeen(mStaff, 'پرسنل', TafsiliKind.none, '110350'),
    Moeen(mPartners, 'صاحبان سهام', TafsiliKind.person, '110400'),
    Moeen(mDebtorsOther, 'سایر اشخاص', TafsiliKind.none, '110450'),
    Moeen(mOtherPersonsDr, 'سایر حسابهای اشخاص'),
    Moeen(mStock, 'موجودی کالا', TafsiliKind.product, '110500'),
    Moeen('1155', 'موجودی کالای متفرقه', TafsiliKind.none, '110550'),
    Moeen(mStockConsign, 'موجودی کالای امانی'),
    Moeen('1160', 'سفارشات', TafsiliKind.none, '110600'),
    Moeen(mPrepayments, 'پیش پرداختها', TafsiliKind.none, '110650'),
    Moeen('1170', 'سربار واقعی سربار جذبی', TafsiliKind.none, '110700'),
    Moeen('1175', 'پیمان در دست اجرا', TafsiliKind.none, '110750'),
    Moeen('5090', 'اسناد ارزی وصولی نزد بانکهای ارزی', TafsiliKind.none, '500900'),
    Moeen('6060', 'اسناد ارزی وصولی نزد صندوق ارزی', TafsiliKind.none, '600600'),
    Moeen('7070', 'پیش پرداختهای ارزی', TafsiliKind.none, '700700'),
  ]),
  Kol('12', 'دارایی های غیر جاری', Side.asset, [
    Moeen('1210', 'سرمایه گذاریهای بلند مدت', TafsiliKind.none, '120100'),
    Moeen(mAssets, 'اموال و ماشین آلات', TafsiliKind.none, '120200'),
    Moeen('1240', 'سایر دارایی ها', TafsiliKind.none, '120400'),
    Moeen(mDeposits, 'سپرده ها'),
    Moeen('1250', 'حسابهای انتظامی', TafsiliKind.none, '120500'),
  ]),
  Kol('20', 'بدهی های جاری', Side.liability, [
    Moeen(mChequesPayable, 'اسناد پرداختنی بانکها', TafsiliKind.none, '200300'),
    Moeen(mAdvances, 'پیش دریافتها', TafsiliKind.none, '200350'),
    Moeen('2040', 'ذخیره مالیات', TafsiliKind.none, '200400'),
    Moeen(mInsurancePayable, 'بیمه پرداختنی'),
    Moeen(mSalaryTaxPayable, 'مالیات حقوق پرداختنی'),
    Moeen('2045', 'تعهدات پرداختنی', TafsiliKind.none, '200450'),
    Moeen('2050', 'سربار جذبی', TafsiliKind.none, '200500'),
    Moeen('2055', 'کنترل تخفیف از خرید', TafsiliKind.none, '200550'),
    Moeen(mOtherControl, 'سایر حسابهای کنترلی'),
    Moeen('2060', 'اعتبارات', TafsiliKind.none, '200600'),
    Moeen('2065', 'ذخیره مطالبات مشکوک الوصول', TafsiliKind.none, '200650'),
    Moeen('2070', 'صورت وضعیت های تایید شده پیمان در دست اجرا', TafsiliKind.none, '200700'),
    Moeen('1260', 'طرف حسابهای انتظامی', TafsiliKind.none, '120600'),
    Moeen('6050', 'اسناد ارزی پرداختنی بانکهای ارزی', TafsiliKind.none, '600500'),
    Moeen('7060', 'پیش دریافتهای ارزی', TafsiliKind.none, '700600'),
  ]),
  Kol('21', 'بدهی های غیر جاری', Side.liability, [
    Moeen(mLoans, 'تسهیلات مالی دریافتنی و اوراق مشارکت', TafsiliKind.none, '210100'),
    Moeen('2120', 'تعهدات بلند مدت اجاره ای سرمایه ای', TafsiliKind.none, '210200'),
    Moeen('2130', 'ذخیره مزایای پایان خدمت', TafsiliKind.none, '210300'),
    Moeen('2140', 'سایر ذخایر', TafsiliKind.none, '210400'),
    Moeen(mOtherLiab, 'سایر بدهی ها', TafsiliKind.none, '210500'),
    Moeen(mAccDepreciation, 'ذخیره استهلاک اموال و ماشین آلات', TafsiliKind.none, '210800'),
  ]),
  Kol('30', 'حقوق صاحبان سرمایه', Side.equity, [
    Moeen(mCapital, 'سرمایه', TafsiliKind.none, '300100'),
    Moeen(mDrawings, 'برداشت'),
    Moeen(mRetained, 'سود و زیان سنواتی', TafsiliKind.none, '300300'),
    Moeen('3040', 'سود سهام پرداختنی', TafsiliKind.none, '300400'),
    Moeen('3050', 'اندوخته های قانونی', TafsiliKind.none, '300500'),
    Moeen('3080', 'سایر حقوق صاحبان سهام', TafsiliKind.none, '300800'),
  ]),
  Kol('40', 'فروش و درآمدها', Side.income, [
    Moeen(mPurchaseDiscount, 'تخفیف از خرید', TafsiliKind.none, '400100'),
    Moeen(mIncome, 'درآمدها', TafsiliKind.incomeCat, '400200'),
    Moeen(mOtherIncome, 'سایر درآمدها'),
    Moeen('4030', 'درآمد پیمان در دست اجرا', TafsiliKind.none, '400300'),
    Moeen('4040', 'فروش موجودی کالای متفرقه', TafsiliKind.none, '400400'),
    Moeen(mServiceSales, 'فروش خدمات', TafsiliKind.none, '400500'),
    Moeen(mSales, 'فروش موجودی کالا', TafsiliKind.product, '400600'),
    Moeen(mPurchaseReturn, 'برگشت از خرید موجودی کالا', TafsiliKind.none, '400700'),
    Moeen('4080', 'فروش اموال و ماشین آلات', TafsiliKind.none, '400800'),
  ]),
  Kol('50', 'هزینه ها و قیمت تمام شده', Side.expense, [
    Moeen(mExpense, 'هزینه ها', TafsiliKind.expenseCat, '500050'),
    Moeen(mOtherExpense, 'سایر هزینه ها'),
    Moeen('5010', 'هزینه های توزیع و فروش', TafsiliKind.none, '500100'),
    Moeen(mSalaryExpense, 'هزینه حقوق و دستمزد'),
    Moeen(mInsuranceExpense, 'هزینه بیمه سهم کارفرما'),
    Moeen('5025', 'قیمت تمام شده درآمد پیمان در دست اجرا', TafsiliKind.none, '500250'),
    Moeen('5030', 'انحراف جذب سربار در قیمت تمام شده', TafsiliKind.none, '500300'),
    Moeen('5035', 'قیمت تمام شده فروش موجودی کالای متفرقه', TafsiliKind.none, '500350'),
    Moeen(mCogs, 'قیمت تمام شده کالاهای فروخته شده از موجودی کالا', TafsiliKind.product, '500400'),
    Moeen('5045', 'قیمت تمام شده برگشت از خرید موجودی کالا', TafsiliKind.none, '500450'),
    Moeen(mSaleDiscount, 'تخفیف از فروش', TafsiliKind.none, '500500'),
    Moeen(mSalesReturn, 'برگشت از فروش موجودی کالا', TafsiliKind.product, '500550'),
    Moeen('5060', 'قیمت تمام شده اموال و ماشین آلات', TafsiliKind.none, '500600'),
    Moeen(mStockLoss, 'ضایعات و کسری انبار', TafsiliKind.product),
    Moeen(mLoanCost, 'هزینه تسهیلات'),
    Moeen(mDepreciation, 'هزینه استهلاک'),
  ]),
  Kol('80', 'حسابهای اختتامیه', Side.equity, [
    Moeen('8010', 'تراز اختتامیه', TafsiliKind.none, '800100'),
    Moeen('8020', 'خلاصه حساب سود و زیان', TafsiliKind.none, '800200'),
  ]),
];

/// Taraz's former 5-digit codes → Sakan codes (used once to convert saved data).
const legacyCodeMap = <String, String>{
  '10101': mPettyCash, '10102': mCash, '10103': mCashFx,
  '10201': mBank, '10202': mBankFx,
  '10301': mChequesAtCash, '10302': mChequesAtBank,
  '10401': mStock, '10402': mStockConsign,
  '10501': mAssets,
  '10601': mDebtorsTrade, '10602': mDebtorsFx, '10603': mDebtorsOther, '10604': mOtherPersonsDr,
  '10701': mPrepayments, '10702': mDeposits, '10703': '1240',
  '20101': mChequesPayable,
  '20201': mDebtorsTrade, '20202': mDebtorsFx, '20203': mDebtorsOther, '20204': mOtherPersonsDr,
  '20301': '2065', '20302': mAccDepreciation,
  '20401': '2130', '20402': '2040', '20403': '2140',
  '20501': mAdvances, '20502': mOtherControl,
  '20601': mLoans, '20602': '2120', '20603': mOtherLiab, '20604': '2045',
  '30101': mCapital, '30102': mDrawings, '30103': mRetained, '30104': mPartners,
  '40101': mIncome, '40102': mOtherIncome, '40103': mSales, '40104': mSalesReturn, '40105': mPurchaseDiscount,
  '50101': mExpense, '50102': mOtherExpense, '50103': mCogs, '50104': mSaleDiscount,
  '50105': mStockLoss, '50106': mLoanCost, '50107': mDepreciation,
};

/// Former 3-digit groups → new groups (for ledgers the user made).
const legacyKolMap = <String, String>{
  '101': '10', '102': '10', '103': '11', '104': '11', '105': '12', '106': '11', '107': '11',
  '201': '20', '202': '11', '203': '21', '204': '21', '205': '20', '206': '21',
  '301': '30', '401': '40', '501': '50',
};

/// The group (کل) of a ledger code; also accepts a group code.
Kol kolOf(String code) {
  for (final k in chart) {
    if (k.code == code) return k;
    for (final m in k.moeens) {
      if (m.code == code) return k;
    }
  }
  return chart.firstWhere((k) => code.startsWith(k.code), orElse: () => chart.last);
}

bool isKolCode(String code) => chart.any((k) => k.code == code);

Moeen? findMoeen(String? code) {
  if (code == null || code.isEmpty) return null;
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

/// Next free Sakan-style code for a ledger the user makes in group [kolCode]:
/// the first unused code of the group's range (e.g. 1001…1099 for «10»).
String? nextLedgerCode(String kolCode) {
  final used = {for (final m in allMoeens) m.code};
  final base = int.parse(kolCode) * 100;
  for (var c = base + 1; c < base + 100; c++) {
    if (!used.contains('$c')) return '$c';
  }
  return null;
}
