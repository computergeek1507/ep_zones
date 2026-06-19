import 'oh_item.dart';
import 'ep_target.dart';
import 'ep_zone.dart';

/// Default sensor-plane bounds for the HLK-LD2450 (millimetres), used when the
/// openHAB Items don't advertise a min/max in their stateDescription.
const double kDefaultMinX = -4860;
const double kDefaultMaxX = 4860;
const double kDefaultMinY = 0;
const double kDefaultMaxY = 7560;

/// One Everything Presence Lite device: its targets, zones, and the config
/// Items needed to draw the detection fan. Values mutate in place as live
/// updates arrive; [applyState] routes an Item update to the right field.
class EpDevice {
  final String id;

  /// Human-friendly name (Thing label); falls back to [id].
  final String label;

  /// Device IP/hostname when known (from the Thing config or direct mode).
  final String? host;
  final List<EpTarget> targets;
  final List<EpZone> zones;

  final String? maxDistanceItem;
  final String? installationAngleItem;
  double maxDistance; // mm
  double installationAngle; // degrees

  // Canvas bounds in mm (lateral X, away Y).
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  late final Map<String, void Function(String)> _handlers = _buildHandlers();

  EpDevice({
    required this.id,
    String? label,
    this.host,
    required this.targets,
    required this.zones,
    this.maxDistanceItem,
    this.installationAngleItem,
    this.maxDistance = kDefaultMaxY,
    this.installationAngle = 0,
    this.minX = kDefaultMinX,
    this.maxX = kDefaultMaxX,
    this.minY = kDefaultMinY,
    this.maxY = kDefaultMaxY,
  }) : label = (label == null || label.isEmpty) ? id : label;

  /// Every openHAB Item name this device cares about.
  Iterable<String> get itemNames => _handlers.keys;

  /// Applies a live state update for [itemName]. Returns true if it belonged
  /// to this device (and was applied).
  bool applyState(String itemName, String state) {
    final h = _handlers[itemName];
    if (h == null) return false;
    h(state);
    return true;
  }

  Map<String, void Function(String)> _buildHandlers() {
    final map = <String, void Function(String)>{};
    void numeric(String? item, void Function(double) set) {
      if (item == null) return;
      map[item] = (s) {
        final v = OhItem.parseNumber(s);
        if (v != null) set(v);
      };
    }

    void boolean(String? item, void Function(bool) set) {
      if (item == null) return;
      map[item] = (s) {
        final t = s.trim().toUpperCase();
        set(t == 'ON' || t == 'OPEN' || t == 'TRUE' || t == '1');
      };
    }

    for (final t in targets) {
      numeric(t.xItem, (v) => t.x = v);
      numeric(t.yItem, (v) => t.y = v);
      boolean(t.activeItem, (v) => t.active = v);
    }
    for (final z in zones) {
      numeric(z.beginXItem, (v) => z.beginX = v);
      numeric(z.beginYItem, (v) => z.beginY = v);
      numeric(z.endXItem, (v) => z.endX = v);
      numeric(z.endYItem, (v) => z.endY = v);
      numeric(z.countItem, (v) => z.count = v.round());
      boolean(z.occupancyItem, (v) => z.occupied = v);
    }
    numeric(maxDistanceItem, (v) => maxDistance = v);
    numeric(installationAngleItem, (v) => installationAngle = v);
    return map;
  }

  bool get anyOccupied => zones.any((z) => z.occupied);
}
