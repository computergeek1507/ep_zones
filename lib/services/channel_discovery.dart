import '../models/ep_device.dart';
import '../models/ep_target.dart';
import '../models/ep_zone.dart';
import '../models/naming_convention.dart';
import '../models/oh_thing.dart';

/// Maps an ESPHome channel id (object_id) to an EP Lite role. Tolerant of
/// minor naming differences (case, an optional `mmwave_`/`target_` prefix).
ItemRole? channelRole(String deviceId, String channelId) {
  final id = channelId.toLowerCase();
  const indexed = <String, RoleKind>{
    r'^target_(\d+)_x$': RoleKind.targetX,
    r'^target_(\d+)_y$': RoleKind.targetY,
    r'^target_(\d+)_active$': RoleKind.targetActive,
    r'^zone_(\d+)_begin_x$': RoleKind.zoneBeginX,
    r'^zone_(\d+)_begin_y$': RoleKind.zoneBeginY,
    r'^zone_(\d+)_end_x$': RoleKind.zoneEndX,
    r'^zone_(\d+)_end_y$': RoleKind.zoneEndY,
    r'^zone_(\d+)_occupancy$': RoleKind.zoneOccupancy,
    r'^zone_(\d+)_(?:target_)?count$': RoleKind.zoneCount,
  };
  for (final e in indexed.entries) {
    final m = RegExp(e.key).firstMatch(id);
    if (m != null) {
      return ItemRole(deviceId, e.value, int.tryParse(m.group(1)!));
    }
  }
  if (RegExp(r'^(?:mmwave_)?max_distance$').hasMatch(id)) {
    return ItemRole(deviceId, RoleKind.maxDistance, null);
  }
  if (RegExp(r'^installation_angle$').hasMatch(id)) {
    return ItemRole(deviceId, RoleKind.installationAngle, null);
  }
  return null;
}

/// A recognized role channel that has no linked Item yet (so it can't be
/// read/written until an Item is created and linked).
class MissingLink {
  final String thingUid;
  final String channelUid;
  final String channelId;
  final String itemType; // defaults to Number when the channel omits it
  final RoleKind role;
  const MissingLink({
    required this.thingUid,
    required this.channelUid,
    required this.channelId,
    required this.itemType,
    required this.role,
  });

  /// Item name to create, derived from the channel UID (REST-safe).
  String get itemName => channelUid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
}

/// Builds [EpDevice]s from ESPHome Things, resolving each role's openHAB Item
/// from the channel's linkedItems.
List<EpDevice> groupThingsIntoDevices(List<OhThing> things) {
  final devices = <EpDevice>[];
  for (final thing in things) {
    if (!thing.isEsphome) continue;
    final b = _ThingBuilder(thing.uid, thing.label, thing.host);
    var matched = false;
    for (final ch in thing.channels) {
      final role = channelRole(thing.uid, ch.id);
      if (role == null) continue;
      matched = true;
      b.add(role, ch.firstLinkedItem);
    }
    if (matched) devices.add(b.build());
  }
  devices.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return devices;
}

/// Role channels on [thing] that still need an Item created + linked.
List<MissingLink> missingLinks(OhThing thing) {
  final out = <MissingLink>[];
  for (final ch in thing.channels) {
    final role = channelRole(thing.uid, ch.id);
    if (role == null) continue;
    if (ch.linkedItems.isNotEmpty) continue;
    out.add(
      MissingLink(
        thingUid: thing.uid,
        channelUid: ch.uid,
        channelId: ch.id,
        itemType: ch.itemType ?? 'Number',
        role: role.kind,
      ),
    );
  }
  return out;
}

class _ThingBuilder {
  final String uid;
  final String label;
  final String? host;
  final Map<int, Map<RoleKind, String?>> targets = {};
  final Map<int, Map<RoleKind, String?>> zones = {};
  String? maxDistance;
  String? installationAngle;

  _ThingBuilder(this.uid, this.label, this.host);

  void add(ItemRole role, String? itemName) {
    if (role.kind.isTarget) {
      (targets[role.index!] ??= {})[role.kind] = itemName;
    } else if (role.kind.isZone) {
      (zones[role.index!] ??= {})[role.kind] = itemName;
    } else if (role.kind == RoleKind.maxDistance) {
      maxDistance = itemName;
    } else if (role.kind == RoleKind.installationAngle) {
      installationAngle = itemName;
    }
  }

  EpDevice build() {
    final targetList = (targets.keys.toList()..sort()).map((i) {
      final r = targets[i]!;
      return EpTarget(
        index: i,
        xItem: r[RoleKind.targetX],
        yItem: r[RoleKind.targetY],
        activeItem: r[RoleKind.targetActive],
      );
    }).toList();

    final zoneList = (zones.keys.toList()..sort()).map((i) {
      final r = zones[i]!;
      return EpZone(
        index: i,
        beginXItem: r[RoleKind.zoneBeginX],
        beginYItem: r[RoleKind.zoneBeginY],
        endXItem: r[RoleKind.zoneEndX],
        endYItem: r[RoleKind.zoneEndY],
        occupancyItem: r[RoleKind.zoneOccupancy],
        countItem: r[RoleKind.zoneCount],
      );
    }).toList();

    return EpDevice(
      id: uid,
      label: label,
      host: host,
      targets: targetList,
      zones: zoneList,
      maxDistanceItem: maxDistance,
      installationAngleItem: installationAngle,
    );
  }
}
