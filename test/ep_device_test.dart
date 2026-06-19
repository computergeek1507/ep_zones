import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/models/ep_device.dart';
import 'package:ep_zones/models/ep_target.dart';
import 'package:ep_zones/models/ep_zone.dart';

void main() {
  EpDevice device() => EpDevice(
        id: 'Office',
        targets: [
          EpTarget(
              index: 1,
              xItem: 'EPL_Office_Target1_X',
              yItem: 'EPL_Office_Target1_Y'),
        ],
        zones: [
          EpZone(
            index: 1,
            beginXItem: 'EPL_Office_Zone1_BeginX',
            beginYItem: 'EPL_Office_Zone1_BeginY',
            endXItem: 'EPL_Office_Zone1_EndX',
            endYItem: 'EPL_Office_Zone1_EndY',
            occupancyItem: 'EPL_Office_Zone1_Occupancy',
            beginX: -1000,
            beginY: 1000,
            endX: 1000,
            endY: 3000,
          ),
        ],
      );

  test('applyState routes Item updates to the right field', () {
    final d = device();
    expect(d.applyState('EPL_Office_Target1_X', '512 mm'), isTrue);
    expect(d.targets.first.x, 512);

    d.applyState('EPL_Office_Zone1_Occupancy', 'ON');
    expect(d.zones.first.occupied, isTrue);
    expect(d.anyOccupied, isTrue);
  });

  test('applyState ignores unknown items', () {
    final d = device();
    expect(d.applyState('Unrelated_Item', '1'), isFalse);
  });

  test('zone geometry helpers and containment', () {
    final z = device().zones.first;
    expect(z.left, -1000);
    expect(z.right, 1000);
    expect(z.contains(0, 2000), isTrue);
    expect(z.contains(2000, 2000), isFalse);
    expect(z.isActive, isTrue);
  });

  test('cornerCommands emits each mapped corner', () {
    final z = device().zones.first;
    final cmds = z.cornerCommands();
    expect(cmds['EPL_Office_Zone1_BeginX'], -1000);
    expect(cmds['EPL_Office_Zone1_EndY'], 3000);
    expect(cmds, hasLength(4));
  });

  test('itemNames covers every mapped role', () {
    final d = device();
    expect(d.itemNames, contains('EPL_Office_Target1_X'));
    expect(d.itemNames, contains('EPL_Office_Zone1_Occupancy'));
  });
}
