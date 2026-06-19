import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ep_device.dart';
import '../models/ep_target.dart';
import '../models/ep_zone.dart';
import '../services/device_manager.dart';
import '../services/yaml_export.dart';
import 'widgets/coord_transform.dart';
import 'widgets/radar_painter.dart';

enum _Drag { none, move, corner }

/// Which units to show in the coordinate readouts.
enum _Units { mm, inch, both }

/// The core screen: live radar with editable zones. Drag a corner handle to
/// resize, drag a zone body to move; edits commit to openHAB on release.
class ZoneEditorPage extends StatefulWidget {
  final DeviceManager manager;
  final String deviceId;
  const ZoneEditorPage({
    super.key,
    required this.manager,
    required this.deviceId,
  });

  @override
  State<ZoneEditorPage> createState() => _ZoneEditorPageState();
}

class _ZoneEditorPageState extends State<ZoneEditorPage> {
  int? _selected;
  _Drag _drag = _Drag.none;
  int _cornerId = 0;
  Offset _lastWorld = Offset.zero;
  bool _linking = false;
  _Units _units = _Units.both;

  /// Zone indices with local edits not yet written to the device.
  final Set<int> _dirty = {};

  // --- unit formatting (mm is the source of truth) ---
  String _inch(double mm) => (mm / 25.4).toStringAsFixed(1);
  String _pairMm(double x, double y) => '(${x.round()}, ${y.round()})';
  String _pairIn(double x, double y) => '(${_inch(x)}, ${_inch(y)})';
  String _unitsLabel() => switch (_units) {
    _Units.mm => 'mm',
    _Units.inch => 'in',
    _Units.both => 'mm+in',
  };

  String _zoneReadout(EpZone z) {
    final inside = z.count > 0 ? '    ${z.count} inside' : '';
    final mm = '${_pairMm(z.left, z.top)} to ${_pairMm(z.right, z.bottom)} mm';
    final inch =
        '${_pairIn(z.left, z.top)} to ${_pairIn(z.right, z.bottom)} in';
    final body = switch (_units) {
      _Units.mm => mm,
      _Units.inch => inch,
      _Units.both => '$mm  /  $inch',
    };
    return 'Z${z.index}:  $body$inside';
  }

  String _targetReadout(EpTarget t) => switch (_units) {
    _Units.mm => 'T${t.index} ${_pairMm(t.x, t.y)} mm',
    _Units.inch => 'T${t.index} ${_pairIn(t.x, t.y)} in',
    _Units.both =>
      'T${t.index} ${_pairMm(t.x, t.y)} mm / ${_pairIn(t.x, t.y)} in',
  };

  DeviceManager get m => widget.manager;

