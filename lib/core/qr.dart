import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// QR code helpers («QR کد» on printed documents).

/// Module matrix of [data] (true = dark), or null when it does not fit in a QR code.
List<List<bool>>? qrMatrix(String data) {
  final text = data.trim();
  if (text.isEmpty) return null;
  try {
    final code = QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M);
    final img = QrImage(code);
    final n = img.moduleCount;
    return [
      for (var r = 0; r < n; r++) [for (var c = 0; c < n; c++) img.isDark(r, c)]
    ];
  } catch (_) {
    return null;
  }
}

/// Inline SVG of the QR code (with a 2-module quiet zone), sized to fill its box.
String qrSvg(String data) {
  final m = qrMatrix(data);
  if (m == null) return '';
  final n = m.length;
  final size = n + 4;
  final p = StringBuffer();
  for (var r = 0; r < n; r++) {
    var c = 0;
    while (c < n) {
      if (!m[r][c]) {
        c++;
        continue;
      }
      final start = c;
      while (c < n && m[r][c]) {
        c++;
      }
      p.write('M${start + 2} ${r + 2}h${c - start}v1h-${c - start}z');
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="100%" height="100%" '
      'preserveAspectRatio="xMidYMid meet" shape-rendering="crispEdges">'
      '<rect width="$size" height="$size" fill="#fff"/><path d="$p" fill="#000"/></svg>';
}

/// Paints a QR code centred in its box.
class QrPainter extends CustomPainter {
  final String data;
  final Color color;
  QrPainter(this.data, {this.color = const Color(0xFF000000)}) : _m = qrMatrix(data);

  final List<List<bool>>? _m;

  @override
  void paint(Canvas canvas, Size size) {
    final m = _m;
    if (m == null) return;
    final n = m.length + 4;
    final side = size.shortestSide;
    final cell = side / n;
    final ox = (size.width - side) / 2 + 2 * cell;
    final oy = (size.height - side) / 2 + 2 * cell;
    canvas.drawRect(
      Rect.fromLTWH((size.width - side) / 2, (size.height - side) / 2, side, side),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    final path = Path();
    for (var r = 0; r < m.length; r++) {
      for (var c = 0; c < m.length; c++) {
        if (m[r][c]) path.addRect(Rect.fromLTWH(ox + c * cell, oy + r * cell, cell + 0.01, cell + 0.01));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(QrPainter old) => old.data != data || old.color != color;
}

/// A QR code widget.
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView(this.data, {super.key, this.size = 96});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: QrPainter(data)));
}
