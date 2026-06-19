import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/models/ep_device.dart';
import 'package:ep_zones/models/ep_zone.dart';
import 'package:ep_zones/services/yaml_export.dart';

void main() {
  final device = EpDevice(
    id: 'esphome:device:abc',
    label: 'Office',
    host: '192.168.1.50',
    targets: const [],
    zones: [
      EpZone(
        index: 1,
        beginXItem: 'a',
        beginYItem: 'b',
        endXItem: 'c',
        endYItem: 'd',
        beginX: -2000,
        beginY: 1000,
        endX: 0,
        endY: 3000,
      ),
      EpZone(index: 2), // incomplete -> skipped
    ],
  );

  test('emits substitutions for complete zones only', () {
    final yaml = buildZonesYaml(device, now: DateTime.utc(2026, 6, 19, 12));
    expect(yaml, contains('substitutions:'));
    expect(yaml, contains('zone_1_begin_x: "-2000"'));
    expect(yaml, contains('zone_1_end_y: "3000"'));
    expect(yaml, contains('Office (192.168.1.50)'));
    expect(yaml, contains('2026-06-19'));
    // Zone 2 is incomplete, so it must not appear.
    expect(yaml, isNot(contains('zone_2_begin_x')));
  });
}
