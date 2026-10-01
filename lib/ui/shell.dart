import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/jalali.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'auth/auth_screens.dart';
import 'dialogs/invoice_editor.dart';
import 'dialogs/product_dialog.dart';
import 'dialogs/simple_dialogs.dart';
import 'dialogs/txn_dialog.dart';
import 'pages/accounts_page.dart';
import 'pages/categories_page.dart';
import 'pages/cheques_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/invoices_page.dart';
import 'pages/loans_page.dart';
import 'pages/people_page.dart';
import 'pages/products_page.dart';
import 'pages/profit_page.dart';
import 'pages/reports_page.dart';
import 'pages/savings_page.dart';
import 'pages/settings_page.dart';
import 'pages/transactions_page.dart';
import 'theme.dart';

enum AppPage {
  dashboard,
  invoices,
  products,
  transactions,
  accounts,
  savings,
  loans,
  cheques,
  categories,
  people,
  reports,
  profit,
  settings,
}

extension AppPageX on AppPage {
  String get label => switch (this) {
        AppPage.dashboard => 'خانه',
        AppPage.invoices => 'فهرست فاکتورها',
        AppPage.products => 'انبار محصولات',
        AppPage.transactions => 'فهرست تراکنش‌ها',
        AppPage.accounts => 'حساب‌ها و بانک',
        AppPage.savings => 'پس‌انداز',
        AppPage.loans => 'وام‌ها و اقساط',
        AppPage.cheques => 'چک‌ها',
        AppPage.categories => 'دسته‌بندی‌ها',
        AppPage.people => 'مخاطبین، بدهی و طلب',
        AppPage.reports => 'گزارش درآمد و هزینه',
        AppPage.profit => 'سود و زیان',
        AppPage.settings => 'تنظیمات و پشتیبان',
      };

  IconData get icon => switch (this) {
        AppPage.dashboard => Icons.home_rounded,
        AppPage.invoices => Icons.receipt_outlined,
        AppPage.products => Icons.inventory_2_outlined,
        AppPage.transactions => Icons.receipt_long_outlined,
        AppPage.accounts => Icons.account_balance_outlined,
        AppPage.savings => Icons.savings_outlined,
        AppPage.loans => Icons.real_estate_agent_outlined,
        AppPage.cheques => Icons.request_page_outlined,
        AppPage.categories => Icons.sell_outlined,
        AppPage.people => Icons.contacts_outlined,
        AppPage.reports => Icons.bar_chart_rounded,
        AppPage.profit => Icons.trending_up_rounded,
        AppPage.settings => Icons.tune_rounded,
      };
}

/// Lets any page switch the visible page (e.g. dashboard "see all").
class Nav extends InheritedWidget {
  final void Function(AppPage page, {String? accountId, String? personId}) go;
  const Nav({super.key, required this.go, required super.child});

  static Nav of(BuildContext context) => context.getInheritedWidgetOfExactType<Nav>()!;

  @override
  bool updateShouldNotify(Nav oldWidget) => false;
}

// ------------------------------------------------------------------ menu model

class _Item {
  final String label;
  final IconData icon;
  final Color? color;
  final String? shortcut;
  final AppPage? page;
  final void Function(BuildContext context)? action;
  final bool divider;

  const _Item(this.label, this.icon, {this.color, this.shortcut, this.page, this.action}) : divider = false;
  const _Item.divider()
      : label = '',
        icon = Icons.remove,
        color = null,
        shortcut = null,
        page = null,
        action = null,
        divider = true;
}

class _Group {
  final String label;
  final IconData icon;
  final AppPage? page; // direct link (no submenu)
  final List<_Item> items;
  const _Group(this.label, this.icon, {this.page, this.items = const []});

  Set<AppPage> get pages => {if (page != null) page!, for (final i in items) if (i.page != null) i.page!};
}

String? _firstOf(AppStore s, AccountType t) {
  for (final a in s.activeAccounts) {
    if (a.type == t) return a.id;
  }
  return null;
}

void _cashIn(BuildContext c) {
  final s = StoreScope.read(c);
  showTxnDialog(c, type: TxnType.income, accountId: _firstOf(s, AccountType.cash), title: 'دریافت نقدی');
}

void _cashOut(BuildContext c) {
  final s = StoreScope.read(c);
  showTxnDialog(c, type: TxnType.expense, accountId: _firstOf(s, AccountType.cash), title: 'پرداخت نقدی');
}

void _toBank(BuildContext c) {
  final s = StoreScope.read(c);
  showTxnDialog(c,
      type: TxnType.transfer,
      accountId: _firstOf(s, AccountType.cash),
      toAccountId: _firstOf(s, AccountType.bank),
      title: 'واریز به بانک');
}

