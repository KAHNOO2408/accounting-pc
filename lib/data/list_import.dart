/// «ورود لیستی اطلاعات» and «دریافت اطلاعات از فایل اکسل» (Sakan): rows of
/// people, products, personnel, assets, opening balances or invoice items,
/// read from Excel with a column ↔ field mapping («معادل سازی»), checked
/// («بررسی اطلاعات»), and inserted («تایید و درج اطلاعات»). Sakan's own
/// Excel exports (ProductName / Barcode / FanyN …) are recognised.
library;

import '../core/format.dart' show parseMoney;
import '../core/jalali.dart';
import 'chart.dart' show findMoeen;
import 'models.dart';
import 'payroll.dart';
import 'store.dart';

enum ImportKind { people, products, employees, assets, balances }

extension ImportKindX on ImportKind {
  String get label => switch (this) {
        ImportKind.people => 'اشخاص',
        ImportKind.products => 'کالا و خدمات',
        ImportKind.employees => 'پرسنل',
        ImportKind.assets => 'اموال',
        ImportKind.balances => 'مانده اول دوره دفاتر',
      };
}

class ImportField {
  final String key;
  final String label;
  final bool required;
  final List<String> synonyms; // header texts that map to this field
  const ImportField(this.key, this.label, {this.required = false, this.synonyms = const []});
}

const _peopleFields = [
  ImportField('name', 'نام شخص', required: true, synonyms: ['نام', 'نام شخص', 'نام طرف حساب', 'عنوان حساب', 'نام حساب', 'نام دفتر', 'BName', 'Name', 'نام و نام خانوادگی', 'BName', 'TarafHesabName']),
  ImportField('code', 'کد', synonyms: ['کد', 'کد شخص', 'کد حساب', 'کد دفتر', 'شماره اختصاصی', 'BID', 'Code', 'Bid']),
  ImportField('kind', 'نوع شخص', synonyms: ['نوع شخص', 'نوع', 'HType']),
  ImportField('company', 'نام شرکت', synonyms: ['نام شرکت', 'شرکت', 'CompanyName']),
  ImportField('phone', 'تلفن', synonyms: ['تلفن', 'تلفن ثابت', 'Tel', 'Tel1', 'Tel1', 'tel']),
  ImportField('mobile', 'همراه', synonyms: ['همراه', 'موبایل', 'تلفن همراه', 'شماره پیامک', 'Mobile', 'tel2', 'SMS']),
  ImportField('nationalId', 'کد ملی', synonyms: ['کد ملی', 'شناسه ملی', 'کدملی', 'شماره ملی', 'mellinum', 'melinum', 'f28']),
  ImportField('economicCode', 'شماره اقتصادی', synonyms: ['شماره اقتصادی', 'کد اقتصادی', 'EghtesadyNumber', 'CorporateCode', 'codeeghtesady']),
  ImportField('postalCode', 'کد پستی', synonyms: ['کد پستی', 'کدپستی', 'CodePosti', 'PostalCode']),
  ImportField('province', 'نام استان', synonyms: ['نام استان', 'استان', 'state', 'Tezih1']),
  ImportField('city', 'نام شهرستان', synonyms: ['نام شهرستان', 'شهرستان', 'شهر', 'city', 'Tezih2']),
  ImportField('cityCode', 'پیش شماره', synonyms: ['پیش شماره', 'کد شهر', 'پیش کد شهر', 'Pishshomare']),
  ImportField('address', 'آدرس', synonyms: ['آدرس', 'نشانی', 'Address', 'CAddress']),
  ImportField('note', 'ملاحظات', synonyms: ['ملاحظات', 'توضیحات', 'شرح', 'Molahezat', 'Tozihat']),
  ImportField('marketer', 'بازاریاب', synonyms: ['بازاریاب']),
  ImportField('balance', 'مانده اول دوره', synonyms: ['مانده', 'مانده اول دوره', 'مانده حساب', 'Remain', 'mande']),
  ImportField('debit', 'بدهکار', synonyms: ['بدهکار', 'مانده بدهکار', 'Bed', 'BedRemain']),
  ImportField('credit', 'بستانکار', synonyms: ['بستانکار', 'مانده بستانکار', 'Bes', 'BesRemain']),
];