  EpZone? _zone(EpDevice d, int? i) {
    if (i == null) return null;
    for (final z in d.zones) {
      if (z.index == i) return z;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final device = m.deviceById(widget.deviceId);
        if (device == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.deviceId)),
            body: const Center(child: Text('Device no longer available')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(device.label),
                if (device.host != null)
                  Text(
                    device.host!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
              ],
            ),
            actions: [
              _liveBadge(),
              Tooltip(
                message:
                    'Units & grid — switch mm/metres, inches/feet, or both',
                child: TextButton(
                  onPressed: () => setState(
                    () => _units = _Units.values[(_units.index + 1) % 3],
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(_unitsLabel()),
                ),
              ),
              IconButton(
                tooltip: 'Export zones to YAML',
                onPressed: () => _exportYaml(device),
                icon: const Icon(Icons.code),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: m.demo ? null : m.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              _missingBanner(device),
              Expanded(child: _radar(device)),
              _controls(device),
            ],
          ),
        );
      },
    );
  }

  Widget _liveBadge() {
    final (label, color) = m.demo
        ? ('DEMO', Colors.purpleAccent)
        : m.directMode
        ? ('ESP', Colors.cyanAccent)
        : m.usingSse
        ? ('LIVE', Colors.greenAccent)
        : ('POLL', Colors.orangeAccent);
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _missingBanner(EpDevice device) {
    final n = m.missingLinkCount(device.id);
    if (n == 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.18),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.link_off, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$n channel(s) have no linked openHAB Item, so zones can\'t be '
              'read or edited yet. Create & link them to continue.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            icon: _linking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link, size: 18),
            label: const Text('Create & link'),
            onPressed: _linking ? null : () => _createLinks(device),
          ),
        ],
      ),
    );
  }

  Future<void> _createLinks(EpDevice device) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _linking = true);
    final n = await m.createMissingLinks(device.id);
    if (!mounted) return;
    setState(() => _linking = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n > 0
              ? 'Created and linked $n Item(s). Values will populate shortly.'
              : 'No Items created${m.lastCommitError != null ? ": ${m.lastCommitError}" : "."}',
        ),
      ),
    );
  }

  Widget _radar(EpDevice device) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // Expand the view to include any zone/target that falls outside the
        // device's nominal bounds, so nothing is clipped at the edges.
        var minX = device.minX, maxX = device.maxX;
        var minY = device.minY, maxY = device.maxY;
        for (final z in device.zones.where((z) => z.isComplete)) {
          minX = math.min(minX, z.left);
          maxX = math.max(maxX, z.right);
          minY = math.min(minY, z.top);
          maxY = math.max(maxY, z.bottom);
        }
        for (final tg in device.targets.where((tg) => tg.present)) {
          minX = math.min(minX, tg.x);
          maxX = math.max(maxX, tg.x);
          maxY = math.max(maxY, tg.y);
        }
        final t = CoordTransform(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          size: size,
        );
        return GestureDetector(
          onTapDown: (d) => _onTap(device, d.localPosition, t),
          onPanStart: (d) => _onPanStart(device, d.localPosition, t),
          onPanUpdate: (d) => _onPanUpdate(device, d.localPosition, t),
          onPanEnd: (_) => _onPanEnd(device),
          child: CustomPaint(
            size: size,
            painter: RadarPainter(
              device: device,
              t: t,
              selectedZone: _selected,
              imperial: _units == _Units.inch,
            ),
          ),
        );
      },
    );
  }

  void _onTap(EpDevice device, Offset local, CoordTransform t) {
    final w = t.toWorld(local);
    for (final z in device.zones.reversed) {
      if (z.isComplete && z.isActive && z.contains(w.dx, w.dy)) {
        setState(() => _selected = z.index);
        return;
      }
    }
  }

  void _onPanStart(EpDevice device, Offset local, CoordTransform t) {
    final w = t.toWorld(local);
    final sel = _zone(device, _selected);
    if (sel != null && sel.isComplete) {
      final corners = zoneCorners(sel);
      for (var i = 0; i < corners.length; i++) {
        final cp = t.toCanvas(corners[i].dx, corners[i].dy);
        if ((cp - local).distance <= RadarPainter.handleRadius * 2.4) {
          _drag = _Drag.corner;
          _cornerId = i;
          _lastWorld = w;
          return;
        }
      }
      if (sel.isActive && sel.contains(w.dx, w.dy)) {
        _drag = _Drag.move;
        _lastWorld = w;
        return;
      }
    }
    for (final z in device.zones.reversed) {
      if (z.isComplete && z.isActive && z.contains(w.dx, w.dy)) {
        setState(() => _selected = z.index);
        _drag = _Drag.move;
        _lastWorld = w;
        return;
      }
    }
    _drag = _Drag.none;
  }

  void _onPanUpdate(EpDevice device, Offset local, CoordTransform t) {
    final z = _zone(device, _selected);
    if (z == null || _drag == _Drag.none) return;
    final w = t.toWorld(local);
    setState(() {
      if (_drag == _Drag.corner) {
        _setCorner(device, z, _cornerId, w.dx, w.dy);
      } else {
        _translate(device, z, w.dx - _lastWorld.dx, w.dy - _lastWorld.dy);
        _lastWorld = w;
      }
      _dirty.add(z.index); // local edit; not sent until Save
    });
  }

  // Edits stay local; nothing is written to the device until Save.
  void _onPanEnd(EpDevice device) {
    final z = _zone(device, _selected);
    if (z != null && _drag != _Drag.none) {
      setState(() => _normalize(z));
    }
    _drag = _Drag.none;
  }

  // --- zone geometry helpers (clamped to device/zone bounds) ---

  double _clampX(EpDevice d, EpZone z, double v) =>
      v.clamp(z.minX ?? d.minX, z.maxX ?? d.maxX).toDouble();
  double _clampY(EpDevice d, EpZone z, double v) =>
      v.clamp(z.minY ?? d.minY, z.maxY ?? d.maxY).toDouble();

  void _setCorner(EpDevice d, EpZone z, int id, double x, double y) {
    x = _clampX(d, z, x);
    y = _clampY(d, z, y);
    switch (id) {
      case 0:
        z.beginX = x;
        z.beginY = y;
      case 1:
        z.endX = x;
        z.beginY = y;
      case 2:
        z.beginX = x;
        z.endY = y;
      case 3:
        z.endX = x;
        z.endY = y;
    }
  }

  void _translate(EpDevice d, EpZone z, double dx, double dy) {
    final minX = z.minX ?? d.minX, maxX = z.maxX ?? d.maxX;
    final minY = z.minY ?? d.minY, maxY = z.maxY ?? d.maxY;
    // Clamp the delta so the whole rectangle stays in bounds.
    dx = dx.clamp(minX - z.left, maxX - z.right);
    dy = dy.clamp(minY - z.top, maxY - z.bottom);
    z.beginX += dx;
    z.endX += dx;
    z.beginY += dy;
    z.endY += dy;
  }

  void _normalize(EpZone z) {
    if (z.beginX > z.endX) {
      final t = z.beginX;
      z.beginX = z.endX;
      z.endX = t;
    }
    if (z.beginY > z.endY) {
      final t = z.beginY;
      z.beginY = z.endY;
      z.endY = t;
    }
    z.beginX = z.beginX.roundToDouble();
    z.beginY = z.beginY.roundToDouble();
    z.endX = z.endX.roundToDouble();
    z.endY = z.endY.roundToDouble();
  }

  // --- controls ---

  Widget _controls(EpDevice device) {
    final sel = _zone(device, _selected);
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final z in device.zones)
                  ChoiceChip(
                    label: Text(
                      'Z${z.index}'
                      '${_dirty.contains(z.index) ? " *" : ""}'
                      '${z.occupied ? " •" : ""}',
                    ),
                    selected: _selected == z.index,
                    onSelected: z.isComplete
                        ? (_) => setState(() => _selected = z.index)
                        : null,
                    avatar: Icon(
                      z.isActive ? Icons.crop_square : Icons.crop_din,
                      size: 16,
                      color: z.occupied ? Colors.green : null,
                    ),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _newZone(device),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New zone'),
                ),
                if (sel != null && sel.isComplete)
                  FilledButton.icon(
                    onPressed: (m.demo || !_dirty.contains(sel.index))
                        ? null
                        : () => _saveZone(sel),
                    icon: const Icon(Icons.save, size: 18),
                    label: Text('Save Z${sel.index}'),
                  ),
                if (_dirty.length > 1)
                  OutlinedButton.icon(
                    onPressed: m.demo ? null : () => _saveAll(device),
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: Text('Save all (${_dirty.length})'),
                  ),
                if (sel != null && sel.isActive)
                  TextButton.icon(
                    onPressed: () => _clearZone(device, sel),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('Clear Z${sel.index}'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              sel == null
                  ? 'Select a zone, or tap "New zone". Drag to move/resize — edits stay local until you tap Save.'
                  : _zoneReadout(sel),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_dirty.isNotEmpty)
              Text(
                'Unsaved: ${(_dirty.toList()..sort()).map((i) => "Z$i").join(", ")}'
                ' — tap Save to write to the device.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
              ),
            _targetsLine(device),
          ],
        ),
      ),
    );
  }

  Widget _targetsLine(EpDevice device) {
    final present = device.targets.where((t) => t.present).toList();
    if (present.isEmpty) {
      return Text(
        'No targets detected',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Text(
      present.map(_targetReadout).join('   '),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: const Color(0xFFFF8A80)),
    );
  }

  Future<void> _newZone(EpDevice device) async {
    final editable = device.zones.where((z) => z.isComplete).toList();
    if (editable.isEmpty) {
      _snack(
        m.missingLinkCount(device.id) > 0
            ? 'Link Items first — tap "Create & link" above.'
            : 'No editable zones found for this device.',
      );
      return;
    }
    final z = editable.firstWhere(
      (z) => !z.isActive,
      orElse: () => EpZone(index: -1),
    );
    if (z.index == -1) {
      _snack('All ${editable.length} zones are in use. Clear one to reuse it.');
      return;
    }
    // Seed a 1.5 m box centred laterally, ~1 m in front of the sensor.
    final cx = ((device.minX + device.maxX) / 2);
    final cy = ((device.minY + device.maxY) / 2);
    setState(() {
      z.beginX = (cx - 750).clamp(device.minX, device.maxX).toDouble();
      z.endX = (cx + 750).clamp(device.minX, device.maxX).toDouble();
      z.beginY = (cy - 750).clamp(device.minY, device.maxY).toDouble();
      z.endY = (cy + 750).clamp(device.minY, device.maxY).toDouble();
      _selected = z.index;
      _normalize(z);
      _dirty.add(z.index);
    });
    _snack('Zone ${z.index} added — drag to position, then Save.');
  }

  Future<void> _exportYaml(EpDevice device) async {
    final yaml = buildZonesYaml(device);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zones → YAML'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              yaml,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: yaml));
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('YAML copied to clipboard');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveZone(EpZone z) async {
    setState(() => _normalize(z));
    await m.commitZone(z);
    if (!mounted) return;
    final ok = m.lastCommitError == null;
    if (ok) setState(() => _dirty.remove(z.index));
    final coords = _units == _Units.inch
        ? '${_pairIn(z.left, z.top)} to ${_pairIn(z.right, z.bottom)} in'
        : '${_pairMm(z.left, z.top)} to ${_pairMm(z.right, z.bottom)} mm';
    _snack(
      ok
          ? 'Saved Z${z.index} to device  $coords'
          : 'Save failed: ${m.lastCommitError}',
    );
  }

  Future<void> _saveAll(EpDevice device) async {
    for (final idx in _dirty.toList()) {
      final z = _zone(device, idx);
      if (z == null || !z.isComplete) continue;
      setState(() => _normalize(z));
      await m.commitZone(z);
      if (!mounted) return;
      if (m.lastCommitError != null) {
        _snack('Save failed on Z$idx: ${m.lastCommitError}');
        return;
      }
      setState(() => _dirty.remove(idx));
    }
    if (mounted) _snack('Saved all zones to device.');
  }

  // Local clear; takes effect on the device when saved.
  void _clearZone(EpDevice device, EpZone z) {
    setState(() {
      z.beginX = 0;
      z.beginY = 0;
      z.endX = 0;
      z.endY = 0;
      _dirty.add(z.index);
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// The four editable corners of a zone in world mm (mirrors RadarPainter).
List<Offset> zoneCorners(EpZone z) => [
  Offset(z.beginX, z.beginY),
  Offset(z.endX, z.beginY),
  Offset(z.beginX, z.endY),
  Offset(z.endX, z.endY),
];
