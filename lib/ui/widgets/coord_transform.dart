import 'dart:ui';

/// Pure mapping between sensor-plane millimetres and canvas pixels.
///
/// World space: X lateral (minX..maxX), Y distance away from sensor
/// (minY..maxY). Canvas space: origin top-left, Y increases downward — so the
/// sensor (Y = minY) sits at the top and targets move down as they recede.
class CoordTransform {
  final double minX, maxX, minY, maxY;
  final Size size;
  final double margin;

  const CoordTransform({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.size,
    this.margin = 16,
  });

  double get _w => (size.width - 2 * margin).clamp(1, double.infinity);
  double get _h => (size.height - 2 * margin).clamp(1, double.infinity);
  double get _spanX => (maxX - minX).abs() < 1e-9 ? 1 : (maxX - minX);
  double get _spanY => (maxY - minY).abs() < 1e-9 ? 1 : (maxY - minY);

  Offset toCanvas(double xMm, double yMm) {
    final fx = (xMm - minX) / _spanX;
    final fy = (yMm - minY) / _spanY;
    return Offset(margin + fx * _w, margin + fy * _h);
  }

  Offset toWorld(Offset canvas) {
    final fx = (canvas.dx - margin) / _w;
    final fy = (canvas.dy - margin) / _h;
    return Offset(minX + fx * _spanX, minY + fy * _spanY);
  }

  double get mmPerPxX => _spanX / _w;
  double get mmPerPxY => _spanY / _h;
}
