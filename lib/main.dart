import 'package:flutter/material.dart';

import 'services/device_manager.dart';
import 'ui/connection_page.dart';
import 'ui/device_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final manager = await DeviceManager.create();
  runApp(EpZonesApp(manager: manager));
}

class EpZonesApp extends StatelessWidget {
  final DeviceManager manager;
  const EpZonesApp({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EP Zones',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _Root(manager: manager),
    );
  }
}

/// Routes between the connection screen and the device list based on state.
class _Root extends StatelessWidget {
  final DeviceManager manager;
  const _Root({required this.manager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        if (manager.connected || manager.demo) {
          return DeviceListPage(manager: manager);
        }
        return ConnectionPage(manager: manager);
      },
    );
  }
}
