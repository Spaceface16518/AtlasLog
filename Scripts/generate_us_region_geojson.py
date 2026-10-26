#!/usr/bin/env python3
"""Bundle Census regions/divisions and the NCPC National Capital Region.

Inputs are the 2025 Census cartographic boundary shapefiles: US regions and
divisions at 1:5m, and counties at 1:500k. See README.md for download commands.
Requires pyshp and shapely; no downloads occur inside this generator.
"""

import argparse
import json
from pathlib import Path

import shapefile
from shapely import union_all
from shapely.geometry import mapping, shape

CENSUS_SOURCE = "U.S. Census Bureau 2025 Cartographic Boundary Files"
NCPC_SOURCE = "https://www.ncpc.gov/docs/publications/Resource_Guides_Full_2024.pdf"
REGIONS = {"1": "Northeast", "2": "Midwest", "3": "South", "4": "West"}
DIVISION_PARENTS = {"1": "1", "2": "1", "3": "2", "4": "2", "5": "3",
                    "6": "3", "7": "3", "8": "4", "9": "4"}
# County-equivalent FIPS codes. Virginia independent cities must be included
# explicitly so dissolving the surrounding counties does not leave holes.
CAPITAL_COUNTIES = {
    "11001": "District of Columbia",
    "24031": "Montgomery", "24033": "Prince George's",
    "51013": "Arlington", "51059": "Fairfax", "51107": "Loudoun",
    "51153": "Prince William", "51510": "Alexandria", "51600": "Fairfax",
    "51610": "Falls Church", "51683": "Manassas", "51685": "Manassas Park",
}


def slug(name):
    return name.lower().replace(" ", "-")


def records(path):
    with shapefile.Reader(str(path), encoding="utf-8") as reader:
        return [(entry.record.as_dict(), shape(entry.shape.__geo_interface__))
                for entry in reader.iterShapeRecords()]


def generate(regions_path, divisions_path, counties_path, hierarchy_path, output_path):
    features, nodes = [], []

    def add(region_id, name, level, parent_id, geometry, notes, source, definition):
        # Preserve the source coordinates and topology. NAD83 lon/lat from the
        # Census files is used at cartographic precision (not survey precision).
        if geometry.geom_type not in {"Polygon", "MultiPolygon"} or not geometry.is_valid:
            raise ValueError(f"Invalid polygon geometry for {region_id}")
        feature_id = region_id.replace(":", "-") + "-census-2025"
        point = geometry.representative_point()
        features.append({
            "type": "Feature",
            "properties": {"featureID": feature_id, "regionID": region_id,
                           "membership": "core", "boundaryKind": "geographic",
                           "definition": definition, "source": source},
            "geometry": mapping(geometry),
        })
        nodes.append({
            "id": region_id, "name": name, "level": level, "parentID": parent_id,
            "centroidLatitude": round(point.y, 5), "centroidLongitude": round(point.x, 5),
            "geometryFeatureIDs": [feature_id], "boundaryKind": "geographic", "notes": notes,
        })

    region_records = sorted(records(regions_path), key=lambda item: item[0]["GEOID"])
    division_records = sorted(records(divisions_path), key=lambda item: item[0]["GEOID"])
    if {row["GEOID"] for row, _ in region_records} != set(REGIONS):
        raise ValueError("Expected all four Census regions")
    if {row["GEOID"] for row, _ in division_records} != set(DIVISION_PARENTS):
        raise ValueError("Expected all nine Census divisions")

    for row, geometry in region_records:
        name = row["NAME"]
        if name != REGIONS[row["GEOID"]]:
            raise ValueError("Census region classification changed")
        add(f"macro:us-{slug(name)}", f"U.S. {name}", "macroRegion",
            "subcontinent:northern-america", geometry, "U.S. Census geographic region.",
            f"{CENSUS_SOURCE}, regions 1:5,000,000", f"{name} Census region")

    for row, geometry in division_records:
        name = row["NAME"]
        parent = REGIONS[DIVISION_PARENTS[row["GEOID"]]]
        add(f"travel:us-{slug(name)}", f"U.S. {name}", "travelRegion",
            f"macro:us-{slug(parent)}", geometry, "U.S. Census geographic division.",
            f"{CENSUS_SOURCE}, divisions 1:5,000,000", f"{name} Census division")

    members = {row["GEOID"]: (row, geometry) for row, geometry in records(counties_path)
               if row["GEOID"] in CAPITAL_COUNTIES}
    if set(members) != set(CAPITAL_COUNTIES):
        raise ValueError("Missing National Capital Region county equivalents")
    for code, (row, _) in members.items():
        if row["NAME"] != CAPITAL_COUNTIES[code]:
            raise ValueError(f"Unexpected county name for {code}: {row['NAME']}")
    capital = union_all([members[code][1] for code in sorted(members)])
    add("travel:washington-capital", "Washington Capital Region", "travelRegion",
        "travel:us-south-atlantic", capital,
        "Washington, DC and nearby Maryland and Virginia communities, following the National Capital Planning Commission’s definition.",
        f"{CENSUS_SOURCE}, counties 1:500,000; membership: {NCPC_SOURCE}",
        "National Capital Region: DC; Montgomery and Prince George's counties in Maryland; "
        "Arlington, Fairfax, Loudoun and Prince William counties in Virginia; "
        "Alexandria, Fairfax, Falls Church, Manassas and Manassas Park independent cities. "
        "Dissolved county-equivalent boundaries; excludes Baltimore, Annapolis and Frederick.")

    # Replace only this pack's nodes; preserve unrelated hierarchy entries.
    existing = json.loads(hierarchy_path.read_text())
    generated_ids = {node["id"] for node in nodes}
    hierarchy = [node for node in existing if node["id"] not in generated_ids] + nodes
    ids = {node["id"] for node in hierarchy}
    if len(ids) != len(hierarchy) or any(node["parentID"] not in ids for node in nodes):
        raise ValueError("Duplicate region IDs or missing parents")
    hierarchy_path.write_text(json.dumps(hierarchy, ensure_ascii=False, indent=2) + "\n")
    output_path.write_text(json.dumps({"type": "FeatureCollection", "features": features},
                                     ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Wrote {len(features)} U.S. regions ({output_path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["regions", "divisions", "counties", "hierarchy", "output"]:
        parser.add_argument(f"--{name}", type=Path, required=True)
    args = parser.parse_args()
    generate(args.regions, args.divisions, args.counties, args.hierarchy, args.output)