const _productFields = [
  ImportField('name', 'نام کالا', required: true, synonyms: ['نام کالا', 'نام', 'شرح کالا', 'ProductName', 'FrasiName', 'نام فارسی', 'KalaName', 'NameKala']),
  ImportField('code', 'کد کالا', synonyms: ['کد کالا', 'کد', 'BID', 'Code', 'CodeKala', 'KalaCode']),
  ImportField('unit', 'نام واحد اول', synonyms: ['نام واحد اول', 'واحد', 'واحد اول', 'FanyN', 'Vahed1', 'VahedName', 'VahedName1', 'vahed1name', 'VahedName']),
  ImportField('barcode', 'بارکد', synonyms: ['بارکد', 'Barcode']),
  ImportField('nationalBarcode', 'بارکد ملی', synonyms: ['بارکد ملی', 'ایران کد', 'IranCode', 'IranCode']),
  ImportField('techNo', 'شماره فنی', synonyms: ['شماره فنی', 'TechNo', 'FanyNo']),
  ImportField('latin', 'نام لاتین', synonyms: ['نام لاتین', 'نام کالا لاتین', 'EnglishName', 'EnglishName', 'latinNme']),
  ImportField('buy', 'بهای خرید واحد اول', synonyms: ['بهای خرید واحد اول', 'بهای خرید', 'فی خرید', 'قیمت خرید', 'خرید1', 'BuyPrice1', 'FiKharid']),
  ImportField('sell', 'فی 1 فروش واحد اول', synonyms: ['فی 1 فروش واحد اول', 'فی 1 فروش', 'بهای فروش', 'فی فروش', 'قیمت فروش', 'فروش1', 'SellPrice1']),
  ImportField('sell2', 'فی 2 فروش واحد اول', synonyms: ['فی 2 فروش واحد اول', 'فی 2 فروش', 'فروش2', 'SellPrice2']),
  ImportField('sell3', 'فی 3 فروش واحد اول', synonyms: ['فی 3 فروش واحد اول', 'فی 3 فروش', 'فروش3', 'SellPrice3']),
  ImportField('consumerPrice', 'بهای مصرف کننده', synonyms: ['بهای مصرف کننده', 'قیمت مصرف کننده', 'FiMasrafKonande']),
  ImportField('unit2', 'نام واحد دوم', synonyms: ['نام واحد دوم', 'واحد دوم', 'VahedName2', 'vahed2name']),
  ImportField('ratio2', 'نسبت واحد دوم به واحد اول', synonyms: ['نسبت واحد دوم به واحد اول', 'نسبت واحد 2 به واحد 1', 'NesbatV2BV1', 'Each2Equal1']),
  ImportField('unit3', 'نام واحد سوم', synonyms: ['نام واحد سوم', 'واحد سوم', 'VahedName3', 'vahed3name']),
  ImportField('ratio3', 'نسبت واحد سوم به واحد اول', synonyms: ['نسبت واحد سوم به واحد اول', 'نسبت واحد 3 به واحد 1', 'NesbatV3BV1', 'Each1Equal3']),
  ImportField('minQty', 'حداقل موجودی', synonyms: ['حداقل موجودی', 'minimum']),
  ImportField('maxQty', 'حداکثر موجودی', synonyms: ['حداکثر موجودی', 'maximum']),
  ImportField('orderPoint', 'نقطه سفارش', synonyms: ['نقطه سفارش', 'orderpoint']),
  ImportField('weight', 'وزن کالا', synonyms: ['وزن کالا', 'وزن', 'وزن (کیلوگرم)', 'vazn', 'kalaweight']),
  ImportField('taxPct', 'درصد مالیات', synonyms: ['درصد مالیات', 'DarsadTax', 'SMaliat']),
  ImportField('dutyPct', 'درصد عوارض', synonyms: ['درصد عوارض', 'DarsadAvarez', 'avarez']),
  ImportField('discountPct', 'درصد تخفیف', synonyms: ['درصد تخفیف', 'DarsadTakhfif']),
  ImportField('marketingPct', 'درصد بازاریابی', synonyms: ['درصد بازاریابی', 'DarsadBazaryabi', 'BazaryabPercent']),
  ImportField('returnPct', 'درصد مرجوعی', synonyms: ['درصد مرجوعی']),
  ImportField('note', 'مشخصات کالا', synonyms: ['مشخصات کالا', 'توضیحات', 'Properties', 'moshakhasatkala']),
  ImportField('restaurant', 'کالای رستورانی', synonyms: ['کالای رستورانی']),
  ImportField('serial', 'سریال دارد', synonyms: ['سریال دارد', 'کنترل سریال']),
  ImportField('openingQty', 'موجودی اول دوره', synonyms: ['موجودی اول دوره', 'موجودی', 'تعداد', 'RemainTedad', 'Tedad']),
  ImportField('openingCost', 'فی موجودی اول دوره', synonyms: ['فی موجودی اول دوره', 'فی موجودی', 'قیمت تمام شده', 'GhimatCardex']),
];

