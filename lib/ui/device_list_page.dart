import 'package:flutter/material.dart';

import '../services/device_manager.dart';
import 'mapping_preview_page.dart';
import 'zone_editor_page.dart';

/// Lists discovered EP Lite devices with a live occupancy badge.
class DeviceListPage extends StatelessWidget {
  final DeviceManager manager;
  const DeviceListPage({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(manager.demo ? 'EP Zones (Demo)' : 'EP Lite Devices'),
        actions: [
          IconButton(
            tooltip: 'Item mapping',
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MappingPreviewPage(manager: manager))),
          ),
          IconButton(
            tooltip: 'Connection settings',
            icon: const Icon(Icons.settings),
            // Just disconnect; the root widget shows the connection screen
            // when not connected. (Pushing a route here would replace the
            // root and break the auto-return to the device list on reconnect.)
            onPressed: manager.disconnect,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final devices = manager.devices;
          if (devices.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sensors_off, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'No EP Lite devices found.\nCheck your Item naming '
                      'convention and that the Items exist in openHAB.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: manager.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: devices.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = devices[i];
              final activeZones = d.zones.where((z) => z.isActive).length;
              final missing = manager.missingLinkCount(d.id);
              final present = d.targets.where((t) => t.present).length;
              final counts = '$activeZones/${d.zones.length} zones active   '
                  '$present target(s)'
                  '${missing > 0 ? "   ⚠ $missing unlinked" : ""}';
              final detail = d.host != null && d.host != d.label
                  ? 'IP ${d.host}'
                  : (d.label != d.id ? d.id : null);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: d.anyOccupied
                      ? Colors.green
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    d.anyOccupied ? Icons.person : Icons.person_outline,
                    color: d.anyOccupied ? Colors.white : null,
                  ),
                ),
                title: Text(d.label),
                subtitle: Text(detail != null ? '$detail\n$counts' : counts),
                isThreeLine: detail != null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ZoneEditorPage(manager: manager, deviceId: d.id))),
              );
            },
          );
        },
      ),
    );
  }
}
