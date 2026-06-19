import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ep_device.dart';
import '../models/ep_zone.dart';
import '../models/oh_thing.dart';
import 'channel_discovery.dart';
import 'demo_source.dart';
import 'device_discovery.dart';
import 'esphome_web_client.dart';
import 'openhab_client.dart';
import 'settings_store.dart';
import 'sse_transport.dart';

/// Central state holder. Loads devices from openHAB, keeps their values live
/// (SSE with a polling fallback), and commits zone edits. ChangeNotifier +
/// manual subscription lifecycle, matching fpp_view's DeviceManager.
class DeviceManager extends ChangeNotifier {
  final SettingsStore _store;
  Settings settings;

  List<EpDevice> devices = [];
  bool connecting = false;
  bool connected = false;
  bool demo = false;
  bool usingSse = false;
  String? error;
  String? lastCommitError;

  OpenhabClient? _client;
  EsphomeWebClient? _esp;
  StreamSubscription<EspEvent>? _espSub;
  List<OhThing> _things = [];
  StreamSubscription<OhStateEvent>? _sse;
  Timer? _pollTimer;
  DemoSource? _demo;
  final Map<String, EpDevice> _itemIndex = {};

  DeviceManager(this._store, this.settings);

  static Future<DeviceManager> create() async {
    final store = SettingsStore();
    final s = await store.load();
    return DeviceManager(store, s);
  }

  Future<void> saveSettings(Settings s) async {
    settings = s;
    await _store.save(s);
    notifyListeners();
  }

  /// One-shot connectivity/auth probe with a throwaway client. Probes the
  /// endpoint the chosen discovery mode actually relies on, so an admin-token
  /// (Things) 401 is caught here rather than at Connect.
  Future<void> testConnection(Settings s) async {
    if (s.discoveryMode == DiscoveryMode.directEsphome) {
      final esp = EsphomeWebClient(host: s.deviceHost);
      try {
        await esp.testConnection();
      } finally {
        esp.close();
      }
      return;
    }
    final c = OpenhabClient(baseUrl: s.normalizedBaseUrl, token: s.token);
    try {
      if (s.discoveryMode == DiscoveryMode.thing) {
        final things = await c.listThings();
        final esphome = things.where((t) => t.isEsphome).length;
        if (esphome == 0) {
          throw const FormatException(
              'Connected, but found no ESPHome Things. Is the device added '
              'via the ESPHome binding?');
        }
      } else {
        await c.testConnection();
      }
    } finally {
      c.close();
    }
  }

  Future<void> connect() async {
    _teardownLive();
    if (!settings.isConfigured) {
      error = 'No openHAB URL configured';
      notifyListeners();
      return;
    }
    connecting = true;
    error = null;
    demo = false;
    notifyListeners();
    try {
      if (settings.discoveryMode == DiscoveryMode.directEsphome) {
        await _connectDirect();
      } else {
        _client = OpenhabClient(
            baseUrl: settings.normalizedBaseUrl, token: settings.token);
        await _loadDevices();
      }
      connected = true;
      connecting = false;
      notifyListeners();
      if (settings.discoveryMode != DiscoveryMode.directEsphome) {
        await _startLive();
      }
    } catch (e) {
      connecting = false;
      connected = false;
      error = e.toString();
      notifyListeners();
    }
  }

  /// Connects straight to the device's ESPHome web server.
  Future<void> _connectDirect() async {
    final host = settings.deviceHost.trim();
    final esp = EsphomeWebClient(host: host);
    _esp = esp;
    final entities = await esp.snapshot();
    final d = buildEsphomeDevice(host, entities);
    devices = d == null ? [] : [d];
    _rebuildIndex();
    if (d == null) {
      error = 'Connected to $host but found no zone/target entities. Is '
          'web_server enabled and are the zone entities present?';
    }
    final stream = await esp.openStateStream();
    _espSub = stream.listen(_applyEsp, onError: (_) {});
  }

  void _applyEsp(EspEvent e) {
    final d = _itemIndex[e.id];
    if (d != null && d.applyState(e.id, e.state)) notifyListeners();
  }

