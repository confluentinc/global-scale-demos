"""
Builds stations.json: {station_name: {lat, lng, lines: [...]}} for every
station across all 9 lines in ../metro_network.py's METRO_LINES, so names are
guaranteed to match what the Kafka payloads carry.

Coordinates come from vendor/dmrc_network.csv (real DMRC station coordinates
from https://github.com/Vinith-J/Delhi-Metro-Network-Analysis), matched by
name using the same cleanup/rename rules used to build metro_network.py's
station lists in the first place (see its module docstring) -- both files are
derived from the same source in the same pass, so they stay consistent.
Any station still unresolved after that falls back to linear interpolation
between its nearest resolved neighbors on the same line; MANUAL_COORDS covers
stations absent from the CSV entirely, or whose row has a data bug (looked up
directly). DISCARD_BAD_CSV_COORDS lists stations whose CSV row parses fine but
is simply wrong (e.g. off by tens of km from its real neighbors) -- these are
treated as unresolved too, so they fall back to the same interpolation rather
than plotting a station miles from where its line actually runs. Both lists
were found by cross-checking straight-line distance between consecutive
stations against the CSV's own (reliable) distance-from-line-start column --
see validate() below, which re-runs that same check on the final output so
future CSV updates get flagged automatically instead of requiring another
manual eyeball pass.
"""
import csv
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from metro_network import METRO_LINES, LINE_DISTANCES_KM  # noqa: E402

# Same cleanup applied when the station lists in metro_network.py were built.
_CONN_BRACKET_RE = re.compile(r'\[Conn:[^\]]*\]')
_CONN_BARE_RE = re.compile(r'Conn:\w+')
_FIRST_LAST_RE = re.compile(r'\((First|Last)[^)]*\)', re.I)

RENAME = {
    'Shyam park': 'Shyam Park',
    'Netaji Subash Place': 'Netaji Subhash Place',
    'Ghevra Metro station': 'Ghevra Metro Station',
    'Bahdurgarh City': 'Bahadurgarh City',
    'ESI BASAI DARAPUR': 'ESI Basai Darapur',
    'Karkar Duma': 'Karkarduma',
    'JAMIA MILLIA ISLAMIA': 'Jamia Millia Islamia',
    'Janak Puri West': 'Janakpuri West',
    'Janak Puri East': 'Janakpuri East',
    'R K Ashram Marg': 'RK Ashram Marg',
    'Barakhamba': 'Barakhamba Road',
    'Supreme Court (Pragati Maidan)': 'Supreme Court',
    'Mayur Vihar Extention': 'Mayur Vihar Extension',
    'Mayur Vihar Phase-1': 'Mayur Vihar-I',
    'Noida City Center': 'Noida City Centre',
    'New Delhi-Airport Express': 'New Delhi',
    'Rohini Sector 18-19': 'Rohini Sector 18,19',
    'Chhattarpur': 'Chhatarpur',
    'Huda City Centre': 'Millennium City Centre Gurugram',
    'Sikandarpur': 'Sikanderpur',
    'Dilli Haat INA': 'Dilli Haat - INA',
}

# Real coordinates looked up directly, for: (a) stations absent from the CSV
# entirely, and (b) CSV rows with an outright data bug (e.g. identical lat/lng).
MANUAL_COORDS = {
    # Post-2019 Blue Line extension past the CSV's last mapped stop.
    "Noida Electronic City": (28.628685, 77.375229),
    # CSV row has identical (and wrong) latitude and longitude values.
    "Shyam Park": (28.6782, 77.391),
    # Pink Line terminus -- can't be interpolated (no station beyond it), so
    # unlike DISCARD_BAD_CSV_COORDS below this one needs a real lookup.
    "Shiv Vihar": (28.721863, 77.289635),
}

# Stations whose CSV row parses fine but is simply wrong -- tens of km away
# from where the station actually is, confirmed by eye against real Delhi
# geography and their real neighbors. All are non-terminus, so discarding
# them here just makes build_line_coords() interpolate them from their
# nearest still-trusted neighbors on the same line, same as a station missing
# from the CSV entirely. Two clusters share suspiciously identical
# coordinates across unrelated stations (28.48086, 77.08489 for "Old
# Faridabad" and all five "Noida Sector 34/52/61/59/62"; 28.65172, 77.22194
# for "Sarai" and "South Extension"), suggesting a geocoding fallback value
# in the source dataset rather than one-off typos.
DISCARD_BAD_CSV_COORDS = {
    "Hindon River", "Mohan Nagar", "Raj Bagh", "Shaheed Nagar",  # Red_Line
    "Lal Quila", "Sarai", "N.H.P.C. Chowk",  # Violet_Line
    "Sector 28 Faridabad", "Old Faridabad",  # Violet_Line (cont.)
    "South Extension",  # Pink_Line
    "Noida Sector 34", "Noida Sector 52", "Noida Sector 61",  # Blue_Line
    "Noida Sector 59", "Noida Sector 62",  # Blue_Line (cont.)
}


