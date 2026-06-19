import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/ui/widgets/coord_transform.dart';

void main() {
  const t = CoordTransform(
    minX: -4860,
    maxX: 4860,
    minY: 0,
    maxY: 7560,
    size: Size(400, 600),
    margin: 16,
  );

  test('sensor origin maps to top-centre', () {
    final p = t.toCanvas(0, 0);
    expect(p.dx, closeTo(200, 0.5)); // x=0 is centred
    expect(p.dy, closeTo(16, 0.5)); // y=minY is at top margin
  });

  test('toWorld is the inverse of toCanvas', () {
    for (final w in const [
      Offset(0, 0),
      Offset(-2000, 3000),
      Offset(4860, 7560),
      Offset(1234, 567),
    ]) {
      final back = t.toWorld(t.toCanvas(w.dx, w.dy));
      expect(back.dx, closeTo(w.dx, 0.01));
      expect(back.dy, closeTo(w.dy, 0.01));
    }
  });

  test('Y increases downward (further = lower on screen)', () {
    expect(t.toCanvas(0, 1000).dy, greaterThan(t.toCanvas(0, 0).dy));
  });
}
