import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/jalali.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'auth/auth_screens.dart';
import 'dialogs/cheque_dialogs.dart';
import 'dialogs/simple_dialogs.dart';
import 'dialogs/txn_dialog.dart';
import 'pages/accounts_page.dart';
import 'pages/categories_page.dart';
import 'pages/cheques_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/people_page.dart';
import 'pages/reports_page.dart';
import 'pages/settings_page.dart';
import 'pages/transactions_page.dart';

enum AppPage { dashboard, transactions, accounts, people, cheques, categories, reports, settings }

extension AppPageX on AppPage {
  /// Title shown on the page itself.
  String get label => switch (this) {
        AppPage.dashboard => 'پیشخوان',
        AppPage.transactions => 'تراکنش‌ها',
        AppPage.accounts => 'حساب‌ها و بانک',
        AppPage.people => 'اشخاص، بدهی و طلب',
        AppPage.cheques => 'چک‌ها',
        AppPage.categories => 'دسته‌بندی‌ها',
        AppPage.reports => 'گزارش‌ها',
        AppPage.settings => 'تنظیمات و پشتیبان',
      };

  /// Short label for the top navigation bar.
  String get tab => switch (this) {
        AppPage.dashboard => 'پیشخوان',
        AppPage.transactions => 'تراکنش‌ها',
        AppPage.accounts => 'حساب‌ها',
        AppPage.people => 'اشخاص',
        AppPage.cheques => 'چک‌ها',
        AppPage.categories => 'دسته‌ها',
        AppPage.reports => 'گزارش‌ها',
        AppPage.settings => 'تنظیمات',
      };