def clean_name(name):
    name = _CONN_BRACKET_RE.sub('', name)
    name = _CONN_BARE_RE.sub('', name)
    name = _FIRST_LAST_RE.sub('', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return RENAME.get(name, name)


def load_coords_by_name():
    with open(os.path.join(HERE, "vendor", "dmrc_network.csv")) as f:
        rows = list(csv.DictReader(f))
    by_name = {}
    for row in rows:
        name = clean_name(row["Station Name"])
        by_name[name] = (float(row["Latitude"]), float(row["Longitude"]))
    return by_name


def resolve(name, coords_by_name):
    # MANUAL_COORDS takes priority: it also covers overriding known-bad CSV
    # rows (e.g. Shyam Park), not just filling in stations absent from it.
    if name in MANUAL_COORDS:
        return MANUAL_COORDS[name]
    if name in DISCARD_BAD_CSV_COORDS:
        return None
    if name in coords_by_name:
        return coords_by_name[name]
    return None


def build_line_coords(stations, coords_by_name):
    resolved = [resolve(s, coords_by_name) for s in stations]
    missing = [i for i, r in enumerate(resolved) if r is None]
    if missing:
        # Interpolate each run of missing stations between its resolved neighbors.
        i = 0
        while i < len(resolved):
            if resolved[i] is None:
                start = i - 1
                end = i
                while resolved[end] is None:
                    end += 1
                lat0, lng0 = resolved[start]
                lat1, lng1 = resolved[end]
                span = end - start
                for k in range(start + 1, end):
                    frac = (k - start) / span
                    resolved[k] = (lat0 + (lat1 - lat0) * frac, lng0 + (lng1 - lng0) * frac)
                i = end
            else:
                i += 1
    return resolved


def haversine_km(a, b):
    lat1, lng1 = a
    lat2, lng2 = b
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    x = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(math.sqrt(x))


def validate(stations):
    """
    Safety net: flags any consecutive-station gap whose straight-line distance
    is wildly larger than the CSV's own (reliable) track-distance delta for
    that gap -- the same check that caught Hindon River/Mohan Nagar/Lal
    Quila/etc. Real track curvature can make the straight-line distance a bit
    *less* than the track distance, but never dramatically more, so this
    only flags genuine outliers, not real long segments (e.g. Blue Line's
    Noida Electronic City extension).
    """
    problems = []
    for line, names in METRO_LINES.items():
        dist_km = LINE_DISTANCES_KM[line]
        for i in range(len(names) - 1):
            a, b = names[i], names[i + 1]
            if a not in stations or b not in stations:
                continue
            expected = dist_km[i + 1] - dist_km[i]
            actual = haversine_km(
                (stations[a]["lat"], stations[a]["lng"]),
                (stations[b]["lat"], stations[b]["lng"]),
            )
            if actual > max(3.0, expected * 2.5):
                problems.append((line, a, b, round(expected, 1), round(actual, 1)))
    return problems


def main():
    coords_by_name = load_coords_by_name()
    stations = {}
    all_missing = []

    for line_name, line_stations in METRO_LINES.items():
        coords = build_line_coords(line_stations, coords_by_name)
        for name, coord in zip(line_stations, coords):
            if coord is None:
                all_missing.append((line_name, name))
                continue
            lat, lng = coord
            entry = stations.setdefault(name, {"lat": round(lat, 6), "lng": round(lng, 6), "lines": []})
            if line_name not in entry["lines"]:
                entry["lines"].append(line_name)

    out_path = os.path.join(HERE, "stations.json")
    with open(out_path, "w") as f:
        json.dump(stations, f, indent=2, sort_keys=True)

    all_names = {name for stations_ in METRO_LINES.values() for name in stations_}
    print(f"Wrote {out_path}: {len(stations)} unique stations ({len(all_names)} expected across all lines).")
    if all_missing:
        print("UNRESOLVED (bug):", all_missing)
    else:
        print("All station names accounted for.")

    problems = validate(stations)
    if problems:
        print(f"\nWARNING: {len(problems)} suspicious gap(s) -- likely bad source coordinates:")
        for line, a, b, expected, actual in problems:
            print(f"  {line}: {a!r} -> {b!r}: expected ~{expected}km, got {actual}km straight-line")
    else:
        print("No suspicious gaps -- every consecutive-station distance is consistent with the real track distance.")


if __name__ == "__main__":
    main()