void _fromBank(BuildContext c) {
  final s = StoreScope.read(c);
  showTxnDialog(c,
      type: TxnType.transfer,
      accountId: _firstOf(s, AccountType.bank),
      toAccountId: _firstOf(s, AccountType.cash),
      title: 'برداشت از بانک');
}

final List<_Group> _menu = [
  const _Group('خانه', Icons.home_rounded, page: AppPage.dashboard),
  _Group('خرید و فروش', Icons.storefront_outlined, items: [
    _Item('ثبت فروش', Icons.sell_outlined,
        color: AppColors.income, shortcut: 'F2', action: (c) => showInvoiceEditor(c, kind: InvoiceKind.sale)),
    _Item('ثبت خرید', Icons.shopping_cart_outlined,
        color: AppColors.expense, shortcut: 'F3', action: (c) => showInvoiceEditor(c, kind: InvoiceKind.purchase)),
    _Item('برگشت از فروش', Icons.assignment_return_outlined,
        color: AppColors.loan, action: (c) => showInvoiceEditor(c, kind: InvoiceKind.saleReturn)),
    _Item('برگشت از خرید', Icons.assignment_return_outlined,
        color: AppColors.loan, action: (c) => showInvoiceEditor(c, kind: InvoiceKind.purchaseReturn)),
    const _Item.divider(),
    _Item('تخفیف از فروش', Icons.local_offer_outlined,
        color: AppColors.discount,
        action: (c) => showTxnDialog(c, type: TxnType.saleDiscount, title: 'ثبت تخفیف از فروش')),
    _Item('تخفیف از خرید', Icons.local_offer_outlined,
        color: AppColors.discount,
        action: (c) => showTxnDialog(c, type: TxnType.purchaseDiscount, title: 'ثبت تخفیف از خرید')),
    const _Item.divider(),
    const _Item('فهرست فاکتورها', Icons.receipt_outlined, page: AppPage.invoices, shortcut: 'Ctrl+2'),
  ]),
  _Group('انبار', Icons.inventory_2_outlined, items: [
    const _Item('انبار محصولات', Icons.inventory_2_outlined, page: AppPage.products, shortcut: 'Ctrl+3'),
    _Item('کالای جدید', Icons.add_box_outlined, shortcut: 'F4', action: (c) => showProductDialog(c)),
  ]),
  _Group('دریافت و پرداخت', Icons.swap_vert_rounded, items: [
    _Item('تراکنش جدید', Icons.add_circle_outline, shortcut: 'Ctrl+N', action: (c) => showTxnDialog(c)),
    _Item('دریافت نقدی', Icons.payments_outlined, color: AppColors.income, action: _cashIn),
    _Item('پرداخت نقدی', Icons.money_off_rounded, color: AppColors.expense, action: _cashOut),
    const _Item.divider(),
    _Item('واریز به بانک', Icons.south_west_rounded, color: AppColors.transfer, action: _toBank),
    _Item('برداشت از بانک', Icons.north_east_rounded, color: AppColors.transfer, action: _fromBank),
    _Item('دریافت و پرداخت بین حساب‌ها', Icons.compare_arrows_rounded,
        color: AppColors.transfer, shortcut: 'Ctrl+T', action: (c) => showTxnDialog(c, type: TxnType.transfer)),
    const _Item.divider(),
    const _Item('فهرست تراکنش‌ها', Icons.receipt_long_outlined, page: AppPage.transactions, shortcut: 'Ctrl+4'),
  ]),
  _Group('مالی', Icons.account_balance_outlined, items: [
    const _Item('حساب‌ها و بانک', Icons.account_balance_outlined, page: AppPage.accounts, shortcut: 'Ctrl+5'),
    const _Item('پس‌انداز', Icons.savings_outlined, page: AppPage.savings),
    const _Item('وام‌ها و اقساط', Icons.real_estate_agent_outlined, page: AppPage.loans),
    const _Item('چک‌ها', Icons.request_page_outlined, page: AppPage.cheques),
    const _Item.divider(),
    const _Item('دسته‌بندی درآمد و هزینه', Icons.sell_outlined, page: AppPage.categories),
  ]),
  _Group('اشخاص', Icons.contacts_outlined, items: [
    const _Item('مخاطبین و حساب اشخاص', Icons.contacts_outlined, page: AppPage.people, shortcut: 'Ctrl+6'),
    _Item('ثبت بدهی و طلب', Icons.handshake_outlined,
        color: AppColors.debt, action: (c) => showTxnDialog(c, type: TxnType.lend, title: 'بدهی و طلب')),
    _Item('مخاطب جدید', Icons.person_add_alt_1_outlined, action: (c) => showPersonDialog(c)),
  ]),
  _Group('گزارشات', Icons.insights_outlined, items: [
    const _Item('سود و زیان', Icons.trending_up_rounded, page: AppPage.profit, shortcut: 'Ctrl+8'),
    const _Item('گزارش درآمد و هزینه', Icons.bar_chart_rounded, page: AppPage.reports, shortcut: 'Ctrl+7'),
  ]),
];

