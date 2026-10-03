import 'package:flutter/material.dart';

import 'common.dart';

/// Shared look of the Sakan-style windows: light sky background, framed
/// buttons with the shortcut key in red, grid header and cells.
const sakanSky = Color(0xFFDCEBFA);
const sakanSkyDark = Color(0xFF9DC3EA);
const sakanSel = Color(0xFF2F6FDE);
const sakanGreen = Color(0xFFD7F2D7);
const sakanPink = Color(0xFFFBE0E0);

Widget sakanBtn(String label, VoidCallback? onTap, {String key = '', IconData? icon, Color? color, double height = 38, int lines = 1}) => SizedBox(
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: color ?? Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: const BorderSide(color: sakanSkyDark),
        ),
        onPressed: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (key.isNotEmpty) ...[
            Text(key, style: const TextStyle(fontSize: 11, color: Color(0xFFD84315), fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
          ],
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
          Flexible(
            child: lines > 1
                ? Text(label, textAlign: TextAlign.center, maxLines: lines, overflow: TextOverflow.ellipsis)
                : FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
          ),
        ]),
      ),
    );

Widget sakanHead(String t, double w, {Color? color, Color? fg}) {
  final c = Container(
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, border: const Border(left: BorderSide(color: Colors.black12))),
    child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

Widget sakanCell(Widget child, double w, {Alignment align = Alignment.center}) {
  final c = Container(
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black12))),
    child: child,
  );
  return w == 0 ? Expanded(child: c) : SizedBox(width: w, child: c);
}

/// A sky-blue window with a gradient title bar.
class SakanWindow extends StatelessWidget {
  final String title;
  final Widget body;
  final double width;
  final double height;
  const SakanWindow({super.key, required this.title, required this.body, this.width = 900, this.height = 640});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      backgroundColor: sakanSky,
      child: SizedBox(
        width: width,
        height: height.clamp(200.0, size.height * 0.94),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HeaderBand(
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15), overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

/// Framed group with its caption under the content (ribbon style).
Widget sakanGroup(String title, Widget child) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.55), border: Border.all(color: sakanSkyDark), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        child,
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );

/// Grid shell: header row + rows (or an empty text).
class SakanGrid extends StatelessWidget {
  final List<Widget> header;
  final int count;
  final Widget Function(BuildContext, int) row;
  final String empty;
  final ScrollController? controller;
  const SakanGrid({super.key, required this.header, required this.count, required this.row, this.empty = 'موردی وجود ندارد', this.controller});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: sakanSkyDark)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(color: const Color(0xFFEFF5FC), child: Row(children: header)),
          const Divider(height: 1),
          Expanded(
            child: count == 0
                ? Center(child: Text(empty, style: const TextStyle(color: Colors.black45)))
                : ListView.builder(controller: controller, itemExtent: 32, itemCount: count, itemBuilder: row),
          ),
        ]),
      );
}
