#!/usr/bin/env python3
"""Generate AtlasLog major_cities.json from GeoNames cities15000.txt.

Usage: python3 Scripts/generate_major_cities.py cities15000.txt AtlasLog/Resources/major_cities.json
GeoNames columns: https://download.geonames.org/export/dump/readme.txt
"""
import csv
import json
import sys
import unicodedata

def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return " ".join("".join(c if c.isalnum() else " " for c in value).split())

def main(source: str, destination: str) -> None:
    records = []
    with open(source, encoding="utf-8") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 19:
                continue
            records.append({
                "id": row[0], "name": row[1], "normalizedName": normalize(row[1]),
                "alternateNames": [name for name in row[3].split(",") if name][:12],
                "latitude": float(row[4]), "longitude": float(row[5]),
                "countryCode": row[8], "countryName": row[8],
                "administrativeArea": row[10] or None, "population": int(row[14] or 0),
            })
    records.sort(key=lambda city: (-city["population"], city["name"]))
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, separators=(",", ":"))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_major_cities.py cities15000.txt output.json")
    main(sys.argv[1], sys.argv[2])