// ----------------------------------------------------------------------- shell

class Shell extends StatefulWidget {
  /// Null when no password is set (lock button hidden).
  final VoidCallback? onLock;
  final AppPage initialPage;
  const Shell({super.key, this.onLock, this.initialPage = AppPage.dashboard});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late AppPage _page = widget.initialPage;
  String? _focusAccount;
  String? _focusPerson;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _go(AppPage p, {String? accountId, String? personId}) {
    setState(() {
      _page = p;
      _focusAccount = accountId;
      _focusPerson = personId;
    });
  }

  void _search() {
    _go(AppPage.transactions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  Widget _body() => switch (_page) {
        AppPage.dashboard => const DashboardPage(),
        AppPage.invoices => const InvoicesPage(),
        AppPage.products => const ProductsPage(),
        AppPage.transactions => TransactionsPage(searchFocus: _searchFocus),
        AppPage.accounts => AccountsPage(key: ValueKey('acc$_focusAccount'), initialAccountId: _focusAccount),
        AppPage.savings => const SavingsPage(),
        AppPage.loans => const LoansPage(),
        AppPage.cheques => const ChequesPage(),
        AppPage.categories => const CategoriesPage(),
        AppPage.people => PeoplePage(key: ValueKey('per$_focusPerson'), initialPersonId: _focusPerson),
        AppPage.reports => const ReportsPage(),
        AppPage.profit => const ProfitPage(),
        AppPage.settings => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => showTxnDialog(context),
      const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => showTxnDialog(context, type: TxnType.expense),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => showTxnDialog(context, type: TxnType.income),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => showTxnDialog(context, type: TxnType.transfer),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _search,
      const SingleActivator(LogicalKeyboardKey.f2): () => showInvoiceEditor(context, kind: InvoiceKind.sale),
      const SingleActivator(LogicalKeyboardKey.f3): () => showInvoiceEditor(context, kind: InvoiceKind.purchase),
      const SingleActivator(LogicalKeyboardKey.f4): () => showProductDialog(context),
      if (widget.onLock != null) const SingleActivator(LogicalKeyboardKey.keyL, control: true): widget.onLock!,
    };
    const digitPages = [
      (LogicalKeyboardKey.digit1, AppPage.dashboard),
      (LogicalKeyboardKey.digit2, AppPage.invoices),
      (LogicalKeyboardKey.digit3, AppPage.products),
      (LogicalKeyboardKey.digit4, AppPage.transactions),
      (LogicalKeyboardKey.digit5, AppPage.accounts),
      (LogicalKeyboardKey.digit6, AppPage.people),
      (LogicalKeyboardKey.digit7, AppPage.reports),
      (LogicalKeyboardKey.digit8, AppPage.profit),
      (LogicalKeyboardKey.digit9, AppPage.settings),
    ];
    for (final d in digitPages) {
      bindings[SingleActivator(d.$1, control: true)] = () => _go(d.$2);
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
                _TopBar(
                  page: _page,
                  onSelect: (p) => _go(p),
                  onSearch: _search,
                  onLock: widget.onLock,
                ),
                if (store.lastError != null)
                  MaterialBanner(
                    content: Text(store.lastError!),
                    actions: [TextButton(onPressed: () => setState(() => store.lastError = null), child: const Text('باشه'))],
                  ),
                Expanded(
                  child: Center(
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

// =================================================================== top bar

class _TopBar extends StatelessWidget {
  final AppPage page;
  final ValueChanged<AppPage> onSelect;
  final VoidCallback onSearch;
  final VoidCallback? onLock;

  const _TopBar({required this.page, required this.onSelect, required this.onSearch, required this.onLock});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final dark = th.brightness == Brightness.dark;
    final name = store.settings.ownerName.trim();
    final chequeBadge = store.upcomingCheques(days: 7).length;
    final loanBadge = store.loans.where((l) {
      final d = store.loanNextDue(l);
      return d != null && !d.isAfter(dateOnly(DateTime.now()).add(const Duration(days: 7)));
    }).length;

    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: th.colorScheme.surface,
        border: Border(bottom: BorderSide(color: th.colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 1280;
        final veryCompact = c.maxWidth < 1000;
        return Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelect(AppPage.dashboard),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    const TarazLogo(size: 36),
                    if (!veryCompact) ...[
                      const SizedBox(width: 10),
                      Text('تراز', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 28, color: th.colorScheme.outlineVariant),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final g in _menu)
                      _GroupTab(
                        group: g,
                        selected: g.pages.contains(page),
                        iconOnly: compact,
                        badge: g.items.any((i) => i.page == AppPage.cheques || i.page == AppPage.loans)
                            ? chequeBadge + loanBadge
                            : 0,
                        onPage: onSelect,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'جستجو (Ctrl+F)', onPressed: onSearch, icon: const Icon(Icons.search_rounded)),
            IconButton(
              tooltip: dark ? 'حالت روشن' : 'حالت تیره',
              onPressed: () => store.updateSettings((s) => s.themeMode = dark ? 'light' : 'dark'),
              icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            ),
            if (onLock != null)
              IconButton(tooltip: 'قفل برنامه (Ctrl+L)', onPressed: onLock, icon: const Icon(Icons.lock_outline_rounded)),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: name.isEmpty ? 'حساب کاربری' : name,
              offset: const Offset(0, 52),
              onSelected: (v) {
                if (v == 'settings') onSelect(AppPage.settings);
                if (v == 'lock') onLock?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'کاربر تراز' : name,
                          style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: th.colorScheme.onSurface)),
                      Text(Jalali.now().formatWithWeekday(), style: th.textTheme.bodySmall),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(dense: true, leading: Icon(Icons.tune_rounded), title: Text('تنظیمات و پشتیبان (Ctrl+9)')),
                ),
                if (onLock != null)
                  const PopupMenuItem(
                    value: 'lock',
                    child: ListTile(dense: true, leading: Icon(Icons.lock_outline_rounded), title: Text('قفل کردن')),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: page == AppPage.settings ? th.colorScheme.primary : th.colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: th.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    name.isEmpty ? '؟' : name.characters.first,
                    style: TextStyle(color: th.colorScheme.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _GroupTab extends StatefulWidget {
  final _Group group;
  final bool selected;
  final bool iconOnly;
  final int badge;
  final ValueChanged<AppPage> onPage;

  const _GroupTab({
    required this.group,
    required this.selected,
    required this.iconOnly,
    required this.badge,
    required this.onPage,
  });

  @override
  State<_GroupTab> createState() => _GroupTabState();
}

class _GroupTabState extends State<_GroupTab> {
  bool _hover = false;

  void _run(_Item i) {
    if (i.page != null) {
      widget.onPage(i.page!);
    } else {
      i.action?.call(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final accent = th.colorScheme.primary;
    final g = widget.group;
    final hasMenu = g.items.isNotEmpty;
    final fg = widget.selected ? accent : (_hover ? th.colorScheme.onSurface : th.hintColor);

    final visual = SizedBox(
      height: 65,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: EdgeInsets.symmetric(horizontal: widget.iconOnly ? 10 : 12, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? accent.withValues(alpha: 0.10)
                  : (_hover ? th.colorScheme.onSurface.withValues(alpha: 0.05) : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: widget.badge > 0,
                  label: Text('${widget.badge}'),
                  child: Icon(g.icon, size: 19, color: fg),
                ),
                if (!widget.iconOnly) ...[
                  const SizedBox(width: 7),
                  Text(g.label,
                      style: TextStyle(color: fg, fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                ],
                if (hasMenu) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: fg),
                ],
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 10,
            right: 10,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: widget.selected ? 1 : 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final hoverable = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: visual,
    );

    if (!hasMenu) {
      return Tooltip(
        message: '${g.label} (Ctrl+1)',
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(onTap: () => widget.onPage(g.page!), child: hoverable),
      );
    }

    return PopupMenuButton<_Item>(
      tooltip: g.label,
      offset: const Offset(0, 60),
      constraints: const BoxConstraints(minWidth: 250),
      onSelected: _run,
      itemBuilder: (_) => [
        for (final i in g.items)
          if (i.divider)
            const PopupMenuDivider()
          else
            PopupMenuItem<_Item>(
              value: i,
              child: Row(
                children: [
                  Icon(i.page?.icon ?? i.icon, size: 20, color: i.color ?? th.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(i.label)),
                  if (i.shortcut != null) ...[
                    const SizedBox(width: 16),
                    Text(i.shortcut!,
                        textDirection: TextDirection.ltr,
                        style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                  ],
                ],
              ),
            ),
      ],
      child: hoverable,
    );
  }
}
