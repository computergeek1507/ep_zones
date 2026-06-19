import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/models/naming_convention.dart';
import 'package:ep_zones/models/oh_item.dart';
import 'package:ep_zones/services/device_discovery.dart';

OhItem num(String name, String state, {double? min, double? max}) =>
    OhItem(name: name, type: 'Number', state: state, min: min, max: max);

void main() {
  const conv = NamingConvention.defaults;

  test('groups items into a device with a zone and a target', () {
    final items = [
      num('EPL_Office_Zone1_BeginX', '-2000 mm', min: -4860, max: 4860),
      num('EPL_Office_Zone1_BeginY', '1000 mm', min: 0, max: 7560),
      num('EPL_Office_Zone1_EndX', '0 mm'),
      num('EPL_Office_Zone1_EndY', '3000 mm'),
      OhItem(
          name: 'EPL_Office_Zone1_Occupancy', type: 'Switch', state: 'ON'),
      num('EPL_Office_Target1_X', '500 mm'),
      num('EPL_Office_Target1_Y', '2500 mm'),
      num('Some_Other_Item', '42'),
    ];

    final devices = groupItemsIntoDevices(items, conv);
    expect(devices, hasLength(1));
    final d = devices.single;
    expect(d.id, 'Office');
    expect(d.zones, hasLength(1));
    expect(d.targets, hasLength(1));

    final z = d.zones.single;
    expect(z.isComplete, isTrue);
    expect(z.beginX, -2000);
    expect(z.endY, 3000);
    expect(z.occupied, isTrue);

    // Bounds picked up from the corner Item stateDescription.
    expect(d.minX, -4860);
    expect(d.maxY, 7560);

    final t = d.targets.single;
    expect(t.x, 500);
    expect(t.y, 2500);
  });

  test('multiple devices are separated and sorted', () {
    final items = [
      num('EPL_Bravo_Zone1_BeginX', '0'),
      num('EPL_Alpha_Zone1_BeginX', '0'),
    ];
    final devices = groupItemsIntoDevices(items, conv);
    expect(devices.map((d) => d.id), ['Alpha', 'Bravo']);
  });

  test('incomplete zone is reported but not complete', () {
    final items = [
      num('EPL_Office_Zone2_BeginX', '0'),
      num('EPL_Office_Zone2_BeginY', '0'),
      // EndX / EndY missing
    ];
    final d = groupItemsIntoDevices(items, conv).single;
    expect(d.zones.single.isComplete, isFalse);
  });

  test('falls back to LD2450 default bounds without stateDescription', () {
    final items = [
      num('EPL_Office_Zone1_BeginX', '0'),
      num('EPL_Office_Zone1_BeginY', '0'),
      num('EPL_Office_Zone1_EndX', '0'),
      num('EPL_Office_Zone1_EndY', '0'),
    ];
    final d = groupItemsIntoDevices(items, conv).single;
    expect(d.minX, -4860);
    expect(d.maxX, 4860);
    expect(d.minY, 0);
    expect(d.maxY, 7560);
  });
}