  /// Re-discovers devices using the live client (re-lists Things/Items, or
  /// re-snapshots the ESPHome device).
  Future<void> refresh() async {
    try {
      if (_esp != null) {
        final host = settings.deviceHost.trim();
        final d = buildEsphomeDevice(host, await _esp!.snapshot());
        devices = d == null ? [] : [d];
        _rebuildIndex();
        notifyListeners();
        return;
      }
      if (_client == null) return;
      await _loadDevices();
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  /// Lists devices per the configured discovery mode and seeds their state.
  Future<void> _loadDevices() async {
    final client = _client!;
    if (settings.discoveryMode == DiscoveryMode.thing) {
      _things = await client.listThings();
      devices = groupThingsIntoDevices(_things);
    } else {
      _things = [];
      devices = groupItemsIntoDevices(await client.listItems(), settings.convention);
    }
    _rebuildIndex();
    await _seedStates();
  }

  /// One-shot fetch of current Item states so values aren't 0 until the first
  /// SSE event arrives.
  Future<void> _seedStates() async {
    final client = _client;
    if (client == null) return;
    try {
      for (final e in await client.pollStates()) {
        _itemIndex[e.itemName]?.applyState(e.itemName, e.state);
      }
    } catch (_) {
      // best-effort seed; live updates will follow
    }
  }

  /// True when talking straight to the ESPHome web server.
  bool get directMode => _esp != null;

  /// All Things from the last discovery (Thing mode only).
  List<OhThing> get things => _things;

  /// Count of recognized role channels on [deviceId] with no linked Item.
  int missingLinkCount(String deviceId) {
    for (final t in _things) {
      if (t.uid == deviceId) return missingLinks(t).length;
    }
    return 0;
  }

  /// Creates + links openHAB Items for any unlinked role channels on a device,
  /// then re-discovers. Returns the number of Items created.
  Future<int> createMissingLinks(String deviceId) async {
    final client = _client;
    if (client == null) return 0;
    OhThing? thing;
    for (final t in _things) {
      if (t.uid == deviceId) thing = t;
    }
    if (thing == null) return 0;
    lastCommitError = null;
    var created = 0;
    for (final ml in missingLinks(thing)) {
      try {
        await client.createItem(ml.itemName, ml.itemType,
            label: '${thing.label} ${ml.channelId}');
        await client.linkItemToChannel(ml.itemName, ml.channelUid);
        created++;
      } catch (e) {
        lastCommitError = e.toString();
      }
    }
    if (created > 0) {
      await _loadDevices();
      notifyListeners();
    }
    return created;
  }

  void enterDemo() {
    _teardownLive();
    demo = true;
    error = null;
    _demo = DemoSource(onTick: notifyListeners);
    devices = [_demo!.device];
    _rebuildIndex();
    connected = true;
    _demo!.start();
    notifyListeners();
  }

  void disconnect() {
    _teardownLive();
    devices = [];
    connected = false;
    demo = false;
    notifyListeners();
  }

  /// Writes a zone's four corner coordinates to openHAB (commit on drag-end).
  /// No-op in demo mode.
  Future<void> commitZone(EpZone zone) async {
    if (demo) return;
    lastCommitError = null;
    final cmds = zone.cornerCommands();
    try {
      final esp = _esp;
      if (esp != null) {
        // Direct mode: send sequentially — the ESP32 web server has very few
        // connection slots and drops concurrent requests.
        for (final e in cmds.entries) {
          await esp.setNumber(e.key, e.value);
        }
        return;
      }
      final client = _client;
      if (client == null) return;
      await Future.wait(
          cmds.entries.map((e) => client.sendCommand(e.key, e.value)));
    } catch (e) {
      lastCommitError = e.toString();
      notifyListeners();
    }
  }

  EpDevice? deviceById(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  // --- internals ---

  void _rebuildIndex() {
    _itemIndex.clear();
    for (final d in devices) {
      for (final name in d.itemNames) {
        _itemIndex[name] = d;
      }
    }
  }

  Future<void> _startLive() async {
    if (_client == null) return;
    if (settings.forcePolling) {
      _startPolling();
      return;
    }
    try {
      final stream = await _client!.openStateStream();
      _sse = stream.listen(
        _applyEvent,
        onError: (_) => _fallbackToPolling(),
        onDone: () {
          // Connection dropped; reconnect via polling to stay live.
          if (connected && _pollTimer == null) _fallbackToPolling();
        },
      );
      usingSse = true;
      notifyListeners();
    } catch (_) {
      _fallbackToPolling();
    }
  }

  void _fallbackToPolling() {
    _sse?.cancel();
    _sse = null;
    usingSse = false;
    _startPolling();
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final ms = settings.pollMs < 250 ? 250 : settings.pollMs;
    _pollTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _pollOnce());
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    final client = _client;
    if (client == null) return;
    try {
      final events = await client.pollStates();
      var changed = false;
      for (final e in events) {
        final d = _itemIndex[e.itemName];
        if (d != null && d.applyState(e.itemName, e.state)) changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {
      // transient; next tick retries
    }
  }

  void _applyEvent(OhStateEvent e) {
    final d = _itemIndex[e.itemName];
    if (d != null && d.applyState(e.itemName, e.state)) {
      notifyListeners();
    }
  }

  void _teardownLive() {
    _sse?.cancel();
    _sse = null;
    _espSub?.cancel();
    _espSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _demo?.stop();
    _demo = null;
    _client?.close();
    _client = null;
    _esp?.close();
    _esp = null;
    usingSse = false;
  }

  @override
  void dispose() {
    _teardownLive();
    super.dispose();
  }
}

/// Re-exported so UI can decide whether to surface the web-SSE caveat.
bool get platformSseSupportsAuthHeader => sseSupportsAuthHeader;
