/// A live tracked target from the LD2450 radar (up to 3 per device).
///
/// Coordinates are millimetres in the sensor plane: X is lateral (negative =
/// left, positive = right), Y is distance away from the sensor (>= 0).
class EpTarget {
  final int index; // 1..3

  /// openHAB Item names backing this target (null when not mapped).
  final String? xItem;
  final String? yItem;
  final String? activeItem;

  // Live values, updated in place from SSE/poll.
  double x;
  double y;
  bool active;

  EpTarget({
    required this.index,
    this.xItem,
    this.yItem,
    this.activeItem,
    this.x = 0,
    this.y = 0,
    this.active = false,
  });

  /// A target counts as present when explicitly active, or — when no active
  /// Item is mapped — when it reports a non-origin position.
  bool get present => activeItem != null ? active : (x != 0 || y != 0);
}
