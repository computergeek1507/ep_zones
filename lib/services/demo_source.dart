import 'dart:async';
import 'dart:math' as math;

import '../models/ep_device.dart';
import '../models/ep_target.dart';
import '../models/ep_zone.dart';

/// Synthetic data source so the radar + zone editor can be developed and
/// demoed without hardware. One target walks a Lissajous path; zone occupancy
/// and counts update as it crosses each zone.
class DemoSource {
  final EpDevice device;
  final void Function() onTick;
  Timer? _timer;
  double _t = 0;

  DemoSource({required this.onTick}) : device = _buildDevice();

  void start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 100), _tick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick(Timer _) {
    _t += 0.06;
    final t1 = device.targets[0];
    t1.x = 1800 * math.sin(_t);
    t1.y = 3000 + 1600 * math.sin(_t * 0.7);
    t1.active = true;

    for (final z in device.zones) {
      final inside = device.targets
          .where((tt) => tt.present)
          .where((tt) => z.contains(tt.x, tt.y))
          .length;
      z.count = inside;
      z.occupied = inside > 0;
    }
    onTick();
  }

  static EpDevice _buildDevice() {
    return EpDevice(
      id: 'Demo',
      minX: -3000,
      maxX: 3000,
      minY: 0,
      maxY: 6000,
      maxDistance: 6000,
      installationAngle: 0,
      targets: [
        EpTarget(index: 1, x: 0, y: 3000, active: true),
        EpTarget(index: 2),
        EpTarget(index: 3),
      ],
      zones: [
        EpZone(
          index: 1,
          beginXItem: 'DEMO_Zone1_BeginX',
          beginYItem: 'DEMO_Zone1_BeginY',
          endXItem: 'DEMO_Zone1_EndX',
          endYItem: 'DEMO_Zone1_EndY',
          beginX: -2200,
          beginY: 1000,
          endX: -200,
          endY: 3000,
        ),
        EpZone(
          index: 2,
          beginXItem: 'DEMO_Zone2_BeginX',
          beginYItem: 'DEMO_Zone2_BeginY',
          endXItem: 'DEMO_Zone2_EndX',
          endYItem: 'DEMO_Zone2_EndY',
          beginX: 300,
          beginY: 2200,
          endX: 2300,
          endY: 4200,
        ),
      ],
    );
  }
}
