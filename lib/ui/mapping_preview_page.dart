import 'package:flutter/material.dart';

import '../models/ep_zone.dart';
import '../services/device_manager.dart';

/// Shows how openHAB Items were parsed into devices/zones/targets so the user
/// can verify the naming convention. Missing roles are flagged.
class MappingPreviewPage extends StatelessWidget {
  final DeviceManager manager;
  const MappingPreviewPage({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item mapping')),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final devices = manager.devices;
          if (devices.isEmpty) {
            return const Center(
              child: Text('No EP Lite Items matched the convention.'),
            );
          }
          return ListView(
            children: [
              for (final d in devices)
                ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(d.label),
                  subtitle: Text(
                    d.label == d.id
                        ? '${d.zones.length} zone(s), ${d.targets.length} target(s)'
                        : '${d.id}\n${d.zones.length} zone(s), ${d.targets.length} target(s)',
                  ),
                  children: [
                    if (manager.missingLinkCount(d.id) > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${manager.missingLinkCount(d.id)} channel(s) '
                                'have no linked Item — create them to read/write.',
                                style: const TextStyle(color: Colors.orange),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Create & link'),
                              onPressed: () => _createLinks(context, d.id),
                            ),
                          ],
                        ),
                      ),
                    for (final z in d.zones)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          z.isComplete ? Icons.check_circle : Icons.error,
                          color: z.isComplete ? Colors.green : Colors.orange,
                          size: 20,
                        ),
                        title: Text('Zone ${z.index}'),
                        subtitle: Text(_zoneDetail(z)),
                      ),
                    for (final t in d.targets)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.my_location, size: 20),
                        title: Text('Target ${t.index}'),
                        subtitle: Text(
                          'X: ${t.xItem ?? "—"}   Y: ${t.yItem ?? "—"}',
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createLinks(BuildContext context, String deviceId) async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await manager.createMissingLinks(deviceId);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n > 0
              ? 'Created and linked $n Item(s).'
              : 'No Items created${manager.lastCommitError != null ? ": ${manager.lastCommitError}" : "."}',
        ),
      ),
    );
  }

  String _zoneDetail(EpZone z) {
    final missing = <String>[
      if (z.beginXItem == null) 'BeginX',
      if (z.beginYItem == null) 'BeginY',
      if (z.endXItem == null) 'EndX',
      if (z.endYItem == null) 'EndY',
    ];
    if (missing.isEmpty) {
      return 'corners mapped'
          '${z.occupancyItem != null ? " + occupancy" : ""}'
          '${z.countItem != null ? " + count" : ""}';
    }
    return 'missing: ${missing.join(", ")}';
  }
}
