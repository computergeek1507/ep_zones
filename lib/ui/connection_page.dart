import 'package:flutter/material.dart';

import '../models/naming_convention.dart';
import '../services/device_manager.dart';
import '../services/settings_store.dart';

/// openHAB connection + naming-convention settings, with a "Test", "Connect",
/// and "Demo" action and inline setup help.
class ConnectionPage extends StatefulWidget {
  final DeviceManager manager;
  const ConnectionPage({super.key, required this.manager});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _prefix;
  late final TextEditingController _sep;
  late final TextEditingController _host;
  late DiscoveryMode _mode;
  late bool _forcePolling;
  String? _testResult;
  bool _testOk = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.manager.settings;
    _url = TextEditingController(text: s.baseUrl);
    _token = TextEditingController(text: s.token);
    _prefix = TextEditingController(text: s.convention.prefix);
    _sep = TextEditingController(text: s.convention.separator);
    _host = TextEditingController(text: s.deviceHost);
    _mode = s.discoveryMode;
    _forcePolling = s.forcePolling;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _prefix.dispose();
    _sep.dispose();
    _host.dispose();
    super.dispose();
  }

  Settings _collect() => widget.manager.settings.copyWith(
        baseUrl: _url.text,
        token: _token.text,
        discoveryMode: _mode,
        deviceHost: _host.text,
        convention: NamingConvention(
          prefix: _prefix.text.trim().isEmpty ? 'EPL' : _prefix.text.trim(),
          separator: _sep.text.isEmpty ? '_' : _sep.text,
        ),
        forcePolling: _forcePolling,
      );

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testResult = null;
    });
    try {
      await widget.manager.testConnection(_collect());
      setState(() {
        _testOk = true;
        _testResult = 'Connected to openHAB successfully.';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.toString();
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    await widget.manager.saveSettings(_collect());
    await widget.manager.connect();
    setState(() => _busy = false);
  }

  void _demo() {
    widget.manager.enterDemo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to openHAB')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Connection mode',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<DiscoveryMode>(
            segments: const [
              ButtonSegment(
                value: DiscoveryMode.thing,
                label: Text('openHAB Thing'),
                icon: Icon(Icons.hub),
              ),
              ButtonSegment(
                value: DiscoveryMode.directEsphome,
                label: Text('Direct ESPHome'),
                icon: Icon(Icons.wifi),
              ),
              ButtonSegment(
                value: DiscoveryMode.naming,
                label: Text('Item naming'),
                icon: Icon(Icons.abc),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_mode) {
              DiscoveryMode.thing =>
                'Lists ESPHome Things in openHAB (e.g. esphome:device:…) and '
                    'maps their channels automatically. Recommended.',
              DiscoveryMode.directEsphome =>
                'Talks straight to the device over HTTP — no openHAB. Requires '
                    'web_server: enabled in the device\'s ESPHome config.',
              DiscoveryMode.naming =>
                'Groups openHAB Items by parsing their names with the '
                    'convention below.',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_mode == DiscoveryMode.directEsphome) ...[
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Device IP / host',
                hintText: '192.168.1.50  (or device.local)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ] else ...[
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'openHAB base URL',
                hintText: 'http://openhab.local:8080',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              decoration: const InputDecoration(
                labelText: 'API token (admin)',
                hintText: 'oh.xxxxx…',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
          if (_mode == DiscoveryMode.naming) ...[
            const SizedBox(height: 12),
            Text('Item naming convention',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _prefix,
                    decoration: const InputDecoration(
                      labelText: 'Prefix',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _sep,
                    decoration: const InputDecoration(
                      labelText: 'Separator',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (_mode != DiscoveryMode.directEsphome)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Force REST polling (no SSE)'),
              subtitle: const Text(
                  'Use if live updates do not arrive (e.g. web + token).'),
              value: _forcePolling,
              onChanged: (v) => setState(() => _forcePolling = v),
            ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_testOk ? Colors.green : Colors.red)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_testResult!,
                  style: TextStyle(
                      color: _testOk ? Colors.green : Colors.red)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _test,
                child: const Text('Test'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _busy ? null : _demo,
                child: const Text('Demo'),
              ),
            ],
          ),
          if (widget.manager.error != null) ...[
            const SizedBox(height: 12),
            Text(widget.manager.error!,
                style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          _setupHelp(context),
        ],
      ),
    );
  }

  Widget _setupHelp(BuildContext context) {
    final c = _collect().convention;
    return ExpansionTile(
      title: const Text('Setup help'),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        const Text(
          'This app reads/writes Everything Presence Lite data through openHAB. '
          'Add each device with the seime ESPHome binding and enable the '
          '(disabled-by-default) target-position and zone number entities.\n',
        ),
        if (_mode == DiscoveryMode.directEsphome) ...[
          const Text('Direct ESPHome mode',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Talks to the device\'s ESPHome web server over HTTP — openHAB is '
            'not involved. Enable it by adding to the device\'s ESPHome YAML:\n',
          ),
          _mono('web_server:\n  version: 3'),
          const SizedBox(height: 6),
          const Text(
            'Then enter the device IP above. Zone edits are written with '
            'POST /number/zone_N_begin_x/set?value=…  Note: target X/Y entities '
            'are disabled by default in firmware — enable them for live targets.\n',
          ),
        ] else if (_mode == DiscoveryMode.thing) ...[
          const Text('openHAB Thing mode',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'The app lists Things like esphome:device:xxxxxxxx and maps their '
            'channels (target_1_x, zone_1_begin_x, zone_1_occupancy, …). '
            'Channels need a linked Item to be read/written — if any are '
            'unlinked, use "Create & link" on the Item mapping screen.\n',
          ),
        ] else ...[
          const Text('Example Item names for a device called "Office":',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _mono(c.example('Office', RoleKind.targetX)),
          _mono(c.example('Office', RoleKind.zoneBeginX)),
          _mono(c.example('Office', RoleKind.zoneEndY)),
          _mono(c.example('Office', RoleKind.zoneOccupancy)),
          const SizedBox(height: 8),
        ],
        const Text(
          'For the web build, openHAB must allow cross-origin (CORS) REST/SSE. '
          'Browser SSE cannot send the token header, so the token is passed as '
          '?accessToken=; if live updates fail, enable "Force REST polling".',
        ),
      ],
    );
  }

  Widget _mono(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(s, style: const TextStyle(fontFamily: 'monospace')),
      );
}
