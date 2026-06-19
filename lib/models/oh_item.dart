/// A single openHAB Item as returned by `GET /rest/items`.
///
/// We only keep the fields the app needs: identity, current state, and the
/// numeric range/step/unit from `stateDescription` (used to size the radar
/// canvas and clamp zone edits).
library;

class OhItem {
  final String name;
  final String type; // e.g. "Number", "Number:Length", "Switch", "Contact"
  final String? label;
  final String state; // raw state string, may include a unit or be NULL/UNDEF
  final double? min;
  final double? max;
  final double? step;
  final String? pattern;

  const OhItem({
    required this.name,
    required this.type,
    required this.state,
    this.label,
    this.min,
    this.max,
    this.step,
    this.pattern,
  });

  /// Numeric value of [state], tolerant of an appended unit ("1234 mm") and of
  /// non-numeric states ("NULL", "UNDEF", "ON"). Returns null when not numeric.
  double? get numericState => parseNumber(state);

  /// True when the state reads as "on"/"open"/true (occupancy & switches).
  bool get boolState {
    final s = state.trim().toUpperCase();
    return s == 'ON' || s == 'OPEN' || s == 'TRUE' || s == '1';
  }

  bool get hasNumericState => numericState != null;

  factory OhItem.fromJson(Map<String, dynamic> j) {
    final sd = j['stateDescription'];
    final desc = sd is Map<String, dynamic> ? sd : const <String, dynamic>{};
    return OhItem(
      name: j['name'] as String,
      type: (j['type'] as String?) ?? 'Unknown',
      label: j['label'] as String?,
      state: (j['state'] as String?) ?? 'NULL',
      min: _toDouble(desc['minimum']),
      max: _toDouble(desc['maximum']),
      step: _toDouble(desc['step']),
      pattern: desc['pattern'] as String?,
    );
  }

  /// Returns a copy with a new [state] (used to apply live SSE updates).
  OhItem withState(String newState) => OhItem(
    name: name,
    type: type,
    label: label,
    state: newState,
    min: min,
    max: max,
    step: step,
    pattern: pattern,
  );

  /// Extracts the leading number from an openHAB state string, ignoring any
  /// trailing unit. Returns null for NULL/UNDEF/non-numeric states.
  static double? parseNumber(String? s) {
    if (s == null) return null;
    final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s.trim());
    if (m == null) return null;
    return double.tryParse(m.group(0)!);
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
