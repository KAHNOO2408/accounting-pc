import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/jalali.dart';
import '../data/journal.dart' show TbLevel;
import '../data/models.dart';
import '../data/store.dart';
import 'auth/auth_screens.dart';
import 'dialogs/cheque_dialogs.dart';
import 'dialogs/chequebook_dialogs.dart';
import 'dialogs/closing_dialogs.dart';
import 'dialogs/asset_dialogs.dart';
import 'dialogs/warehouse_dialogs.dart';
import 'dialogs/split_dialogs.dart';
import 'dialogs/users_dialogs.dart';
import 'dialogs/composite_dialogs.dart';
import 'dialogs/invoice_editor.dart';
import 'dialogs/misc_dialogs.dart';
import 'dialogs/opening_dialog.dart';
import 'dialogs/voucher_dialog.dart';
import 'dialogs/txn_dialog.dart';
import 'pages/accounts_page.dart';
import 'pages/home_page.dart';
import 'pages/cheques_page.dart';
import 'pages/invoices_page.dart';
import 'pages/ledger_pages.dart';
import 'pages/ledger_reports.dart';
import 'pages/people_page.dart';
import 'pages/products_page.dart';
import 'dialogs/stock_dialogs.dart';
import 'pages/profit_page.dart';
import 'pages/reports_page.dart';
import 'pages/settings_page.dart';
import 'pages/stock_ops.dart';
import 'pages/transactions_page.dart';
import 'pages/vouchers_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

enum AppPage {
  home,
  vouchers,
  invoices,
  proformas,
  products,
  stockCount,
  transactions,
  accounts,
  cheques,
  people,
  accountsTable,
  balanceSheet,
  reports,
  profit,
  settings,
}

/// Lets any page switch the visible page (e.g. dashboard "see all").
class Nav extends InheritedWidget {
  final void Function(
    AppPage page, {
    String? accountId,
    String? personId,
    ChequeDirection? chequeDir,
    ChequeStatus? chequeStatus,
    InvoiceKind? invoiceKind,
  }) go;
  const Nav({super.key, required this.go, required super.child});

  static Nav of(BuildContext context) => context.getInheritedWidgetOfExactType<Nav>()!;

  @override
  bool updateShouldNotify(Nav oldWidget) => false;
}

// ------------------------------------------------------------------ ribbon model

class _Item {
  final String label;
  final IconData icon;
  final Color color;
  final String? shortcut;
  final ShortcutActivator? activator;
  final void Function(BuildContext context, _ShellState shell)? run;

  const _Item(this.label, this.icon, this.color, {this.shortcut, this.activator, this.run});

  bool get soon => run == null;
}

class _Group {
  final String title;
  final List<_Item> items;
  const _Group(this.title, this.items);
}

class _Tab {
  final String title;
  final List<_Group> groups;
  const _Tab(this.title, this.groups);
}

const _blue = Color(0xFF2563EB);
const _green = AppColors.income;
const _red = AppColors.expense;
const _violet = AppColors.debt;
const _amber = AppColors.loan;
const _cyan = AppColors.discount;
const _slate = Color(0xFF6366F1);

SingleActivator _k(LogicalKeyboardKey k, {bool ctrl = false, bool alt = false, bool shift = false}) =>
    SingleActivator(k, control: ctrl, alt: alt, shift: shift);

void Function(BuildContext, _ShellState) _page(AppPage p,
        {ChequeDirection? dir, ChequeStatus? status, InvoiceKind? kind, String? hint}) =>
    (c, sh) {
      sh._go(p, chequeDir: dir, chequeStatus: status, invoiceKind: kind);
      if (hint != null) toast(c, hint);
    };

String? _firstOf(AppStore s, AccountType t) {
  for (final a in s.activeAccounts) {
    if (a.type == t) return a.id;
  }
  return null;
}

final _accTable = _Item('جدول و مشاهده حساب‌ها', Icons.table_view_outlined, _slate,
    shortcut: 'Ctrl+A', activator: _k(LogicalKeyboardKey.keyA, ctrl: true), run: _page(AppPage.accountsTable));

/// Tabs and button labels of the ribbon (used by «دسترسی دکمه ها»).
List<(String, List<String>)> ribbonCatalog() => [
      for (final t in _tabs)
        (
          t.title,
          [
            ...{
              for (final g in t.groups)
                for (final i in g.items) i.label,
            },
          ],
        ),
    ];