  IconData get icon => switch (this) {
        AppPage.dashboard => Icons.grid_view_rounded,
        AppPage.transactions => Icons.receipt_long_outlined,
        AppPage.accounts => Icons.account_balance_outlined,
        AppPage.people => Icons.people_alt_outlined,
        AppPage.cheques => Icons.request_page_outlined,
        AppPage.categories => Icons.sell_outlined,
        AppPage.reports => Icons.insights_outlined,
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

class Shell extends StatefulWidget {
  /// Null when no password is set (lock button hidden).
  final VoidCallback? onLock;
  const Shell({super.key, this.onLock});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppPage _page = AppPage.dashboard;
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
        AppPage.transactions => TransactionsPage(searchFocus: _searchFocus),
        AppPage.accounts => AccountsPage(key: ValueKey('acc$_focusAccount'), initialAccountId: _focusAccount),
        AppPage.people => PeoplePage(key: ValueKey('per$_focusPerson'), initialPersonId: _focusPerson),
        AppPage.cheques => const ChequesPage(),
        AppPage.categories => const CategoriesPage(),
        AppPage.reports => const ReportsPage(),
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
      if (widget.onLock != null) const SingleActivator(LogicalKeyboardKey.keyL, control: true): widget.onLock!,
    };
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
    ];
    for (var i = 0; i < AppPage.values.length && i < digitKeys.length; i++) {
      final p = AppPage.values[i];
      bindings[SingleActivator(digitKeys[i], control: true)] = () => _go(p);
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
    final tabs = AppPage.values.where((p) => p != AppPage.settings).toList();

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
        final compact = c.maxWidth < 1320;
        final veryCompact = c.maxWidth < 1000;
        return Row(
          children: [
            // brand
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
            const SizedBox(width: 18),
            Container(width: 1, height: 28, color: th.colorScheme.outlineVariant),
            const SizedBox(width: 10),
            // tabs
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      _TopTab(
                        page: tabs[i],
                        selected: page == tabs[i],
                        iconOnly: compact,
                        shortcut: 'Ctrl+${AppPage.values.indexOf(tabs[i]) + 1}',
                        badge: tabs[i] == AppPage.cheques ? store.upcomingCheques(days: 7).length : 0,
                        onTap: () => onSelect(tabs[i]),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // actions
            IconButton(
              tooltip: 'جستجو (Ctrl+F)',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            const SizedBox(width: 4),
            _NewMenu(compact: veryCompact),
            const SizedBox(width: 8),
            IconButton(
              tooltip: dark ? 'حالت روشن' : 'حالت تیره',
              onPressed: () => store.updateSettings((s) => s.themeMode = dark ? 'light' : 'dark'),
              icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            ),
            if (onLock != null)
              IconButton(
                tooltip: 'قفل برنامه (Ctrl+L)',
                onPressed: onLock,
                icon: const Icon(Icons.lock_outline_rounded),
              ),
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
                  child: ListTile(dense: true, leading: Icon(Icons.tune_rounded), title: Text('تنظیمات و پشتیبان (Ctrl+8)')),
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

class _TopTab extends StatefulWidget {
  final AppPage page;
  final bool selected;
  final bool iconOnly;
  final String shortcut;
  final int badge;
  final VoidCallback onTap;

  const _TopTab({
    required this.page,
    required this.selected,
    required this.iconOnly,
    required this.shortcut,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<_TopTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final accent = th.colorScheme.primary;
    final fg = widget.selected ? accent : (_hover ? th.colorScheme.onSurface : th.hintColor);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Badge(
          isLabelVisible: widget.badge > 0,
          label: Text('${widget.badge}'),
          child: Icon(widget.page.icon, size: 19, color: fg),
        ),
        if (!widget.iconOnly) ...[
          const SizedBox(width: 8),
          Text(widget.page.tab,
              style: TextStyle(color: fg, fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
        ],
      ],
    );
    return Tooltip(
      message: '${widget.page.label}  (${widget.shortcut})',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: EdgeInsets.symmetric(horizontal: widget.iconOnly ? 12 : 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? accent.withValues(alpha: 0.10)
                        : (_hover ? th.colorScheme.onSurface.withValues(alpha: 0.05) : Colors.transparent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: content,
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
          ),
        ),
      ),
    );
  }
}

/// "New" split button with a menu of document types.
class _NewMenu extends StatelessWidget {
  final bool compact;
  const _NewMenu({required this.compact});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 14),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadiusDirectional.horizontal(start: Radius.circular(10)),
            ),
          ),
          onPressed: () => showTxnDialog(context),
          icon: const Icon(Icons.add_rounded, size: 19),
          label: Text(compact ? 'ثبت' : 'ثبت تراکنش'),
        ),
        const SizedBox(width: 1),
        PopupMenuButton<String>(
          tooltip: 'موارد دیگر',
          offset: const Offset(0, 50),
          onSelected: (v) {
            switch (v) {
              case 'income':
                showTxnDialog(context, type: TxnType.income);
              case 'expense':
                showTxnDialog(context, type: TxnType.expense);
              case 'transfer':
                showTxnDialog(context, type: TxnType.transfer);
              case 'debt':
                showTxnDialog(context, type: TxnType.lend);
              case 'cheque':
                showChequeDialog(context);
              case 'account':
                showAccountDialog(context);
              case 'person':
                showPersonDialog(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'income', child: ListTile(dense: true, leading: Icon(Icons.south_west_rounded), title: Text('درآمد  (Ctrl+I)'))),
            PopupMenuItem(value: 'expense', child: ListTile(dense: true, leading: Icon(Icons.north_east_rounded), title: Text('هزینه  (Ctrl+E)'))),
            PopupMenuItem(value: 'transfer', child: ListTile(dense: true, leading: Icon(Icons.swap_horiz_rounded), title: Text('انتقال  (Ctrl+T)'))),
            PopupMenuItem(value: 'debt', child: ListTile(dense: true, leading: Icon(Icons.handshake_outlined), title: Text('بدهی و طلب'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'cheque', child: ListTile(dense: true, leading: Icon(Icons.request_page_outlined), title: Text('چک جدید'))),
            PopupMenuItem(value: 'account', child: ListTile(dense: true, leading: Icon(Icons.account_balance_outlined), title: Text('حساب جدید'))),
            PopupMenuItem(value: 'person', child: ListTile(dense: true, leading: Icon(Icons.person_add_alt_1_outlined), title: Text('شخص جدید'))),
          ],
          child: Container(
            height: 44,
            width: 36,
            decoration: BoxDecoration(
              color: th.colorScheme.primary,
              borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(10)),
            ),
            child: Icon(Icons.expand_more_rounded, color: th.colorScheme.onPrimary, size: 20),
          ),
        ),
      ],
    );
  }
}
