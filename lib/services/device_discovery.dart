import '../models/ep_device.dart';
import '../models/ep_target.dart';
import '../models/ep_zone.dart';
import '../models/naming_convention.dart';
import '../models/oh_item.dart';

/// Groups a flat list of openHAB Items into [EpDevice]s using [conv].
///
/// Pure and side-effect free so it can be unit tested. Initial live values are
/// seeded from each Item's current state; ranges (min/max) come from the corner
/// Items' stateDescription, falling back to LD2450 defaults.
List<EpDevice> groupItemsIntoDevices(
  List<OhItem> items,
  NamingConvention conv,
) {
  final byId = <String, _DeviceBuilder>{};
  for (final item in items) {
    final role = conv.parse(item.name);
    if (role == null) continue;
    byId
        .putIfAbsent(role.deviceId, () => _DeviceBuilder(role.deviceId))
        .add(role, item);
  }
  final devices = byId.values.map((b) => b.build()).toList();
  devices.sort((a, b) => a.id.compareTo(b.id));
  return devices;
}

class _TargetBuilder {
  OhItem? x, y, active;
}

class _ZoneBuilder {
  OhItem? beginX, beginY, endX, endY, occupancy, count;
}

class _DeviceBuilder {
  final String id;
  final Map<int, _TargetBuilder> targets = {};
  final Map<int, _ZoneBuilder> zones = {};
  OhItem? maxDistance;
  OhItem? installationAngle;

  _DeviceBuilder(this.id);

  void add(ItemRole role, OhItem item) {
    switch (role.kind) {
      case RoleKind.targetX:
        _t(role.index!).x = item;
      case RoleKind.targetY:
        _t(role.index!).y = item;
      case RoleKind.targetActive:
        _t(role.index!).active = item;
      case RoleKind.zoneBeginX:
        _z(role.index!).beginX = item;
      case RoleKind.zoneBeginY:
        _z(role.index!).beginY = item;
      case RoleKind.zoneEndX:
        _z(role.index!).endX = item;
      case RoleKind.zoneEndY:
        _z(role.index!).endY = item;
      case RoleKind.zoneOccupancy:
        _z(role.index!).occupancy = item;
      case RoleKind.zoneCount:
        _z(role.index!).count = item;
      case RoleKind.maxDistance:
        maxDistance = item;
      case RoleKind.installationAngle:
        installationAngle = item;
    }
  }

  _TargetBuilder _t(int i) => targets.putIfAbsent(i, () => _TargetBuilder());
  _ZoneBuilder _z(int i) => zones.putIfAbsent(i, () => _ZoneBuilder());

  EpDevice build() {
    final targetList = (targets.keys.toList()..sort()).map((i) {
      final t = targets[i]!;
      return EpTarget(
        index: i,
        xItem: t.x?.name,
        yItem: t.y?.name,
        activeItem: t.active?.name,
        x: t.x?.numericState ?? 0,
        y: t.y?.numericState ?? 0,
        active: t.active?.boolState ?? false,
      );
    }).toList();

    final zoneList = (zones.keys.toList()..sort()).map((i) {
      final z = zones[i]!;
      return EpZone(
        index: i,
        beginXItem: z.beginX?.name,
        beginYItem: z.beginY?.name,
        endXItem: z.endX?.name,
        endYItem: z.endY?.name,
        occupancyItem: z.occupancy?.name,
        countItem: z.count?.name,
        beginX: z.beginX?.numericState ?? 0,
        beginY: z.beginY?.numericState ?? 0,
        endX: z.endX?.numericState ?? 0,
        endY: z.endY?.numericState ?? 0,
        occupied: z.occupancy?.boolState ?? false,
        count: (z.count?.numericState ?? 0).round(),
        minX: z.beginX?.min ?? z.endX?.min,
        maxX: z.beginX?.max ?? z.endX?.max,
        minY: z.beginY?.min ?? z.endY?.min,
        maxY: z.beginY?.max ?? z.endY?.max,
      );
    }).toList();

    final bounds = _computeBounds(zoneList);

    return EpDevice(
      id: id,
      targets: targetList,
      zones: zoneList,
      maxDistanceItem: maxDistance?.name,
      installationAngleItem: installationAngle?.name,
      maxDistance: maxDistance?.numericState ?? kDefaultMaxY,
      installationAngle: installationAngle?.numericState ?? 0,
      minX: bounds[0],
      maxX: bounds[1],
      minY: bounds[2],
      maxY: bounds[3],
    );
  }

  /// [minX, maxX, minY, maxY] from zone corner ranges, padded, with defaults.
  List<double> _computeBounds(List<EpZone> zoneList) {
    double? minX, maxX, minY, maxY;
    for (final z in zoneList) {
      minX = _min(minX, z.minX);
      maxX = _max(maxX, z.maxX);
      minY = _min(minY, z.minY);
      maxY = _max(maxY, z.maxY);
    }
    return [
      minX ?? kDefaultMinX,
      maxX ?? kDefaultMaxX,
      minY ?? kDefaultMinY,
      maxY ?? kDefaultMaxY,
    ];
  }

  double? _min(double? a, double? b) =>
      b == null ? a : (a == null ? b : (a < b ? a : b));
  double? _max(double? a, double? b) =>
      b == null ? a : (a == null ? b : (a > b ? a : b));
}
