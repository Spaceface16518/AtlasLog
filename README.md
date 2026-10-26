# AtlasLog

AtlasLog is a private, local-first iPhone travel map. A full-screen Apple map and persistent native drawer let you record cities and landmarks, distinguish meaningful travel from limited or pass-through visits, maintain a wishlist, flag places to revisit, import selected geotagged photos, and review a compact passport-style summary.

The product name is centralized in `AppIdentity`; stored data and domain APIs do not depend on the display name.

## MVP features

- Full-screen SwiftUI `Map` with standard flat and satellite/realistic modes.
- Cities, countries, travel regions, large regions, subcontinents, and continents as selectable display levels.
- Tap a bundled region boundary to highlight it and reveal its selected row in Explore, including unvisited regions. Tap empty water to clear the selection.
- Status treatments for meaningful visits, limited visits, wishlist places, and want-to-return places.
- The sheet's All, Visited, Meaningful, Want to visit, and Want to return filters apply to cities and every region layer. Counts reflect matching rows; All includes untracked catalog regions. Selecting an excluded region on the map returns the sheet to All so its row can be revealed.
- Offline bundled major-city search with deterministic exact/prefix/token/population ranking.
- Apple Maps completion and selected-result resolution when a network is available.
- Manual city, landmark, and coordinate entry plus editing and deletion.
- Explicit multi-selection photo import, GPS/PHAsset metadata extraction, bounded processing, nearest-city matching, review, deduplication, and incremental saves.
- Complete Natural Earth Admin 0 country geometry at 1:110m, country-composed
  UN M49 continent/subcontinent geometry, and representative travel-region
  geometry, plus all four U.S. Census regions, all nine Census divisions, and
  Washington Capital Region.
- Derived country/U.S. region/subcontinent/continent roll-ups with manual overrides and hierarchy roll-ups from manually visited travel regions.
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

On October 26, 2026, Xcode 27.1 passed **64 distinct tests** across focused and
regression runs on a regular iPhone 18 Pro simulator running iOS 27.0 (24A434):
55 Swift Testing tests and nine XCTest UI tests. The two successful runs (one
focused UI test and the remaining 63 tests) had no failures, skips, or reported
runtime warnings. The final build also succeeded.

Map-selection coverage directly taps Europe, Africa, France, and Northern Africa,
asserts that the matching row is selected and visible, clears selection over
water, returns from Passport by tapping the same region, and checks that travel
totals remain unchanged. It also verifies that the selected label stays near the
tap and that switching to Cities clears it. Geometry tests cover overlapping
U.S. regions, polygon holes, islands, empty water, and active-layer filtering.
The passing UI test captured [Europe](docs/evidence/map-region-selection/europe-selected.png)
and [France](docs/evidence/map-region-selection/france-selected.png) screenshots.

Status-filter checks cover all five filters on saved cities and derived countries,
empty results and Show all on every region layer, manual region-status edits,
and selecting a region hidden by the current filter. The passing UI test captured
[Meaningful continents](docs/evidence/status-filters/meaningful-continents.png)
and [a wishlist region](docs/evidence/status-filters/wishlist-region.png).

Coverage includes V1-to-V2 migration, area roll-ups and deletion, manual overrides,
photo matching, invalid-date rejection, visit and wishlist persistence, private
notes, passport totals, settings, and the photo-import entry screen. The new
coverage checks DC and nearby cities, all nine Census divisions including Alaska
and Hawaii, the Capital Region's included independent cities and excluded nearby
cities, hierarchy integrity, refreshing old visits, and removing the last visit.
A DC photo matches the bundled city without geocoding; its regional statuses
remain derived and clear when the visit is deleted. UI regressions verify DC's
two travel-region totals, relaunch persistence, regional map navigation, and
clearing selected-region labels across all six layers.

The region and city generators reproduce the checked-in output byte for byte.
All 30 original city records and all previous hierarchy nodes are preserved.

Device Hub checks for this change confirmed bundled Washington search, saving
a meaningful DC visit, one city/one country/two travel regions, and the new
U.S. South, U.S. South Atlantic, and Washington Capital Region Passport entries.

Earlier interactive Device Hub checks on the same regular iPhone simulator
covered meaningful visits with notes, Passport totals, country shading, photo
selection/review/import (San Francisco), and an Apple Maps Paris result retaining
France / FR. No physical-phone validation was performed. iOS 27.0 was the latest
installed runtime supporting the regular iPhone; the available iOS 27.1 runtime
supported only iPhone Duo. The offline catalog now contains 42 cities, including
12 in and around DC; the geographic limitations below still apply.

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