const _employeeFields = [
  ImportField('firstName', 'نام', required: true, synonyms: ['نام', 'nme']),
  ImportField('lastName', 'نام خانوادگی', required: true, synonyms: ['نام خانوادگی', 'فامیلی', 'FamilyNme']),
  ImportField('fatherName', 'نام پدر', synonyms: ['نام پدر', 'fatherName']),
  ImportField('nationalId', 'کد ملی', synonyms: ['کد ملی', 'شماره ملی', 'mellinum', 'melinum']),
  ImportField('idNo', 'شماره شناسنامه', synonyms: ['شماره شناسنامه', 'shsh']),
  ImportField('issuePlace', 'محل صدور', synonyms: ['محل صدور', 'mahaleSodor']),
  ImportField('birthDate', 'تاریخ تولد', synonyms: ['تاریخ تولد', 'DteBirth']),
  ImportField('sex', 'جنسیت', synonyms: ['جنسیت', 'Sex']),
  ImportField('married', 'وضعیت تاهل', synonyms: ['وضعیت تاهل', 'تاهل', 'married']),
  ImportField('nationality', 'ملیت', synonyms: ['ملیت', 'meliat']),
  ImportField('phone', 'تلفن', synonyms: ['تلفن', 'همراه', 'همراه SMS', 'موبایل', 'Mobile']),
  ImportField('address', 'آدرس', synonyms: ['آدرس', 'Address']),
  ImportField('personnelCode', 'کد پرسنلی', synonyms: ['کد پرسنلی', 'PersonelCode']),
  ImportField('cardCode', 'شماره کارت', synonyms: ['شماره کارت', 'شماره کارت پرسنلی', 'cardcode', 'CardNo']),
  ImportField('jobName', 'شغل', synonyms: ['شغل', 'نام شغل', 'jobName']),
  ImportField('insuranceNo', 'شماره بیمه', synonyms: ['شماره بیمه', 'BimeNumber', 'empbimeNumber']),
  ImportField('accountNo', 'شماره حساب', synonyms: ['شماره حساب', 'HesabNumber']),
  ImportField('hireDate', 'تاریخ استخدام', synonyms: ['تاریخ استخدام', 'empDteEstekhdam']),
  ImportField('monthlyWage', 'حقوق ماهیانه', synonyms: ['حقوق ماهیانه', 'حقوق پایه', 'hoghoghMahiane']),
];

const _assetFields = [
  ImportField('name', 'نام اموال', required: true, synonyms: ['نام اموال', 'نام', 'AmvalName']),
  ImportField('assetNo', 'شماره اموال', synonyms: ['شماره اموال']),
  ImportField('location', 'محل استقرار', synonyms: ['محل استقرار', 'محل']),
  ImportField('receiver', 'تحویل گیرنده', synonyms: ['تحویل گیرنده']),
  ImportField('cost', 'بهای تمام شده', synonyms: ['بهای تمام شده', 'مبلغ', 'قیمت']),
];

const _balanceFields = [
  ImportField('code', 'کد دفتر', synonyms: ['کد دفتر', 'کد حساب', 'کد', 'BID', 'bid', 'BCode', 'bookid']),
  ImportField('name', 'نام دفتر', synonyms: ['نام دفتر', 'نام حساب', 'عنوان حساب', 'نام', 'BName', 'bname', 'bookname']),
  ImportField('amount', 'مبلغ', synonyms: ['مبلغ', 'مانده', 'Remain', 'mande']),
  ImportField('debit', 'بدهکار', synonyms: ['بدهکار', 'مانده بدهکار', 'Bed', 'BedRemain']),
  ImportField('credit', 'بستانکار', synonyms: ['بستانکار', 'مانده بستانکار', 'Bes', 'BesRemain']),
  ImportField('side', 'تشخیص', synonyms: ['تشخیص', 'typ', 'tashkhis']),
];

