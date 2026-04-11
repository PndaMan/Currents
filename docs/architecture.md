# Architecture

Currents is a single-binary iOS app with no backend. It runs everything — storage, forecasting, ML inference, map rendering, astro computation — on-device.

## Layering

```
SwiftUI Views        →    Features/*
@Observable State    →    App/AppState
Repositories         →    Core/DB/Repositories/*
GRDB + SQLite        →    Core/DB/AppDatabase.swift
```

The only long-lived object is `AppState`, created in `CurrentsApp.swift` and propagated through `@Environment`. It owns the database handle, all repositories, and the cross-cutting services (location, classifier, map manager). Because `AppState` is `@MainActor @Observable`, SwiftUI re-renders automatically when repository methods mutate the database.

## Modules

### `Core/DB`
GRDB models (`Catch`, `Spot`, `Species`, …) with `PersistableRecord` conformance. Repositories are thin, synchronous, and throw on error — there is no Combine layer. `AppDatabase` owns a single `DatabasePool` and exposes it via `db.read { … }` / `db.write { … }`.

Seed data (200+ species, 100+ gear items) is embedded as Swift string literals (`Core/DB/SeedData/*.swift`) rather than bundled JSON. This avoids Xcode's historically flaky resource bundling inside SPM targets and means the data travels with the compiled binary.

### `Core/ML`
- `ForecastEngine` — a pure `struct` with static methods. Given current conditions, moon phase, tide phase, wind, and species profile, it returns a `ForecastResult` with a 0–100 score, per-factor breakdown, hourly projection for the day, and human-readable reasons. No global state, no I/O, trivially testable.
- `FishClassifier` — an `actor` wrapping a `VNCoreMLModel`. Loads `FishID.mlmodelc` from the bundle on boot and falls back to Vision's built-in `VNClassifyImageRequest` if the custom model is missing.

### `Core/Weather`
`WeatherService` is an actor that wraps Open-Meteo's public API. It caches by coordinate at 2-decimal precision (≈1 km) with a 30-minute TTL and a persistent fallback to the last-known cache when offline. No API key required.

### `Core/Astro`
- `SolunarEngine` — sunrise, sunset, dawn/dusk golden hours, moon phase, major/minor feeding windows, and an hourly solunar influence curve.
- `TideEngine` — simplified harmonic tide prediction for coastal locations.

### `Core/Maps`
`MapManager` tracks downloaded PMTiles regions and exposes them to the SwiftUI `Map` view. MapKit is the primary renderer; PMTiles is layered on top for bathymetry and air-gapped regions.

### `Features/*`
One folder per user-facing surface (`Map`, `Catch`, `Forecast`, `Gear`, `Profile`, `Trip`, `Species`). Views are SwiftUI-first and pull directly from repositories — there is no separate ViewModel layer. The architecture trades the indirection a classic MVVM layer provides for simpler call sites and fewer files.

## Offline-first guarantees

1. Every read path hits SQLite only. No view makes a network call at render time.
2. Every write path persists to SQLite before returning control to the view. The UI always sees instant success.
3. Network access is opportunistic — `WeatherService` tries the network, falls back to cache. If both fail the forecast still renders with default-neutral factors.
4. Maps have a downloaded-regions registry so the user can pre-fetch tiles for a trip and work fully offline.

## Concurrency

- `@MainActor` on `AppState` and all `ObservableObject` repositories — keeps SwiftUI reads on the main thread without ceremony.
- `actor` on anything that does async I/O or manages a mutable cache (`WeatherService`, `FishClassifier`).
- `Sendable` values for anything crossing an actor boundary (`ForecastResult`, `WeatherData`, `HourlyForecast`).
- No `DispatchQueue`, no completion handlers. `async/await` end-to-end.

## Testing

Unit tests live in `ios/Tests/`. The forecast engine is the primary test target because it's pure — the same input always gives the same output, so regressions are easy to catch. Repository tests spin up an in-memory `AppDatabase.empty()` and exercise the full SQL path.

## Code signing for sideloading

The GitHub Actions workflow builds two artifacts on every push:

1. `Currents-simulator.zip` — an iOS simulator `.app` bundle for [Appetize.io](https://appetize.io).
2. `Currents.ipa` — a device `.ipa` fakesigned with `ldid` using `ios/Currents/App/Currents.entitlements`, ready to sideload via [Sideloader](https://sideloader.app) or install via TrollStore.

The entitlements file enables `platform-application` and `com.apple.private.security.no-sandbox`, which is what unjailbroken sideloaders (and jailbroken systems) expect from an ldid-signed binary.
