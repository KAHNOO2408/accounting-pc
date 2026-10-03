import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/report_layout.dart';
import '../widgets/common.dart';
import 'report_render.dart';

/// Visual report designer: every element can be moved, resized and edited.
/// Returns the edited layout, or null when cancelled.
Future<ReportLayout?> showReportDesigner(BuildContext context, ReportLayout layout, ReportData sample) =>
    showDialog<ReportLayout>(context: context, barrierDismissible: false, builder: (_) => _Designer(layout: layout.copy(), sample: sample));

class _Designer extends StatefulWidget {
  final ReportLayout layout;
  final ReportData sample;
  const _Designer({required this.layout, required this.sample});

  @override
  State<_Designer> createState() => _DesignerState();
}

class _DesignerState extends State<_Designer> {
  late final ReportLayout l = widget.layout;
  RItem? _sel;
  double _zoom = 1.5;
  bool _preview = false;
  final _focus = FocusNode();
  int _seq = 0;

  double get _scale => 3.78 * _zoom;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double _snap(double v) => (v * 2).round() / 2;

  String _newId() => 'n${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  void _add(String kind, {String text = ''}) {
    final band = _sel?.band ?? BandKind.header;
    final it = switch (kind) {
      'hline' => RItem(id: _newId(), band: band, x: 10, y: 2, w: 60, h: 0.6, border: Sides.top),
      'vline' => RItem(id: _newId(), band: band, x: 30, y: 0, w: 0.6, h: 10, border: Sides.left),
      'box' => RItem(id: _newId(), band: band, x: 10, y: 1, w: 40, h: 12, border: Sides.all),
      _ => RItem(id: _newId(), band: band, x: 10, y: 1, w: 40, h: 6, text: text.isEmpty ? 'متن جدید' : text, fontSize: 9),
    };
    setState(() {
      l.items.add(it);
      _sel = it;
    });
  }

  void _delete() {
    if (_sel == null) return;
    setState(() {
      l.items.remove(_sel);
      _sel = null;
    });
  }

  void _duplicate() {
    final s = _sel;
    if (s == null) return;
    final c = s.copy(id: _newId())
      ..x = s.x + 2
      ..y = s.y + 2;
    setState(() {
      l.items.add(c);
      _sel = c;
    });
  }

  void _nudge(double dx, double dy) {
    final s = _sel;
    if (s == null) return;
    setState(() {
      s.x = _snap(s.x + dx);
      s.y = _snap(s.y + dy);
    });
  }

  Future<void> _editText(RItem it) async {
    final c = TextEditingController(text: it.text);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => FormDialog(
        title: 'ویرایش متن',
        width: 520,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('تایید')),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(labelText: 'متن')),
          const SizedBox(height: 10),
          Text('درج فیلد:', style: Theme.of(ctx).textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final f in [...invoiceFields, ...rowFields])
              ActionChip(
                label: Text(f, style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  final sel = c.selection;
                  final t = '{$f}';
                  final start = sel.isValid ? sel.start : c.text.length;
                  final end = sel.isValid ? sel.end : c.text.length;
                  c.text = c.text.replaceRange(start, end, t);
                  c.selection = TextSelection.collapsed(offset: start + t.length);
                },
              ),
          ]),
        ]),
      ),
    );
    c.dispose();
    if (r != null) setState(() => it.text = r);
  }

  // ------------------------------------------------------------------ canvas

  Widget _bandView(BandKind b) {
    final sc = _scale;
    final w = l.contentW * sc;
    final h = l.heightOf(b) * sc;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: const Color(0xFFB9D3F0),
        child: Directionality(textDirection: TextDirection.ltr, child: Text(b.title, style: const TextStyle(fontSize: 11, color: Color(0xFF1F3B63)))),
      ),
      GestureDetector(
        onTap: () => setState(() => _sel = null),
        child: Container(
          width: w,
          height: h,
          decoration: const BoxDecoration(color: Colors.white),
          child: CustomPaint(
            painter: _GridPainter(sc),
            child: Stack(clipBehavior: Clip.none, children: [
              for (final it in l.itemsOf(b))
                Positioned(
                  left: it.x * sc,
                  top: it.y * sc,
                  child: GestureDetector(
                    onTap: () {
                      _focus.requestFocus();
                      setState(() => _sel = it);
                    },
                    onDoubleTap: () => _editText(it),
                    onPanStart: (_) => setState(() => _sel = it),
                    onPanUpdate: (d) => setState(() {
                      it.x = (it.x + d.delta.dx / sc).cl(-5, l.contentW + 5);
                      it.y = (it.y + d.delta.dy / sc).cl(-5, l.heightOf(b) + 5);
                    }),
                    onPanEnd: (_) => setState(() {
                      it.x = _snap(it.x);
                      it.y = _snap(it.y);
                    }),
                    child: Stack(clipBehavior: Clip.none, children: [
                      ReportItemView(item: it, text: it.text, scale: sc, selected: identical(it, _sel)),
                      if (identical(it, _sel))
                        Positioned(
                          right: -5,
                          bottom: -5,
                          child: GestureDetector(
                            onPanUpdate: (d) => setState(() {
                              it.w = (it.w + d.delta.dx / sc).cl(0.5, l.contentW);
                              it.h = (it.h + d.delta.dy / sc).cl(0.5, 200);
                            }),
                            onPanEnd: (_) => setState(() {
                              it.w = _snap(it.w).cl(0.5, l.contentW);
                              it.h = _snap(it.h).cl(0.5, 200);
                            }),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeDownRight,
                              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.blue, border: Border.all(color: Colors.white))),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
      // band height handle
      GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => l.bandHeights[b] = (l.heightOf(b) + d.delta.dy / sc).cl(2, 200)),
        onVerticalDragEnd: (_) => setState(() => l.bandHeights[b] = _snap(l.heightOf(b))),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Container(width: w, height: 5, color: const Color(0xFF8FB3DE)),
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _canvas() {
    final sc = _scale;
    if (_preview) {
      return Column(children: reportPages(l, widget.sample, sc));
    }
    return Container(
      width: l.pageW * sc,
      padding: EdgeInsets.all(l.margin * sc),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)]),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final b in BandKind.values) _bandView(b),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ properties

  Widget _num(String label, double value, ValueChanged<double> on, {double step = 0.5}) {
    return Row(children: [
      SizedBox(width: 82, child: Text(label, style: const TextStyle(fontSize: 12))),
      IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => on(_snap(value - step))), icon: const Icon(Icons.remove, size: 16)),
      Expanded(
        child: TextField(
          key: ValueKey('$label${_sel?.id}$value'),
          controller: TextEditingController(text: value.toStringAsFixed(1)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
          onSubmitted: (v) {
            final d = double.tryParse(v.replaceAll('٫', '.'));
            if (d != null) setState(() => on(d));
          },
        ),
      ),
      IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => on(_snap(value + step))), icon: const Icon(Icons.add, size: 16)),
    ]);
  }

  Widget _props() {
    final th = Theme.of(context);
    final s = _sel;
    if (s == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        Text('مشخصات صفحه', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: l.name),
          decoration: const InputDecoration(labelText: 'نام طرح', isDense: true),
          onChanged: (v) => l.name = v,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final (n, w, h) in [('A5', 148.0, 210.0), ('A4', 210.0, 297.0), ('A5 افقی', 210.0, 148.0), ('۸۰ میلی‌متری', 80.0, 200.0)])
            OutlinedButton(
              onPressed: () => setState(() {
                l.pageW = w;
                l.pageH = h;
              }),
              child: Text(n),
            ),
        ]),
        const SizedBox(height: 6),
        _num('عرض صفحه', l.pageW, (v) => l.pageW = v.cl(50, 400), step: 1),
        _num('ارتفاع صفحه', l.pageH, (v) => l.pageH = v.cl(50, 600), step: 1),
        _num('حاشیه', l.margin, (v) => l.margin = v.cl(0, 40)),
        const Divider(),
        Text('ارتفاع باندها', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        for (final b in BandKind.values) _num(b.title.split(':').first, l.heightOf(b), (v) => l.bandHeights[b] = v.cl(2, 200)),
        const Divider(),
        Text('روی هر جزء کلیک کنید تا انتخاب شود؛ با کشیدن جابه‌جا می‌شود، با مربع آبی گوشه اندازه‌اش عوض می‌شود و با دوبار کلیک متنش ویرایش می‌شود. '
            'کلیدهای جهت‌نما جابه‌جایی دقیق (Shift = بیشتر) و Delete حذف است.',
            style: th.textTheme.bodySmall?.copyWith(color: th.hintColor)),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Text('مشخصات جزء', style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const Spacer(),
        IconButton(tooltip: 'کپی', onPressed: _duplicate, icon: const Icon(Icons.copy_rounded, size: 18)),
        IconButton(tooltip: 'حذف (Delete)', onPressed: _delete, icon: Icon(Icons.delete_outline, size: 18, color: th.colorScheme.error)),
      ]),
      InkWell(
        onTap: () => _editText(s),
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'متن (برای ویرایش کلیک کنید)', isDense: true),
          child: Text(s.text.isEmpty ? '—' : s.text, maxLines: 3),
        ),
      ),
      const SizedBox(height: 8),
      FieldDropdown<BandKind>(
        label: 'باند',
        value: s.band,
        items: [for (final b in BandKind.values) DropdownMenuItem(value: b, child: Text(b.title.split(':').first))],
        onChanged: (v) => setState(() => s.band = v ?? s.band),
      ),
      _num('X (چپ)', s.x, (v) => s.x = v),
      _num('Y (بالا)', s.y, (v) => s.y = v),
      _num('عرض', s.w, (v) => s.w = v.cl(0.5, 400)),
      _num('ارتفاع', s.h, (v) => s.h = v.cl(0.5, 300)),
      _num('اندازه قلم', s.fontSize, (v) => s.fontSize = v.cl(4, 48)),
      Row(children: [
        FilterChip(label: const Text('ضخیم'), selected: s.bold, onSelected: (v) => setState(() => s.bold = v)),
        const SizedBox(width: 6),
        FilterChip(label: const Text('عمودی'), selected: s.vertical, onSelected: (v) => setState(() => s.vertical = v)),
      ]),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right, size: 18)),
          ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center, size: 18)),
          ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left, size: 18)),
        ],
        selected: {s.align},
        onSelectionChanged: (v) => setState(() => s.align = v.first),
      ),
      const SizedBox(height: 10),
      Text('کادر', style: th.textTheme.labelLarge),
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (final (n, bit) in [('بالا', Sides.top), ('راست', Sides.right), ('پایین', Sides.bottom), ('چپ', Sides.left)])
          FilterChip(
            label: Text(n),
            selected: s.border & bit != 0,
            onSelected: (v) => setState(() => s.border = v ? s.border | bit : s.border & ~bit),
          ),
        ActionChip(label: const Text('همه'), onPressed: () => setState(() => s.border = Sides.all)),
        ActionChip(label: const Text('هیچ'), onPressed: () => setState(() => s.border = 0)),
      ]),
      _num('ضخامت کادر', s.borderWidth, (v) => s.borderWidth = v.cl(0.1, 3), step: 0.1),
      const SizedBox(height: 6),
      Row(children: [
        const Text('رنگ زمینه: '),
        for (final c in [0, 0xFFEEEEEE, 0xFFD9D9D9, 0xFFFFF2CC, 0xFFDDEBF7])
          InkWell(
            onTap: () => setState(() => s.fill = c),
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c == 0 ? Colors.white : Color(c),
                border: Border.all(color: s.fill == c ? Colors.blue : Colors.black26, width: s.fill == c ? 2 : 1),
              ),
              child: c == 0 ? const Icon(Icons.block, size: 14, color: Colors.black38) : null,
            ),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final size = MediaQuery.of(context).size;
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return;
        final big = HardwareKeyboard.instance.isShiftPressed ? 2.0 : 0.5;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.delete) _delete();
        if (k == LogicalKeyboardKey.arrowLeft) _nudge(-big, 0);
        if (k == LogicalKeyboardKey.arrowRight) _nudge(big, 0);
        if (k == LogicalKeyboardKey.arrowUp) _nudge(0, -big);
        if (k == LogicalKeyboardKey.arrowDown) _nudge(0, big);
        if (k == LogicalKeyboardKey.f9) Navigator.pop(context, l);
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(10),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: size.width - 20,
          height: size.height - 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: const Color(0xFFE8EEF6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                const Icon(Icons.design_services_outlined, size: 20),
                const SizedBox(width: 6),
                Text('${l.name}.mrt-Designer', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 16),
                _tool(Icons.title_rounded, 'افزودن متن', () => _add('text')),
                PopupMenuButton<String>(
                  tooltip: 'افزودن فیلد',
                  icon: const Icon(Icons.data_object_rounded),
                  itemBuilder: (_) => [
                    for (final f in [...invoiceFields, ...rowFields]) PopupMenuItem(value: f, child: Text(f)),
                  ],
                  onSelected: (f) => _add('text', text: '{$f}'),
                ),
                _tool(Icons.crop_square_rounded, 'افزودن کادر', () => _add('box')),
                _tool(Icons.horizontal_rule_rounded, 'خط افقی', () => _add('hline')),
                _tool(Icons.more_vert_rounded, 'خط عمودی', () => _add('vline')),
                const VerticalDivider(),
                _tool(Icons.copy_rounded, 'کپی', _duplicate),
                _tool(Icons.delete_outline_rounded, 'حذف (Delete)', _delete),
                const VerticalDivider(),
                _tool(Icons.zoom_out, 'کوچک‌نمایی', () => setState(() => _zoom = (_zoom - 0.25).cl(0.5, 4))),
                Text('${(_zoom * 100).round()}%'),
                _tool(Icons.zoom_in, 'بزرگ‌نمایی', () => setState(() => _zoom = (_zoom + 0.25).cl(0.5, 4))),
                const SizedBox(width: 10),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Page1')),
                    ButtonSegment(value: true, label: Text('Preview')),
                  ],
                  selected: {_preview},
                  onSelectionChanged: (v) => setState(() => _preview = v.first),
                ),
                const Spacer(),
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, l),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('ذخیره طرح (F9)'),
                ),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 300, child: Material(color: th.colorScheme.surface, child: _props())),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Container(
                    color: const Color(0xFFB8BFC9),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _canvas()),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String tip, VoidCallback onTap) => IconButton(tooltip: tip, onPressed: onTap, icon: Icon(icon));
}

class _GridPainter extends CustomPainter {
  final double scale;
  _GridPainter(this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFE3E7EE)
      ..strokeWidth = 0.6;
    final step = 5 * scale; // every 5 mm
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.scale != scale;
}

extension _Cl on double {
  double cl(num lo, num hi) => this < lo ? lo.toDouble() : (this > hi ? hi.toDouble() : this);
}
