# Currents — Offline-First Fishing App

## Project Overview
Fishing companion + light social app for anglers worldwide (freshwater + coastal). Offline-first is a hard requirement. Self-hostable backend (later phase). Initially built with SA data but designed to be global.

**Current phase: Offline-only iOS app** — no backend, no sync. Every feature that can work without a server should be implemented first.

## Architecture Decisions

### iOS Client
- **Swift 5.10+**, **SwiftUI** with iOS 26 Liquid Glass design language
- **SQLite via GRDB.swift** for local storage (PowerSync added later when backend comes)
- **MapLibre Native iOS** + **PMTiles** for offline maps
- **CoreML** (YOLOv8n) for on-device fish species identification
- **CoreLocation** for spot tracking
- **Swift Package Manager** only (no CocoaPods)
- **Swift Charts** for pressure trends and gear effectiveness
- **Nuke** for image caching
- **AVFoundation** + Vision framework for camera

### Design
- Target iOS 26+ with Liquid Glass UI throughout
- Translucent materials, vibrancy, glass tab bars, fluid animations
- Dark mode first (anglers fish early morning / late evening)

### Offline-First Rules
1. Every screen reads from local SQLite. No network calls on UI thread, ever.
2. Every write goes to local SQLite first. User sees instant success.
3. Map uses pre-bundled PMTiles for offline regions.
4. Show "stale since X" badge for old data, never block UI.

## Data Model (Local SQLite — no PostGIS, plain lat/lon/geohash)
See `docs/data-model.md` for full schema.

Core tables: users (local profile), species (seeded), catches, spots, gear_loadouts, weather_obs (cached), forecasts (locally computed).

## Key Conventions
- Feature-based folder structure under `Hooked/Features/`
- MVVM: SwiftUI Views -> ViewModels -> Repositories -> GRDB
- Keep ML inference off main thread (use async/await)
- Strip EXIF GPS from any photo before it could be shared (future-proofing)

## Repo Layout
```
currents/
├── ios/Currents/         # Xcode project
│   ├── App/              # @main, app delegate
│   ├── Features/         # Map, Catch, Forecast, Gear, Profile
│   ├── Core/             # DB, ML, Maps, Location
│   └── Resources/Models/ # .mlpackage files
├── ml/                   # Training + CoreML conversion (Python)
├── tiles/                # PMTiles generation scripts
├── docs/                 # Architecture docs
└── README.md
```

## What NOT to Build Yet
- Backend (FastAPI, PowerSync, Redis, MinIO)
- Social feed, friends, public catches
- Push notifications (APNs)
- Server-side forecast computation
- User accounts / auth / JWT
- Sync infrastructure

## External Data (bundled/cached, not live API)
- Species data: seed from FishBase export (bundled JSON/SQLite)
- Bathymetry: pre-generated PMTiles from GLOBathy
- Spawning zones: bundled from GO-FISH dataset
- Weather: CoreLocation + WeatherKit (Apple's API, works on-device with API key)
