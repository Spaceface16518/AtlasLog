# AtlasLog

AtlasLog is a private, local-first iPhone travel map. A full-screen Apple map and persistent native drawer let you record cities and landmarks, distinguish meaningful travel from limited or pass-through visits, maintain a wishlist, flag places to revisit, import selected geotagged photos, and review a compact passport-style summary.

The product name is centralized in `AppIdentity`; stored data and domain APIs do not depend on the display name.

## MVP features

- Full-screen SwiftUI `Map` with standard flat and satellite/realistic modes.
- Cities, countries, travel regions, large regions, subcontinents, and continents as selectable display levels.
- Status treatments for meaningful visits, limited visits, wishlist places, and want-to-return places.
- Offline bundled major-city search with deterministic exact/prefix/token/population ranking.
- Apple Maps completion and selected-result resolution when a network is available.
- Manual city, landmark, and coordinate entry plus editing and deletion.
- Explicit multi-selection photo import, GPS/PHAsset metadata extraction, bounded processing, nearest-city matching, review, deduplication, and incremental saves.
- Complete Natural Earth Admin 0 country geometry at 1:110m, country-composed
  UN M49 continent/subcontinent geometry, and representative travel-region
  geometry.
- Derived country/subcontinent/continent roll-ups with manual overrides and hierarchy roll-ups from manually visited travel regions.
- Passport metrics and hierarchical travel lists.
- Local SwiftData persistence, debug-only sample journey, privacy controls, acknowledgements, and delete-all.
- Swift Testing domain tests and a small XCTest UI flow.

## Architecture

The app uses a lightweight feature-oriented layout under `AtlasLog/Features`. SwiftData V2 models contain user data only, with separate dated visits per place and a migration from V1 travel history. Bundled catalogs remain `Codable` values cached in actors. `TravelRecordService` owns status invariants, place upserts, and area roll-ups; `PassportStatisticsService` owns summary aggregation. Derived areas are refreshed when the app opens so existing visits receive current region totals. MapKit/Photos boundaries are small injected services. Photo work is coordinated by `PhotoImportProcessor`, with at most four representations processed concurrently and serialized reverse-geocoding fallback.

There are no third-party runtime dependencies, accounts, CloudKit, authentication, or custom map engine.

## Requirements and build

- macOS with Xcode 26.6 or later.
- iOS 26 simulator or device.
- Swift 6 with complete strict-concurrency checking.

```sh
xcodebuild -project AtlasLog.xcodeproj -scheme AtlasLog \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild -project AtlasLog.xcodeproj -scheme AtlasLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The app does not request live-location access at launch.

### Latest validation

On October 26, 2026, Xcode 27.1 passed the 45-test baseline suite on a regular iPhone 18 Pro
simulator running iOS 27.0: 41 Swift Testing tests and four XCTest UI tests.
Coverage includes V1-to-V2 migration, area roll-ups and deletion, photo matching,
invalid-date rejection, visit and wishlist persistence, private notes, passport
totals, map-level navigation, settings, and the photo-import entry screen.
Regression coverage also verifies that geocoded photos retain their country
for Passport totals and that cleared or retried searches discard stale errors.
A subsequent targeted UI regression passed for clearing selected-region labels
across all six map layers. Returning to the original layer keeps the label cleared
until another region is selected.

Interactive checks through Device Hub on that same regular iPhone simulator
covered city search, saving a meaningful visit with a note, navigation after
saving, Passport metrics, country map shading, and photo selection/review/import.
The final photo-import retest resolved an Apple simulator sample to San Francisco,
United States, and correctly added one city and one country. No physical-phone
validation was performed. iOS 27.0 was the latest installed runtime supporting
the regular iPhone; the available iOS 27.1 runtime supported only iPhone Duo.
The 30-city fixture and other MVP limitations below still apply.

## Bundled resource generation

The checked-in `major_cities.json` is a clearly labeled, globally distributed development fixture. It is sufficient to exercise offline search and import matching but is not the complete GeoNames `cities15000` catalog. Generate the full catalog after downloading `cities15000.txt`:

```sh
python3 Scripts/generate_major_cities.py cities15000.txt AtlasLog/Resources/major_cities.json
```

Country geometry is generated from Natural Earth Admin 0 Countries 1:110m:

```sh
uv run --with pyshp python Scripts/generate_country_geojson.py \
  ne_110m_admin_0_countries.shp AtlasLog/Resources/country_boundaries.geojson