final List<_Tab> _tabs = [
  _Tab('اسناد', [
    _Group('اسناد', [
      _Item('لیست اسناد', Icons.list_alt_rounded, _blue,
          shortcut: 'Alt+F1', activator: _k(LogicalKeyboardKey.f1, alt: true), run: _page(AppPage.vouchers)),
      _Item('سند حسابداری دستی', Icons.edit_note_rounded, _blue,
          shortcut: 'Alt+F2', activator: _k(LogicalKeyboardKey.f2, alt: true), run: (c, _) => showVoucherDialog(c)),
      _Item('سند افتتاحیه', Icons.flag_outlined, _amber, run: (c, _) => openOpeningVoucher(c)),
      _Item('مرکز اسناد', Icons.home_work_outlined, _amber, run: (c, _) => showDocCentersDialog(c)),
    ]),
    _Group('اختتامیه', [
      _Item('خلاصه حساب سود و زیان', Icons.query_stats_rounded, _green, run: _page(AppPage.profit)),
      _Item('تقسیم سود و زیان سال مالی', Icons.pie_chart_outline_rounded, _amber, run: (c, _) => showProfitSplitDialog(c)),
      _Item('تقسیم سود و زیان صاحبان سهام', Icons.groups_2_outlined, _amber,
          run: (c, _) => showProfitSplitDialog(c, shareholders: true)),
      _Item('سند اختتامیه', Icons.sports_score_rounded, _red, run: (c, _) => showClosingDialog(c)),
      _Item('انتقال تراز اختتامیه به تراز افتتاحیه', Icons.move_down_rounded, _green, run: (c, _) => showTransferClosingDialog(c)),
      const _Item('انتقال حساب‌ها به دفتر', Icons.drive_file_move_outline, _slate),
    ]),
    _Group('تسعیر نرخ', [
      const _Item('اعمال کاهش در قیمت تمام شده کالا', Icons.trending_down_rounded, _red),
      const _Item('اعمال افزایش در قیمت تمام شده کالا', Icons.trending_up_rounded, _green),
      const _Item('تسعیر نرخ ارز', Icons.currency_exchange_rounded, _amber),
    ]),
    _Group('سایر اسناد', [
      _Item('تخفیف از خرید', Icons.local_offer_outlined, _cyan,
          shortcut: 'Ctrl+1',
          activator: _k(LogicalKeyboardKey.digit1, ctrl: true),
          run: (c, _) => showTxnDialog(c, type: TxnType.purchaseDiscount, title: 'تخفیف از خرید')),
      _Item('تخفیف از فروش', Icons.local_offer_outlined, _cyan,
          shortcut: 'Ctrl+2',
          activator: _k(LogicalKeyboardKey.digit2, ctrl: true),
          run: (c, _) => showTxnDialog(c, type: TxnType.saleDiscount, title: 'تخفیف از فروش')),
      _accTable,
    ]),
  ]),
  _Tab('خرید و فروش', [
    _Group('مشاهده', [
      _Item('کاردکس کالا', Icons.inventory_outlined, _amber,
          shortcut: 'Ctrl+3', activator: _k(LogicalKeyboardKey.digit3, ctrl: true), run: (c, _) => pickAndShowKardex(c)),
      _Item('جدول کالا', Icons.grid_on_rounded, _amber, run: (c, _) => showStockList(c)),
      _Item('جدول اموال', Icons.chair_outlined, _violet, run: (c, _) => showAssetsTable(c)),
    ]),
    _Group('فروش', [
      _Item('فاکتور فروش', Icons.sell_outlined, _green,
          shortcut: 'F6',
          activator: _k(LogicalKeyboardKey.f6),
          run: (c, _) => showInvoiceEditor(c, kind: InvoiceKind.sale)),
      _Item('فروش اموال و تجهیزات', Icons.chair_alt_outlined, _green, run: (c, _) => showAssetSellDialog(c)),
      _Item('چاپ فاکتور و حواله', Icons.print_outlined, _blue,
          run: _page(AppPage.invoices, hint: 'فاکتور را باز کنید و «چاپ» (Ctrl+P) را بزنید')),
    ]),
    _Group('خرید', [
      _Item('فاکتور خرید', Icons.shopping_cart_outlined, _red,
          shortcut: 'F5',
          activator: _k(LogicalKeyboardKey.f5),
          run: (c, _) => showInvoiceEditor(c, kind: InvoiceKind.purchase)),
      _Item('خرید اموال و تجهیزات', Icons.chair_alt_outlined, _red, run: (c, _) => showAssetBuyDialog(c)),
    ]),
    _Group('برگشت', [
      _Item('برگشت از فروش طی دوره جاری', Icons.assignment_return_outlined, _amber,
          shortcut: 'Ctrl+F6',
          activator: _k(LogicalKeyboardKey.f6, ctrl: true),
          run: (c, _) => showInvoiceEditor(c, kind: InvoiceKind.saleReturn)),
      _Item('برگشت از فروش دوره قبل', Icons.history_rounded, _amber,
          run: (c, _) => showInvoiceEditor(c, kind: InvoiceKind.saleReturn)),
      _Item('برگشت از خرید', Icons.remove_shopping_cart_outlined, _amber,
          shortcut: 'Ctrl+F5',
          activator: _k(LogicalKeyboardKey.f5, ctrl: true),
          run: (c, _) => showInvoiceEditor(c, kind: InvoiceKind.purchaseReturn)),
      _accTable,
    ]),
  ]),
  _Tab('عملیات کالا', [
    _Group('انبار', [
      _Item('انبارگردانی', Icons.fact_check_outlined, _amber,
          shortcut: 'Ctrl+9', activator: _k(LogicalKeyboardKey.digit9, ctrl: true), run: _page(AppPage.stockCount)),
      _Item('انتقال بین کاردکس‌ها', Icons.compare_arrows_rounded, _amber,
          shortcut: 'Ctrl+8', activator: _k(LogicalKeyboardKey.digit8, ctrl: true), run: (c, _) => showConvertDialog(c)),
      _Item('انتقال بین انبارها', Icons.warehouse_outlined, _cyan,
          shortcut: 'Ctrl+4', activator: _k(LogicalKeyboardKey.digit4, ctrl: true), run: (c, _) => showTransferDialog(c)),
      _Item('ضایعات یا مصرف کالا', Icons.delete_sweep_outlined, _red,
          shortcut: 'Ctrl+7', activator: _k(LogicalKeyboardKey.digit7, ctrl: true), run: (c, _) => showWasteDialog(c)),
      _Item('تبدیل کالا', Icons.autorenew_rounded, _amber, run: (c, _) => showConvertDialog(c)),
    ]),
    _Group('پیش فاکتور', [
      _Item('پیش فاکتور', Icons.note_add_outlined, _cyan,
          shortcut: 'F7', activator: _k(LogicalKeyboardKey.f7), run: (c, _) => showInvoiceEditor(c, proforma: true)),
      _Item('لیست پیش فاکتور', Icons.library_books_outlined, _cyan,
          shortcut: 'Ctrl+F7', activator: _k(LogicalKeyboardKey.f7, ctrl: true), run: _page(AppPage.proformas)),
    ]),
    _Group('مشاهده حساب‌ها', [_accTable]),
  ]),
  _Tab('مالی', [
    _Group('عملیات نقدی', [
      _Item('دریافت نقدی', Icons.payments_outlined, _green,
          shortcut: 'F1',
          activator: _k(LogicalKeyboardKey.f1),
          run: (c, _) => showTxnDialog(c,
              type: TxnType.income, accountId: _firstOf(StoreScope.read(c), AccountType.cash), title: 'دریافت نقدی')),
      _Item('پرداخت نقدی', Icons.money_off_rounded, _red,
          shortcut: 'F2',
          activator: _k(LogicalKeyboardKey.f2),
          run: (c, _) => showTxnDialog(c,
              type: TxnType.expense, accountId: _firstOf(StoreScope.read(c), AccountType.cash), title: 'پرداخت نقدی')),
      _Item('واریز به بانک', Icons.south_west_rounded, _blue,
          shortcut: 'Ctrl+F1',
          activator: _k(LogicalKeyboardKey.f1, ctrl: true),
          run: (c, _) {
            final s = StoreScope.read(c);
            showTxnDialog(c,
                type: TxnType.transfer,
                accountId: _firstOf(s, AccountType.cash),
                toAccountId: _firstOf(s, AccountType.bank),
                title: 'واریز به بانک');
          }),
      _Item('برداشت بانکی', Icons.north_east_rounded, _blue,
          shortcut: 'Ctrl+F2',
          activator: _k(LogicalKeyboardKey.f2, ctrl: true),
          run: (c, _) {
            final s = StoreScope.read(c);
            showTxnDialog(c,
                type: TxnType.transfer,
                accountId: _firstOf(s, AccountType.bank),
                toAccountId: _firstOf(s, AccountType.cash),
                title: 'برداشت بانکی');
          }),
    ]),
    _Group('عملیات چک', [
      _Item('دریافت چک', Icons.download_rounded, _green,
          shortcut: 'F3',
          activator: _k(LogicalKeyboardKey.f3),
          run: (c, _) => showChequeDialog(c, direction: ChequeDirection.received)),
      _Item('پرداخت چک', Icons.upload_rounded, _red,
          shortcut: 'F4',
          activator: _k(LogicalKeyboardKey.f4),
          run: (c, _) => showChequeDialog(c, direction: ChequeDirection.issued)),
      _Item('واگذاری چک', Icons.forward_rounded, _violet,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.pending, hint: 'روی چک، منوی ⋮ ← «واگذاری چک»')),
      _Item('به حساب گذاشتن چک', Icons.account_balance_outlined, _cyan,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.pending, hint: 'روی چک، منوی ⋮ ← «به حساب گذاشتن»')),
      _Item('اعلام سررسید چک', Icons.event_outlined, _amber,
          shortcut: 'Ctrl+F4',
          activator: _k(LogicalKeyboardKey.f4, ctrl: true),
          run: _page(AppPage.cheques, dir: ChequeDirection.received, status: ChequeStatus.pending)),
      _Item('اعلام وصول نقدی چک', Icons.price_check_rounded, _green,
          shortcut: 'Ctrl+F3',
          activator: _k(LogicalKeyboardKey.f3, ctrl: true),
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.pending, hint: 'روی چک، «وصول نقدی» را بزنید')),
      _Item('اعلام وصول چک نزد بانک', Icons.task_alt_rounded, _green,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.deposited, hint: 'روی چک، «وصول نزد بانک» را بزنید')),
      _Item('عدم وصول چک نزد بانک', Icons.cancel_outlined, _red,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.deposited, hint: 'روی چک، منوی ⋮ ← «عدم وصول»')),
      _Item('پس دادن چک وارده', Icons.reply_rounded, _amber,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.pending, hint: 'روی چک، منوی ⋮ ← «پس دادن چک وارده»')),
      _Item('پس گرفتن چک صادره', Icons.reply_all_rounded, _amber,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.issued, status: ChequeStatus.pending, hint: 'روی چک، منوی ⋮ ← «پس گرفتن چک صادره»')),
      _Item('پس گرفتن چک واگذار شده', Icons.undo_rounded, _amber,
          run: _page(AppPage.cheques,
              dir: ChequeDirection.received, status: ChequeStatus.endorsed, hint: 'روی چک، منوی ⋮ ← «پس گرفتن»')),
      _Item('معرفی دسته چک', Icons.menu_book_outlined, _violet, run: (c, _) => showChequeBooksWindow(c)),
      _accTable,
    ]),
  ]),
  _Tab('مالی ویژه', [
    _Group('ادغام', [
      _Item('دریافت پرداخت مرکب', Icons.call_split_rounded, _blue,
          shortcut: 'Shift+F5', activator: _k(LogicalKeyboardKey.f5, shift: true), run: (c, _) => showCompositeDialog(c)),
      _Item('مبادلات داخلی', Icons.sync_alt_rounded, _blue,
          shortcut: 'Shift+F6',
          activator: _k(LogicalKeyboardKey.f6, shift: true),
          run: (c, _) => showTxnDialog(c, type: TxnType.transfer, title: 'مبادلات داخلی')),
      _Item('دریافت پرداخت بین حساب‌ها', Icons.compare_arrows_rounded, _blue,
          run: (c, _) => showTxnDialog(c, type: TxnType.transfer, title: 'دریافت و پرداخت بین حساب‌ها')),
      _Item('جا به جایی چک', Icons.swap_horiz_rounded, _cyan, run: (c, _) => showChequeMoveDialog(c)),
      _Item('راس‌گیری چک', Icons.calculate_outlined, _cyan, run: (c, _) => showChequeAverageDialog(c)),
      _accTable,
    ]),
  ]),
  _Tab('هزینه و درآمد', [
    _Group('', [
      _Item('ثبت درآمد ها', Icons.add_card_outlined, _green,
          shortcut: 'Alt+F11',
          activator: _k(LogicalKeyboardKey.f11, alt: true),
          run: (c, _) => showTxnDialog(c, type: TxnType.income, title: 'ثبت درآمد')),
      _Item('برگشت درآمد', Icons.undo_rounded, _amber,
          shortcut: 'Alt+F11',
          run: (c, _) => showTxnDialog(c, type: TxnType.expense, title: 'برگشت درآمد')),
    ]),
    _Group('', [
      _Item('پرداخت هزینه های مرکب', Icons.playlist_add_rounded, _red,
          shortcut: 'Shift+F7', activator: _k(LogicalKeyboardKey.f7, shift: true), run: (c, _) => showCompositeExpenseDialog(c)),
      _Item('برگشت هزینه', Icons.redo_rounded, _amber,
          shortcut: 'Alt+F10',
          run: (c, _) => showTxnDialog(c, type: TxnType.income, title: 'برگشت هزینه')),
      _Item('پرداخت هزینه', Icons.receipt_long_outlined, _red,
          shortcut: 'Alt+F10',
          activator: _k(LogicalKeyboardKey.f10, alt: true),
          run: (c, _) => showTxnDialog(c, type: TxnType.expense, title: 'پرداخت هزینه')),
      _accTable,
    ]),
  ]),
  _Tab('گزارشات', [
    _Group('گزارشات استاندارد', [
      _Item('ترازنامه', Icons.balance_rounded, _blue, run: _page(AppPage.balanceSheet)),
      _Item('تراز آزمایشی', Icons.scale_outlined, _blue, run: (c, _) => showTrialBalanceFilter(c)),
      _Item('صورت حساب سود و زیان', Icons.query_stats_rounded, _green,
          shortcut: 'Alt+F5', activator: _k(LogicalKeyboardKey.f5, alt: true), run: _page(AppPage.profit)),
      _Item('دفتر کل', Icons.menu_book_rounded, _blue, run: (c, _) => showGeneralLedgerFilter(c)),
      _Item('دفاتر معین', Icons.book_outlined, _blue,
          run: (c, _) => showGeneralLedgerFilter(c, title: 'چاپ دفتر معین', level: TbLevel.moeen)),
      _Item('دفاتر تفصیلی', Icons.import_contacts_outlined, _violet,
          run: (c, _) => showGeneralLedgerFilter(c, title: 'چاپ دفتر تفصیلی', level: TbLevel.tafsili)),
      _Item('دفتر روزنامه', Icons.today_outlined, _blue, run: _page(AppPage.transactions)),
      _Item('گزارشات خرید', Icons.shopping_cart_outlined, _red,
          run: _page(AppPage.invoices, kind: InvoiceKind.purchase)),
      _Item('گزارشات فروش', Icons.sell_outlined, _green, run: _page(AppPage.invoices, kind: InvoiceKind.sale)),
      _Item('گزارشات مالی', Icons.bar_chart_rounded, _blue, run: _page(AppPage.reports)),
      _Item('گزارشات کالا و انبار', Icons.inventory_2_outlined, _amber, run: _page(AppPage.products)),
      _Item('جدول اشخاص', Icons.people_alt_outlined, _violet, run: _page(AppPage.accountsTable)),
      const _Item('جدول سرمایه‌داران', Icons.diamond_outlined, _slate),
      const _Item('جدول اشخاص ارزی', Icons.currency_exchange_rounded, _slate),
      const _Item('مدیریت گزارشات', Icons.dashboard_customize_outlined, _slate),
      const _Item('گزارش از گروه مراکز دفتر', Icons.account_tree_outlined, _slate),
    ]),
  ]),
  _Tab('متفرقه', [
    _Group('تنظیمات', [
      _Item('تنظیمات', Icons.tune_rounded, _blue, run: _page(AppPage.settings)),
      const _Item('سطل بازیافت', Icons.delete_outline_rounded, _slate),
    ]),
    _Group('متفرقه', [
      const _Item('کدبندی دفاتر کل و معین', Icons.account_tree_outlined, _slate),
      const _Item('معرفی دفاتر مالی', Icons.library_add_outlined, _slate),
      _Item('مرکز اسناد', Icons.home_work_outlined, _amber, run: (c, _) => showDocCentersDialog(c)),
      const _Item('مرکز دفاتر', Icons.domain_outlined, _slate),
      const _Item('بازاریابان', Icons.campaign_outlined, _slate),
      const _Item('گروه‌های یارانه', Icons.group_work_outlined, _slate),
      const _Item('تخفیف عمومی', Icons.percent_rounded, _slate),
      const _Item('واحدهای شمارش', Icons.straighten_rounded, _slate),
      const _Item('لیست ارزها', Icons.attach_money_rounded, _slate),
      _Item('لیست انبارها', Icons.warehouse_outlined, _amber, run: (c, _) => showWarehousesWindow(c)),
      _Item('تصویر پس زمینه', Icons.wallpaper_rounded, _cyan, run: (c, _) => showBackgroundDialog(c)),
      const _Item('ارسال پیام', Icons.sms_outlined, _slate, shortcut: 'Ctrl+F11'),
    ]),
    _Group('کاربران', [
      _Item('کاربران', Icons.manage_accounts_outlined, _blue, run: (c, _) => showUsersWindow(c)),
      _Item('ردپای کاربران', Icons.history_toggle_off_rounded, _violet, run: (c, _) => showAuditReport(c)),
      const _Item('تنظیم دکمه‌ها', Icons.smart_button_outlined, _slate),
    ]),
  ]),
  _Tab('کنترل اسناد', [
    _Group('کنترل', [
      _Item('کنترل کاردکس', Icons.rule_rounded, _amber, run: (c, _) => runKardexControl(c)),
      _Item('چک کاردکس', Icons.playlist_add_check_rounded, _amber, run: (c, _) => showKardexCheck(c)),
      _Item('کنترل کالا', Icons.inventory_2_outlined, _amber,
          run: _page(AppPage.products, hint: 'کالاهای کم‌موجود یا منفی با رنگ قرمز/نارنجی مشخص‌اند')),
      _Item('محاسبه قیمت تمام شده', Icons.functions_rounded, _amber,
          run: _page(AppPage.products, hint: 'قیمت تمام‌شده خودکار با میانگین موزون خرید محاسبه می‌شود')),
      _Item('کنترل تراز اسناد', Icons.balance_rounded, _blue, run: (c, _) => showTrialBalanceFilter(c)),
      _Item('گزارش خلاف ماهیت', Icons.report_gmailerrorred_outlined, _red, run: (c, _) => runNatureReport(c)),
      _Item('کنترل چک‌های ثبت شده', Icons.request_page_outlined, _cyan, run: _page(AppPage.cheques)),
      _Item('مرتب کردن اسناد', Icons.sort_rounded, _blue,
          run: (c, _) => toast(c, 'اسناد همیشه بر اساس تاریخ و ترتیب ثبت مرتب هستند')),
      _Item('نمایش اخطارهای ورودی', Icons.warning_amber_rounded, _amber, run: (c, _) => showIncomingWarnings(c)),
      const _Item('مدیریت گروه مراکز دفتر', Icons.hub_outlined, _slate),
    ]),
  ]),
  _Tab('خروج و پشتیبان', [
    _Group('خروج', [
      const _Item('ورود به دفاتر دیگر', Icons.folder_open_outlined, _slate, shortcut: 'F12'),
      _Item('خروج', Icons.power_settings_new_rounded, _red,
          shortcut: 'Ctrl+F12', activator: _k(LogicalKeyboardKey.f12, ctrl: true), run: (c, _) => confirmExit(c)),
      _Item('تهیه کپی نسخه پشتیبان', Icons.backup_outlined, _green,
          shortcut: 'F11', activator: _k(LogicalKeyboardKey.f11), run: (c, _) => quickBackup(c)),
      _Item('درباره ما', Icons.info_outline_rounded, _blue, run: (c, _) => showAboutTaraz(c)),
      _Item('اطلاعات نسخه خریداری شده', Icons.verified_outlined, _blue, run: (c, _) => showAboutTaraz(c, license: true)),
      const _Item('ارتباط از راه دور', Icons.support_agent_rounded, _slate),
    ]),
  ]),
];

