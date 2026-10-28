# ساختار سکان (استخراج‌شده از فایل‌های نصب سکان)

این پوشه مرجع «تمام و کمال مثل سکان» برای تراز است. منبع: قالب‌های گزارش `.mrt` (۲۷۹ فایل) و دیتابیس اولیهٔ `Backs/firstdb.bak`.
فقط داده‌ها استخراج شده‌اند (نام و نوع فیلدها، کدها و عناوین)، نه کد برنامهٔ سکان.

- `coding.json` — درخت گروه‌های حساب، کدینگ دفاتر کل/معین (کد ۴ رقمی + مسیر ۶ رقمی) و کد انواع فاکتور (TypeFactor)
- `forms/*.json` — فیلدهای هر منبع داده (فرم/گزارش) با برچسب فارسی و نوع

## روش‌های پرداخت/دریافت (DPM)

- `DPMBardashAzKarteEtebary`
- `DPMCashPay`
- `DPMCashget`
- `DPMCheqGet`
- `DPMCheqPay`
- `DPMDaryaftHavaleBanki`
- `DPMDaryafteArz`
- `DPMKasrAzPisgDarayaft`
- `DPMKasrAzPishPardakht`
- `DPMPardakhtArz`
- `DPMPardakhtAzTankhahGardan`
- `DPMPardakhtBeSayerAshkhas`
- `DPMPardakhtBeTankhahGardan`
- `DPMPardakhtTavasoteSayereAshkhas`
- `DPMPasDadaneCheqeDaryaftany`
- `DPMPasGereftaneCheqeSadere`
- `DPMPasGereftaneCheqeVagozarShode`
- `DPMTakhfifAzForosh`
- `DPMTakhfifAzKharid`
- `DPMVagozaryeCheqeVarede`

## منابع داده

