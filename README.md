# EP Zones

A cross-platform Flutter app (**Android · Windows · Web**) to view live mmWave targets and
**visually configure the detection zones** on
[Everything Presence Lite](https://everythingsmart.io) sensors. It's the openHAB-friendly
counterpart to Home Assistant's "Zone Configurator" — but it can also talk **straight to the
device** over its ESPHome web API, with no home-automation hub at all.

> EP Lite uses an HLK-LD2450 24 GHz radar that tracks up to 3 targets (X/Y in mm) and supports
> up to 4 rectangular zones. This app draws the radar plane, shows targets moving in real time,
> and lets you drag zone rectangles — writing the coordinates back to the device.

## Features

- **Live radar view** — sensor origin, detection fan, moving target dots, zone rectangles.
- **Drag-to-edit zones** — move a zone or drag a corner handle; edits stay **local until you
  press Save**, so nothing is written to the device mid-drag.
- **Three connection modes:**
  - **openHAB Thing** *(recommended)* — discovers ESPHome Things (e.g. `esphome:device:abcd`)
    via the [seime ESPHome binding](https://github.com/seime/openhab-esphome) and maps their
    channels automatically. One tap creates + links any missing openHAB Items.
  - **Direct ESPHome** — talks straight to the device's web server over HTTP (no openHAB).
    Requires `web_server:` enabled in the device's ESPHome config.
  - **Item naming** — groups plain openHAB Items by a configurable name convention.
- **Live updates** over openHAB SSE (`/rest/events`) or the ESPHome `/events` stream, with a
  REST polling fallback.
- **Export zones to YAML** — copy an ESPHome `substitutions:` block of the current zone
  coordinates.
- **Demo mode** — a synthetic target walks the plane so you can try everything with no hardware.

## Getting started

```bash
flutter pub get
flutter run -d windows     # or -d chrome, or an Android device
flutter test               # unit tests (parsing, geometry, discovery, SSE)
```

On first launch, pick a connection mode:

### openHAB Thing mode
1. Add each EP Lite device to openHAB with the seime ESPHome binding.
2. Enter your openHAB base URL and an **admin API token** (openHAB → your profile →
   *Create API Token*). The `/rest/things` endpoint requires admin scope.
3. **Test** → **Connect**, open the device, and if any channels are unlinked tap **Create &
   link** on the *Item mapping* screen.

### Direct ESPHome mode
1. Enable the web server on the device's ESPHome config:
   ```yaml
   web_server:
     version: 3
   ```
2. Enter the device IP (e.g. `192.168.1.50`), **Test** → **Connect**.

> The LD2450 `target_N_x` / `target_N_y` position entities are **disabled by default** in EP Lite
> firmware. Enable them if you want the live target dot; zones and occupancy work either way.

## Architecture

Lightweight `ChangeNotifier` + `http` + `shared_preferences`, no heavy state framework.

- `lib/models/` — `OhItem`, `OhThing`, `EpDevice`/`EpZone`/`EpTarget`, `NamingConvention`.
- `lib/services/`
  - `openhab_client.dart` — openHAB REST + SSE (items, things, item/link creation, commands).
  - `esphome_web_client.dart` — direct ESPHome web API (`/events` SSE, `POST /<domain>/<name>/set`).
  - `device_discovery.dart` / `channel_discovery.dart` — pure grouping of Items/Things into devices.
  - `sse_transport_*.dart` — platform-split SSE (dart:io stream vs browser `EventSource`).
  - `device_manager.dart` — connection lifecycle, live updates, save/commit.
  - `yaml_export.dart`, `demo_source.dart`.
- `lib/ui/` — connection / device list / mapping preview / **zone editor**, with `RadarPainter`
  and a pure `CoordTransform`.

## Building for Windows

If a fresh `flutter build windows` fails with *"No CMAKE_CXX_COMPILER could be found"* and you
have a global [vcpkg](https://github.com/microsoft/vcpkg) integration installed, a corrupt vcpkg
lib can break CMake's compiler probe. Build with vcpkg disabled for the session:

```bat
"...\VC\Auxiliary\Build\vcvars64.bat" && set VcpkgEnabled=false && flutter build windows
```

## License

MIT — see [LICENSE](LICENSE).