```

Continent and subcontinent membership follows the United Nations Statistics
Division M49 geographic hierarchy. Refresh the checked-in composed geometry
from a downloaded copy of the official English overview table:

```sh
curl -L https://unstats.un.org/unsd/methodology/m49/overview/ \
  -o /tmp/m49-overview.html
uv run --with shapely python Scripts/generate_composed_region_geojson.py \
  --m49-html /tmp/m49-overview.html \
  --countries AtlasLog/Resources/country_boundaries.geojson \
  --hierarchy AtlasLog/Resources/region_hierarchy.json \
  --output AtlasLog/Resources/composed_regions.geojson
```

AtlasLog maps the M49 Americas into its existing six-continent taxonomy:
South America remains separate, while Northern America, Central America, and
the Caribbean compose North America. The generator documents explicit
assignments for the separately drawn Natural Earth map units that M49 does not
list separately (Northern Cyprus, Kosovo, Somaliland, and Taiwan), and excludes
Antarctica because it is not an AtlasLog display level.

Country shapes are dissolved into each aggregate before writing GeoJSON. This
removes shared country edges so continent and subcontinent map levels render
only their respective aggregate borders; the country level continues to use
the original country resource.

Builds never download resources. Generated JSON and GeoJSON are checked into the app target.

## Data sources

- GeoNames city schema/data, CC BY 4.0: `geonames.org`.
- Natural Earth Admin 0 1:110m country geometry, public domain: `naturalearthdata.com`.
- United Nations Statistics Division M49 geographic regions for country,
  subregion, and region membership: `unstats.un.org`.
- Apple Maps for map tiles, online suggestions, selected-place resolution, and reverse geocoding.

The in-app acknowledgement screen reads `Resources/DataAttributions.md`.

## Privacy and travel semantics

Travel records remain in the local SwiftData store. Photo import reads only items the person explicitly selects. AtlasLog stores an available asset identifier for deduplication, coordinates/dates required for the confirmed visit, and the resulting place record. It never persists original photo bytes, full-size copies, faces, captions, or album membership.

A **meaningful visit** is a visited place the person wants included in main totals; airport-only, pass-through, or unwanted childhood classifications can remain visited but limited. **Want to visit** is for an unvisited destination. **Want to return** keeps a place visited while also surfacing it with future destinations.

## Known limitations

- Cultural travel boundaries are interpretive; Cascadia is explicitly an app-defined travel grouping, not an authoritative cultural border.
- Large-region entries do not yet have geometry and focus via their centroid.
- Natural Earth 1:110m omits the tiny countries of Micronesia and Polynesia, so
  those two M49 subregions will appear only after the country source moves to a
  finer scale.
- The bundled city file is a sample fixture rather than the full GeoNames `cities15000` extract.
- Apple Maps search, reverse geocoding, and uncached map imagery require network access.
- Photo location metadata may be absent or stripped.
- Nearby-city matching uses a 50 km threshold and can require manual correction.
- There is no synchronization or app-managed backup beyond normal device backup behavior.
- The MVP has no activity or achievement tracking.

## Roadmap (not implemented)

- CloudKit synchronization and account-independent export/import.
- Generic achievements; GPX and workout imports.
- Trip timelines and flight history.
- Widgets and App Intents.
- More travel-region definitions and user-editable region boundaries.
- Optional activity domains such as hikes, runs, rides, and waterways only after a future product decision.
