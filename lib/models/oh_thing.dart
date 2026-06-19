/// An openHAB Thing and its channels, as returned by `GET /rest/things`.
///
/// For the ESPHome binding each EP Lite device is one Thing (e.g.
/// `esphome:device:40ea2c136a`) whose channels mirror the device's entities
/// (`target_1_x`, `zone_1_begin_x`, `zone_1_occupancy`, …).
class OhThing {
  final String uid;
  final String label;
  final String thingTypeUID;
  final String status; // ONLINE / OFFLINE / …
  final Map<String, dynamic> configuration;
  final List<OhChannel> channels;

  const OhThing({
    required this.uid,
    required this.label,
    required this.thingTypeUID,
    required this.status,
    this.configuration = const {},
    required this.channels,
  });

  bool get isEsphome =>
      uid.startsWith('esphome:') || thingTypeUID.startsWith('esphome:');

  /// Device IP/hostname from the Thing config, if the binding exposes one.
  String? get host {
    for (final key in const [
      'hostname',
      'host',
      'ipAddress',
      'ip',
      'address',
    ]) {
      final v = configuration[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  factory OhThing.fromJson(Map<String, dynamic> j) {
    final ch = (j['channels'] as List?) ?? const [];
    final status = j['statusInfo'];
    final config = j['configuration'];
    return OhThing(
      uid: j['UID'] as String,
      label: (j['label'] as String?) ?? (j['UID'] as String),
      thingTypeUID: (j['thingTypeUID'] as String?) ?? '',
      status: status is Map ? (status['status'] as String? ?? '') : '',
      configuration: config is Map<String, dynamic>
          ? config
          : const <String, dynamic>{},
      channels: ch
          .whereType<Map<String, dynamic>>()
          .map(OhChannel.fromJson)
          .toList(growable: false),
    );
  }
}

class OhChannel {
  final String uid; // e.g. esphome:device:40ea2c136a:zone_1_begin_x
  final String id; // e.g. zone_1_begin_x
  final String? itemType; // Number, Number:Length, Switch, Contact, …
  final String? label;
  final List<String> linkedItems;

  const OhChannel({
    required this.uid,
    required this.id,
    this.itemType,
    this.label,
    this.linkedItems = const [],
  });

  String? get firstLinkedItem =>
      linkedItems.isNotEmpty ? linkedItems.first : null;

  factory OhChannel.fromJson(Map<String, dynamic> j) {
    final uid = j['uid'] as String;
    return OhChannel(
      uid: uid,
      id: (j['id'] as String?) ?? uid.split(':').last,
      itemType: j['itemType'] as String?,
      label: j['label'] as String?,
      linkedItems: ((j['linkedItems'] as List?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
