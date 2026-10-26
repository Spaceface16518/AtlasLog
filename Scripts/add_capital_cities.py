#!/usr/bin/env python3
"""Merge a curated DC-area city pack from GeoNames cities15000.txt.

Usage: python Scripts/add_capital_cities.py cities15000.txt major_cities.json
Preserves all other bundled cities and uses stable GeoNames IDs on refresh.
"""
import csv
import json
import sys
from pathlib import Path

from generate_major_cities import normalize

CITIES = {
    "4140963": ("Washington", "DC"), "4347242": ("Annapolis", "MD"),
    "4347778": ("Baltimore", "MD"), "4348599": ("Bethesda", "MD"),
    "4355585": ("Frederick", "MD"), "4367175": ("Rockville", "MD"),
    "4369596": ("Silver Spring", "MD"), "4744091": ("Alexandria", "VA"),
    "4744709": ("Arlington", "VA"), "4758023": ("Fairfax", "VA"),
    "4769125": ("Leesburg", "VA"), "4781708": ("Richmond", "VA"),
}
STATES = {"DC": "District of Columbia", "MD": "Maryland", "VA": "Virginia"}


def main(source, destination):
    additions = {}
    with open(source, encoding="utf-8") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if not row or row[0] not in CITIES:
                continue
            if len(row) < 19 or row[8] != "US" or (row[1], row[10]) != CITIES[row[0]]:
                raise ValueError(f"Unexpected GeoNames record: {row[0]}")
            name = "Washington, DC" if row[0] == "4140963" else row[1]
            # Preserve GeoNames aliases; add common local spellings for DC.
            aliases = [row[1], *row[3].split(",")]
            if row[0] == "4140963":
                aliases += ["Washington DC", "Washington D.C.", "DC", "District of Columbia"]
            additions[row[0]] = {
                "id": row[0], "name": name, "normalizedName": normalize(name),
                "alternateNames": sorted({alias for alias in aliases if alias}),
                "latitude": float(row[4]), "longitude": float(row[5]),
                "countryCode": "US", "countryName": "United States",
                "administrativeArea": STATES[row[10]], "population": int(row[14] or 0),
            }
    if set(additions) != set(CITIES):
        raise ValueError("The GeoNames input is missing a required city")
    path = Path(destination)
    existing = json.loads(path.read_text())
    cities = [city for city in existing if city["id"] not in additions] + list(additions.values())
    cities.sort(key=lambda city: (-(city["population"] or 0), city["name"]))
    if len({city["id"] for city in cities}) != len(cities):
        raise ValueError("Duplicate city IDs")
    path.write_text("[\n" + ",\n".join("  " + json.dumps(city, ensure_ascii=False, separators=(",", ":"))
                                     for city in cities) + "\n]\n")
    print(f"Wrote {len(cities)} bundled cities, including {len(additions)} DC-area cities")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
