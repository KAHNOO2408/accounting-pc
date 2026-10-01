import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../theme.dart';

class MonthBar {
  final String label;
  final int income;
  final int expense;
  const MonthBar(this.label, this.income, this.expense);
}

/// Grouped income/expense column chart with hover tooltip.
class IncomeExpenseChart extends StatefulWidget {
  final List<MonthBar> data;
  final double height;
  const IncomeExpenseChart({super.key, required this.data, this.height = 240});

  @override
  State<IncomeExpenseChart> createState() => _IncomeExpenseChartState();
}

class _IncomeExpenseChartState extends State<IncomeExpenseChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final data = widget.data;
    var maxV = 0;
    for (final d in data) {
      if (d.income > maxV) maxV = d.income;
      if (d.expense > maxV) maxV = d.expense;
    }
    if (maxV == 0) maxV = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(builder: (context, c) {
            final slot = c.maxWidth / (data.isEmpty ? 1 : data.length);
            return MouseRegion(
              onHover: (e) {
                // The chart is painted left-to-right in time (oldest on the right in RTL).
                final dx = e.localPosition.dx;
                var i = (dx / slot).floor();
                i = data.length - 1 - i;
                if (i < 0 || i >= data.length) i = -1;
                setState(() => _hover = i < 0 ? null : i);
              },
              onExit: (_) => setState(() => _hover = null),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BarsPainter(
                        data: data,
                        maxV: maxV,
                        grid: th.colorScheme.outlineVariant,
                        hover: _hover,
                        hoverBg: th.colorScheme.primary.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  if (_hover != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Center(child: _tooltip(context, data[_hover!])),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              for (final d in data.reversed)
                Expanded(
                  child: Text(
                    d.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: th.textTheme.labelSmall?.copyWith(color: th.hintColor),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(context, AppColors.income, 'درآمد'),
            const SizedBox(width: 18),
            _legend(context, AppColors.expense, 'هزینه'),
          ],
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color c, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: Theme.of(context).textTheme.labelMedium),
        ],
      );

  Widget _tooltip(BuildContext context, MonthBar d) {
    final th = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: th.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontFamily: 'Vazirmatn', color: th.colorScheme.onInverseSurface, fontSize: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(d.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('درآمد: ${groupDigits(d.income)}'),
            Text('هزینه: ${groupDigits(d.expense)}'),
            Text('خالص: ${groupDigits(d.income - d.expense)}'),
          ],
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<MonthBar> data;
  final int maxV;
  final Color grid;
  final int? hover;
  final Color hoverBg;

  _BarsPainter({required this.data, required this.maxV, required this.grid, required this.hover, required this.hoverBg});

  @override
  void paint(Canvas canvas, Size size) {
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (data.isEmpty) return;
    final slot = size.width / data.length;
    final barW = (slot * 0.28).clamp(4.0, 26.0).toDouble();
    for (var k = 0; k < data.length; k++) {
      // oldest month on the right (RTL reading), newest on the left
      final i = data.length - 1 - k;
      final d = data[i];
      final cx = slot * k + slot / 2;
      if (hover == i) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(slot * k + 2, 0, slot - 4, size.height), const Radius.circular(8)),
          Paint()..color = hoverBg,
        );
      }
      _bar(canvas, size, cx - barW - 2, barW, d.income, AppColors.income);
      _bar(canvas, size, cx + 2, barW, d.expense, AppColors.expense);
    }
  }

  void _bar(Canvas canvas, Size size, double x, double w, int v, Color c) {
    if (v <= 0) return;
    final h = (v / maxV) * (size.height - 4);
    final r = RRect.fromRectAndCorners(
      Rect.fromLTWH(x, size.height - h, w, h),
      topLeft: const Radius.circular(5),
      topRight: const Radius.circular(5),
    );
    canvas.drawRRect(r, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.data != data || old.maxV != maxV || old.hover != hover || old.grid != grid;
}

/// Horizontal share bars (e.g. expenses by category).
class ShareBars extends StatelessWidget {
  final List<(String, int, Color)> items;
  final int maxItems;
  const ShareBars({super.key, required this.items, this.maxItems = 8});

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final total = items.fold<int>(0, (s, e) => s + e.$2);
    final shown = items.take(maxItems).toList();
    return Column(
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: e.$3, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.$1, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(
                      '${total == 0 ? 0 : (e.$2 * 100 / total).round()}٪',
                      style: th.textTheme.labelMedium?.copyWith(color: th.hintColor),
                    ),
                    const SizedBox(width: 12),
                    Text(groupDigits(e.$2), textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : e.$2 / total,
                    minHeight: 6,
                    color: e.$3,
                    backgroundColor: e.$3.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