List<ImportField> importFields(ImportKind k) => switch (k) {
      ImportKind.people => _peopleFields,
      ImportKind.products => _productFields,
      ImportKind.employees => _employeeFields,
      ImportKind.assets => _assetFields,
      ImportKind.balances => _balanceFields,
    };

String _norm(String s) => normalizeDigits(s).replaceAll('‌', ' ').replaceAll(RegExp(r'[\s:_]+'), '').replaceAll('ي', 'ی').replaceAll('ك', 'ک').toLowerCase();

/// «معادل سازی»: field key → column index, from the header row.
Map<String, int> autoMap(ImportKind k, List<String> header) {
  final out = <String, int>{};
  final hs = [for (final h in header) _norm(h)];
  for (final f in importFields(k)) {
    for (final syn in [f.label, ...f.synonyms]) {
      final i = hs.indexOf(_norm(syn));
      if (i >= 0 && !out.containsValue(i)) {
        out[f.key] = i;
        break;
      }
    }
  }
  return out;
}

/// Turns sheet rows into field maps with [map] (skipping the header and empty rows).
List<Map<String, String>> mapRows(List<List<String>> rows, Map<String, int> map, {bool header = true}) => [
      for (final r in rows.skip(header ? 1 : 0))
        if (r.any((c) => c.trim().isNotEmpty))
          {for (final e in map.entries) e.key: e.value < r.length ? r[e.value].trim() : ''},
    ];

double _num(String? v) => double.tryParse(normalizeDigits(v ?? '').replaceAll(',', '').replaceAll('٬', '').trim()) ?? 0;
bool _yes(String? v) => const {'1', 'بله', 'دارد', 'true', 'yes', 'x', '✓', 'بلی'}.contains((v ?? '').trim().toLowerCase());

DateTime? _date(String? v) {
  final t = normalizeDigits(v ?? '').trim();
  final serial = double.tryParse(t);
  if (serial != null && serial > 20000 && serial < 80000) return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
  final m = RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(t);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  return y < 1700 ? Jalali(y, mo, d).toDateTime() : DateTime(y, mo, d);
}

/// Signed opening amount: «مانده» (with «تشخیص» بد/بس) or «بدهکار» − «بستانکار».
int _signed(Map<String, String> r) {
  if ((r['debit'] ?? '').isNotEmpty || (r['credit'] ?? '').isNotEmpty) return _num(r['debit']).round() - _num(r['credit']).round();
  final a = (r['amount'] ?? r['balance'] ?? '').trim();
  var v = _num(a.replaceAll(RegExp(r'[()]'), '')).round();
  if (a.startsWith('(') || a.startsWith('-')) v = -v.abs();
  final side = (r['side'] ?? '').trim();
  if (side.startsWith('بس') || side == 'cr') v = -v.abs();
  return v;
}

extension ListImport on AppStore {
  /// «بررسی اطلاعات»: one message per row ('' = ok).
  List<String> checkImport(ImportKind k, List<Map<String, String>> rows) {
    final errs = <String>[];
    final seen = <String>{};
    for (final r in rows) {
      final e = <String>[];
      for (final f in importFields(k).where((f) => f.required)) {
        if ((r[f.key] ?? '').trim().isEmpty) e.add('${f.label} خالی است');
      }
      final code = (r['code'] ?? '').trim();
      if (code.isNotEmpty && k != ImportKind.balances && !seen.add(code)) e.add('کد $code در لیست تکراری است');
      switch (k) {
        case ImportKind.people:
          final nid = normalizeDigits(r['nationalId'] ?? '');
          if (nid.isNotEmpty && !RegExp(r'^\d{10,11}$').hasMatch(nid)) e.add('کد ملی نامعتبر است');
          if (code.isNotEmpty && int.tryParse(normalizeDigits(code)) == null) e.add('کد باید عدد باشد');
        case ImportKind.products:
          for (final key in ['buy', 'sell', 'sell2', 'sell3', 'openingQty', 'openingCost']) {
            final v = (r[key] ?? '').trim();
            if (v.isNotEmpty && double.tryParse(normalizeDigits(v).replaceAll(',', '')) == null) e.add('${importFields(k).firstWhere((f) => f.key == key).label} عدد نیست');
          }
        case ImportKind.employees:
          final nid = normalizeDigits(r['nationalId'] ?? '');
          if (nid.isNotEmpty && nid.length != 10) e.add('کد ملی باید ۱۰ رقم باشد');
          final pc = (r['personnelCode'] ?? '').trim();
          if (pc.isNotEmpty && employees.any((x) => x.personnelCode == pc && '${x.firstName} ${x.lastName}' != '${r['firstName']} ${r['lastName']}')) e.add('کد پرسنلی $pc تکراری است');
        case ImportKind.balances:
          if (code.isEmpty && (r['name'] ?? '').trim().isEmpty) e.add('کد یا نام دفتر لازم است');
          if (_balanceTarget(r) == null) e.add('دفتر «${r['name'] ?? code}» پیدا نشد');
        case ImportKind.assets:
          break;
      }
      errs.add(e.join('، '));
    }
    return errs;
  }