// ----------------------------------------------------------------------- shell

class Shell extends StatefulWidget {
  /// Null when no password is set (lock button hidden).
  final VoidCallback? onLock;
  final AppPage initialPage;
  const Shell({super.key, this.onLock, this.initialPage = AppPage.home});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late AppPage _page = widget.initialPage;
  String? _focusAccount;
  String? _focusPerson;
  ChequeDirection? _chequeDir;
  ChequeStatus? _chequeStatus;
  InvoiceKind? _invoiceKind;
  int _tab = 0;
  bool _ribbonOpen = true;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _go(
    AppPage p, {
    String? accountId,
    String? personId,
    ChequeDirection? chequeDir,
    ChequeStatus? chequeStatus,
    InvoiceKind? invoiceKind,
  }) {
    setState(() {
      _page = p;
      _focusAccount = accountId;
      _focusPerson = personId;
      _chequeDir = chequeDir;
      _chequeStatus = chequeStatus;
      _invoiceKind = invoiceKind;
    });
  }

  void _search() {
    _go(AppPage.transactions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _runItem(BuildContext context, _Item i) {
    if (!StoreScope.read(context).canUse(i.label)) {
      toast(context, 'شما به «${i.label}» دسترسی ندارید', error: true);
      return;
    }
    if (i.run == null) {
      showComingSoon(context, i.label);
    } else {
      i.run!(context, this);
    }
  }

  Widget _body() => switch (_page) {
        AppPage.home => const HomePage(),
        AppPage.vouchers => const VouchersPage(),
        AppPage.invoices => InvoicesPage(key: ValueKey('inv$_invoiceKind'), initialKind: _invoiceKind),
        AppPage.proformas => const InvoicesPage(key: ValueKey('proformas'), proforma: true),
        AppPage.products => const ProductsPage(),
        AppPage.stockCount => const StockCountPage(),
        AppPage.transactions => TransactionsPage(searchFocus: _searchFocus),
        AppPage.accounts => AccountsPage(key: ValueKey('acc$_focusAccount'), initialAccountId: _focusAccount),
        AppPage.cheques => ChequesPage(
            key: ValueKey('chq$_chequeDir$_chequeStatus'),
            initialDirection: _chequeDir ?? ChequeDirection.received,
            initialStatus: _chequeDir == null ? ChequeStatus.pending : _chequeStatus,
          ),
        AppPage.people => PeoplePage(key: ValueKey('per$_focusPerson'), initialPersonId: _focusPerson),
        AppPage.accountsTable => const AccountsTablePage(),
        AppPage.balanceSheet => const BalanceSheetPage(),
        AppPage.reports => const ReportsPage(),
        AppPage.profit => const ProfitPage(),
        AppPage.settings => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _search,
      if (widget.onLock != null) const SingleActivator(LogicalKeyboardKey.keyL, control: true): widget.onLock!,
    };
    for (final t in _tabs) {
      for (final g in t.groups) {
        for (final i in g.items) {
          if (i.activator != null && i.run != null) {
            bindings.putIfAbsent(i.activator!, () => () => _runItem(context, i));
          }
        }
      }
    }

    return Nav(
      go: _go,
      child: CallbackShortcuts(
        bindings: bindings,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TitleBar(
                  tab: _tab,
                  ribbonOpen: _ribbonOpen,
                  onTab: (i) => setState(() {
                    if (i == _tab) {
                      _ribbonOpen = !_ribbonOpen;
                    } else {
                      _tab = i;
                      _ribbonOpen = true;
                    }
                  }),
                  onSearch: _search,
                  onLock: widget.onLock,
                  onSettings: () => _go(AppPage.settings),
                  onHome: () => _go(AppPage.home),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.topCenter,
                  child: _ribbonOpen
                      ? _Ribbon(
                          tab: _tabs[_tab],
                          onItem: (i) => _runItem(context, i),
                          onCollapse: () => setState(() => _ribbonOpen = false),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (store.lastError != null)
                  MaterialBanner(
                    content: Text(store.lastError!),
                    actions: [TextButton(onPressed: () => setState(() => store.lastError = null), child: const Text('باشه'))],
                  ),
                Expanded(
                  child: _page == AppPage.home
                      ? const HomePage()
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1680),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: KeyedSubtree(key: ValueKey(_page), child: _body()),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =================================================================== title bar

class _TitleBar extends StatelessWidget {
  final int tab;
  final bool ribbonOpen;
  final ValueChanged<int> onTab;
  final VoidCallback onSearch;
  final VoidCallback? onLock;
  final VoidCallback onSettings;
  final VoidCallback onHome;

  const _TitleBar({
    required this.tab,
    required this.ribbonOpen,
    required this.onTab,
    required this.onSearch,
    required this.onLock,
    required this.onSettings,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final dark = th.brightness == Brightness.dark;
    final name = store.settings.ownerName.trim();
    final brand = Brand.of(context);
    const fg = Colors.white;

    return Container(
      height: 56,
      decoration: BoxDecoration(gradient: brand.chrome),
      padding: const EdgeInsetsDirectional.only(start: 14, end: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onHome,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Row(children: [
                  const TarazLogo(size: 32, onDark: true),
                  const SizedBox(width: 8),
                  Text('تراز', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: fg)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _tabs.length; i++) _TabChip(
                    title: _tabs[i].title,
                    selected: i == tab,
                    open: ribbonOpen,
                    onTap: () => onTab(i),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              IconButton(
                tooltip: 'جستجو (Ctrl+F)',
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded, size: 21, color: fg),
              ),
              IconButton(
                tooltip: dark ? 'حالت روشن' : 'حالت تیره',
                onPressed: () => store.updateSettings((s) => s.themeMode = dark ? 'light' : 'dark'),
                icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 21, color: fg),
              ),
              if (onLock != null)
                IconButton(
                  tooltip: 'قفل برنامه (Ctrl+L)',
                  onPressed: onLock,
                  icon: const Icon(Icons.lock_outline_rounded, size: 21, color: fg),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: name.isEmpty ? 'تنظیمات' : '$name — ${Jalali.now().formatLong()}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onSettings,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 1.5)),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      child: Text(name.isEmpty ? '؟' : name.characters.first,
                          style: const TextStyle(color: fg, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Tab header; the selected one is "attached" to the ribbon below it.
class _TabChip extends StatefulWidget {
  final String title;
  final bool selected;
  final bool open;
  final VoidCallback onTap;
  const _TabChip({required this.title, required this.selected, required this.open, required this.onTap});

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = Brand.of(context);
    final attached = widget.selected && widget.open;
    final top = brand.ribbon.colors.first;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.fromLTRB(14, 9, 14, attached ? 12 : 9),
          decoration: BoxDecoration(
            color: attached
                ? top
                : (widget.selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : (_hover ? Colors.white.withValues(alpha: 0.14) : Colors.transparent)),
            borderRadius: attached
                ? const BorderRadius.vertical(top: Radius.circular(10))
                : BorderRadius.circular(9),
          ),
          margin: attached ? const EdgeInsets.symmetric(horizontal: 2) : const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text(
            widget.title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w500,
              color: attached ? brand.accent : Colors.white.withValues(alpha: widget.selected ? 1 : 0.86),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================== ribbon

class _Ribbon extends StatelessWidget {
  final _Tab tab;
  final ValueChanged<_Item> onItem;
  final VoidCallback onCollapse;

  const _Ribbon({required this.tab, required this.onItem, required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final brand = Brand.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: brand.ribbon,
        boxShadow: [
          BoxShadow(color: brand.accent.withValues(alpha: brand.dark ? 0.25 : 0.16), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var g = 0; g < tab.groups.length; g++) ...[
                      if (g > 0) const SizedBox(width: 8),
                      _RibbonGroup(group: tab.groups[g], onItem: onItem),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'جمع کردن نوار (یا دوباره روی تب بزنید)',
            visualDensity: VisualDensity.compact,
            onPressed: onCollapse,
            icon: Icon(Icons.keyboard_arrow_up_rounded, color: brand.accent),
          ),
        ],
      ),
    );
  }
}

class _RibbonGroup extends StatelessWidget {
  final _Group group;
  final ValueChanged<_Item> onItem;
  const _RibbonGroup({required this.group, required this.onItem});

  @override
  Widget build(BuildContext context) {
    final brand = Brand.of(context);
    final th = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: brand.dark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.accent.withValues(alpha: brand.dark ? 0.25 : 0.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in group.items)
                  if (StoreScope.of(context).canUse(i.label)) _RibbonButton(item: i, onTap: () => onItem(i)),
              ],
            ),
          ),
          const Spacer(),
          if (group.title.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  brand.accent.withValues(alpha: brand.dark ? 0.30 : 0.12),
                  brand.partner.withValues(alpha: brand.dark ? 0.30 : 0.12),
                ]),
              ),
              child: Text(
                group.title,
                textAlign: TextAlign.center,
                style: th.textTheme.labelSmall?.copyWith(
                  color: brand.dark ? Colors.white70 : brand.deep,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _RibbonButton extends StatefulWidget {
  final _Item item;
  final VoidCallback onTap;
  const _RibbonButton({required this.item, required this.onTap});

  @override
  State<_RibbonButton> createState() => _RibbonButtonState();
}

class _RibbonButtonState extends State<_RibbonButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final brand = Brand.of(context);
    final i = widget.item;
    final c = i.soon ? const Color(0xFF94A3B8) : i.color;
    final light = Color.lerp(c, Colors.white, 0.35)!;
    return Tooltip(
      message: i.soon ? '${i.label} — به‌زودی' : (i.shortcut == null ? i.label : '${i.label}  (${i.shortcut})'),
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 84,
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
            decoration: BoxDecoration(
              color: _hover ? c.withValues(alpha: brand.dark ? 0.18 : 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _hover ? c.withValues(alpha: 0.35) : Colors.transparent),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 38,
                      height: 38,
                      transform: Matrix4.translationValues(0, _hover ? -1.5 : 0, 0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: i.soon ? [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)] : [light, c],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: i.soon
                            ? null
                            : [BoxShadow(color: c.withValues(alpha: _hover ? 0.45 : 0.30), blurRadius: _hover ? 10 : 6, offset: const Offset(0, 3))],
                      ),
                      child: Icon(i.icon, size: 20, color: Colors.white),
                    ),
                    if (i.soon)
                      Positioned(
                        top: -4,
                        left: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFF64748B), borderRadius: BorderRadius.circular(4)),
                          child: const Text('به‌زودی', style: TextStyle(fontSize: 7.5, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  i.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: i.soon ? th.hintColor : th.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (i.shortcut != null)
                  Text(i.shortcut!,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: i.soon ? th.hintColor : const Color(0xFFDC2626))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
