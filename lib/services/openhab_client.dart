import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/oh_item.dart';
import '../models/oh_thing.dart';
import 'sse_transport.dart';

/// A live state update for one Item, derived from an openHAB SSE event.
class OhStateEvent {
  final String itemName;
  final String state;
  const OhStateEvent(this.itemName, this.state);
}

/// Thin openHAB REST + SSE client. Modeled on fpp_view's FppApi: a small
/// http.Client wrapper with a configurable timeout and manual JSON handling.
class OpenhabClient {
  final String baseUrl; // normalized, no trailing slash
  final String token;
  final Duration timeout;
  final http.Client _http;
  SseConnection? _sseConn;

  OpenhabClient({
    required this.baseUrl,
    String token = '',
    this.timeout = const Duration(seconds: 8),
    http.Client? httpClient,
  }) : token = _normToken(token),
       _http = httpClient ?? http.Client();

  /// Trims whitespace and strips an accidental "Bearer " prefix.
  static String _normToken(String t) {
    t = t.trim();
    if (t.toLowerCase().startsWith('bearer ')) t = t.substring(7).trim();
    return t;
  }

  Map<String, String> get _authHeaders =>
      token.isEmpty ? {} : {'Authorization': 'Bearer $token'};

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Throws a helpful message on auth/other failures; returns on 200.
  void _ensureOk(http.Response resp, String what) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw http.ClientException(
        '$what: HTTP ${resp.statusCode} Unauthorized. openHAB needs an '
        'admin API token (especially for Things). In openHAB: your profile → '
        'Create API Token, then paste it here.',
      );
    }
    if (resp.statusCode != 200) {
      throw http.ClientException('$what: HTTP ${resp.statusCode}');
    }
  }

  /// Fetches all Items (name, type, state, stateDescription).
  Future<List<OhItem>> listItems() async {
    final resp = await _http
        .get(_uri('/rest/items?recursive=false'), headers: _authHeaders)
        .timeout(timeout);
    _ensureOk(resp, 'GET /rest/items');
    final body = jsonDecode(resp.body);
    if (body is! List) {
      throw const FormatException('Unexpected /rest/items response');
    }
    return body
        .whereType<Map<String, dynamic>>()
        .map(OhItem.fromJson)
        .toList(growable: false);
  }

  Future<OhItem> getItem(String name) async {
    final resp = await _http
        .get(
          _uri('/rest/items/${Uri.encodeComponent(name)}'),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw http.ClientException('GET item $name failed: ${resp.statusCode}');
    }
    return OhItem.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Sends a command to an Item (used to write zone corner coordinates).
  Future<void> sendCommand(String name, double value) async {
    final resp = await _http
        .post(
          _uri('/rest/items/${Uri.encodeComponent(name)}'),
          headers: {..._authHeaders, 'Content-Type': 'text/plain'},
          body: formatCommandValue(value),
        )
        .timeout(timeout);
    if (resp.statusCode != 200 &&
        resp.statusCode != 201 &&
        resp.statusCode != 202) {
      throw http.ClientException(
        'Command to $name failed: HTTP ${resp.statusCode}',
      );
    }
  }

  /// Lists all Things (with their channels + linkedItems).
  Future<List<OhThing>> listThings() async {
    final resp = await _http
        .get(_uri('/rest/things'), headers: _authHeaders)
        .timeout(timeout);
    _ensureOk(resp, 'GET /rest/things');
    final body = jsonDecode(resp.body);
    if (body is! List) {
      throw const FormatException('Unexpected /rest/things response');
    }
    return body
        .whereType<Map<String, dynamic>>()
        .map(OhThing.fromJson)
        .toList(growable: false);
  }

  /// Creates an Item (used to back an unlinked channel).
  Future<void> createItem(String name, String type, {String? label}) async {
    final payload = <String, dynamic>{'type': type, 'name': name};
    if (label != null) payload['label'] = label;
    final resp = await _http
        .put(
          _uri('/rest/items/${Uri.encodeComponent(name)}'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw http.ClientException(
        'Create item $name failed: HTTP ${resp.statusCode}',
      );
    }
  }

  /// Links an Item to a channel so its state is readable/commandable via REST.
  Future<void> linkItemToChannel(String itemName, String channelUid) async {
    final resp = await _http
        .put(
          _uri(
            '/rest/links/${Uri.encodeComponent(itemName)}/'
            '${Uri.encodeComponent(channelUid)}',
          ),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'itemName': itemName,
            'channelUID': channelUid,
            'configuration': <String, dynamic>{},
          }),
        )
        .timeout(timeout);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw http.ClientException(
        'Link $itemName→$channelUid failed: HTTP ${resp.statusCode}',
      );
    }
  }

  /// Quick connectivity/auth check. Throws on failure.
  Future<void> testConnection() async {
    final resp = await _http
        .get(
          _uri('/rest/items?fields=name&recursive=false'),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw http.ClientException(
        'Unauthorized (HTTP ${resp.statusCode}) — '
        'check the API token',
      );
    }
    if (resp.statusCode != 200) {
      throw http.ClientException('openHAB returned HTTP ${resp.statusCode}');
    }
  }

  /// Opens the SSE state stream and yields parsed [OhStateEvent]s.
  Future<Stream<OhStateEvent>> openStateStream() async {
    final url =
        '$baseUrl/rest/events?topics='
        '${Uri.encodeQueryComponent('openhab/items/*/statechanged')}';
    final conn = await openSse(url, bearerToken: token);
    _sseConn = conn;
    return conn.dataEvents
        .map(parseOhEvent)
        .where((e) => e != null)
        .cast<OhStateEvent>()
        .transform(_closeOnCancel(conn));
  }

  /// Polling fallback: fetch current state of all Items as state events.
  Future<List<OhStateEvent>> pollStates() async {
    final resp = await _http
        .get(
          _uri('/rest/items?fields=name,state&recursive=false'),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw http.ClientException('poll failed: HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(
          (j) => OhStateEvent(
            j['name'] as String,
            (j['state'] as String?) ?? 'NULL',
          ),
        )
        .toList(growable: false);
  }

  void close() {
    _sseConn?.close();
    _sseConn = null;
    _http.close();
  }

  /// Ensures the underlying SSE connection is closed when the stream
  /// subscription is cancelled.
  StreamTransformer<OhStateEvent, OhStateEvent> _closeOnCancel(
    SseConnection conn,
  ) {
    return StreamTransformer.fromHandlers(
      handleDone: (sink) {
        conn.close();
        sink.close();
      },
    );
  }
}

/// Formats a numeric command, dropping a redundant ".0" for integral values
/// (zone coordinates are whole millimetres).
String formatCommandValue(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  return v.toString();
}

/// Parses one openHAB SSE `data:` payload into an [OhStateEvent].
///
/// The payload looks like:
/// {"topic":"openhab/items/Foo/statechanged",
///  "payload":"{\"type\":\"Decimal\",\"value\":\"123\"}",
///  "type":"ItemStateChangedEvent"}
OhStateEvent? parseOhEvent(String data) {
  try {
    final outer = jsonDecode(data);
    if (outer is! Map) return null;
    final topic = outer['topic'] as String?;
    if (topic == null) return null;
    final parts = topic.split('/');
    // openhab / items / <name> / statechanged
    final idx = parts.indexOf('items');
    if (idx < 0 || idx + 1 >= parts.length) return null;
    final name = parts[idx + 1];
    final payloadRaw = outer['payload'];
    if (payloadRaw is! String) return null;
    final payload = jsonDecode(payloadRaw);
    if (payload is! Map) return null;
    final value = payload['value'];
    if (value == null) return null;
    return OhStateEvent(name, value.toString());
  } catch (_) {
    return null;
  }
}
