#!/usr/bin/env python3
"""Compose AtlasLog continent and subcontinent geometry from country geometry.

The country-to-region classification comes from the English table on the
United Nations Statistics Division M49 overview page. The checked-in Natural
Earth country polygons remain the only geometry source.

Usage:
  python3 Scripts/generate_composed_region_geojson.py \
    --m49-html /tmp/m49-overview.html \
    --countries AtlasLog/Resources/country_boundaries.geojson \
    --hierarchy AtlasLog/Resources/region_hierarchy.json \
    --output AtlasLog/Resources/composed_regions.geojson
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

M49_SOURCE = (
    "United Nations Statistics Division M49 geographic regions "
    "(unstats.un.org/unsd/methodology/m49)"
)
NATURAL_EARTH_SOURCE = "Natural Earth Admin 0 Countries 1:110m"

# Natural Earth includes map units that M49 either treats as part of another
# statistical area or does not list as a separate country/area. Keeping these
# assignments explicit makes the composition deterministic and reviewable.
CLASSIFICATION_OVERRIDES = {
    "CYN": ("Asia", "Western Asia"),
    "SOL": ("Africa", "Eastern Africa"),
    "TW": ("Asia", "Eastern Asia"),
    "XK": ("Europe", "Southern Europe"),
}

# AtlasLog intentionally uses the common six-continent travel taxonomy.
IGNORED_COUNTRY_CODES = {
    "AQ": "AtlasLog does not expose Antarctica as a selectable continent.",
}

CONTINENT_ORDER = (
    "Africa",
    "Asia",
    "Europe",
    "North America",
    "South America",
    "Oceania",
)


class M49TableParser(HTMLParser):
    """Extract rows from the official page's English download table."""

    def __init__(self) -> None:
        super().__init__()
        self.in_table = False
        self.in_cell = False
        self.current_cell: list[str] = []
        self.current_row: list[str] = []
        self.rows: list[list[str]] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        attributes = dict(attrs)
        if tag == "table" and attributes.get("id") == "downloadTableEN":
            self.in_table = True
        elif self.in_table and tag == "tr":
            self.current_row = []
        elif self.in_table and tag in {"td", "th"}:
            self.in_cell = True
            self.current_cell = []

    def handle_data(self, data: str) -> None:
        if self.in_cell:
            self.current_cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if self.in_table and tag in {"td", "th"}:
            self.current_row.append(" ".join("".join(self.current_cell).split()))
            self.in_cell = False
        elif self.in_table and tag == "tr":
            if self.current_row:
                self.rows.append(self.current_row)
        elif self.in_table and tag == "table":
            self.in_table = False


def slug(value: str) -> str:
    return "-".join(
        "".join(
            character.lower() if character.isalnum() else " "
            for character in value
        ).split()
    )


def load_m49_classification(path: Path) -> dict[str, tuple[str, str]]:
    parser = M49TableParser()
    parser.feed(path.read_text(encoding="utf-8"))
    if len(parser.rows) < 2:
        raise ValueError("The UN M49 English table was not found or contained no data.")

    header = parser.rows[0]
    expected = {
        "Region Name",
        "Sub-region Name",
        "Intermediate Region Name",
        "ISO-alpha2 Code",
    }
    if not expected.issubset(header):
        raise ValueError("The UN M49 table columns have changed.")

    column = {name: header.index(name) for name in expected}
    classification: dict[str, tuple[str, str]] = {}
    for row in parser.rows[1:]:
        if len(row) != len(header):
            continue
        code = row[column["ISO-alpha2 Code"]].upper()
        region = row[column["Region Name"]]
        intermediate = row[column["Intermediate Region Name"]]
        subregion = intermediate or row[column["Sub-region Name"]]
        if code and region and subregion:
            classification[code] = (region, subregion)
    if len(classification) < 240:
        raise ValueError(
            f"Expected at least 240 M49 country/area rows, found {len(classification)}."
        )
    return classification


def atlas_continent(region: str, subcontinent: str) -> str:
    if region != "Americas":
        return region
    return "South America" if subcontinent == "South America" else "North America"


def polygons(feature: dict[str, Any]) -> list[Any]:
    geometry = feature["geometry"]
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    raise ValueError(f"Unsupported country geometry type: {geometry['type']}")


def center(features: list[dict[str, Any]]) -> tuple[float, float]:
    points = [
        point
        for feature in features
        for polygon in polygons(feature)
        for ring in polygon
        for point in ring
    ]
    latitudes = [point[1] for point in points]
    longitudes = sorted(point[0] % 360 for point in points)

    gaps = [
        ((longitudes[(index + 1) % len(longitudes)] - longitude) % 360, index)
        for index, longitude in enumerate(longitudes)
    ]
    _, gap_index = max(gaps)
    start = longitudes[(gap_index + 1) % len(longitudes)]
    end = longitudes[gap_index]
    if end < start:
        end += 360
    longitude = ((start + end) / 2 + 180) % 360 - 180
    latitude = (min(latitudes) + max(latitudes)) / 2
    return round(latitude, 4), round(longitude, 4)