  /// The person, account or ledger an opening row belongs to.
  (String, String?)? _balanceTarget(Map<String, String> r) {
    final code = normalizeDigits((r['code'] ?? '').trim());
    final name = (r['name'] ?? '').trim();
    final p = people.where((p) => (code.isNotEmpty && '${p.code}' == code) || (name.isNotEmpty && p.name == name)).firstOrNull;
    if (p != null) return ('person', p.id);
    final a = accounts.where((a) => a.name == name).firstOrNull;
    if (a != null) return ('account', a.id);
    final pr = products.where((x) => (code.isNotEmpty && x.code == code) || (name.isNotEmpty && x.name == name)).firstOrNull;
    if (pr != null) return ('product', pr.id);
    if (code.isNotEmpty && findMoeen(code) != null) return ('moeen', code);
    return null;
  }

  /// «تایید و درج اطلاعات»: inserts the rows without errors; existing records
  /// (same code, or same name) are updated. Returns (inserted, updated).
  (int, int) applyImport(ImportKind k, List<Map<String, String>> rows) {
    var ins = 0, upd = 0;
    final errs = checkImport(k, rows);
    final opening = <VoucherLine>[];
    for (var i = 0; i < rows.length; i++) {
      if (errs[i].isNotEmpty) continue;
      final r = rows[i];
      String v(String key) => (r[key] ?? '').trim();
      switch (k) {
        case ImportKind.people:
          final code = int.tryParse(normalizeDigits(v('code'))) ?? 0;
          final old = people.where((p) => (code != 0 && p.code == code) || p.name == v('name')).firstOrNull;
          final p = old ?? Person(id: newId(), name: v('name'), code: code);
          p.name = v('name');
          if (v('phone').isNotEmpty || v('mobile').isNotEmpty) p.phone = [v('mobile'), v('phone')].where((x) => x.isNotEmpty).join('، ');
          if (v('note').isNotEmpty) p.note = v('note');
          if (v('marketer').isNotEmpty) p.marketer = _yes(v('marketer'));
          if (v('kind').isNotEmpty) p.info['kind'] = v('kind').contains('حقوق') ? 'legal' : 'real';
          for (final key in ['nationalId', 'economicCode', 'postalCode', 'province', 'city', 'cityCode', 'address']) {
            if (v(key).isNotEmpty) p.info[key] = key == 'address' || key == 'province' || key == 'city' ? v(key) : normalizeDigits(v(key));
          }
          if (v('company').isNotEmpty) p.info['company'] = v('company');
          if (v('balance').isNotEmpty || v('debit').isNotEmpty || v('credit').isNotEmpty) p.opening = _signed({...r, 'amount': r['balance'] ?? ''});
          upsertPerson(p);
          old == null ? ins++ : upd++;
        case ImportKind.products:
          final old = products.where((p) => (v('code').isNotEmpty && p.code == v('code')) || (v('barcode').isNotEmpty && p.info['barcode'] == normalizeDigits(v('barcode'))) || p.name == v('name')).firstOrNull;
          final p = old ?? Product(id: newId(), name: v('name'), code: v('code'));
          p.name = v('name');
          if (v('code').isNotEmpty) p.code = v('code');
          if (v('unit').isNotEmpty) p.unit = v('unit');
          if (v('buy').isNotEmpty) p.buyPrice = parseMoney(v('buy'));
          if (v('sell').isNotEmpty) p.sellPrice = parseMoney(v('sell'));
          if (v('sell2').isNotEmpty) p.sellPrice2 = parseMoney(v('sell2'));
          if (v('sell3').isNotEmpty) p.sellPrice3 = parseMoney(v('sell3'));
          if (v('unit2').isNotEmpty) p.unit2 = v('unit2');
          if (v('ratio2').isNotEmpty) p.ratio2 = _num(v('ratio2'));
          if (v('unit3').isNotEmpty) p.unit3 = v('unit3');
          if (v('ratio3').isNotEmpty) p.ratio3 = _num(v('ratio3'));
          if (v('minQty').isNotEmpty) p.minQty = _num(v('minQty'));
          if (v('weight').isNotEmpty) p.weight = _num(v('weight'));
          if (v('note').isNotEmpty) p.note = v('note');
          if (v('openingQty').isNotEmpty) p.openingQty = _num(v('openingQty'));
          if (v('openingCost').isNotEmpty) p.openingCost = parseMoney(v('openingCost'));
          for (final key in ['barcode', 'nationalBarcode', 'techNo', 'latin', 'consumerPrice', 'maxQty', 'orderPoint', 'taxPct', 'dutyPct', 'discountPct', 'marketingPct', 'returnPct']) {
            if (v(key).isNotEmpty) p.info[key] = key == 'latin' ? v(key) : normalizeDigits(v(key)).replaceAll(',', '');
          }
          if (v('restaurant').isNotEmpty) p.info['restaurant'] = _yes(v('restaurant')) ? '1' : '';
          if (v('serial').isNotEmpty) p.info['serial'] = _yes(v('serial')) ? '1' : '';
          p.info.removeWhere((_, x) => x.isEmpty);
          upsertProduct(p);
          old == null ? ins++ : upd++;
        case ImportKind.employees:
          final old = employees.where((e) => (v('personnelCode').isNotEmpty && e.personnelCode == v('personnelCode')) || (v('nationalId').isNotEmpty && e.nationalId == normalizeDigits(v('nationalId')))).firstOrNull;
          final e = old ?? Employee(id: newId(), personId: '');
          e
            ..firstName = v('firstName')
            ..lastName = v('lastName');
          if (v('fatherName').isNotEmpty) e.fatherName = v('fatherName');
          if (v('nationalId').isNotEmpty) e.nationalId = normalizeDigits(v('nationalId'));
          if (v('idNo').isNotEmpty) e.idNo = normalizeDigits(v('idNo'));
          if (v('issuePlace').isNotEmpty) e.issuePlace = v('issuePlace');
          if (v('birthDate').isNotEmpty) e.birthDate = _date(v('birthDate'));
          if (v('hireDate').isNotEmpty) e.hireDate = _date(v('hireDate'));
          if (v('sex').isNotEmpty) e.male = !v('sex').contains('زن') && !v('sex').contains('مونث');
          if (v('married').isNotEmpty) e.married = v('married').contains('متاهل') || _yes(v('married'));
          if (v('nationality').isNotEmpty) e.nationality = v('nationality');
          if (v('phone').isNotEmpty) e.phone = v('phone');
          if (v('address').isNotEmpty) e.address = v('address');
          if (v('personnelCode').isNotEmpty) e.personnelCode = v('personnelCode');
          if (v('cardCode').isNotEmpty) e.cardCode = v('cardCode');
          if (v('jobName').isNotEmpty) e.jobName = v('jobName');
          if (v('insuranceNo').isNotEmpty) e.insuranceNo = v('insuranceNo');
          if (v('accountNo').isNotEmpty) e.accountNo = v('accountNo');
          if (v('monthlyWage').isNotEmpty) e.monthlyWage = parseMoney(v('monthlyWage'));
          if (saveEmployee(e) == null) old == null ? ins++ : upd++;
        case ImportKind.assets:
          final old = assets.where((a) => (v('assetNo').isNotEmpty && a.assetNo == v('assetNo')) || a.name == v('name')).firstOrNull;
          final a = old ?? Asset(id: newId(), code: nextAssetCode(), name: v('name'));
          a
            ..name = v('name')
            ..assetNo = v('assetNo').isEmpty ? a.assetNo : v('assetNo')
            ..location = v('location').isEmpty ? a.location : v('location')
            ..receiver = v('receiver').isEmpty ? a.receiver : v('receiver');
          if (v('cost').isNotEmpty) a.cost = parseMoney(v('cost'));
          saveAsset(a);
          old == null ? ins++ : upd++;
        case ImportKind.balances:
          final t = _balanceTarget(r)!;
          final amount = _signed(r);
          switch (t.$1) {
            case 'person':
              person(t.$2)!.opening = amount;
              upsertPerson(person(t.$2)!);
            case 'account':
              final a = account(t.$2)!..opening = amount;
              upsertAccount(a);
            case 'product':
              final p = product(t.$2)!;
              if (p.openingQty > 0) p.openingCost = (amount / p.openingQty).round();
              upsertProduct(p);
            default:
              if (amount != 0) opening.add(VoucherLine(moeen: t.$2!, desc: 'مانده اول دوره ${v('name')}', debit: amount > 0 ? amount : 0, credit: amount < 0 ? -amount : 0));
          }
          upd++;
      }
    }
    if (opening.isNotEmpty) {
      updateSettings((st) {
        for (final l in opening) {
          st.openingOther[l.moeen] = l.debit - l.credit;
        }
      });
    }
    return (ins, upd);
  }

