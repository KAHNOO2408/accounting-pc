import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/jalali.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../theme.dart';
import 'jalali_picker.dart';

Color txnColor(TxnType t) => switch (t) {
      TxnType.income || TxnType.sale || TxnType.purchaseReturn => AppColors.income,
      TxnType.expense || TxnType.purchase || TxnType.saleReturn => AppColors.expense,
      TxnType.transfer => AppColors.transfer,
      TxnType.loanIn || TxnType.loanPay => AppColors.loan,
      TxnType.purchaseDiscount || TxnType.saleDiscount => AppColors.discount,
      _ => AppColors.debt,
    };

IconData txnIcon(TxnType t) => switch (t) {
      TxnType.income => Icons.south_west_rounded,
      TxnType.expense => Icons.north_east_rounded,
      TxnType.transfer => Icons.swap_horiz_rounded,
      TxnType.lend => Icons.call_made_rounded,
      TxnType.borrow => Icons.call_received_rounded,
      TxnType.collect => Icons.download_rounded,
      TxnType.repay => Icons.upload_rounded,
      TxnType.sale => Icons.sell_outlined,
      TxnType.purchase => Icons.shopping_cart_outlined,
      TxnType.saleReturn => Icons.assignment_return_outlined,
      TxnType.purchaseReturn => Icons.assignment_return_outlined,
      TxnType.purchaseDiscount => Icons.local_offer_outlined,
      TxnType.saleDiscount => Icons.local_offer_outlined,
      TxnType.loanIn => Icons.real_estate_agent_outlined,
      TxnType.loanPay => Icons.event_repeat_outlined,
    };

IconData accountIcon(AccountType t) => switch (t) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.bank => Icons.account_balance_outlined,
      AccountType.card => Icons.credit_card_rounded,
      AccountType.wallet => Icons.account_balance_wallet_outlined,
      AccountType.savings => Icons.savings_outlined,
      AccountType.other => Icons.folder_outlined,
    };

/// Amount always rendered left-to-right so the sign and separators stay correct.
class Money extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final bool showUnit;
  final bool signed;
  final Color? color;
  final bool colorBySign;

  const Money(
    this.value, {
    super.key,
    this.style,
    this.showUnit = false,
    this.signed = false,
    this.color,
    this.colorBySign = false,
  });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    var c = color;
    if (colorBySign && value != 0) c = value > 0 ? AppColors.income : AppColors.expense;
    final txt = signed && value > 0 ? '+${groupDigits(value)}' : groupDigits(value);
    final st = (style ?? DefaultTextStyle.of(context).style).copyWith(color: c);
    if (!showUnit) {
      return Text(txt, textDirection: TextDirection.ltr, style: st, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(txt, textDirection: TextDirection.ltr, style: st, maxLines: 1),
        const SizedBox(width: 4),
        Text(store.settings.currency,
            style: st.copyWith(fontSize: (st.fontSize ?? 14) * 0.7, fontWeight: FontWeight.w400, color: Theme.of(context).hintColor)),
      ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final brand = Brand.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      child: Row(
        children: [
          Container(
            width: 6,
            height: subtitle == null ? 30 : 46,
            margin: const EdgeInsetsDirectional.only(end: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [brand.accent, brand.partner]),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: th.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: brand.dark ? Colors.white : brand.deep)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
                ],
              ],
            ),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When true the child spans the full card width (tables), title keeps its inset.
  final bool flush;

  const Panel({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.flush = false,
  });

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final titleRow = title == null
        ? null
        : Row(
            children: [
              Expanded(
                child: Text(title!, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ],
          );
    if (flush) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titleRow != null)
              Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 10), child: titleRow),
            child,
          ],
        ),
      );
    }
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titleRow != null) ...[
              titleRow,
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? hint;

  const StatTile({super.key, required this.label, required this.value, required this.icon, required this.color, this.hint});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
                  const SizedBox(height: 4),
                  Money(value, showUnit: true, style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(hint!, style: th.textTheme.labelSmall?.copyWith(color: th.hintColor)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: th.hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class ColorDot extends StatelessWidget {
  final int color;
  final double size;
  const ColorDot(this.color, {super.key, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
      );
}

/// Labelled dropdown that works on any Flutter 3.x version.
class FieldDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? errorText;

  const FieldDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = items.any((i) => i.value == value);
    Widget? hint;
    if (value == null) {
      for (final i in items) {
        if (i.value == null) {
          hint = i.child;
          break;
        }
      }
    }
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      isEmpty: !hasValue,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: hasValue ? value : null,
          hint: hint,
          isExpanded: true,
          isDense: false,
          items: items,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class MoneyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'مبلغ',
    this.autofocus = false,
    this.validator,
    this.onSubmitted,
  });

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final v = parseMoney(widget.controller.text);
    return TextFormField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      inputFormatters: [MoneyInputFormatter()],
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: store.settings.currency,
        helperText: v > 0 ? '${amountInWords(v)} ${store.settings.currency}' : ' ',
        helperMaxLines: 2,
      ),
    );
  }
}

/// Read-only field that opens the Jalali date picker.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;

  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final r = await showJalaliDatePicker(context, initial: value ?? DateTime.now());
        if (r != null) onChanged(r);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
          suffixIcon: clearable && value != null
              ? IconButton(
                  tooltip: 'پاک کردن',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => onChanged(null),
                )
              : null,
        ),
        child: Text(value == null ? '' : Jalali.fromDateTime(value!).formatWithWeekday()),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'حذف', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontFamily: 'Vazirmatn')),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    width: 440,
    duration: const Duration(seconds: 3),
  ));
}

/// Standard dialog frame used by all forms.
class FormDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final double width;

  const FormDialog({super.key, required this.title, required this.child, required this.actions, this.leading, this.width = 560});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final brand = Brand.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(gradient: brand.header),
              padding: const EdgeInsets.fromLTRB(22, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Text(title,
                        style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  IconButton(
                    tooltip: 'بستن (Esc)',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: child,
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  if (leading != null)
                    Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: leading!))
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  ...actions.expand((w) => [const SizedBox(width: 8), w]).skip(1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const List<int> palette = [
  0xFF4F46E5,
  0xFF0F766E,
  0xFF2F6FED,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFDC2626,
  0xFFE07A2F,
  0xFFCA8A04,
  0xFF16A34A,
  0xFF0891B2,
  0xFF475569,
];

class ColorPickerRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const ColorPickerRow({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in palette)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == value ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: c == value ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
          ),
      ],
    );
  }
}

/// Coloured header strip for large dialogs; text, icons and outlined buttons turn white.
class HeaderBand extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;
  const HeaderBand({super.key, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final brand = Brand.of(context);
    return Container(
      decoration: BoxDecoration(gradient: brand.header),
      padding: padding,
      child: Theme(
        data: th.copyWith(
          textTheme: th.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
          hintColor: Colors.white70,
          iconTheme: const IconThemeData(color: Colors.white),
          iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Colors.white)),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
      ),
    );
  }
}
