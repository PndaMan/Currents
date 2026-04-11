# Data Model

All data lives in a single SQLite file managed by GRDB. The schema is intentionally flat — no PostGIS, no triggers, no views — because the app needs to run on a phone with no cloud to fall back on.

## Tables

### `species`
Seeded from `Core/DB/SeedData/SpeciesSeedData.swift` on first launch (200+ global game fish).

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK |  |
| `commonName` | TEXT |  |
| `scientificName` | TEXT |  |
| `family` | TEXT |  |
| `habitat` | TEXT | freshwater / saltwater / brackish |
| `optimalTempC` | REAL | feeds into ForecastEngine |
| `minTempC`, `maxTempC` | REAL |  |
| `regulations` | TEXT | bag limit / size limit notes |
| `imageURL` | TEXT | optional CDN URL, cached locally |

### `spot`
User-saved fishing spots. `geohash` is stored as a precision-7 prefix for fast radius queries.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `name` | TEXT |  |
| `latitude`, `longitude` | REAL |  |
| `geohash` | TEXT | precision 7 |
| `waterbodyId` | INTEGER FK | optional |
| `notes` | TEXT |  |
| `isPrivate` | INTEGER | 0/1 |
| `createdAt` | TIMESTAMP |  |

### `catch`
The centerpiece. One row per fish logged.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `speciesId` | INTEGER FK → species |  |
| `spotId` | TEXT FK → spot | nullable — catches can exist without a named spot |
| `latitude`, `longitude` | REAL | always captured even when linked to a spot |
| `caughtAt` | TIMESTAMP |  |
| `weightKg`, `lengthCm` | REAL |  |
| `waterTempC` | REAL |  |
| `photoFilename` | TEXT | points to PhotoManager-owned file |
| `gearLoadoutId` | INTEGER FK |  |
| `notes` | TEXT |  |
| `forecastScoreAtCapture` | INTEGER | frozen score for later analytics |
| `pressureAtCapture` | REAL |  |

Capturing the forecast score *at the moment of capture* means analytics can retroactively validate whether the model actually predicts catches — a regression test for the ForecastEngine on real-world data.

### `gear_catalog`
A catalog of popular rods / reels / lures / flies seeded from `GearCatalogSeedData.swift`.

### `gear_loadout`
A named combination of catalog items — `"Surf rod + 6 oz sinker + bait hook"` — that the user links to a catch in one tap.

### `trip`
Groups catches under a named outing. Timeline analytics aggregate catches by trip for "best session ever" style insights.

### `waterbody`
Optional join table linking spots to a named lake / river / coastline. Populated from a bundled geojson where available.

### `spawning_zone`
Bundled polygons describing seasonal spawning grounds. `ForecastEngine` boosts the score when the user is inside an active zone.

### `weather_observation`
A cache of successful `WeatherService` fetches, keyed by coarse coordinate. Used as the fallback when the app goes offline.

## Indexes

```sql
CREATE INDEX idx_catch_speciesId ON "catch" (speciesId);
CREATE INDEX idx_catch_spotId    ON "catch" (spotId);
CREATE INDEX idx_catch_caughtAt  ON "catch" (caughtAt);
CREATE INDEX idx_spot_geohash    ON spot (geohash);
```

Geohash-prefix lookups are fast enough for the expected dataset size (a heavy user might have a few thousand catches; SQLite on a modern iPhone plows through that).

## Migrations

Schema migrations live in `AppDatabase.swift` as `DatabaseMigrator` steps. New versions are additive — we never drop user data.
