# Marathon Maps — implementation roadmap

## Current state (committed)

- **MapsApp.qml** wires the full JSX `ref-maps` chrome: glass-titlebar
  search bar + Nominatim search-results list + bottom place card with
  the 4-action row (Directions/Call/Share/Save).
- **AGPS / Geoclue** via the shell-side `LocationManager` is exposed
  to the app-runner as the `LocationService` IPC client and consumed
  by `MapsApp.bestCoord`. The Map's `center` and the user-location
  marker both bind to it, falling back to QtPositioning's
  `PositionSource` when Geoclue isn't reporting yet, then to a
  default coordinate so the first paint always shows _something_.
- **CARTO Dark Matter tile manifest** ships at
  `apps/maps/resources/tile-providers.json` and gets installed
  alongside the app at
  `$XDG_DATA_HOME/marathon-apps/maps/resources/tile-providers.json`.
  `MapsApp` resolves a `file://` URL to it via the new
  `MARATHON_APP_PATH` context property and passes it to the
  QtLocation OSM plugin's `osm.mapping.providersrepository.address`.

## Known limitation

QtLocation 6.10's `osm` plugin silently ignores the custom
`providersrepository.address` for raster tiles in our setup — the
plugin parses the manifest but still falls back to its hard-coded
mapId-100 (`tile.openstreetmap.org`) provider on first tile fetch.
There's no `qt.location` log category to confirm why, and the
behaviour is consistent across cache wipes, `qrc://` and `file://`
URL forms, and the Qt-blessed `tile_providers v1` schema.

Net: the map renders, scrolls, geocodes, locates — but it renders
the default light OSM raster style instead of the Marathon DS dark
style the JSX calls for.

## Path forward: MapLibre Native + OpenFreeMap

The proper fix is to drop QtLocation's OSM plugin in favour of
**`maplibre-native-qt`** with **OpenFreeMap** vector tiles. Why:

- MapLibre is the actively-maintained open-source fork of pre-relicense
  Mapbox GL Native (BSD-2 core; LGPLv3 Qt bindings — dynamic-link
  safe for our shell).
- Vector tiles let us style the basemap to match the Marathon DS
  palette exactly (dark teal + neutrals + the locked-palette
  approach from the JSX ref).
- OpenFreeMap is no-key, no-quota, MIT, OSM-derived, and ships a
  dark style URL out of the box.
- `maplibre-native-qt` provides a QtLocation Plugin (`name: "maplibre"`)
  that's a near-drop-in for the existing `osm` plugin — `Map`,
  `MapQuickItem`, `MapPolyline` etc all keep working. Only the
  `Plugin {}` block changes plus a style URL parameter.
- Vector rendering runs comfortably on SDM845-class hardware
  (Adreno 630); Pure Maps has shipped vector tiles on the much
  weaker A64 Pinephone for years.

## Migration plan

1. **Vendor `maplibre-native-qt`** as a git submodule under
   `thirdparty/maplibre-native-qt/`. Shallow-clone with submodules
   to keep the tree manageable.
2. **CMake integration** — add an optional subdirectory in the top
   `CMakeLists.txt`, gated behind `MARATHON_WITH_MAPLIBRE=ON`. When
   the option is off (and on platforms where the dependency tree
   hasn't built yet), the existing QtLocation OSM plugin path
   remains the default.
3. **Swap the Plugin** in `MapsApp.qml`:

   ```qml
   plugin: Plugin {
       name: "maplibre"
       PluginParameter {
           name: "maplibre.map.styles"
           value: "https://tiles.openfreemap.org/styles/dark"
       }
   }
   ```

   No other QML changes required — the search overlay, place card,
   markers, and PositionSource binding all stay.
4. **Drop the QtLocation OSM path** once MapLibre is the default
   on Duranium, including the `tile-providers.json` manifest
   workaround and the `MARATHON_APP_PATH` plumbing once nothing
   else consumes it.
5. **pmaports MR** to package `maplibre-native-qt` on Alpine
   aarch64 so Duranium builds pull it in normally rather than
   building from source.

## Sources

- [maplibre-native-qt](https://github.com/maplibre/maplibre-native-qt) (v3.0 stable, Oct 2024)
- [OpenFreeMap](https://openfreemap.org/) (free, no-key, MIT)
- [MapLibre Qt usage docs](https://maplibre.org/maplibre-native-qt/docs/md_docs_2Usage.html)
- [Pure Maps on PinePhone](https://github.com/rinigus/pure-maps) — proof point for vector
  rendering on phone-class ARM SoCs.