def composed_feature(
    region_id: str, name: str, members: list[dict[str, Any]]
) -> dict[str, Any]:
    member_polygons = [
        polygon for feature in members for polygon in polygons(feature)
    ]
    return {
        "type": "Feature",
        "properties": {
            "featureID": f"{region_id.replace(':', '-')}-countries",
            "regionID": region_id,
            "membership": "core",
            "boundaryKind": "geographic",
            "definition": f"{name}, composed from {len(members)} country geometries",
            "source": f"{NATURAL_EARTH_SOURCE}; membership: {M49_SOURCE}",
        },
        "geometry": {
            "type": "MultiPolygon",
            "coordinates": member_polygons,
        },
    }


def hierarchy_node(
    region_id: str,
    name: str,
    level: str,
    parent_id: str | None,
    members: list[dict[str, Any]],
) -> dict[str, Any]:
    latitude, longitude = center(members)
    return {
        "id": region_id,
        "name": name,
        "level": level,
        "parentID": parent_id,
        "centroidLatitude": latitude,
        "centroidLongitude": longitude,
        "geometryFeatureIDs": [f"{region_id.replace(':', '-')}-countries"],
        "boundaryKind": "geographic",
        "notes": f"Country membership follows {M49_SOURCE}.",
    }


def generate(
    m49_html: Path, countries_path: Path, hierarchy_path: Path, output_path: Path
) -> None:
    classification = load_m49_classification(m49_html)
    classification.update(CLASSIFICATION_OVERRIDES)

    country_collection = json.loads(countries_path.read_text(encoding="utf-8"))
    country_features = country_collection["features"]
    continents: dict[str, list[dict[str, Any]]] = defaultdict(list)
    subcontinents: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    unmatched: list[str] = []

    for feature in country_features:
        code = feature["properties"]["isoCode"].upper()
        if code in IGNORED_COUNTRY_CODES:
            continue
        assignment = classification.get(code)
        if assignment is None:
            unmatched.append(code)
            continue
        region, subcontinent = assignment
        continent = atlas_continent(region, subcontinent)
        continents[continent].append(feature)
        subcontinents[(continent, subcontinent)].append(feature)

    if unmatched:
        raise ValueError(
            "Country geometries without an M49 assignment or explicit override: "
            + ", ".join(sorted(unmatched))
        )
    if set(continents) != set(CONTINENT_ORDER):
        raise ValueError(f"Unexpected continent set: {sorted(continents)}")

    features: list[dict[str, Any]] = []
    nodes: list[dict[str, Any]] = []
    for continent in CONTINENT_ORDER:
        continent_id = f"continent:{slug(continent)}"
        members = continents[continent]
        features.append(composed_feature(continent_id, continent, members))
        nodes.append(
            hierarchy_node(continent_id, continent, "continent", None, members)
        )

        children = sorted(
            (
                (subcontinent, child_members)
                for (parent, subcontinent), child_members in subcontinents.items()
                if parent == continent
            ),
            key=lambda item: item[0],
        )
        for subcontinent, child_members in children:
            subcontinent_id = f"subcontinent:{slug(subcontinent)}"
            features.append(
                composed_feature(subcontinent_id, subcontinent, child_members)
            )
            nodes.append(
                hierarchy_node(
                    subcontinent_id,
                    subcontinent,
                    "subcontinent",
                    continent_id,
                    child_members,
                )
            )

    output_path.write_text(
        json.dumps(
            {"type": "FeatureCollection", "features": features},
            ensure_ascii=False,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )

    existing_nodes = json.loads(hierarchy_path.read_text(encoding="utf-8"))
    manual_nodes = [
        node
        for node in existing_nodes
        if node["level"] not in {"continent", "subcontinent"}
    ]
    hierarchy_path.write_text(
        json.dumps(nodes + manual_nodes, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(
        f"Composed {len(continents)} continents and {len(subcontinents)} "
        f"subcontinents from {len(country_features) - len(IGNORED_COUNTRY_CODES)} "
        "country geometries."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--m49-html", type=Path, required=True)
    parser.add_argument("--countries", type=Path, required=True)
    parser.add_argument("--hierarchy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    generate(
        arguments.m49_html,
        arguments.countries,
        arguments.hierarchy,
        arguments.output,
    )


if __name__ == "__main__":
    main()
