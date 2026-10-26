#!/usr/bin/env python3
"""Convert Natural Earth Admin 0 1:110m shapefile to compact AtlasLog GeoJSON.

Usage: uv run --with pyshp python Scripts/generate_country_geojson.py path/to/ne_110m_admin_0_countries.shp AtlasLog/Resources/country_boundaries.geojson
"""
import json
import sys
import shapefile

def main(source: str, destination: str) -> None:
    reader = shapefile.Reader(source)
    names = [field[0] for field in reader.fields[1:]]
    features = []
    for record in reader.iterShapeRecords():
        attrs = dict(zip(names, record.record))
        code = attrs.get("ISO_A2_EH") or attrs.get("ISO_A2")
        if not code or code == "-99":
            code = attrs.get("ADM0_A3") or attrs.get("SOV_A3")
        feature = record.shape.__geo_interface__
        features.append({
            "type": "Feature",
            "properties": {
                "featureID": f"country-{code}", "regionID": f"country:{code}",
                "membership": "core", "boundaryKind": "administrative",
                "definition": attrs.get("NAME_EN") or attrs.get("NAME") or code,
                "source": "Natural Earth Admin 0 Countries 1:110m",
                "isoCode": code,
            },
            "geometry": feature,
        })
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump({"type": "FeatureCollection", "features": features}, handle, separators=(",", ":"))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_country_geojson.py input.shp output.geojson")
    main(sys.argv[1], sys.argv[2])
