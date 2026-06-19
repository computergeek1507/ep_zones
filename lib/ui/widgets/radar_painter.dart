import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/ep_device.dart';
import '../../models/ep_zone.dart';
import 'coord_transform.dart';

/// Draws the sensor radar plane: mm grid, detection fan, zones (with handles on
/// the selected one), and live target dots. Extends the dot-overlay approach of
/// pixel_mapper's LayoutPainter to a mm-coordinate radar view.
class RadarPainter extends CustomPainter {
  final EpDevice device;
  final CoordTransform t;
  final int? selectedZone;

  /// When true, the reference grid is drawn in feet instead of metres.
  final bool imperial;

  RadarPainter({
    required this.device,
    required this.t,
    this.selectedZone,
    this.imperial = false,
  });

  static const double handleRadius = 9;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas);
    _drawFan(canvas);
    for (final z in device.zones) {
      _drawZone(canvas, z, z.index == selectedZone);
    }
    _drawSensor(canvas);
    for (final tg in device.targets) {
      if (tg.present) _drawTarget(canvas, tg.index, tg.x, tg.y);
    }
  }

  void _drawGrid(Canvas canvas) {
    final bg = Paint()..color = const Color(0xFF0E1620);
    canvas.drawRect(Offset.zero & t.size, bg);

    final grid = Paint()
      ..color = const Color(0xFF1E2A38)
      ..strokeWidth = 1;
    // Grid step: 1 m (metric) or 2 ft (imperial), with matching labels.
    final step = imperial ? 609.6 : 1000.0;
    String label(double v) =>
        imperial ? '${(v / 304.8).round()}ft' : '${(v / 1000).round()}m';

    final startX = (device.minX / step).ceil() * step;
    for (double x = startX; x <= device.maxX; x += step) {
      final p1 = t.toCanvas(x, device.minY);
      final p2 = t.toCanvas(x, device.maxY);
      canvas.drawLine(
        p1,
        p2,
        x.abs() < 0.5 ? (grid..color = const Color(0xFF35506B)) : grid,
      );
      grid.color = const Color(0xFF1E2A38);
    }
    final startY = (device.minY / step).ceil() * step;
    for (double y = startY; y <= device.maxY; y += step) {
      canvas.drawLine(
        t.toCanvas(device.minX, y),
        t.toCanvas(device.maxX, y),
        grid,
      );
      _label(
        canvas,
        label(y),
        t.toCanvas(device.minX, y) + const Offset(2, 2),
        const Color(0xFF54708A),
        10,
      );
    }
  }

  void _drawFan(Canvas canvas) {
    // LD2450 field of view is ~120° (±60°). Sweep around the installation angle.
    final origin = t.toCanvas(0, device.minY);
    const halfFov = 60 * math.pi / 180;
    final baseAngle = math.pi / 2 + device.installationAngle * math.pi / 180;
    final r = device.maxDistance;
    final path = Path()..moveTo(origin.dx, origin.dy);
    const segments = 24;
    for (int i = 0; i <= segments; i++) {
      final a = baseAngle - halfFov + (2 * halfFov) * (i / segments);
      final wx = r * math.cos(a);
      final wy = device.minY + r * math.sin(a);
      final p = t.toCanvas(wx, wy);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x1435C2F0)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x3335C2F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawZone(Canvas canvas, EpZone z, bool selected) {
    if (!z.isComplete) return;
    final a = t.toCanvas(z.left, z.top);
    final b = t.toCanvas(z.right, z.bottom);
    final rect = Rect.fromPoints(a, b);
    final color = z.occupied
        ? const Color(0xFF00E676)
        : const Color(0xFF35C2F0);
    canvas.drawRect(
      rect,
      Paint()..color = color.withValues(alpha: z.occupied ? 0.22 : 0.10),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: selected ? 1 : 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 1.5,
    );

    if (selected) {
      for (final c in _corners(z)) {
        final cp = t.toCanvas(c.dx, c.dy);
        canvas.drawCircle(
          cp,
          RadarPainter.handleRadius,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          cp,
          RadarPainter.handleRadius,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // Zone label + live count — drawn last (on top of handles) with a dark
    // background pill, clamped so it stays fully on-canvas.
    _zoneLabel(
      canvas,
      'Z${z.index}${z.count > 0 ? "  •${z.count}" : ""}',
      rect,
      color,
      selected,
    );
  }

  void _zoneLabel(
    Canvas canvas,
    String text,
    Rect rect,
    Color color,
    bool selected,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Nudge right past the corner handle on the selected zone.
    var x = rect.left + (selected ? RadarPainter.handleRadius + 4 : 5);
    var y = rect.top + 3;
    final maxX = (t.size.width - tp.width - 4).clamp(2.0, double.infinity);
    final maxY = (t.size.height - tp.height - 4).clamp(2.0, double.infinity);
    x = x.clamp(2.0, maxX);
    y = y.clamp(2.0, maxY);
    final bg = Rect.fromLTWH(x - 3, y - 1, tp.width + 6, tp.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(3)),
      Paint()..color = const Color(0xCC0B121A),
    );
    tp.paint(canvas, Offset(x, y));
  }

  /// The four editable corners in world mm.
  static List<Offset> _corners(EpZone z) => [
    Offset(z.beginX, z.beginY),
    Offset(z.endX, z.beginY),
    Offset(z.beginX, z.endY),
    Offset(z.endX, z.endY),
  ];

  void _drawSensor(Canvas canvas) {
    final o = t.toCanvas(0, device.minY);
    canvas.drawCircle(o, 6, Paint()..color = const Color(0xFFFFC107));
    canvas.drawCircle(
      o,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawTarget(Canvas canvas, int idx, double x, double y) {
    final p = t.toCanvas(x, y);
    canvas.drawCircle(p, 9, Paint()..color = const Color(0xFFFF5252));
    canvas.drawCircle(
      p,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _label(canvas, '$idx', p + const Offset(11, -6), Colors.white, 11);
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant RadarPainter old) => true;
}
