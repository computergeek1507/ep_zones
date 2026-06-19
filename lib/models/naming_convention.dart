/// Maps openHAB Item names to Everything Presence Lite roles using a
/// configurable naming convention.
///
/// Default pattern: `EPL_<Device>_<Role>` with `_` as the separator, e.g.
///   EPL_Office_Target1_X        -> device "Office", target 1, X coordinate
///   EPL_Office_Zone1_BeginX     -> device "Office", zone 1, begin X
///   EPL_Office_Zone2_Occupancy  -> device "Office", zone 2, occupancy
///   EPL_Office_MaxDistance      -> device "Office", config max distance
///
/// All parsing here is pure (no I/O) so it can be unit tested directly.
library;

/// The distinct roles an Item can play for an EP Lite device.
enum RoleKind {
  targetX,
  targetY,
  targetActive,
  zoneBeginX,
  zoneBeginY,
  zoneEndX,
  zoneEndY,
  zoneOccupancy,
  zoneCount,
  maxDistance,
  installationAngle,
}

/// Whether a role belongs to a target, a zone, or the device itself.
extension RoleKindInfo on RoleKind {
  bool get isTarget =>
      this == RoleKind.targetX ||
      this == RoleKind.targetY ||
      this == RoleKind.targetActive;

  bool get isZone =>
      this == RoleKind.zoneBeginX ||
      this == RoleKind.zoneBeginY ||
      this == RoleKind.zoneEndX ||
      this == RoleKind.zoneEndY ||
      this == RoleKind.zoneOccupancy ||
      this == RoleKind.zoneCount;

  bool get isConfig =>
      this == RoleKind.maxDistance || this == RoleKind.installationAngle;
}

/// The result of parsing a single Item name.
class ItemRole {
  final String deviceId;
  final RoleKind kind;

  /// Target number (1..3) or zone number (1..4). Null for device config roles.
  final int? index;

  const ItemRole(this.deviceId, this.kind, this.index);

  @override
  String toString() => 'ItemRole($deviceId, $kind, $index)';

  @override
  bool operator ==(Object other) =>
      other is ItemRole &&
      other.deviceId == deviceId &&
      other.kind == kind &&
      other.index == index;

  @override
  int get hashCode => Object.hash(deviceId, kind, index);
}

/// Internal description of one role's suffix (the part after the device name).
/// [tokens] are joined by the convention separator; `%i` marks the numeric
/// index group.
class _RoleSpec {
  final RoleKind kind;
  final List<String> tokens;
  const _RoleSpec(this.kind, this.tokens);
}

const List<_RoleSpec> _roleSpecs = [
  _RoleSpec(RoleKind.targetX, ['Target%i', 'X']),
  _RoleSpec(RoleKind.targetY, ['Target%i', 'Y']),
  _RoleSpec(RoleKind.targetActive, ['Target%i', 'Active']),
  _RoleSpec(RoleKind.zoneBeginX, ['Zone%i', 'BeginX']),
  _RoleSpec(RoleKind.zoneBeginY, ['Zone%i', 'BeginY']),
  _RoleSpec(RoleKind.zoneEndX, ['Zone%i', 'EndX']),
  _RoleSpec(RoleKind.zoneEndY, ['Zone%i', 'EndY']),
  _RoleSpec(RoleKind.zoneOccupancy, ['Zone%i', 'Occupancy']),
  _RoleSpec(RoleKind.zoneCount, ['Zone%i', 'Count']),
  _RoleSpec(RoleKind.maxDistance, ['MaxDistance']),
  _RoleSpec(RoleKind.installationAngle, ['InstallationAngle']),
];

class NamingConvention {
  /// Leading marker shared by every EP Lite Item (e.g. `EPL`).
  final String prefix;

  /// Separator between the prefix, device id, and role tokens (e.g. `_`).
  final String separator;

  const NamingConvention({this.prefix = 'EPL', this.separator = '_'});

  static const NamingConvention defaults = NamingConvention();

  NamingConvention copyWith({String? prefix, String? separator}) =>
      NamingConvention(
        prefix: prefix ?? this.prefix,
        separator: separator ?? this.separator,
      );

  /// Pre-built matchers, one per role, anchored to the full Item name.
  /// `dev` captures the device id, `idx` (when present) the numeric index.
  List<MapEntry<RoleKind, RegExp>> _matchers() {
    final sep = RegExp.escape(separator);
    final pre = RegExp.escape(prefix);
    return _roleSpecs.map((spec) {
      final core = spec.tokens
          .map((t) => t == 'Target%i'
              ? 'Target(?<idx>\\d+)'
              : t == 'Zone%i'
                  ? 'Zone(?<idx>\\d+)'
                  : RegExp.escape(t))
          .join(sep);
      final re = RegExp('^$pre$sep(?<dev>.+)$sep$core\$');
      return MapEntry(spec.kind, re);
    }).toList();
  }

  /// Parses one Item name, or returns null if it does not match the convention.
  ItemRole? parse(String itemName) {
    for (final entry in _matchers()) {
      final m = entry.value.firstMatch(itemName);
      if (m == null) continue;
      final dev = m.namedGroup('dev');
      if (dev == null || dev.isEmpty) continue;
      int? idx;
      // Only index-bearing roles declare an `idx` group.
      try {
        idx = int.tryParse(m.namedGroup('idx') ?? '');
      } on ArgumentError {
        idx = null; // no such group in this pattern
      }
      return ItemRole(dev, entry.key, idx);
    }
    return null;
  }

  /// Example Item name for the given role, used in setup help / previews.
  String example(String device, RoleKind kind, {int index = 1}) {
    final spec = _roleSpecs.firstWhere((s) => s.kind == kind);
    final core = spec.tokens
        .map((t) => t.replaceFirst('%i', '$index'))
        .join(separator);
    return [prefix, device, core].join(separator);
  }

  Map<String, String> toJson() => {'prefix': prefix, 'separator': separator};

  factory NamingConvention.fromJson(Map<String, dynamic> j) => NamingConvention(
        prefix: (j['prefix'] as String?) ?? 'EPL',
        separator: (j['separator'] as String?) ?? '_',
      );
}
