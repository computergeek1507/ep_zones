import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/services/esphome_web_client.dart';

void main() {
  group('normalizeHost', () {
    test('adds scheme and strips trailing slash', () {
      expect(
        EsphomeWebClient.normalizeHost('192.168.1.50'),
        'http://192.168.1.50',
      );
      expect(
        EsphomeWebClient.normalizeHost('http://dev.local/'),
        'http://dev.local',
      );
      expect(
        EsphomeWebClient.normalizeHost(' device.local '),
        'http://device.local',
      );
    });
  });

  group('splitEspId', () {
    test('handles legacy domain-object_id and new domain/Name forms', () {
      expect(splitEspId('number-zone_1_begin_x'), ('number', 'zone_1_begin_x'));
      expect(splitEspId('number/Zone 1 Begin X'), ('number', 'Zone 1 Begin X'));
      expect(splitEspId('binary_sensor-zone_1_occupancy'), (
        'binary_sensor',
        'zone_1_occupancy',
      ));
    });
  });

  group('parseEspEvent', () {
    test('legacy id format', () {
      final e = parseEspEvent(
        '{"id":"number-zone_1_begin_x","value":1000,"state":"1000 mm"}',
      )!;
      expect(e.domain, 'number');
      expect(e.key, 'zone_1_begin_x');
      expect(e.state, '1000 mm');
    });

    test('newer id format with friendly name normalizes to object id', () {
      final e = parseEspEvent(
        '{"id":"number/Zone 1 Begin X","name_id":"number/Zone 1 Begin X",'
        '"value":1000,"state":"1000 mm"}',
      )!;
      expect(e.domain, 'number');
      expect(e.key, 'zone_1_begin_x');
      expect(e.id, 'number/Zone 1 Begin X');
    });

    test('prefers the name-based id for control when both are present', () {
      // Recent firmware sends both; the web server matches writes by name.
      final e = parseEspEvent(
        '{"id":"number-zone_1_begin_x","name_id":"number/Zone 1 Begin X",'
        '"value":1000,"state":"1000 mm"}',
      )!;
      expect(e.id, 'number/Zone 1 Begin X');
      expect(e.key, 'zone_1_begin_x');
    });

    test('falls back to name_id and returns null on junk', () {
      final e = parseEspEvent(
        '{"name_id":"binary_sensor-zone_2_occupancy","state":"ON"}',
      )!;
      expect(e.key, 'zone_2_occupancy');
      expect(parseEspEvent('not json'), isNull);
      expect(parseEspEvent('["log line"]'), isNull);
    });
  });

  group('buildEsphomeDevice', () {
    test('builds from a snapshot using either id format', () {
      final entities = [
        const EspEvent(
          'number-zone_1_begin_x',
          'number',
          'zone_1_begin_x',
          '-2000',
        ),
        const EspEvent(
          'number-zone_1_begin_y',
          'number',
          'zone_1_begin_y',
          '1000',
        ),
        const EspEvent('number-zone_1_end_x', 'number', 'zone_1_end_x', '0'),
        const EspEvent('number-zone_1_end_y', 'number', 'zone_1_end_y', '3000'),
        const EspEvent(
          'binary_sensor-zone_1_occupancy',
          'binary_sensor',
          'zone_1_occupancy',
          'ON',
        ),
        const EspEvent('sensor/Target 1 X', 'sensor', 'target_1_x', '512 mm'),
        const EspEvent('sensor/Target 1 Y', 'sensor', 'target_1_y', '2500 mm'),
        const EspEvent('sensor-illuminance', 'sensor', 'illuminance', '40 lx'),
      ];
      final d = buildEsphomeDevice('192.168.1.50', entities)!;
      final z = d.zones.single;
      expect(z.isComplete, isTrue);
      expect(z.beginX, -2000);
      expect(z.endY, 3000);
      expect(z.occupied, isTrue);
      // The raw SSE id is the routing/control key.
      expect(z.beginXItem, 'number-zone_1_begin_x');
      final t = d.targets.single;
      expect(t.x, 512);
      expect(t.xItem, 'sensor/Target 1 X');
    });

    test('returns null when no EP roles present', () {
      expect(
        buildEsphomeDevice('h', [
          const EspEvent('sensor-illuminance', 'sensor', 'illuminance', '1'),
        ]),
        isNull,
      );
    });
  });
}