| منبع | فیلد | گزارش | فایل |
|---|---|---|---|
| BargashtAzForoshAghlam | 221 | 4 | `forms/BargashtAzForoshAghlam.json` |
| MojodiKala | 217 | 6 | `forms/MojodiKala.json` |
| PrintInfoFrosh | 176 | 36 | `forms/PrintInfoFrosh.json` |
| infoBackFrosh | 148 | 4 | `forms/infoBackFrosh.json` |
| FactorForosh | 138 | 7 | `forms/FactorForosh.json` |
| InfromationFactorKharid | 133 | 10 | `forms/InfromationFactorKharid.json` |
| SalaryFishHoghogh | 124 | 2 | `forms/SalaryFishHoghogh.json` |
| HavaleAnbar | 120 | 4 | `forms/HavaleAnbar.json` |
| InforMationBackKharid | 120 | 4 | `forms/InforMationBackKharid.json` |
| BackKharidBalanc | 118 | 2 | `forms/BackKharidBalanc.json` |
| FactorForoshAghlam | 113 | 5 | `forms/FactorForoshAghlam.json` |
| InfoServiceKhadamat | 112 | 2 | `forms/InfoServiceKhadamat.json` |
| AmaniDaryaftaniKharid | 97 | 2 | `forms/AmaniDaryaftaniKharid.json` |
| AnbarGardani | 96 | 1 | `forms/AnbarGardani.json` |
| PrintKalaFrosh | 95 | 36 | `forms/PrintKalaFrosh.json` |
| FactorKharidAghlam | 92 | 4 | `forms/FactorKharidAghlam.json` |
| RizBackKharid | 91 | 2 | `forms/RizBackKharid.json` |
| TransferCardex | 87 | 1 | `forms/TransferCardex.json` |
| KalaKharid | 86 | 11 | `forms/KalaKharid.json` |
| AmaniDaryaftani | 85 | 1 | `forms/AmaniDaryaftani.json` |
| AmaniPardakhtani | 85 | 1 | `forms/AmaniPardakhtani.json` |
| MandeAmaniDaryaftani | 85 | 1 | `forms/MandeAmaniDaryaftani.json` |
| RizAghlamServicKhadamt | 84 | 1 | `forms/RizAghlamServicKhadamt.json` |
| RizBackKharidBalanc | 84 | 1 | `forms/RizBackKharidBalanc.json` |
| RizKharidVaBackKharid | 84 | 2 | `forms/RizKharidVaBackKharid.json` |
| MandeAmaniPardakhtani | 83 | 2 | `forms/MandeAmaniPardakhtani.json` |
| KalaBackFrosh | 82 | 4 | `forms/KalaBackFrosh.json` |
| ResidAnbar | 81 | 2 | `forms/ResidAnbar.json` |
| RizKharidBalanc | 80 | 1 | `forms/RizKharidBalanc.json` |
| HavaleBeyneAnbar | 78 | 1 | `forms/HavaleBeyneAnbar.json` |
| FroshgahFactor | 77 | 3 | `forms/FroshgahFactor.json` |
| ResturantFactor | 77 | 3 | `forms/ResturantFactor.json` |
| ResturantKitchen | 77 | 2 | `forms/ResturantKitchen.json` |
| SalaryBime | 77 | 1 | `forms/SalaryBime.json` |
| factorServiceKhadamar | 77 | 1 | `forms/factorServiceKhadamar.json` |
| MixBuildFactor | 76 | 2 | `forms/MixBuildFactor.json` |
| MixBuild | 75 | 1 | `forms/MixBuild.json` |
| BargashtAzForosh | 73 | 2 | `forms/BargashtAzForosh.json` |
| AmaniPardakhtaniFactor | 72 | 2 | `forms/AmaniPardakhtaniFactor.json` |
| KharidBalanc | 71 | 1 | `forms/KharidBalanc.json` |
| BackKharid | 69 | 2 | `forms/BackKharid.json` |
| Cardex | 67 | 3 | `forms/Cardex.json` |
| FactorKharid | 67 | 2 | `forms/FactorKharid.json` |
| damaged | 65 | 1 | `forms/damaged.json` |
| FroshVbackEshantion | 63 | 1 | `forms/FroshVbackEshantion.json` |
| FroshMotafaregh | 62 | 2 | `forms/FroshMotafaregh.json` |
| RizForoshGroup | 62 | 2 | `forms/RizForoshGroup.json` |
| SefareshFactor | 62 | 1 | `forms/SefareshFactor.json` |
| RizEshantionKharidVaBackKharid | 61 | 1 | `forms/RizEshantionKharidVaBackKharid.json` |
| RizKharidMotafaregh | 60 | 1 | `forms/RizKharidMotafaregh.json` |
| KharidMotafaregh | 59 | 1 | `forms/KharidMotafaregh.json` |
| RizKharidAmval | 59 | 1 | `forms/RizKharidAmval.json` |
| KharidAmval | 58 | 1 | `forms/KharidAmval.json` |
| SalaryPersonelInfo | 58 | 2 | `forms/SalaryPersonelInfo.json` |
| HazineFactorFrosh | 57 | 28 | `forms/HazineFactorFrosh.json` |
| CheqGet | 56 | 1 | `forms/CheqGet.json` |
| CheqPay | 56 | 1 | `forms/CheqPay.json` |
| FroshAmval | 56 | 2 | `forms/FroshAmval.json` |
| HazineBackFactorFrosh | 56 | 1 | `forms/HazineBackFactorFrosh.json` |
| VagozaryeCehq | 56 | 1 | `forms/VagozaryeCehq.json` |
| hazineAmani | 56 | 2 | `forms/hazineAmani.json` |
| PasDadaneCheqeVarede | 55 | 1 | `forms/PasDadaneCheqeVarede.json` |
| KalaServicKhadamat | 52 | 2 | `forms/KalaServicKhadamat.json` |
| RizFroshMotafaregh | 52 | 2 | `forms/RizFroshMotafaregh.json` |
| KalaBackKharid | 50 | 3 | `forms/KalaBackKharid.json` |
| AmaniPardakhtaniForosh | 49 | 1 | `forms/AmaniPardakhtaniForosh.json` |
| PasGereftaneCheqeSadere | 48 | 1 | `forms/PasGereftaneCheqeSadere.json` |
| RizKhadamatServicKhadamat | 47 | 1 | `forms/RizKhadamatServicKhadamat.json` |
| khadamatlist | 47 | 1 | `forms/khadamatlist.json` |
| RizFroshAmval | 46 | 1 | `forms/RizFroshAmval.json` |
| AmaniDP | 45 | 1 | `forms/AmaniDP.json` |
| PrintMali | 43 | 61 | `forms/PrintMali.json` |
| BackForoshGroup | 41 | 1 | `forms/BackForoshGroup.json` |
| ForoshGroup | 40 | 1 | `forms/ForoshGroup.json` |
| InnerCheqReport | 40 | 3 | `forms/InnerCheqReport.json` |
| kalaPreFactor | 40 | 1 | `forms/kalaPreFactor.json` |
| BedBesReport | 39 | 1 | `forms/BedBesReport.json` |
| SefareshReport | 39 | 1 | `forms/SefareshReport.json` |
| RizBackForoshGroup | 38 | 1 | `forms/RizBackForoshGroup.json` |
| HazineBackFactorKharid | 37 | 7 | `forms/HazineBackFactorKharid.json` |
| HazineFactorKharid | 37 | 2 | `forms/HazineFactorKharid.json` |
| NotCategorized | 37 | 2 | `forms/NotCategorized.json` |
| DPiMCheqGet | 36 | 3 | `forms/DPiMCheqGet.json` |
| SalaryMaliatDisk | 36 | 1 | `forms/SalaryMaliatDisk.json` |
| InfoFactorPre | 35 | 2 | `forms/InfoFactorPre.json` |
| RizKharidGroup | 35 | 1 | `forms/RizKharidGroup.json` |
| SodoreEntezamy | 35 | 3 | `forms/SodoreEntezamy.json` |
| Bargasht_Hazine | 34 | 2 | `forms/Bargasht_Hazine.json` |
| DPiMCheqPay | 34 | 3 | `forms/DPiMCheqPay.json` |
| DPiMPasDadaneCheqeDaryaftany | 34 | 3 | `forms/DPiMPasDadaneCheqeDaryaftany.json` |
| DPiMPasGereftaneCheqeVagozarShode | 34 | 3 | `forms/DPiMPasGereftaneCheqeVagozarShode.json` |
| DPiMVagozaryeCheqeVarede | 34 | 3 | `forms/DPiMVagozaryeCheqeVarede.json` |
| Pardakht_Hazine | 34 | 2 | `forms/Pardakht_Hazine.json` |
| Paziresh_LabelFix | 34 | 1 | `forms/Paziresh_LabelFix.json` |
| Paziresh_Resid | 34 | 1 | `forms/Paziresh_Resid.json` |
| CheqRemoving | 33 | 1 | `forms/CheqRemoving.json` |
| Information (اطلاعات) | 33 | 278 | `forms/Information_x0020__x0028_اطلاعات_x0029__x0020_.json` |
| PasGereftaneCheqeVagozarShode | 33 | 1 | `forms/PasGereftaneCheqeVagozarShode.json` |
| RizBackKharidGroup | 33 | 1 | `forms/RizBackKharidGroup.json` |
| RizServiceGroup | 33 | 1 | `forms/RizServiceGroup.json` |
| ServiceGroup | 33 | 1 | `forms/ServiceGroup.json` |
| TarazeAzmayeshi | 33 | 3 | `forms/TarazeAzmayeshi.json` |
| BookTafzili | 31 | 5 | `forms/BookTafzili.json` |
| DPiMPasGereftaneCheqeSadere | 30 | 3 | `forms/DPiMPasGereftaneCheqeSadere.json` |
| HadeaghalMojodi | 30 | 1 | `forms/HadeaghalMojodi.json` |
| HadeaxaqrMojodi | 30 | 1 | `forms/HadeaxaqrMojodi.json` |
| HazineServicKhadamat | 30 | 1 | `forms/HazineServicKhadamat.json` |
| NoghteSefaresh | 30 | 1 | `forms/NoghteSefaresh.json` |
| AodateEntezamyVarede | 29 | 2 | `forms/AodateEntezamyVarede.json` |
| DaryaftEntezamy | 29 | 2 | `forms/DaryaftEntezamy.json` |
| HazinBackKharid | 29 | 1 | `forms/HazinBackKharid.json` |
| HazineFroshVaBack | 29 | 1 | `forms/HazineFroshVaBack.json` |
| KalaTicket | 29 | 1 | `forms/KalaTicket.json` |
| SalaryMorkhasiPage | 29 | 1 | `forms/SalaryMorkhasiPage.json` |
| Garanti | 28 | 1 | `forms/Garanti.json` |
| PrintCalc_Tolidi | 28 | 1 | `forms/PrintCalc_Tolidi.json` |
| DPiMDaryaftHavaleBanki | 27 | 3 | `forms/DPiMDaryaftHavaleBanki.json` |
| OuttedCheq | 27 | 3 | `forms/OuttedCheq.json` |
| DPiMBardashAzKarteEtebary | 26 | 3 | `forms/DPiMBardashAzKarteEtebary.json` |
| DPiMCashPay | 26 | 3 | `forms/DPiMCashPay.json` |
| DPiMCashget | 26 | 3 | `forms/DPiMCashget.json` |
| DPiMDaryafteArz | 26 | 3 | `forms/DPiMDaryafteArz.json` |
| DPiMKasrAzPisgDarayaft | 26 | 3 | `forms/DPiMKasrAzPisgDarayaft.json` |
| DPiMKasrAzPishPardakht | 26 | 3 | `forms/DPiMKasrAzPishPardakht.json` |
| DPiMPardakhtArz | 26 | 3 | `forms/DPiMPardakhtArz.json` |
| DPiMPardakhtAzTankhahGardan | 26 | 3 | `forms/DPiMPardakhtAzTankhahGardan.json` |
| DPiMPardakhtBeSayerAshkhas | 26 | 3 | `forms/DPiMPardakhtBeSayerAshkhas.json` |
| DPiMPardakhtBeTankhahGardan | 26 | 3 | `forms/DPiMPardakhtBeTankhahGardan.json` |
| DPiMPardakhtTavasoteSayereAshkhas | 26 | 3 | `forms/DPiMPardakhtTavasoteSayereAshkhas.json` |
| DPiMTakhfifAzForosh | 26 | 3 | `forms/DPiMTakhfifAzForosh.json` |
| DPiMTakhfifAzKharid | 26 | 3 | `forms/DPiMTakhfifAzKharid.json` |
| EntezamyReport | 26 | 1 | `forms/EntezamyReport.json` |
| VarizBeBankTavasoteAshkhas | 26 | 1 | `forms/VarizBeBankTavasoteAshkhas.json` |
| CashGet | 25 | 1 | `forms/CashGet.json` |
| CashPay | 25 | 1 | `forms/CashPay.json` |
| HumanBedBes | 25 | 1 | `forms/HumanBedBes.json` |
| BookKol | 24 | 3 | `forms/BookKol.json` |
| PrintCalc_Masrafi | 23 | 1 | `forms/PrintCalc_Masrafi.json` |
| SalaryNatijeAmalkarMonth | 23 | 1 | `forms/SalaryNatijeAmalkarMonth.json` |
| TBB | 23 | 1 | `forms/TBB.json` |
| TBD | 23 | 1 | `forms/TBD.json` |
| ResturantDesk | 22 | 1 | `forms/ResturantDesk.json` |
| BookRozName | 21 | 2 | `forms/BookRozName.json` |
| PrintInfoHazineMorakab | 21 | 1 | `forms/PrintInfoHazineMorakab.json` |
| ResturantMoshtarakKitchen | 21 | 1 | `forms/ResturantMoshtarakKitchen.json` |
| SSalary_Doc | 21 | 3 | `forms/SSalary_Doc.json` |
| soratHesabsodzian | 21 | 1 | `forms/soratHesabsodzian.json` |
| BackKharidGroup | 20 | 1 | `forms/BackKharidGroup.json` |
| MFull | 19 | 1 | `forms/MFull.json` |
| MojodiAnbar | 19 | 1 | `forms/MojodiAnbar.json` |
| visitorlist | 19 | 1 | `forms/visitorlist.json` |
| MotefaregheFGroup | 18 | 1 | `forms/MotefaregheFGroup.json` |
| SalaryLoan | 18 | 1 | `forms/SalaryLoan.json` |
| SalaryMorkhasi | 18 | 1 | `forms/SalaryMorkhasi.json` |
| KharidGroup | 17 | 1 | `forms/KharidGroup.json` |
| SSalary_Karmand | 17 | 3 | `forms/SSalary_Karmand.json` |
| SalaryMamoriat | 17 | 1 | `forms/SalaryMamoriat.json` |
| SalaryMamoriatPage | 17 | 1 | `forms/SalaryMamoriatPage.json` |
| BarcodPrint | 15 | 3 | `forms/BarcodPrint.json` |
| DaftarcheAghsat | 15 | 1 | `forms/DaftarcheAghsat.json` |
| Haznie_Morakab_Books | 15 | 1 | `forms/Haznie_Morakab_Books.json` |
| Pish | 15 | 2 | `forms/Pish.json` |
| PrintHazineMorakabkala | 15 | 1 | `forms/PrintHazineMorakabkala.json` |
| Garanti_Record | 14 | 1 | `forms/Garanti_Record.json` |
| MotefaregheGroup | 14 | 1 | `forms/MotefaregheGroup.json` |
| SalaryChilds | 14 | 1 | `forms/SalaryChilds.json` |
| SalaryEnterOut | 14 | 1 | `forms/SalaryEnterOut.json` |
| SalaryJarime | 14 | 1 | `forms/SalaryJarime.json` |
| SalaryPadash | 14 | 1 | `forms/SalaryPadash.json` |
| books | 14 | 3 | `forms/books.json` |
| Information (اطلاعات) 2 | 13 | 1 | `forms/Information_x0020__x0028_اطلاعات_x0029__x0020_2.json` |
| TFull | 13 | 1 | `forms/TFull.json` |
| BookMoein2 | 12 | 1 | `forms/BookMoein2.json` |
| MotefaregheRizGroup | 12 | 1 | `forms/MotefaregheRizGroup.json` |
| PrintRFID_Resid | 12 | 1 | `forms/PrintRFID_Resid.json` |
| SalaryBazkharidMorkhasi | 12 | 1 | `forms/SalaryBazkharidMorkhasi.json` |
| Sanadtibed | 12 | 4 | `forms/Sanadtibed.json` |
| Sanadtibes | 12 | 4 | `forms/Sanadtibes.json` |
| BookMoein | 11 | 1 | `forms/BookMoein.json` |
| SalaryBimeKarfarma | 11 | 1 | `forms/SalaryBimeKarfarma.json` |
| SalaryEydi | 11 | 1 | `forms/SalaryEydi.json` |
| SalaryRemainMorkhasi | 11 | 1 | `forms/SalaryRemainMorkhasi.json` |
| Information (زانیارییه_x200C_کان) | 10 | 1 | `forms/Information_x0020__x0028_زانیارییه_x200C_کان_x0029__x0020_.json` |
| MotefaregheFRizGroup | 10 | 1 | `forms/MotefaregheFRizGroup.json` |
| SalaryKosorat | 10 | 4 | `forms/SalaryKosorat.json` |
| PrintRFID_UsedCard | 9 | 9 | `forms/PrintRFID_UsedCard.json` |
| SalaryMazaya | 9 | 4 | `forms/SalaryMazaya.json` |
| AmarReport | 8 | 1 | `forms/AmarReport.json` |
| CheqE | 8 | 4 | `forms/CheqE.json` |
| ForoshgahPrintBarcode | 8 | 1 | `forms/ForoshgahPrintBarcode.json` |
| MojodiAmval | 8 | 1 | `forms/MojodiAmval.json` |
| SalaryAlbasePersonel | 8 | 1 | `forms/SalaryAlbasePersonel.json` |
| Sanadinfo | 8 | 5 | `forms/Sanadinfo.json` |
| ZemanatNameE | 8 | 4 | `forms/ZemanatNameE.json` |
| d | 8 | 1 | `forms/d.json` |
| MAll | 7 | 1 | `forms/MAll.json` |
| SefteE | 7 | 4 | `forms/SefteE.json` |
| VasiqeE | 7 | 4 | `forms/VasiqeE.json` |
| PrintCalc_Info | 6 | 1 | `forms/PrintCalc_Info.json` |
| Sanadmtbed | 6 | 3 | `forms/Sanadmtbed.json` |
| Sanadmtbes | 6 | 3 | `forms/Sanadmtbes.json` |
| CurrencyList | 5 | 1 | `forms/CurrencyList.json` |
| SSalary_Kosorat | 5 | 3 | `forms/SSalary_Kosorat.json` |
| SSalary_Mazaya | 5 | 3 | `forms/SSalary_Mazaya.json` |
| Sanadkmbed | 5 | 4 | `forms/Sanadkmbed.json` |
| Sanadkmbes | 5 | 4 | `forms/Sanadkmbes.json` |
| TAll | 5 | 1 | `forms/TAll.json` |
| DPMBardashAzKarteEtebary | 4 | 3 | `forms/DPMBardashAzKarteEtebary.json` |
| DPMCashPay | 4 | 3 | `forms/DPMCashPay.json` |
| DPMCashget | 4 | 3 | `forms/DPMCashget.json` |
| DPMCheqGet | 4 | 3 | `forms/DPMCheqGet.json` |
| DPMCheqPay | 4 | 3 | `forms/DPMCheqPay.json` |
| DPMDaryaftHavaleBanki | 4 | 3 | `forms/DPMDaryaftHavaleBanki.json` |
| DPMDaryafteArz | 4 | 3 | `forms/DPMDaryafteArz.json` |
| DPMKasrAzPisgDarayaft | 4 | 3 | `forms/DPMKasrAzPisgDarayaft.json` |
| DPMKasrAzPishPardakht | 4 | 3 | `forms/DPMKasrAzPishPardakht.json` |
| DPMPardakhtArz | 4 | 3 | `forms/DPMPardakhtArz.json` |
| DPMPardakhtAzTankhahGardan | 4 | 3 | `forms/DPMPardakhtAzTankhahGardan.json` |
| DPMPardakhtBeSayerAshkhas | 4 | 3 | `forms/DPMPardakhtBeSayerAshkhas.json` |
| DPMPardakhtBeTankhahGardan | 4 | 3 | `forms/DPMPardakhtBeTankhahGardan.json` |
| DPMPardakhtTavasoteSayereAshkhas | 4 | 3 | `forms/DPMPardakhtTavasoteSayereAshkhas.json` |
| DPMPasDadaneCheqeDaryaftany | 4 | 3 | `forms/DPMPasDadaneCheqeDaryaftany.json` |
| DPMPasGereftaneCheqeSadere | 4 | 3 | `forms/DPMPasGereftaneCheqeSadere.json` |
| DPMPasGereftaneCheqeVagozarShode | 4 | 3 | `forms/DPMPasGereftaneCheqeVagozarShode.json` |
| DPMTakhfifAzForosh | 4 | 3 | `forms/DPMTakhfifAzForosh.json` |
| DPMTakhfifAzKharid | 4 | 3 | `forms/DPMTakhfifAzKharid.json` |
| DPMVagozaryeCheqeVarede | 4 | 3 | `forms/DPMVagozaryeCheqeVarede.json` |
| PrintCalc_Daily | 4 | 1 | `forms/PrintCalc_Daily.json` |
| SodzianCharts | 4 | 2 | `forms/SodzianCharts.json` |
| PrintDraw | 3 | 9 | `forms/PrintDraw.json` |
