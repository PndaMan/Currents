<p align="center">
  <img src="docs/assets/logo.png" alt="Currents" width="140" />
</p>

<h1 align="center">Currents</h1>

<p align="center">
  <b>An offline-first fishing companion for iOS.</b><br>
  Built in Swift, designed for anglers who fish where the cell signal doesn't reach.
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#build">Build</a> ·
  <a href="#roadmap">Roadmap</a> ·
  <a href="#license">License</a>
</p>

---

## Overview

Currents is a fully local, offline-first fishing app: log catches, analyse gear, track spots, forecast the bite, and identify species on-device. Nothing leaves your phone unless you choose to share it. No accounts, no tracking, no cloud round-trips.

The app is written in **Swift 5.10 / SwiftUI**, targeting **iOS 26** with the Liquid Glass design language, and persists everything through **GRDB.swift** on SQLite. Weather data is fetched from the free [Open-Meteo](https://open-meteo.com) API when online and cached aggressively for offline use. Fish species identification runs on-device via **CoreML**.

## Features

### Catch logging
- **Pin-drop locations** — pick a spot anywhere on the map, not just your current GPS fix.
- **Photo capture** with inline species suggestion from the on-device classifier.
- **Metadata that matters** — weight, length, water temperature, gear used, notes, forecast score at the moment of capture.
- **Private by default** — nothing leaves the device. A per-catch privacy radius obfuscates shared coordinates.

### Bite forecast
The `ForecastEngine` computes a 0–100 bite score from a weighted combination of factors that actually predict fish behavior:

| Factor | Weight | Source |
|---|---|---|
| Barometric pressure trend | 15 | Open-Meteo hourly pressure |
| Solunar major / minor windows | 15 | On-device astro calc (no API) |
| Tide phase | 15 | Simplified harmonic prediction |
| Time of day (golden hours) | 15 | Sunrise / sunset from location |
| Pressure level | 10 | Open-Meteo current |
| Moon phase | 10 | Synodic cycle from 1999-12-25 new moon |
| Wind | 8 | Open-Meteo current |
| Water temp vs species optimum | 7 | Bundled species table |
| Spawning zone activity | 5 | Bundled seed data |

Each factor is normalised 0–1 and combined additively, so the same engine works for freshwater bass and saltwater kingfish just by swapping the species profile.

### Location inspector
Tap anywhere on the map and Currents shows you **why that spot is (or isn't) worth a cast**: live weather, a full bite-score breakdown, probable fishing spots ranked by local catch history, and nearby saved waypoints. Save the tap as a new spot in one button press.

### Offline maps
Apple Maps as the default renderer, with bathymetry-aware tile overlays where available. Downloadable PMTiles regions for air-gapped use are wired through `MapManager`.

### On-device species identification
A CoreML classifier runs inference locally — no images leave the device. See [`docs/ml.md`](docs/ml.md) for the model pipeline and how to swap in your own trained weights.

### Analytics
- Personal bests per species
- Monthly catch trend
- Best hours (heatmap derived from your own catch history)
- Gear effectiveness — which rig caught which species most often
- Spot productivity ranking

## Architecture

```
┌──────────────────────────────────────────┐
│  SwiftUI Views  (Features/*)             │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│  ViewModels / @Observable AppState       │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│  Repositories  (Core/DB/Repositories/*)  │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│  GRDB.swift  →  SQLite                   │
└──────────────────────────────────────────┘

     Cross-cutting services
     ─────────────────────
     WeatherService    (actor, Open-Meteo cache)
     ForecastEngine    (pure value type, deterministic)
     SolunarEngine     (astro, no network)
     TideEngine        (harmonic prediction)
     FishClassifier    (actor, CoreML + Vision)
     LocationManager   (CoreLocation wrapper)
     MapManager        (MapKit + PMTiles regions)
```

### Design rules

1. **Every screen reads from local SQLite.** No network calls on the UI thread, ever.
2. **Every write goes to local SQLite first.** The user sees instant success; sync happens later (when a sync layer exists).
3. **Pure functions for anything forecast-related.** `ForecastEngine` and `SolunarEngine` take values in, return values out. Trivial to test, deterministic, no hidden state.
4. **Actors for anything async.** `WeatherService` and `FishClassifier` are actors so concurrent callers serialise cleanly without locks.
5. **Seed data is compiled in**, not bundled as resources. Apple's resource bundling has historically been flaky for Swift Package Manager targets and non-trivial Xcode configurations — embedding JSON as Swift string literals removes a whole class of "works locally, crashes in CI" bugs. See `Core/DB/SeedData/`.

See [`docs/architecture.md`](docs/architecture.md) for the full breakdown.

## Repo layout

```
currents/
├── ios/                          Xcode project (generated via XcodeGen)
│   ├── Currents/
│   │   ├── App/                  @main, AppState, Info.plist
│   │   ├── Core/                 DB, Weather, ML, Astro, Maps, Theme
│   │   ├── Features/             Map, Catch, Forecast, Gear, Profile, Trip, Species
│   │   └── Resources/            Assets.xcassets, Data/
│   ├── Tests/                    XCTest unit tests
│   └── project.yml               XcodeGen spec
├── ml/                           Model training + CoreML conversion
│   ├── train.py
│   ├── convert_coreml.py
│   └── README.md
├── scripts/                      Seed-data generators (Python → Swift)
├── docs/                         Architecture, data model, ML notes
├── .github/workflows/            iOS build + IPA artifact CI
├── Makefile                      Common commands
└── README.md                     You are here
```

## Build

### Requirements
- macOS with Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 26 simulator runtime

### Generate the project & run

```bash
cd ios
xcodegen generate
open Currents.xcodeproj
```

Or from the command line:

```bash
make ios
```

### CI / sideloaded IPA

Every push to `master` builds an unsigned `.ipa` via GitHub Actions ([.github/workflows/ios.yml](.github/workflows/ios.yml)). The binary is fakesigned with `ldid` using the entitlements in `ios/Currents/App/Currents.entitlements`, which makes it compatible with sideloading tools like [Sideloader](https://sideloader.app) and TrollStore. Download the `Currents-IPA` artifact from any green build and install it on your device — no paid Apple Developer account required.

## Roadmap

- [x] Catch logging with pin-drop locations, photos, gear
- [x] Bite forecast engine (pressure / solunar / tide / weather)
- [x] Location inspector (tap-to-analyse anywhere on the map)
- [x] Personal bests, trip logging, species guide
- [x] Unsigned IPA builds via CI
- [ ] On-device CoreML fish classifier shipped with the app
- [ ] PMTiles bundled bathymetry regions
- [ ] Optional self-hostable sync layer (PowerSync)
- [ ] Social features (opt-in public catches with obfuscated locations)

## Contributing

Issues and PRs welcome. See [`docs/contributing.md`](docs/contributing.md) for the commit-message conventions, test expectations, and the preferred development loop.

## License

MIT — see [`LICENSE`](LICENSE).