  /// Invoice rows from Excel («دریافت اطلاعات از اکسل» in the invoice):
  /// identifies the product by name, barcode, technical number or code.
  (List<InvoiceLine>, List<String>) importInvoiceRows(List<Map<String, String>> rows, {String by = 'name'}) {
    final out = <InvoiceLine>[];
    final missing = <String>[];
    for (final r in rows) {
      final key = normalizeDigits((r['product'] ?? '').trim());
      if (key.isEmpty) continue;
      final p = products.where((p) => switch (by) {
            'barcode' => normalizeDigits(p.info['barcode'] ?? '') == key || (p.info['barcodes'] ?? '').split(',').contains(key),
            'techNo' => normalizeDigits(p.info['techNo'] ?? '') == key,
            'code' => p.code == key,
            _ => p.name.trim() == key,
          }).firstOrNull;
      if (p == null) {
        missing.add(key);
        continue;
      }
      final qty = _num(r['qty']) == 0 ? 1.0 : _num(r['qty']);
      final price = (r['price'] ?? '').isEmpty ? p.sellPrice : parseMoney(r['price']!);
      final disc = parseMoney(r['discount'] ?? '');
      final wh = warehouses.where((w) => w.name == (r['warehouse'] ?? '').trim()).firstOrNull;
      out.add(InvoiceLine(productId: p.id, title: p.name, qty: qty, unitPrice: price, discount: disc, warehouseId: wh?.id));
    }
    return (out, missing);
  }
}

