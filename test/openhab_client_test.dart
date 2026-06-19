import 'package:flutter_test/flutter_test.dart';
import 'package:ep_zones/services/openhab_client.dart';
import 'package:ep_zones/models/oh_item.dart';

void main() {
  group('parseOhEvent', () {
    test('parses an ItemStateChangedEvent payload', () {
      const data =
          '{"topic":"openhab/items/EPL_Office_Target1_X/statechanged",'
          '"payload":"{\\"type\\":\\"Decimal\\",\\"value\\":\\"512\\"}",'
          '"type":"ItemStateChangedEvent"}';
      final e = parseOhEvent(data);
      expect(e, isNotNull);
      expect(e!.itemName, 'EPL_Office_Target1_X');
      expect(e.state, '512');
    });

    test('parses a quantity value with a unit', () {
      const data =
          '{"topic":"openhab/items/EPL_Office_Zone1_BeginX/state",'
          '"payload":"{\\"type\\":\\"Quantity\\",\\"value\\":\\"-2000 mm\\"}",'
          '"type":"ItemStateEvent"}';
      final e = parseOhEvent(data)!;
      expect(e.itemName, 'EPL_Office_Zone1_BeginX');
      expect(OhItem.parseNumber(e.state), -2000);
    });

    test('returns null for malformed or unrelated payloads', () {
      expect(parseOhEvent('not json'), isNull);
      expect(parseOhEvent('{"topic":"openhab/things/x/status"}'), isNull);
    });
  });

  group('formatCommandValue', () {
    test('drops .0 for integral values', () {
      expect(formatCommandValue(2000), '2000');
      expect(formatCommandValue(-1500.0), '-1500');
    });
    test('keeps fractional values', () {
      expect(formatCommandValue(12.5), '12.5');
    });
  });

  group('OhItem', () {
    test('parses numeric state with trailing unit', () {
      final i = OhItem(name: 'x', type: 'Number', state: '1234 mm');
      expect(i.numericState, 1234);
    });
    test('boolState recognises ON/OPEN', () {
      expect(OhItem(name: 'x', type: 'Switch', state: 'ON').boolState, isTrue);
      expect(
        OhItem(name: 'x', type: 'Contact', state: 'OPEN').boolState,
        isTrue,
      );
      expect(
        OhItem(name: 'x', type: 'Switch', state: 'OFF').boolState,
        isFalse,
      );
    });
    test('non-numeric state yields null', () {
      expect(
        OhItem(name: 'x', type: 'Number', state: 'NULL').numericState,
        isNull,
      );
    });
  });
}
