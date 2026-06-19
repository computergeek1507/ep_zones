import '../models/ep_device.dart';

/// Builds an ESPHome-friendly YAML snapshot of a device's zones.
///
/// Emits a `substitutions:` block (zone_N_begin_x, …) plus a readable comment
/// header, so the coordinates can be pasted into an ESPHome config or kept as a
/// reference. Pure — pass [now] in tests for a stable timestamp.
String buildZonesYaml(EpDevice d, {DateTime? now}) {
  final ts = (now ?? DateTime.now()).toIso8601String();
  final sb = StringBuffer();
  sb.writeln('# Everything Presence Lite — zone export');
  sb.writeln('# Device: ${d.label}${d.host != null ? " (${d.host})" : ""}');
  sb.writeln('# Generated: $ts');
  sb.writeln('# Coordinates are millimetres in the LD2450 sensor plane');
  sb.writeln('# (X lateral, Y away from sensor).');
  sb.writeln('#');
  for (final z in d.zones) {
    if (!z.isComplete) continue;
    sb.writeln('# Zone ${z.index}: '
        'X ${z.left.round()}…${z.right.round()}, '
        'Y ${z.top.round()}…${z.bottom.round()}'
        '${z.isActive ? "" : "  (inactive)"}');
  }
  sb.writeln('substitutions:');
  for (final z in d.zones) {
    if (!z.isComplete) continue;
    sb.writeln('  zone_${z.index}_begin_x: "${z.beginX.round()}"');
    sb.writeln('  zone_${z.index}_begin_y: "${z.beginY.round()}"');
    sb.writeln('  zone_${z.index}_end_x: "${z.endX.round()}"');
    sb.writeln('  zone_${z.index}_end_y: "${z.endY.round()}"');
  }
  return sb.toString();
}