const invoiceRowFields = [
  ImportField('product', 'شناسایی کالا', required: true, synonyms: ['نام کالا', 'کالا', 'بارکد', 'شماره فنی', 'کد کالا', 'ProductName', 'Barcode']),
  ImportField('qty', 'تعداد', synonyms: ['تعداد', 'تعداد1', 'مقدار']),
  ImportField('price', 'بهای واحد', synonyms: ['بهای واحد', 'فی', 'قیمت', 'فی واحد']),
  ImportField('discount', 'تخفیف', synonyms: ['تخفیف', 'تخفیف 1']),
  ImportField('warehouse', 'نام انبار', synonyms: ['نام انبار', 'انبار']),
];

Map<String, int> autoMapFields(List<ImportField> fields, List<String> header) {
  final out = <String, int>{};
  final hs = [for (final h in header) _norm(h)];
  for (final f in fields) {
    for (final syn in [f.label, ...f.synonyms]) {
      final i = hs.indexOf(_norm(syn));
      if (i >= 0 && !out.containsValue(i)) {
        out[f.key] = i;
        break;
      }
    }
  }
  return out;
}

/// «انتقال اطلاعات از سکان»: guesses what a sheet holds from its header
/// (Persian grid titles or Sakan's own column names). Null = not recognised.
ImportKind? detectKind(List<String> header) {
  ImportKind? best;
  var bestScore = 0;
  for (final k in ImportKind.values) {
    final m = autoMap(k, header);
    if (importFields(k).any((f) => f.required && !m.containsKey(f.key))) continue;
    var score = m.length;
    if (k == ImportKind.balances) {
      if (!m.containsKey('amount') && !m.containsKey('debit') && !m.containsKey('credit')) continue;
      score -= 1; // a list with its own fields wins over a bare balance list
    }
    if (score > bestScore) {
      bestScore = score;
      best = k;
    }
  }
  return best;
}
