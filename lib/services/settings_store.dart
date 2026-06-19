import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/naming_convention.dart';

/// How the app finds and talks to EP Lite devices.
enum DiscoveryMode {
  /// Parse openHAB Item names with a [NamingConvention].
  naming,

  /// List openHAB ESPHome Things and map their channels (recommended).
  thing,

  /// Talk straight to the device's ESPHome web server (no openHAB).
  directEsphome,
}

/// Persists connection + convention settings via shared_preferences.
///
/// Note: the API token is stored in plain shared_preferences for parity with
/// the other apps in this workspace. If stronger protection is wanted later,
/// swap to flutter_secure_storage behind this same interface.
class Settings {
  final String baseUrl; // e.g. http://openhab.local:8080
  final String token; // openHAB API token (optional)
  final DiscoveryMode discoveryMode;
  final String deviceHost; // ESPHome device IP/host for directEsphome mode
  final NamingConvention convention;

  /// Force REST polling instead of SSE (useful on web when SSE auth fails).
  final bool forcePolling;

  /// Poll interval in milliseconds when polling is used.
  final int pollMs;

  const Settings({
    this.baseUrl = '',
    this.token = '',
    this.discoveryMode = DiscoveryMode.thing,
    this.deviceHost = '',
    this.convention = NamingConvention.defaults,
    this.forcePolling = false,
    this.pollMs = 1000,
  });

  bool get isConfigured => discoveryMode == DiscoveryMode.directEsphome
      ? deviceHost.trim().isNotEmpty
      : baseUrl.trim().isNotEmpty;

  /// Base URL without a trailing slash.
  String get normalizedBaseUrl {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Settings copyWith({
    String? baseUrl,
    String? token,
    DiscoveryMode? discoveryMode,
    String? deviceHost,
    NamingConvention? convention,
    bool? forcePolling,
    int? pollMs,
  }) => Settings(
    baseUrl: baseUrl ?? this.baseUrl,
    token: token ?? this.token,
    discoveryMode: discoveryMode ?? this.discoveryMode,
    deviceHost: deviceHost ?? this.deviceHost,
    convention: convention ?? this.convention,
    forcePolling: forcePolling ?? this.forcePolling,
    pollMs: pollMs ?? this.pollMs,
  );
}

class SettingsStore {
  static const _key = 'ep_zones_settings';

  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const Settings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return Settings(
        baseUrl: (j['baseUrl'] as String?) ?? '',
        token: (j['token'] as String?) ?? '',
        discoveryMode:
            DiscoveryMode.values.asNameMap()[j['discoveryMode'] as String? ??
                ''] ??
            DiscoveryMode.thing,
        deviceHost: (j['deviceHost'] as String?) ?? '',
        convention: NamingConvention.fromJson(
          (j['convention'] as Map<String, dynamic>?) ?? const {},
        ),
        forcePolling: (j['forcePolling'] as bool?) ?? false,
        pollMs: (j['pollMs'] as int?) ?? 1000,
      );
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> save(Settings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'baseUrl': s.baseUrl,
        'token': s.token,
        'discoveryMode': s.discoveryMode.name,
        'deviceHost': s.deviceHost,
        'convention': s.convention.toJson(),
        'forcePolling': s.forcePolling,
        'pollMs': s.pollMs,
      }),
    );
  }
}
