import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ep_device.dart';
import '../models/ep_target.dart';
import '../models/ep_zone.dart';
import '../models/naming_convention.dart';
import 'channel_discovery.dart';
import 'openhab_client.dart' show formatCommandValue;
import 'sse_transport.dart';

/// A single entity state from an ESPHome web_server SSE event.
class EspEvent {
  /// Raw SSE identifier, e.g. `number-zone_1_begin_x` (legacy) or
  /// `number/Zone 1 Begin X` (newer firmware). Used as the routing key and to
  /// reconstruct the control URL.
  final String id;
  final String domain; // number / sensor / binary_sensor …
  final String key; // normalized object-id form, e.g. zone_1_begin_x
  final String state; // string state ("1000 mm", "ON", "123")
  const EspEvent(this.id, this.domain, this.key, this.state);
}

/// Splits an ESPHome web id into (domain, rawIdentifier). Handles both the
/// legacy `domain-object_id` and the newer `domain/Friendly Name` forms.
(String, String) splitEspId(String id) {
  final slash = id.indexOf('/');
  if (slash >= 0) return (id.substring(0, slash), id.substring(slash + 1));
  final dash = id.indexOf('-');
  if (dash >= 0) return (id.substring(0, dash), id.substring(dash + 1));
  return ('number', id);
}

/// Normalizes a raw identifier to the object-id form used for role matching:
/// lowercase with spaces/slashes/hyphens collapsed to underscores.
String espKey(String rawId) =>
    rawId.toLowerCase().replaceAll(RegExp(r'[ /\-]+'), '_');

/// Talks directly to an EP Lite device's ESPHome **web server** (HTTP),
/// bypassing openHAB. Requires `web_server:` enabled in the device's ESPHome
/// config. Reads come from the `/events` SSE stream; zone writes use
/// `POST /<domain>/<entity>/set?value=`.
class EsphomeWebClient {
  final String baseUrl; // http://<ip>[:port], no trailing slash
  final Duration timeout;
  final http.Client _http;
  SseConnection? _sseConn;

  EsphomeWebClient({
    required String host,
    this.timeout = const Duration(seconds: 8),
    http.Client? httpClient,
  }) : baseUrl = normalizeHost(host),
       _http = httpClient ?? http.Client();

