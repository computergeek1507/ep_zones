import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/models/naming_convention.dart';

void main() {
  const c = NamingConvention.defaults;

  test('parses target coordinate items', () {
    expect(c.parse('EPL_Office_Target1_X'),
        const ItemRole('Office', RoleKind.targetX, 1));
    expect(c.parse('EPL_Office_Target2_Y'),
        const ItemRole('Office', RoleKind.targetY, 2));
    expect(c.parse('EPL_Office_Target3_Active'),
        const ItemRole('Office', RoleKind.targetActive, 3));
  });

  test('parses zone corner + sensor items', () {
    expect(c.parse('EPL_Office_Zone1_BeginX'),
        const ItemRole('Office', RoleKind.zoneBeginX, 1));
    expect(c.parse('EPL_Office_Zone4_EndY'),
        const ItemRole('Office', RoleKind.zoneEndY, 4));
    expect(c.parse('EPL_Office_Zone2_Occupancy'),
        const ItemRole('Office', RoleKind.zoneOccupancy, 2));
    expect(c.parse('EPL_Office_Zone2_Count'),
        const ItemRole('Office', RoleKind.zoneCount, 2));
  });

  test('parses device config items (no index)', () {
    expect(c.parse('EPL_Office_MaxDistance'),
        const ItemRole('Office', RoleKind.maxDistance, null));
    expect(c.parse('EPL_Office_InstallationAngle'),
        const ItemRole('Office', RoleKind.installationAngle, null));
  });

  test('handles device names containing the separator', () {
    expect(c.parse('EPL_Living_Room_Zone1_BeginX'),
        const ItemRole('Living_Room', RoleKind.zoneBeginX, 1));
  });

  test('returns null for non-matching names', () {
    expect(c.parse('Other_Thing_State'), isNull);
    expect(c.parse('EPL_Office_Unknown'), isNull);
    expect(c.parse('EPL_Office_Zone1_BeginZ'), isNull);
  });

  test('honours a custom prefix and separator', () {
    const custom = NamingConvention(prefix: 'ep', separator: '.');
    expect(custom.parse('ep.Kitchen.Zone1.EndX'),
        const ItemRole('Kitchen', RoleKind.zoneEndX, 1));
    // Default-style name must not match the custom convention.
    expect(custom.parse('EPL_Office_Target1_X'), isNull);
  });

  test('example() round-trips through parse()', () {
    final name = c.example('Den', RoleKind.zoneBeginX, index: 3);
    expect(name, 'EPL_Den_Zone3_BeginX');
    expect(c.parse(name), const ItemRole('Den', RoleKind.zoneBeginX, 3));
  });
}
