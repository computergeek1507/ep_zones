import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/models/naming_convention.dart';
import 'package:ep_zones/models/oh_thing.dart';
import 'package:ep_zones/services/channel_discovery.dart';

OhChannel ch(
  String id, {
  List<String> links = const [],
  String type = 'Number',
}) => OhChannel(
  uid: 'esphome:device:40ea2c136a:$id',
  id: id,
  itemType: type,
  linkedItems: links,
);

void main() {
  group('channelRole', () {
    const dev = 'esphome:device:40ea2c136a';
    test('maps target and zone channel ids', () {
      expect(
        channelRole(dev, 'target_1_x'),
        const ItemRole(dev, RoleKind.targetX, 1),
      );
      expect(
        channelRole(dev, 'target_3_y'),
        const ItemRole(dev, RoleKind.targetY, 3),
      );
      expect(
        channelRole(dev, 'zone_2_begin_x'),
        const ItemRole(dev, RoleKind.zoneBeginX, 2),
      );
      expect(
        channelRole(dev, 'zone_4_end_y'),
        const ItemRole(dev, RoleKind.zoneEndY, 4),
      );
      expect(
        channelRole(dev, 'zone_1_occupancy'),
        const ItemRole(dev, RoleKind.zoneOccupancy, 1),
      );
    });

    test('accepts both count variants and is case-insensitive', () {
      expect(channelRole(dev, 'zone_1_target_count')!.kind, RoleKind.zoneCount);
      expect(channelRole(dev, 'zone_1_count')!.kind, RoleKind.zoneCount);
      expect(channelRole(dev, 'ZONE_1_BEGIN_X')!.kind, RoleKind.zoneBeginX);
    });

    test('maps config channels and rejects unrelated ones', () {
      expect(channelRole(dev, 'max_distance')!.kind, RoleKind.maxDistance);
      expect(
        channelRole(dev, 'mmwave_max_distance')!.kind,
        RoleKind.maxDistance,
      );
      expect(
        channelRole(dev, 'installation_angle')!.kind,
        RoleKind.installationAngle,
      );
      expect(channelRole(dev, 'illuminance'), isNull);
      expect(channelRole(dev, 'esp_temperature'), isNull);
    });
  });

  group('groupThingsIntoDevices', () {
    final thing = OhThing(
      uid: 'esphome:device:40ea2c136a',
      label: 'Office EP Lite',
      thingTypeUID: 'esphome:device',
      status: 'ONLINE',
      channels: [
        ch('target_1_x', links: ['EPL_t1x']),
        ch('target_1_y', links: ['EPL_t1y']),
        ch('zone_1_begin_x', links: ['EPL_z1bx']),
        ch('zone_1_begin_y', links: ['EPL_z1by']),
        ch('zone_1_end_x', links: ['EPL_z1ex']),
        ch('zone_1_end_y', links: ['EPL_z1ey']),
        ch('zone_1_occupancy', links: ['EPL_z1occ'], type: 'Switch'),
        ch('illuminance', links: ['EPL_lux']),
      ],
    );

    test('builds a device keyed by Thing UID with label', () {
      final devices = groupThingsIntoDevices([thing]);
      expect(devices, hasLength(1));
      final d = devices.single;
      expect(d.id, 'esphome:device:40ea2c136a');
      expect(d.label, 'Office EP Lite');
      expect(d.targets.single.xItem, 'EPL_t1x');
      final z = d.zones.single;
      expect(z.isComplete, isTrue);
      expect(z.beginXItem, 'EPL_z1bx');
      expect(z.occupancyItem, 'EPL_z1occ');
    });

    test('non-esphome things are ignored', () {
      final other = OhThing(
        uid: 'mqtt:topic:foo',
        label: 'Foo',
        thingTypeUID: 'mqtt:topic',
        status: 'ONLINE',
        channels: [
          ch('zone_1_begin_x', links: ['x']),
        ],
      );
      expect(groupThingsIntoDevices([other]), isEmpty);
    });
  });

  group('missingLinks', () {
    test('reports recognized channels without a linked item', () {
      final thing = OhThing(
        uid: 'esphome:device:abc',
        label: 'Den',
        thingTypeUID: 'esphome:device',
        status: 'ONLINE',
        channels: [
          ch('zone_1_begin_x'), // no link
          ch('zone_1_begin_y', links: ['has_link']),
          ch('illuminance'), // not a role -> ignored
        ],
      );
      final missing = missingLinks(thing);
      expect(missing, hasLength(1));
      expect(missing.single.channelId, 'zone_1_begin_x');
      // Item name derives from the (globally unique) channel UID.
      expect(
        missing.single.itemName,
        'esphome_device_40ea2c136a_zone_1_begin_x',
      );
    });
  });
}