  static String normalizeHost(String h) {
    h = h.trim();
    if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'http://$h';
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  Future<void> testConnection() async {
    http.Response resp;
    try {
      resp = await _http.get(Uri.parse(baseUrl)).timeout(timeout);
    } catch (e) {
      throw http.ClientException(
        'Could not reach $baseUrl. Check the IP, and that the device is on '
        'with web_server enabled in its ESPHome config. ($e)',
      );
    }
    if (resp.statusCode == 401) {
      throw http.ClientException(
        'ESPHome web server requires authentication (HTTP 401).',
      );
    }
    if (resp.statusCode != 200) {
      throw http.ClientException(
        'ESPHome web server returned HTTP ${resp.statusCode}. Is web_server '
        'enabled on the device?',
      );
    }
  }

  /// Sets a `number` entity (zone coordinate). [id] is the entity's raw SSE id;
  /// the web server matches by the entity *name*, so [id] should be the
  /// name-based form (`number/Zone 1 Begin X`) — see [parseEspEvent].
  ///
  /// Uses a fresh connection per call and retries transient "connection closed"
  /// errors, because the ESP32 AsyncWebServer has few connection slots and
  /// readily drops reused/extra sockets.
  Future<void> setNumber(String id, double value) async {
    final (domain, rawId) = splitEspId(id);
    final v = formatCommandValue(value);
    final url = Uri.parse(
      '$baseUrl/$domain/${Uri.encodeComponent(rawId)}/set?value=$v',
    );
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      final client = http.Client();
      try {
        final resp = await client.post(url).timeout(timeout);
        if (resp.statusCode == 200) return;
        if (resp.statusCode == 404) {
          throw http.ClientException(
            'Set "$rawId" failed: HTTP 404 (no entity by that name). ($url)',
          );
        }
        lastErr = http.ClientException(
          'Set "$rawId" failed: HTTP ${resp.statusCode}. ($url)',
        );
      } on http.ClientException catch (e) {
        if (e.message.contains('404')) rethrow;
        lastErr = e; // e.g. "Connection closed before full header" → retry
      } catch (e) {
        lastErr = e;
      } finally {
        client.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw http.ClientException('$lastErr');
  }

  /// Collects a one-shot snapshot of entity states by briefly listening to the
  /// `/events` stream (the web server emits the full state set on connect).
  Future<List<EspEvent>> snapshot({
    Duration window = const Duration(milliseconds: 2500),
  }) async {
    final conn = await openSse('$baseUrl/events');
    final seen = <String, EspEvent>{};
    final sub = conn.dataEvents.listen((data) {
      final e = parseEspEvent(data);
      if (e != null) seen[e.id] = e;
    });
    await Future<void>.delayed(window);
    await sub.cancel();
    conn.close();
    return seen.values.toList(growable: false);
  }

  /// Continuous live state stream.
  Future<Stream<EspEvent>> openStateStream() async {
    final conn = await openSse('$baseUrl/events');
    _sseConn = conn;
    return conn.dataEvents
        .map(parseEspEvent)
        .where((e) => e != null)
        .cast<EspEvent>()
        .transform(
          StreamTransformer.fromHandlers(
            handleDone: (sink) {
              conn.close();
              sink.close();
            },
          ),
        );
  }

  void close() {
    _sseConn?.close();
    _sseConn = null;
    _http.close();
  }
}

/// Parses one ESPHome web_server SSE `data:` payload, tolerant of the legacy
/// (`number-zone_1_begin_x`) and newer (`number/Zone 1 Begin X`) id formats.
///
/// The web server matches control requests by entity *name*, so when both a
/// legacy `id` and a name-based identifier are present we keep the name-based
/// one (the `domain/Name` form) as the canonical id used for writes.
EspEvent? parseEspEvent(String data) {
  try {
    final j = jsonDecode(data);
    if (j is! Map) return null;
    final idA = j['id'] as String?;
    final idB = j['name_id'] as String?;
    // Prefer whichever is name-based (contains '/').
    final canonical = [
      idA,
      idB,
    ].firstWhere((c) => c != null && c.contains('/'), orElse: () => idA ?? idB);
    if (canonical == null) return null;
    final (domain, rawId) = splitEspId(canonical);
    final state = (j['state'] ?? j['value'])?.toString() ?? '';
    return EspEvent(canonical, domain, espKey(rawId), state);
  } catch (_) {
    return null;
  }
}

/// Builds one [EpDevice] from an ESPHome entity snapshot, keyed by [host].
/// The raw SSE id is used as each role's item key (for live routing and the
/// control URL). Returns null if no EP Lite roles were found.
EpDevice? buildEsphomeDevice(String host, List<EspEvent> entities) {
  final targets = <int, Map<RoleKind, String>>{};
  final zones = <int, Map<RoleKind, String>>{};
  String? maxDistance, installationAngle;
  var matched = false;

  for (final e in entities) {
    final role = channelRole(host, e.key);
    if (role == null) continue;
    matched = true;
    if (role.kind.isTarget) {
      (targets[role.index!] ??= {})[role.kind] = e.id;
    } else if (role.kind.isZone) {
      (zones[role.index!] ??= {})[role.kind] = e.id;
    } else if (role.kind == RoleKind.maxDistance) {
      maxDistance = e.id;
    } else if (role.kind == RoleKind.installationAngle) {
      installationAngle = e.id;
    }
  }
  if (!matched) return null;

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

  final device = EpDevice(
    id: host,
    label: host,
    host: host,
    targets: targetList,
    zones: zoneList,
    maxDistanceItem: maxDistance,
    installationAngleItem: installationAngle,
  );
  // Seed current values (item keys are the raw SSE ids).
  for (final e in entities) {
    device.applyState(e.id, e.state);
  }
  return device;
}
