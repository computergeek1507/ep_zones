/// A configurable detection zone, defined by two corners in sensor-plane mm.
///
/// The four corner coordinates are writable openHAB Number Items (the ESPHome
/// `number` entities). Occupancy and target-count are read-only sensors.
class EpZone {
  final int index; // 1..4

  // Backing openHAB Item names (null when that role isn't mapped).
  final String? beginXItem;
  final String? beginYItem;
  final String? endXItem;
  final String? endYItem;
  final String? occupancyItem;
  final String? countItem;

  // Live values in millimetres.
  double beginX;
  double beginY;
  double endX;
  double endY;
  bool occupied;
  int count;

  // Allowed range for the corner Items (from openHAB stateDescription), used
  // to clamp edits. Falls back to device bounds when unknown.
  final double? minX;
  final double? maxX;
  final double? minY;
  final double? maxY;

  EpZone({
    required this.index,
    this.beginXItem,
    this.beginYItem,
    this.endXItem,
    this.endYItem,
    this.occupancyItem,
    this.countItem,
    this.beginX = 0,
    this.beginY = 0,
    this.endX = 0,
    this.endY = 0,
    this.occupied = false,
    this.count = 0,
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
  });

  /// A zone is editable only when all four corner Items are mapped.
  bool get isComplete =>
      beginXItem != null &&
      beginYItem != null &&
      endXItem != null &&
      endYItem != null;

  /// A zone is "configured" on the device when it has a non-zero area.
  bool get isActive => (endX - beginX).abs() > 1 && (endY - beginY).abs() > 1;

  double get left => beginX < endX ? beginX : endX;
  double get right => beginX < endX ? endX : beginX;
  double get top => beginY < endY ? beginY : endY;
  double get bottom => beginY < endY ? endY : beginY;

  /// True when (px, py) in mm lies inside this zone's rectangle.
  bool contains(double px, double py) =>
      px >= left && px <= right && py >= top && py <= bottom;

  /// Item name + new value for each corner, for committing an edit.
  Map<String, double> cornerCommands() {
    final m = <String, double>{};
    if (beginXItem != null) m[beginXItem!] = beginX;
    if (beginYItem != null) m[beginYItem!] = beginY;
    if (endXItem != null) m[endXItem!] = endX;
    if (endYItem != null) m[endYItem!] = endY;
    return m;
  }
}