### U.S. and Washington coverage

`us_regions.geojson` adds 14 regions: four Census regions on the **Large regions**
layer, nine Census divisions on **Travel regions**, and **Washington Capital
Region** on **Travel regions**. The Census divisions cover all 50 states and DC;
territories are not part of that classification. The Capital Region uses NCPC's
definition rather than a rectangular approximation: DC, Montgomery and Prince
George's counties in Maryland, Arlington/Fairfax/Loudoun/Prince William counties
in Virginia, and the five enclosed Virginia independent cities. Baltimore,
Annapolis, Frederick and Richmond are outside this local region.

A DC visit derives Washington Capital Region → U.S. South Atlantic → U.S. South
→ Northern America → North America, plus United States. Both travel regions
count in Passport. This nesting follows Census statistical geography, which
places DC in South Atlantic, not Middle Atlantic. Existing visits refresh at
launch; deleting the last visit clears derived status. Explicit manual overrides
remain authoritative, and legacy approximate cultural regions still require
confirmation. U.S. photo-import regions stay derived rather than becoming
permanent manual marks. All region layers draw their bundled boundaries. Map
taps select the containing region without changing travel status or moving the
camera; overlapping regions prefer the one with the smaller bounding footprint.
Selecting a region from the list still frames its geometry where it does not
cross the date line.

Download and unpack the official source files into a temporary directory:

```sh
mkdir -p /tmp/atlaslog-us-regions
cd /tmp/atlaslog-us-regions
curl -fLO https://www2.census.gov/geo/tiger/GENZ2025/shp/cb_2025_us_region_5m.zip
curl -fLO https://www2.census.gov/geo/tiger/GENZ2025/shp/cb_2025_us_division_5m.zip
curl -fLO https://www2.census.gov/geo/tiger/GENZ2025/shp/cb_2025_us_county_500k.zip
curl -fLO https://download.geonames.org/export/dump/cities15000.zip
for archive in *.zip; do unzip -o "$archive"; done
```

Then, from the repository root:

```sh
uv run --with shapely --with pyshp python Scripts/generate_us_region_geojson.py \
  --regions /tmp/atlaslog-us-regions/cb_2025_us_region_5m.shp \
  --divisions /tmp/atlaslog-us-regions/cb_2025_us_division_5m.shp \
  --counties /tmp/atlaslog-us-regions/cb_2025_us_county_500k.shp \
  --hierarchy AtlasLog/Resources/region_hierarchy.json \
  --output AtlasLog/Resources/us_regions.geojson
python3 Scripts/add_capital_cities.py /tmp/atlaslog-us-regions/cities15000.txt \
  AtlasLog/Resources/major_cities.json
```

The generator validates source IDs/names and polygon topology, dissolves the
Capital Region's internal county/city borders, and preserves unrelated hierarchy
nodes. Census NAD83 longitude/latitude coordinates are retained at cartographic
precision, not survey precision. Source download SHA-256 values (October 26,
2026) are recorded in [the source manifest](Scripts/us_region_sources.json).
GeoNames updates its extract, so future city refreshes may change populations
and aliases. Neither generator changes stable region or city IDs.

## Data sources

- GeoNames city schema/data, CC BY 4.0: `geonames.org`.
- Natural Earth Admin 0 1:110m country geometry, public domain: `naturalearthdata.com`.
- United Nations Statistics Division M49 geographic regions for country,
  subregion, and region membership: `unstats.un.org`.
- U.S. Census Bureau 2025 cartographic boundaries and NCPC National Capital
  Region definition; provenance and exact source links are in the in-app acknowledgements.
- Apple Maps for map tiles, online suggestions, selected-place resolution, and reverse geocoding.

The in-app acknowledgement screen reads `Resources/DataAttributions.md`.

## Privacy and travel semantics

Travel records remain in the local SwiftData store. Photo import reads only items the person explicitly selects. AtlasLog stores an available asset identifier for deduplication, coordinates/dates required for the confirmed visit, and the resulting place record. It never persists original photo bytes, full-size copies, faces, captions, or album membership.

A **meaningful visit** is a visited place the person wants included in main totals; airport-only, pass-through, or unwanted childhood classifications can remain visited but limited. **Want to visit** is for an unvisited destination. **Want to return** keeps a place visited while also surfacing it with future destinations.

## Known limitations

- Cultural travel boundaries are interpretive; Cascadia is explicitly an app-defined travel grouping, not an authoritative cultural border.
- The four U.S. large regions have boundaries; the Andes entry still has only a centroid.
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
