/// «وارد کردن طرح سکان»: converts a Stimulsoft report file (.mrt), as used by
/// Sakan's report designer, into a band layout of this app. Text boxes, frames,
/// lines and rectangles keep their position and size; Sakan's data fields are
/// mapped to the fields of this app (unknown fields print empty).
library;

import 'models.dart' show PrintDocType;
import 'report_layout.dart';

// --------------------------------------------------------------------- tiny XML

class _X {
  final String name;
  final Map<String, String> attrs;
  final List<_X> children = [];
  final StringBuffer _text = StringBuffer();
  _X(this.name, this.attrs);

  String get text => _text.toString();

  _X? child(String n) {
    for (final c in children) {
      if (c.name == n) return c;
    }
    return null;
  }

  String prop(String n) => child(n)?.text.trim() ?? '';
}

String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|lt|gt|amp|quot|apos);'), (m) {
      final e = m[1]!;
      if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
      return switch (e) { 'lt' => '<', 'gt' => '>', 'amp' => '&', 'quot' => '"', _ => "'" };
    });

_X _parse(String xml) {
  final root = _X('#root', const {});
  final stack = <_X>[root];
  var i = 0;
  final n = xml.length;
  final tag = RegExp(r'<(/?)([^\s/>]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|' "'[^']*'" r'))*)\s*(/?)>');
  final attr = RegExp(r'([^\s=]+)\s*=\s*(?:"([^"]*)"|' "'([^']*)')");
  while (i < n) {
    final lt = xml.indexOf('<', i);
    if (lt < 0) {
      stack.last._text.write(_unescape(xml.substring(i)));
      break;
    }
    if (lt > i) stack.last._text.write(_unescape(xml.substring(i, lt)));
    if (xml.startsWith('<?', lt)) {
      final e = xml.indexOf('?>', lt);
      i = e < 0 ? n : e + 2;
      continue;
    }
    if (xml.startsWith('<!--', lt)) {
      final e = xml.indexOf('-->', lt);
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (xml.startsWith('<![CDATA[', lt)) {
      final e = xml.indexOf(']]>', lt);
      stack.last._text.write(xml.substring(lt + 9, e < 0 ? n : e));
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (xml.startsWith('<!', lt)) {
      final e = xml.indexOf('>', lt);
      i = e < 0 ? n : e + 1;
      continue;
    }
    final m = tag.matchAsPrefix(xml, lt);
    if (m == null) {
      stack.last._text.write('<');
      i = lt + 1;
      continue;
    }
    i = m.end;
    if (m[1] == '/') {
      if (stack.length > 1) stack.removeLast();
      continue;
    }
    final attrs = <String, String>{
      for (final a in attr.allMatches(m[3] ?? '')) a[1]!: _unescape(a[2] ?? a[3] ?? ''),
    };
    final el = _X(m[2]!, attrs);
    stack.last.children.add(el);
    if (m[4] != '/') stack.add(el);
  }
  return root;
}

// --------------------------------------------------------------------- fields

/// Sakan column → field of this app (invoices, warehouse slips).
const _invoiceMap = {
  // header (PrintInfoFrosh, InfromationFactorKharid, infoBackFrosh…)
  'Kharidar': 'نام خریدار',
  'FroshandeName': 'نام خریدار',
  'Froshande': 'نام خریدار',
  'KharidarName': 'نام خریدار',
  'Dte_Shamsi': 'تاریخ',
  'FactorDate_Shamsi': 'تاریخ',
  'DteP_Shamsi': 'تاریخ',
  'Dte': 'تاریخ',
  'Fdate_Shamsi': 'تاریخ',
  'ShFactor': 'شماره فاکتور',
  'FCode': 'شماره فاکتور',
  'HavaleNum': 'شماره حواله',
  'DocMabnaNum': 'شماره سند',
  'DocNum': 'شماره سند',
  'Tel1': 'تلفن فروشنده',
  'Tel2': 'تلفن فروشنده',
  'KharidarTel': 'تلفن خریدار',
  'Mobile': 'تلفن خریدار',
  'Address': 'آدرس خریدار',
  'Babat': 'بابت',
  'shdarkhast': 'شماره درخواست',
  'JamFator_system': 'جمع کل فاکتور',
  'JamFator': 'جمع کل فاکتور',
  'MablaghFactorSystem': 'جمع کل فاکتور',
  'MablagKolFactorTSystem': 'جمع اقلام با احتساب تخفیف',
  'MablagKolFactorT': 'جمع اقلام با احتساب تخفیف',
  'MablagKolFactorSystem': 'جمع فاکتور بدون تخفیف',
  'MablagKolFactor': 'جمع فاکتور بدون تخفیف',
  'MablaghFactorBKHTSystem': 'جمع فاکتور بدون تخفیف',
  'JamTakhfif_sys': 'جمع تخفیف',
  'JamTakhfif': 'جمع تخفیف',
  'JamTakhfifAghlam_system': 'جمع تخفیف',
  'HazineKharidar_system': 'هزینه حمل بعهده خریدار',
  'HazineKharidar': 'هزینه حمل بعهده خریدار',
  'jamHazinehaSystem': 'هزینه حمل بعهده فروشنده',
  'BedBesRemainOld_system': 'مانده حساب از قبل',
  'BedBesRemainOld': 'مانده حساب از قبل',
  'BedBesRemainNew_system': 'کل مانده حساب',
  'BedBesRemainNew': 'کل مانده حساب',
  'BedRemainNew_System': 'کل مانده حساب',
  'JamDrayafti_system': 'جمع دریافتی',
  'JamDrayafti': 'جمع دریافتی',
  'JamPardakhati_system': 'جمع دریافتی',
  'JamPardakhati': 'جمع دریافتی',
  'TasvieDateNumber': 'نحوه تسویه',
  'Tozihat': 'توضیحات',
  // PrintMali
  'Money_TakhfifAzForosh': 'مبلغ تخفیف از فروش',
  'Money_TakhfifAzKharid': 'مبلغ تخفیف از فروش',
  'Money_DaryafteCheq': 'مبلغ دریافت چک',
  'Money_PardakhteCheq': 'مبلغ دریافت چک',
  'Money_DaryaftNaghdy': 'مبلغ دریافت نقدی',
  'Money_PardakhtNaghdy': 'مبلغ دریافت نقدی',
  'Money_DaryaftHavaleyeBanki': 'مبلغ حواله بانکی',
  'Money_PardakhtHavaleyeBanki': 'مبلغ حواله بانکی',
  // company (Information)
  'ReportHeader': 'نام فروشگاه',
  'CompanyName': 'نام فروشگاه',
  'DaftarName': 'نام فروشگاه',
  'CAddress': 'آدرس فروشگاه',
  'Tels': 'تلفن فروشنده',
  'DateShamsi': 'تاریخ',
  // Sakan fields (docs/sakan/forms)
  'TypeFactor': 'کد نوع فاکتور',
  'Factor': 'نوع فاکتور',
  'FactorDate_x0020_Shamsi': 'تاریخ فروش',
  'FactorDate': 'تاریخ فروش',
  'DateFactor_Shamsi': 'تاریخ',
  'Kharidar_ID': 'کد خریدار',
  'jam_cardex': 'قیمت تمام شده فاکتور',
  'JamCrdexSystem': 'قیمت تمام شده فاکتور',
  'JamVaznKalaFactor': 'وزن فاکتور',
  'ArzName': 'ارز سیستم',
  'JamKalaSystem': 'جمع فاکتور بدون تخفیف',
  'JamTakhfifSystem': 'جمع تخفیف',
  'JamMablaghSystem': 'جمع اقلام با احتساب تخفیف',
  'JamFactor': 'جمع کل فاکتور',
  'Fid': 'شماره فاکتور',
  'NameTarafHesab': 'نام خریدار',
  'TarafHesabName': 'نام خریدار',
  'BalancKharidarName': 'نام خریدار',
  'ForoshandeBName': 'نام خریدار',
  'PardakhtKonande': 'نام خریدار',
  'BazaryabName': 'بازاریابان',
  'BazaryabBName': 'بازاریابان',
  'BazaryabMob': 'شماره همراه بازاریاب',
  'HazineBazaryabanSystem': 'هزینه پورسانت',
  'HazineBazaryaban2ArzKaridar': 'هزینه پورسانت',
  'MPakhshName': 'مسئول پخش',
  'MPakhshBName': 'مسئول پخش',
  'MPakhshMob': 'شماره همراه مسئول پخش',
  'JamMaliatF_sys': 'جمع مالیات',
  'JamMaliat_sys': 'جمع مالیات',
  'JamMaliataghlam_sys': 'جمع مالیات',
  'JamArzeshF_sys': 'جمع عوارض',
  'JamArzesh_sys': 'جمع عوارض',
  'Jamavaezaghlam_sys': 'جمع عوارض',
  'MablaghArzeshSystem': 'جمع مالیات و عوارض',
  'SahemArzeshSystem': 'جمع مالیات و عوارض',
  'AvarezMaliatFull': 'جمع مالیات و عوارض',
};

/// Columns of the item rows.
const _rowMap = {
  'FrasiName': 'نام کالا',
  'KalaName': 'نام کالا',
  'Name': 'نام کالا',
  'FiVahed1System': 'فی واحد 1',
  'Fiv1System': 'فی',
  'Fi_system': 'فی',
  'FiVahed1': 'فی واحد 1',
  'Fi': 'فی',
  'TedadVahed1': 'تعداد واحد 1',
  'Tedad': 'تعداد',
  'VahedName1': 'واحد 1',
  'VahedName': 'واحد',
  'JamKalaKaridarSystem': 'جمع',
  'JamKalaKaridar': 'جمع',
  'jamesatr': 'جمع',
  'JamKol': 'جمع',
  'Jam1System': 'جمع بدون تخفیف',
  'TakhfifSystem': 'تخفیف',
  'Takhfif': 'تخفیف',
  'Barcode': 'کد کالا',
  'KalaCode': 'کد کالا',
  'Code': 'کد کالا',
  'AnbarName': 'نام انبار',
  // Sakan fields (docs/sakan/forms)
  'AName': 'نام انبار',
  'StoreName': 'نام انبار',
  'CodeKala': 'کد کالا',
  'FanyNo': 'شماره فنی',
  'Properties': 'مشخصات کالا',
  'VazenKalaBeV1': 'وزن واحد',
  'JamVazenKala': 'جمع وزن کالا',
  'GhimatCardex': 'قیمت تمام شده',
  'GhimatCardexSystem': 'قیمت تمام شده',
  'SodNAKhalsSystem': 'سود و زیان ناخالص ردیف',
  'SodNAKhales': 'سود و زیان ناخالص ردیف',
  'SodNAKhalsKaridar': 'سود و زیان ناخالص ردیف',
  'darsadSodNakhales': 'درصد سود ردیف',
  'DarsadTakhfif': 'درصد تخفیف',
  'SellPrice1': 'بهای فروش 1',
  'SellPrice2': 'بهای فروش 2',
  'SellPrice3': 'بهای فروش 3',
  'MojodiTedad1': 'موجودی',
  'TedadAll1': 'موجودی',
  'Vahed1': 'واحد 1',
  'JamMablaghSystem': 'جمع',
  'JamT_sys': 'جمع',
  'JamSystem': 'جمع',
  'Jam1Syatem': 'جمع بدون تخفیف',
  'Takhfif_System': 'تخفیف',
  'Number': 'تعداد',
  'Tedad1': 'تعداد',
  'TedadV1': 'تعداد',
  'FiV1': 'فی',
  'FioteadV1_System': 'فی',
  'BuyPrice1': 'فی',
  'MainVahedId': 'واحد منتخب',
  'MainVahedid': 'واحد منتخب',
  'VahedName2': 'واحد 2',
  'VhaedName2': 'واحد 2',
  'Vahed2Name': 'واحد 2',
  'Vahed2': 'واحد 2',
  'VahedName3': 'واحد 3',
  'VahedNAme3': 'واحد 3',
  'Vahed3': 'واحد 3',
  'TedadVahed2': 'تعداد واحد 2',
  'TedadVahed3': 'تعداد واحد 3',
  'FiVahed2System': 'فی واحد 2',
  'Fivahed2System': 'فی واحد 2',
  'FiVahed3System': 'فی واحد 3',
  'Fivahed3System': 'فی واحد 3',
  'NesbatV2BV1': 'نسبت واحد 2 به واحد 1',
  'Each2Equal1': 'نسبت واحد 2 به واحد 1',
  'Nesbat21': 'نسبت واحد 2 به واحد 1',
  'NesbatV3BV1': 'نسبت واحد 3 به واحد 1',
  'Each1Equal3': 'نسبت واحد 3 به واحد 1',
  'Nesbat31': 'نسبت واحد 3 به واحد 1',
  'DarsadBazarYaban': 'درصد بازاریابی',
  'darsadebazaryabi': 'درصد بازاریابی',
  'BazaryabPercent': 'درصد بازاریابی',
  'SBazaryabSystem': 'سهم بازاریابی',
  'SahemBazaryab': 'سهم بازاریابی',
  'Bazaryabi_system': 'سهم بازاریابی',
  'Bazaryabi': 'سهم بازاریابی',
  'sahmebazaryabi': 'سهم بازاریابی',
  'SMaliat': 'درصد مالیات',
  'DarsadArzesh': 'درصد عوارض',
  'JamMaliat': 'مالیات ردیف',
  'SahemArzesh': 'عوارض ردیف',
  'JamArzesh': 'عوارض ردیف',
  'JamKol_sys': 'جمع ردیف با مالیات',
};

/// Ledger reports (دفتر کل / معین / تفصیلی).
const _ledgerMap = {
  'Sharh': 'شرح سند',
  'Bed': 'بدهکار',
  'Bes': 'بستانکار',
  'Remian': 'مانده ردیف',
  'Remain': 'مانده ردیف',
  'endremain': 'مانده ردیف',
  'Date_x0020_Shamsi': 'تاریخ سند',
  'Date_Shamsi': 'تاریخ سند',
  'Dte_Shamsi': 'تاریخ سند',
  'DocNum': 'ش س',
  'DocMabnaNum': 'ش س',
  'Type': 'ت',
  'BName': 'نام حساب',
  'BID': 'کد حساب',
  'KolName': 'عنوان کل',
  'MName': 'عنوان معین',
  'ReportHeader': 'نام فروشگاه',
  'CompanyName': 'نام فروشگاه',
  'DateShamsi': 'تاریخ',
};

/// Extra Sakan invoice columns (fields added later).
const _invoiceMap2 = {
  'mellinum': 'کد ملی خریدار',
  'corporatecode': 'کد اقتصادی خریدار',
  'postal': 'کد پستی خریدار',
  'usernamfamily': 'نام کاربر',
  'jameyaranesystem': 'جمع یارانه',
  'kolmablaghe': 'هزینه حمل',
  'sahmfroshande': 'هزینه حمل بعهده فروشنده',
  'sahemkharidar': 'هزینه حمل بعهده خریدار',
  'jamhazinefroshande_system': 'هزینه حمل بعهده فروشنده',
  'jamhazinekharidar_system': 'هزینه حمل بعهده خریدار',
  'fdate': 'تاریخ',
  'subscribename': 'نام خریدار',
  'fulltakhfif': 'جمع تخفیف',
  'shserial': 'سریال',
};

/// «سند حسابداری» (Sanadinfo, Sanadtibed / Sanadtibes, Sanadmtbed…, Sanadkmbed…).
const _voucherMap = {
  'docnum': 'شماره سند',
  'docmabnanum': 'شماره ثابت',
  'dte_shamsi': 'تاریخ سند',
  'date_x0020_shamsi': 'تاریخ سند',
  'sharhesanad': 'شرح سند',
  'babatesanad': 'بابت',
  'tafzilibname': 'نام تفصیلی',
  'tafzilibid': 'کد تفصیلی',
  'sharherecord': 'شرح ردیف',
  'kolbname': 'نام کل',
  'kolbid': 'کد کل',
  'moeinbid': 'کد معین',
  'moeinbname': 'نام معین',
  'bed': 'بدهکار',
  'bes': 'بستانکار',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// «فیش حقوقی» (SalaryFishHoghogh, SSalary_*, SalaryMazaya / SalaryKosorat).
const _payslipMap = {
  'nme': 'نام و نام خانوادگی',
  'personname': 'نام و نام خانوادگی',
  'fathername': 'نام پدر',
  'personelcode': 'کد پرسنلی',
  'personelid': 'کد پرسنلی',
  'melinum': 'کد ملی',
  'empbimenumber': 'شماره بیمه',
  'jobname': 'شغل',
  'estekhdamtype': 'نوع استخدام',
  'hesabnumber': 'شماره حساب',
  'dorename': 'دوره',
  'hoghoghmahiane': 'حقوق ماهیانه',
  'ezafekari': 'اضافه کار',
  'haghshift': 'حق شیفت',
  'haghmamoriat': 'حق ماموریت',
  'safar': 'حق ماموریت',
  'padash': 'پاداش',
  'eydi': 'عیدی',
  'bazkharidayammorkhasi': 'بازخرید مرخصی',
  'haghsanavat': 'حق سنوات',
  'pardakhthayemoavaghe': 'پرداخت های معوقه',
  'maliat': 'مالیات',
  'bimesahmbimeshode': 'بیمه سهم بیمه شده',
  'jarime': 'جریمه',
  'vam': 'وام',
  'mosaede': 'مساعده',
  'kasrkar': 'کسر کار',
  'gheybat': 'غیبت',
  'morkhasibedonehoghogh': 'مرخصی بدون حقوق',
  'ezafekarcount': 'ساعت اضافه کار',
  'kasrkarcount': 'ساعت کسر کار',
  'morkhasiwithoutsalarycount': 'روزهای مرخصی بدون حقوق',
  'gheybatcount': 'روزهای غیبت',
  'remainbook': 'مانده دفتر',
  'bookremain': 'مانده دفتر',
  'mablaghepardakhti': 'خالص پرداختی',
  'mazayajam': 'جمع حقوق و مزایا',
  'kosoratjam': 'جمع کسورات',
  'mazayanme': 'عنوان',
  'kosoratnme': 'عنوان',
  'mazayaprice': 'مزایا',
  'kosoratprice': 'کسورات',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// «چک ها» (CheqGet / CheqPay / OuttedCheq / InnerCheqReport / CheqE …).
const _chequeMap = {
  'cheknumber': 'شماره چک',
  'cheqnumber': 'شماره چک',
  'chekmoney': 'مبلغ',
  'cheqmoney': 'مبلغ',
  'money': 'مبلغ',
  'datechek_shamsi': 'سررسید',
  'dte_shamsi': 'تاریخ صدور',
  'bankname': 'بانک',
  'daryaftkonande': 'دریافت کننده',
  'daryaftkonandebname': 'دریافت کننده',
  'pardakhtkonande': 'طرف حساب',
  'pardakhtkonandebname': 'طرف حساب',
  'bname': 'طرف حساب',
  'cheqhuman': 'طرف حساب',
  'babat': 'شرح',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// «اسناد انتظامی» (SefteE / VasiqeE / ZemanatNameE / EntezamyReport …).
const _guaranteeMap = {
  'seftenumber': 'شماره سریال',
  'vasiqenumber': 'شماره سریال',
  'zemanatnamenumber': 'شماره سریال',
  'snumber': 'شماره سریال',
  'seftemoney': 'مبلغ',
  'vasiqemoney': 'مبلغ',
  'zemanatnamemoney': 'مبلغ',
  'smoney': 'مبلغ',
  'seftehuman': 'متعلق به',
  'vasiqehuman': 'متعلق به',
  'zemanatnamehuman': 'متعلق به',
  'vasiqetype': 'نوع',
  'type': 'نوع',
  'sdate_shamsi': 'سررسید',
  'seftedate_shamsi': 'سررسید',
  'holdenplace': 'مکان نگهداری',
  'seftehoidenplace': 'مکان نگهداری',
  'dte_shamsi': 'تاریخ سند',
  'docmabnanum': 'شماره سند',
  'babat': 'بابت',
  'tarafhesabentezamybname': 'طرف حساب',
  'dbidname': 'طرف حساب',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// «تراز آزمایشی» (TarazeAzmayeshi).
const _trialMap = {
  'bookid': 'کد حساب',
  'bid': 'کد حساب',
  'bookname': 'نام حساب',
  'bname': 'نام حساب',
  'startbed': 'بدهکار ابتدای دوره',
  'startbes': 'بستانکار ابتدای دوره',
  'pbed': 'گردش بدهکار',
  'pbes': 'گردش بستانکار',
  'increment': 'گردش بدهکار',
  'decrement': 'گردش بستانکار',
  'fullbed': 'بدهکار انتهای دوره',
  'fullbes': 'بستانکار انتهای دوره',
  'ffbed': 'مانده بدهکار',
  'ffbes': 'مانده بستانکار',
  'ffbedsod': 'مانده سود و زیانی بدهکار',
  'ffbessod': 'مانده سود و زیانی بستانکار',
  'typ': 'تشخیص',
  'startdatesh': 'از تاریخ',
  'enddatesh': 'تا تاریخ',
  'daftarname': 'نام دفتر مالی',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// «موجودی کالا» (MojodiKala / MojodiAnbar / AnbarBeTafkikKala …).
const _stockMap = {
  'bid': 'کد کالا',
  'codekala': 'کد کالا',
  'frasiname': 'نام کالا',
  'kalaname': 'نام کالا',
  'vahed1': 'واحد',
  'vahedname1': 'واحد',
  'vahed2': 'واحد دوم',
  'vahed3': 'واحد سوم',
  'mojoditedad1': 'موجودی',
  'mojoditedad': 'موجودی',
  'jamtedad': 'موجودی',
  'fulltedad': 'موجودی',
  'mojoditedad2': 'موجودی واحد دوم',
  'mojoditedad3': 'موجودی واحد سوم',
  'mojodirial': 'ارزش موجودی',
  'jamkolstore': 'ارزش موجودی',
  'jamkolfull': 'ارزش موجودی',
  'fi': 'فی',
  'ghimatcardex': 'فی',
  'buyprice1': 'فی',
  'buyprice2': 'فی',
  'sellprice1': 'بهای فروش',
  'fimasrafkonande': 'بهای مصرف کننده',
  'minimum': 'حداقل موجودی',
  'maximum': 'حداکثر موجودی',
  'storename': 'نام انبار',
  'aname': 'نام انبار',
  'buytedad': 'خرید',
  'buyfirsttedad': 'خرید',
  'buykhalestedad': 'خرید',
  'rejectbuytedad': 'برگشت از خرید',
  'selltedad': 'فروش',
  'rejectselltedad': 'برگشت از فروش',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// «لیست حقوق / بیمه / مالیات» (SalaryBime, SalaryMaliatDisk, SSalary_Karmand, SalaryPersonelInfo …).
const _salaryListMap = {
  'nme': 'نام',
  'familynme': 'نام خانوادگی',
  'fullname': 'نام و نام خانوادگی',
  'fathername': 'نام پدر',
  'melinum': 'کد ملی',
  'mellinum': 'کد ملی',
  'shsh': 'شماره شناسنامه',
  'empbimenumber': 'شماره بیمه',
  'bimenumber': 'شماره بیمه',
  'personelcode': 'کد پرسنلی',
  'jobname': 'شغل',
  'empsemat': 'شغل',
  'sex': 'جنسیت',
  'meliat': 'ملیت',
  'country': 'ملیت',
  'empdteestekhdam_shamsi': 'تاریخ استخدام',
  'enfesaldte_shamsi': 'تاریخ ترک کار',
  'c1': 'روزهای کارکرد',
  'c2': 'دستمزد روزانه',
  'c3': 'حقوق ماهیانه',
  'c26': 'دستمزد مشمول بیمه',
  'c27': 'جمع حقوق و مزایا',
  'c28': 'دستمزد غیر مشمول بیمه',
  'bimesahmbimeshode': 'بیمه سهم بیمه شده',
  'bimesahmkarfarma': 'بیمه سهم کارفرما',
  'bimekarfarma': 'بیمه سهم کارفرما',
  'bimebikarisahmkarfarma': 'بیمه بیکاری',
  'jambime': 'جمع بیمه',
  's17': 'حقوق ماهیانه',
  's18': 'مزایای مستمر',
  's19': 'اضافه کار',
  's32': 'مشمول مالیات',
  's34': 'مالیات',
  'maliat': 'مالیات',
  'hesabnumber': 'شماره حساب',
  'kargahname': 'نام کارگاه',
  'kargahnumber': 'شماره کارگاه',
  'karfarmaname': 'نام کارفرما',
  'addresskargah': 'آدرس کارگاه',
  'bimename': 'نام مرکز بیمه',
  'gname': 'دوره',
  'price': 'خالص پرداختی',
  'reportheader': 'نام فروشگاه',
  'companyname': 'نام فروشگاه',
  'dateshamsi': 'تاریخ',
};

/// Field of a column for the non-invoice documents ('' = none).
String _docField(PrintDocType type, String src, String col, {bool sum = false}) {
  final s = src.toLowerCase();
  switch (type) {
    case PrintDocType.voucher:
      if (col == 'tafzilimoney' || col == 'kolmoney' || col == 'moeinmoney') {
        final side = s.endsWith('bed') ? 'بدهکار' : (s.endsWith('bes') ? 'بستانکار' : '');
        return sum && side.isNotEmpty ? 'جمع $side' : side;
      }
      if (sum && (col == 'bed' || col == 'bes')) return col == 'bed' ? 'جمع بدهکار' : 'جمع بستانکار';
      return _voucherMap[col] ?? '';
    case PrintDocType.payslip:
      if ((s == 'ssalary_mazaya' || s == 'ssalary_kosorat') && (col == 'sharh' || col == 'price')) {
        if (col == 'sharh') return 'عنوان';
        return sum ? (s.endsWith('mazaya') ? 'جمع حقوق و مزایا' : 'جمع کسورات') : (s.endsWith('mazaya') ? 'مزایا' : 'کسورات');
      }
      if (s == 'ssalary_karmand' && col == 'price') return 'خالص پرداختی';
      if (sum && (col == 'mazayaprice' || col == 'kosoratprice')) return col == 'mazayaprice' ? 'جمع حقوق و مزایا' : 'جمع کسورات';
      return _payslipMap[col] ?? '';
    case PrintDocType.cheque:
      if (sum && (col.endsWith('money'))) return 'جمع مبلغ';
      if (col == 'count') return 'تعداد';
      if (col.endsWith('arzsign')) return 'واحد پول';
      if (col == 'sandoghname') return 'صندوق';
      return _chequeMap[col] ?? '';
    case PrintDocType.guarantee:
      if (sum && col.endsWith('money')) return 'جمع مبلغ';
      return _guaranteeMap[col] ?? '';
    case PrintDocType.trialBalance:
      final ft = _trialMap[col] ?? '';
      if (!sum || ft.isEmpty) return ft;
      return switch (ft) {
        'بدهکار ابتدای دوره' || 'بستانکار ابتدای دوره' || 'گردش بدهکار' || 'گردش بستانکار' || 'مانده بدهکار' || 'مانده بستانکار' || 'بدهکار انتهای دوره' || 'بستانکار انتهای دوره' => 'جمع $ft',
        'مانده سود و زیانی بدهکار' => 'مانده سود و زیان بدهکار',
        'مانده سود و زیانی بستانکار' => 'مانده سود و زیان بستانکار',
        _ => '',
      };
    case PrintDocType.stock:
      final fk = _stockMap[col] ?? '';
      if (!sum) return fk;
      return fk == 'ارزش موجودی' ? 'جمع ارزش موجودی' : (fk.startsWith('موجودی') ? 'جمع موجودی' : '');
    case PrintDocType.salaryList:
      final fl = _salaryListMap[col] ?? '';
      if (!sum) return fl;
      return switch (fl) {
        'جمع حقوق و مزایا' || 'جمع کسورات' => fl,
        'جمع بیمه' => 'جمع کل بیمه',
        'خالص پرداختی' => 'جمع خالص پرداختی',
        'مالیات' => 'جمع مالیات',
        'مشمول مالیات' => 'جمع مشمول مالیات',
        'دستمزد مشمول بیمه' => 'جمع دستمزد مشمول بیمه',
        'بیمه سهم بیمه شده' || 'بیمه سهم کارفرما' || 'بیمه بیکاری' => 'جمع $fl',
        _ => '',
      };
    default:
      return '';
  }
}

bool _isDocType(PrintDocType t) =>
    t == PrintDocType.voucher ||
    t == PrintDocType.payslip ||
    t == PrintDocType.cheque ||
    t == PrintDocType.guarantee ||
    t == PrintDocType.trialBalance ||
    t == PrintDocType.stock ||
    t == PrintDocType.salaryList;

/// Sakan's computed totals of the trial balance: (Σbed − Σbes ± |…|)/2.
String _trialFormula(String e) {
  if (!e.contains('Abs(')) return '';
  final pl = e.contains('sod');
  final t = e.replaceAll(' ', '');
  if (t.startsWith('(((')) return pl ? '{مانده سود و زیان بدهکار}' : '{مانده خالص بدهکار}';
  if (t.startsWith('(Abs(')) return pl ? '{مانده سود و زیان بستانکار}' : '{مانده خالص بستانکار}';
  if (RegExp(r'^Sum\([^)]*ffbed').hasMatch(t)) return '{جمع مانده بدهکار}';
  if (RegExp(r'^Sum\([^)]*ffbes').hasMatch(t)) return '{جمع مانده بستانکار}';
  return '';
}

Map<String, String> _lower(Map<String, String> m) => {for (final e in m.entries) e.key.toLowerCase(): e.value};
final _invoiceLc = _lower(_invoiceMap);
final _rowLc = _lower(_rowMap);
final _ledgerLc = _lower(_ledgerMap);

/// Item-row data sources (one record per printed row).
bool _isRowSource(String src) => RegExp(r'Kala|Aghlam|Khadamat|Servic|Book|Cardex|Havale', caseSensitive: false).hasMatch(src);

/// Maps one `{expression}` of a Sakan text box to a field of this app, or ''.
String mapSakanExpression(String expr, PrintDocType type) {
  var e = expr.trim();
  if (e.isEmpty) return '';
  if (e == 'Line' || e == 'LineABC' || e == 'LineRoman') return '{ردیف}';
  if (e == 'PageNofM' || e == 'PageNumber' || e == 'PageNumberThrough') return '{صفحه}';
  if (e == 'Today' || e == 'Time') return '';
  final ledger = type == PrintDocType.ledger;
  if (_isDocType(type)) {
    if (type == PrintDocType.trialBalance && e.contains('Abs(')) return _trialFormula(e);
    if (e.startsWith('Farsi.BeHorof(') || e.contains('ToWords')) return type == PrintDocType.cheque ? '' : '{مبلغ به حروف}';
    e = e.replaceAll(RegExp(r'^\((double|decimal|int|long|string)\)\s*'), '');
    final sm = RegExp(r'^Sum\(([^()]+)\)$').firstMatch(e);
    if (sm != null) {
      final parts = sm[1]!.split('.');
      final f = _docField(type, parts.length > 1 ? parts.first.trim() : '', parts.last.trim().toLowerCase(), sum: true);
      return f.isEmpty ? '' : '{$f}';
    }
    final dm = RegExp(r'^([A-Za-z_][\w]*)\.([\w]+)$').firstMatch(e);
    if (dm == null) return '';
    final f = _docField(type, dm[1]!, dm[2]!.toLowerCase());
    return f.isEmpty ? '' : '{$f}';
  }
  if (e.startsWith('Farsi.BeHorof(') || e.contains('ToWords')) return ledger ? '' : '{مبلغ به حروف}';
  // casts and Sum(...)
  e = e.replaceAll(RegExp(r'^\((double|decimal|int|long|string)\)\s*'), '');
  final sum = RegExp(r'^Sum\(([^()]+)\)$').firstMatch(e);
  if (sum != null) {
    final col = sum[1]!.split('.').last.trim().toLowerCase();
    if (ledger) {
      return switch (col) { 'bed' => '{جمع بدهکار}', 'bes' => '{جمع بستانکار}', _ => '' };
    }
    return switch (col) {
      'tedadvahed1' || 'tedad' => '{جمع اقلام}',
      'jam1system' || 'jamkol' => '{جمع فاکتور بدون تخفیف}',
      'jamkalakaridarsystem' || 'jamesatr' => '{جمع اقلام با احتساب تخفیف}',
      'takhfifsystem' => '{جمع تخفیف}',
      _ => '',
    };
  }
  // the summed payment boxes of Sakan's invoices
  if (e.contains('+')) {
    if (e.contains('Money_DaryafteCheq')) return '{مبلغ دریافت چک}';
    if (e.contains('Money_DaryaftNaghdy')) return '{مبلغ دریافت نقدی}';
    if (e.contains('MablagKolFactorTSystem')) return '{جمع اقلام با احتساب تخفیف}';
    return '';
  }
  final m = RegExp(r'^([A-Za-z_][\w]*)\.([\w]+)$').firstMatch(e);
  if (m == null) return '';
  final src = m[1]!;
  final col = m[2]!.toLowerCase();
  if (ledger) {
    final f = _ledgerLc[col];
    return f == null ? '' : '{$f}';
  }
  final f = _isRowSource(src) ? (_rowLc[col] ?? _invoiceLc[col]) : (_invoiceLc[col] ?? _rowLc[col]);
  final f2 = f ?? _invoiceMap2[col];
  return f2 == null ? '' : '{$f2}';
}

String _mapText(String text, PrintDocType type) =>
    text.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) => mapSakanExpression(m[1]!, type)).replaceAll('\r', '');

// --------------------------------------------------------------------- conversion

class _Rect {
  final double x, y, w, h;
  const _Rect(this.x, this.y, this.w, this.h);
  static _Rect parse(String s) {
    final p = s.split(',').map((v) => double.tryParse(v.trim()) ?? 0).toList();
    while (p.length < 4) {
      p.add(0);
    }
    return _Rect(p[0], p[1], p[2], p[3]);
  }
}

const _bandTypes = {
  'ReportTitleBand',
  'PageHeaderBand',
  'HeaderBand',
  'GroupHeaderBand',
  'DataBand',
  'GroupFooterBand',
  'FooterBand',
  'ReportSummaryBand',
  'PageFooterBand',
  'ColumnHeaderBand',
  'ColumnFooterBand',
  'ChildBand',
};

class _Band {
  final String type;
  final _X el;
  final _Rect r;
  _Band(this.type, this.el, this.r);
}

String _sType(_X e) {
  final t = e.attrs['type'] ?? '';
  final i = t.lastIndexOf('.');
  final s = i < 0 ? t : t.substring(i + 1);
  return s.startsWith('Sti') ? s.substring(3) : s;
}

int _sides(String border) {
  final part = border.split(';').first;
  if (border.contains(';Transparent;')) return 0;
  var b = 0;
  for (final s in part.split(',')) {
    switch (s.trim()) {
      case 'All':
        b = Sides.all;
      case 'Top':
        b |= Sides.top;
      case 'Bottom':
        b |= Sides.bottom;
      case 'Left':
        b |= Sides.left;
      case 'Right':
        b |= Sides.right;
    }
  }
  return b;
}

double _borderWidth(String border) {
  final p = border.split(';');
  final w = p.length > 2 ? double.tryParse(p[2]) ?? 1 : 1;
  return (w * 0.3).clamp(0.2, 1.5).toDouble();
}

const _named = {
  'WhiteSmoke': 0xFFF5F5F5,
  'Gainsboro': 0xFFDCDCDC,
  'MistyRose': 0xFFFFE4E1,
  'LightGray': 0xFFD3D3D3,
  'Silver': 0xFFC0C0C0,
  'Azure': 0xFFF0FFFF,
  'LightSteelBlue': 0xFFB0C4DE,
  'LightBlue': 0xFFADD8E6,
  'PaleGoldenrod': 0xFFEEE8AA,
  'LightSkyBlue': 0xFF87CEFA,
  'PaleGreen': 0xFF98FB98,
  'LightYellow': 0xFFFFFFE0,
  'Lavender': 0xFFE6E6FA,
  'Beige': 0xFFF5F5DC,
  'LightCyan': 0xFFE0FFFF,
  'Honeydew': 0xFFF0FFF0,
  'AliceBlue': 0xFFF0F8FF,
  'Linen': 0xFFFAF0E6,
  'Ivory': 0xFFFFFFF0,
  'Khaki': 0xFFF0E68C,
  'Yellow': 0xFFFFFF00,
  'Black': 0xFF000000,
  'Gray': 0xFF808080,
  'DarkGray': 0xFFA9A9A9,
};

int _fill(String brush) {
  final b = brush.trim();
  if (b.isEmpty || b == 'Transparent' || b == 'White' || b.startsWith('[255:255:255')) return 0;
  final rgb = RegExp(r'^\[(\d+):(\d+):(\d+)(?::(\d+))?\]$').firstMatch(b);
  if (rgb != null) {
    final v = [for (var i = 1; i <= 4; i++) int.tryParse(rgb[i] ?? '') ?? 255];
    // [a:r:g:b] or [r:g:b]
    final (a, r, g, bl) = rgb[4] == null ? (255, v[0], v[1], v[2]) : (v[0], v[1], v[2], v[3]);
    if (a == 0) return 0;
    return 0xFF000000 | (r << 16) | (g << 8) | bl;
  }
  return _named[b] ?? 0;
}

int _seq = 0;
String _newId() => 'm${DateTime.now().microsecondsSinceEpoch}${_seq++}';

/// Name of the report stored in the file (or '').
String mrtReportName(String xml) {
  final m = RegExp(r'<ReportName>([^<]*)</ReportName>').firstMatch(xml);
  final n = m?[1]?.trim() ?? '';
  return n == 'Report' ? '' : n;
}

/// Result of an import, with what could not be brought over.
class MrtImport {
  final ReportLayout layout;
  final int items;
  final int skipped;
  final List<String> unknownFields;
  const MrtImport(this.layout, this.items, this.skipped, this.unknownFields);
}

/// Converts the .mrt [xml] into a layout of [type]. Throws [FormatException]
/// when the file is not a Stimulsoft report.
MrtImport importMrt(String xml, {required PrintDocType type, String variant = '', String name = 'طرح سکان'}) {
  if (!xml.contains('<StiSerializer')) throw const FormatException('این فایل، گزارش استیمول (mrt) نیست');
  final root = _parse(xml.startsWith('﻿') ? xml.substring(1) : xml);
  final ser = root.child('StiSerializer');
  final pages = ser?.child('Pages');
  if (pages == null || pages.children.isEmpty) throw const FormatException('صفحه‌ای در فایل گزارش نیست');
  final page = pages.children.first;

  // Report unit → millimetres.
  final unit = ser!.prop('ReportUnit');
  final k = switch (unit) {
    'Millimeters' => 1.0,
    'Inches' => 25.4,
    'HundredthsOfInch' => 0.254,
    _ => 10.0, // Centimeters
  };

  var pageW = (double.tryParse(page.prop('PageWidth')) ?? 21) * k;
  var pageH = (double.tryParse(page.prop('PageHeight')) ?? 29.7) * k;
  final pm = page.prop('Margins').isEmpty ? '1,1,1,1' : page.prop('Margins');
  final margins = pm.split(',').map((v) => (double.tryParse(v.trim()) ?? 1) * k).toList();
  // one margin for all sides here: the left/right one keeps the band width
  final margin = margins.isEmpty ? 10.0 : (margins.length > 1 ? (margins[0] < margins[1] ? margins[0] : margins[1]) : margins[0]);
  if (pageW <= 0) pageW = 210;
  if (pageH <= 0) pageH = 297;

  final comps = page.child('Components')?.children ?? const <_X>[];
  final bands = <_Band>[];
  final loose = <_X>[];
  for (final c in comps) {
    final t = _sType(c);
    if (_bandTypes.contains(t)) {
      bands.add(_Band(t, c, _Rect.parse(c.prop('ClientRectangle'))));
    } else {
      loose.add(c);
    }
  }
  bands.sort((a, b) => a.r.y.compareTo(b.r.y));

  // Which of our bands each Sakan band goes to.
  final dataIdx = bands.indexWhere((b) => b.type == 'DataBand');
  final assign = <_Band, BandKind>{};
  if (dataIdx >= 0) {
    assign[bands[dataIdx]] = BandKind.data;
    // column titles: the HeaderBand right above the data
    for (var i = dataIdx - 1; i >= 0; i--) {
      final t = bands[i].type;
      if (t == 'HeaderBand' || t == 'ColumnHeaderBand') {
        assign[bands[i]] = BandKind.columns;
        break;
      }
      if (t != 'GroupHeaderBand') break;
    }
    for (var i = 0; i < dataIdx; i++) {
      final b = bands[i];
      if (assign.containsKey(b) || b.type == 'GroupHeaderBand') continue;
      assign[b] = BandKind.header;
    }
    var firstAfter = true;
    for (var i = dataIdx + 1; i < bands.length; i++) {
      final b = bands[i];
      if (b.type == 'GroupFooterBand' || b.type == 'DataBand' || b.type == 'GroupHeaderBand') continue;
      if (b.type == 'PageHeaderBand' || b.type == 'ReportTitleBand') {
        assign[b] = BandKind.header;
        continue;
      }
      assign[b] = firstAfter ? BandKind.footer1 : BandKind.footer2;
      firstAfter = false;
    }
  } else {
    for (final b in bands) {
      assign[b] = BandKind.header;
    }
  }

  // Stack the Sakan bands of each of our bands one under another.
  final offset = <_Band, double>{};
  final heights = {for (final b in BandKind.values) b: 0.0};
  for (final kind in BandKind.values) {
    final group = bands.where((b) => assign[b] == kind).toList();
    var y = 0.0;
    for (final b in group) {
      offset[b] = y;
      y += b.r.h * k;
    }
    heights[kind] = y;
  }

  final items = <RItem>[];
  var skipped = 0;
  final unknown = <String>{};

  void addComp(_X c, BandKind band, double ox, double oy, double maxH) {
    final t = _sType(c);
    final r = _Rect.parse(c.prop('ClientRectangle'));
    var x = ox + r.x * k, y = oy + r.y * k, w = r.w * k, h = r.h * k;
    if (y < 0) {
      h += y;
      y = 0;
    }
    if (maxH > 0 && y + h > maxH) h = maxH - y;
    if (w <= 0 && h <= 0) return;
    switch (t) {
      case 'Text':
      case 'TextInCells':
      case 'RichText':
        final raw = c.prop('Text');
        for (final m in RegExp(r'\{([^{}]*)\}').allMatches(raw)) {
          if (mapSakanExpression(m[1]!, type).isEmpty) unknown.add(m[1]!.trim());
        }
        final font = c.prop('Font').split(',');
        final size = font.length > 1 ? double.tryParse(font[1].trim()) ?? 10 : 10;
        final opts = c.prop('TextOptions');
        final angle = int.tryParse(RegExp(r'Angle=(-?\d+)').firstMatch(opts)?[1] ?? '0') ?? 0;
        var al = c.prop('HorAlignment');
        // Stimulsoft mirrors the alignment of right-to-left text boxes.
        if (opts.contains('RightToLeft=True')) al = switch (al) { 'Right' => 'Left', '' || 'Left' => 'Right', _ => al };
        final border = c.prop('Border');
        items.add(RItem(
          id: _newId(),
          band: band,
          x: x,
          y: y,
          w: w <= 0 ? 1 : w,
          h: h <= 0 ? 1 : h,
          text: _mapText(raw, type).trim(),
          // Sakan's fonts (David, B Nazanin) are smaller than Vazirmatn at the same size.
          fontSize: (size * 0.85).clamp(5, 40).toDouble(),
          bold: font.skip(2).any((f) => f.contains('Bold')),
          align: switch (al) { 'Center' || 'Width' => 'center', 'Right' => 'right', _ => 'left' },
          border: border.isEmpty ? 0 : _sides(border),
          borderWidth: border.isEmpty ? 0.3 : _borderWidth(border),
          vertical: angle == 90 || angle == 270,
          fill: _fill(c.prop('Brush')),
        ));
      case 'HorizontalLinePrimitive':
        items.add(RItem(id: _newId(), band: band, x: x, y: y, w: w <= 0 ? 1 : w, h: 0.6, border: Sides.top));
      case 'VerticalLinePrimitive':
        items.add(RItem(id: _newId(), band: band, x: x, y: y, w: 0.6, h: h <= 0 ? 1 : h, border: Sides.left));
      case 'RectanglePrimitive':
      case 'RoundedRectanglePrimitive':
        items.add(RItem(id: _newId(), band: band, x: x, y: y, w: w, h: h, border: Sides.all));
      case 'Shape':
        final st = c.child('ShapeType')?.attrs['type'] ?? '';
        if (st.contains('Rectangle') || st.contains('Oval')) {
          items.add(RItem(id: _newId(), band: band, x: x, y: y, w: w, h: h, border: Sides.all, fill: _fill(c.prop('Brush'))));
        } else if (st.contains('HorizontalLine')) {
          items.add(RItem(id: _newId(), band: band, x: x, y: y + h / 2, w: w, h: 0.6, border: Sides.top));
        } else {
          skipped++;
        }
      case 'Container':
      case 'Panel':
        for (final cc in c.child('Components')?.children ?? const <_X>[]) {
          addComp(cc, band, x, y, maxH);
        }
      case 'StartPointPrimitive':
      case 'EndPointPrimitive':
        break;
      default:
        skipped++; // images, barcodes, charts, check boxes…
    }
  }

  for (final b in bands) {
    final kind = assign[b];
    if (kind == null) continue;
    for (final c in b.el.child('Components')?.children ?? const <_X>[]) {
      addComp(c, kind, 0, offset[b]!, heights[kind]!);
    }
  }
  // components placed on the page itself (frames drawn across bands…)
  for (final c in loose) {
    final r = _Rect.parse(c.prop('ClientRectangle'));
    // (bands sit 0.4 cm apart in Sakan's designer, so allow a little above the band)
    final band = bands.where((b) => assign[b] != null && r.y >= b.r.y - 0.45 && r.y < b.r.y + b.r.h).firstOrNull;
    if (band == null) {
      if (_sType(c) != 'StartPointPrimitive' && _sType(c) != 'EndPointPrimitive') skipped++;
      continue;
    }
    final kind = assign[band]!;
    addComp(c, kind, -0.0, offset[band]! - band.r.y * k, heights[kind]!);
  }

  final l = ReportLayout(
    id: _newId(),
    type: type,
    variant: variant,
    name: name,
    pageW: pageW,
    pageH: pageH,
    margin: margin,
    bandHeights: {for (final b in BandKind.values) b: heights[b]! <= 0 ? (b == BandKind.data ? 6.0 : 0.0) : heights[b]!},
    items: items,
  );
  return MrtImport(l, items.length, skipped, unknown.toList()..sort());
}
