"""
Pure metro network model: real station order for a 9-line network, real
per-station distance-from-line-start (km, from a published network dataset),
and route/offset math derived from it. No env vars, no Kafka/Schema-Registry
clients, no side effects requiring credentials -- safe to import from anything
that just needs the network data (e.g. live-map/server.py), without dragging
in python-producer.py's Kafka connection setup.

Station lists + distances were extracted from
https://github.com/Vinith-J/Delhi-Metro-Network-Analysis (DelhiMetroNetwork.csv),
verified by confirming the distance-sorted order matches real DMRC geography,
with station-name cleanup (stripping "[Conn: X]"/"(First/Last Station)"
annotations, fixing typos, and aligning spelling with this project's existing
conventions so identical stations use identical names across lines -- this is
what makes cross-line interchanges resolve correctly). Not modeled: the Green
Line's short Ashok Park Main<->Kirti Nagar branch, the Blue Line's Vaishali
branch, Rapid Metro (Gurugram) and the Aqua Line (Noida-Greater Noida) --
different operators, not part of DMRC's 9 lines.
"""

_RED_LINE_STATIONS = [
    "Shaheed Sthal", "Hindon River", "Arthala", "Mohan Nagar", "Shyam Park",
    "Major Mohit Sharma", "Raj Bagh", "Shaheed Nagar", "Dilshad Garden", "Jhil Mil",
    "Mansarovar Park", "Shahdara", "Welcome", "Seelampur", "Shastri Park",
    "Kashmere Gate", "Tis Hazari", "Pul Bangash", "Pratap Nagar", "Shastri Nagar",
    "Inderlok", "Kanhaiya Nagar", "Keshav Puram", "Netaji Subhash Place",
    "Kohat Enclave", "Pitam Pura", "Rohini East", "Rohini West", "Rithala",
]
_RED_LINE_DIST_KM = [
    0.0, 1.0, 2.5, 3.2, 4.5, 5.7, 6.9, 8.2, 9.4, 10.3, 11.4, 12.5, 13.7, 14.8, 16.4,
    18.5, 19.7, 20.6, 21.4, 23.1, 24.3, 25.5, 26.2, 27.4, 28.6, 29.6, 30.4, 31.7, 32.7,
]

_YELLOW_LINE_STATIONS = [
    "Samaypur Badli", "Rohini Sector 18,19", "Haiderpur Badli Mor", "Jahangirpuri",
    "Adarsh Nagar", "Azadpur", "Model Town", "Guru Tegh Bahadur Nagar",
    "Vishwavidyalaya", "Vidhan Sabha", "Civil Lines", "Kashmere Gate", "Chandni Chowk",
    "Chawri Bazar", "New Delhi", "Rajiv Chowk", "Patel Chowk", "Central Secretariat",
    "Udyog Bhawan", "Lok Kalyan Marg", "Jor Bagh", "Dilli Haat - INA", "AIIMS",
    "Green Park", "Hauz Khas", "Malviya Nagar", "Saket", "Qutab Minar", "Chhatarpur",
    "Sultanpur", "Ghitorni", "Arjan Garh", "Guru Dronacharya", "Sikanderpur",
    "MG Road", "IFFCO Chowk", "Millennium City Centre Gurugram",
]
_YELLOW_LINE_DIST_KM = [
    0.0, 0.8, 2.1, 3.4, 4.7, 6.2, 7.6, 9.0, 9.8, 10.8, 12.1, 13.2, 14.3, 15.3, 16.1,
    17.2, 18.5, 19.4, 19.7, 21.3, 22.5, 23.8, 24.6, 25.6, 27.4, 29.1, 30.0, 31.7, 33.0,
    34.6, 35.9, 38.6, 40.9, 41.9, 43.1, 44.2, 45.7,
]

_BLUE_LINE_STATIONS = [
    "Dwarka Sector 21", "Dwarka Sector 8", "Dwarka Sector 9", "Dwarka Sector 10",
    "Dwarka Sector 11", "Dwarka Sector 12", "Dwarka Sector 13", "Dwarka Sector 14",
    "Dwarka", "Dwarka Mor", "Nawada", "Uttam Nagar West", "Uttam Nagar East",
    "Janakpuri West", "Janakpuri East", "Tilak Nagar", "Subhash Nagar",
    "Tagore Garden", "Rajouri Garden", "Ramesh Nagar", "Moti Nagar", "Kirti Nagar",
    "Shadipur", "Patel Nagar", "Rajendra Place", "Karol Bagh", "Jhandewalan",
    "RK Ashram Marg", "Rajiv Chowk", "Barakhamba Road", "Mandi House", "Supreme Court",
    "Indraprastha", "Yamuna Bank", "Akshardham", "Mayur Vihar-I",
    "Mayur Vihar Extension", "New Ashok Nagar", "Noida Sector 15", "Noida Sector 16",
    "Noida Sector 18", "Botanical Garden", "Golf Course", "Noida City Centre",
    "Noida Sector 34", "Noida Sector 52", "Noida Sector 61", "Noida Sector 59",
    "Noida Sector 62", "Noida Electronic City",
]
_BLUE_LINE_DIST_KM = [
    0.0, 1.7, 2.7, 3.8, 4.8, 5.8, 6.7, 7.6, 9.1, 10.2, 11.4, 12.4, 13.4, 14.7, 15.7,
    16.7, 17.6, 18.5, 19.6, 20.6, 21.8, 22.8, 23.5, 24.8, 25.7, 26.7, 27.9, 28.9, 30.1,
    30.8, 31.8, 32.6, 33.4, 35.2, 36.5, 38.3, 39.5, 40.4, 41.4, 42.5, 43.6, 44.7, 45.9,
    47.2, 48.1, 49.3, 50.5, 51.5, 52.7, 58.97,
]

_GREEN_LINE_STATIONS = [
    "Inderlok", "Ashok Park Main", "Punjabi Bagh", "Shivaji Park", "Madipur",
    "Paschim Vihar (East)", "Paschim Vihar (West)", "Peera Garhi", "Udyog Nagar",
    "Maharaja Surajmal Stadium", "Nangloi", "Nangloi Railway Station", "Rajdhani Park",
    "Mundka", "Mundka Industrial Area (MIA)", "Ghevra Metro Station", "Tikri Kalan",
    "Tikri Border", "Pandit Shree Ram Sharma", "Bahadurgarh City",
    "Brigadier Hoshiar Singh",
]
_GREEN_LINE_DIST_KM = [
    0.0, 1.4, 2.3, 3.9, 5.0, 5.7, 6.7, 7.6, 8.8, 9.5, 10.3, 11.2, 12.4, 13.7, 15.0,
    17.1, 18.9, 20.2, 21.5, 23.0, 24.8,
]

_VIOLET_LINE_STATIONS = [
    "Kashmere Gate", "Lal Quila", "Jama Masjid", "Delhi Gate", "ITO", "Mandi House",
    "Janpath", "Central Secretariat", "Khan Market", "Jawaharlal Nehru Stadium",
    "Jangpura", "Lajpat Nagar", "Moolchand", "Kailash Colony", "Nehru Place",
    "Kalkaji Mandir", "Govind Puri", "Okhla", "Jasola", "Sarita Vihar", "Mohan Estate",
    "Tughlakabad", "Badarpur Border", "Sarai", "N.H.P.C. Chowk", "Mewala Maharajpur",
    "Sector 28 Faridabad", "Badkal Mor", "Old Faridabad", "Neelam Chowk Ajronda",
    "Bata Chowk", "Escorts Mujesar", "Sant Surdas - Sihi", "Raja Nahar Singh",
]
_VIOLET_LINE_DIST_KM = [
    0.0, 1.5, 2.3, 3.7, 5.0, 5.8, 7.2, 8.5, 10.6, 12.0, 12.9, 14.4, 15.1, 16.4, 17.4,
    18.2, 18.9, 20.0, 20.9, 22.1, 23.3, 25.2, 26.3, 28.8, 30.4, 31.3, 32.5, 34.2, 35.4,
    37.0, 38.3, 40.1, 41.8, 43.5,
]

_PINK_LINE_STATIONS = [
    "Majlis Park", "Azadpur", "Shalimar Bagh", "Netaji Subhash Place", "Shakurpur",
    "Punjabi Bagh West", "ESI Basai Darapur", "Rajouri Garden", "Maya Puri",
    "Naraina Vihar", "Delhi Cantt", "Durgabai Deshmukh South Campus",
    "Sir Vishweshwaraiah Moti Bagh", "Bhikaji Cama Place", "Sarojini Nagar",
    "Dilli Haat - INA", "South Extension", "Lajpat Nagar", "Vinobapuri", "Ashram",
    "Sarai Kale Khan Hazrat Nizamuddin", "Mayur Vihar-I", "Mayur Vihar Pocket I",
    "Trilokpuri Sanjay Lake", "Vinod Nagar East", "Mandawali - West Vinod Nagar",
    "IP Extension", "Anand Vihar", "Karkarduma", "Karkarduma Court", "Krishna Nagar",
    "East Azad Nagar", "Welcome", "Jaffrabad", "Maujpur", "Gokulpuri", "Johri Enclave",
    "Shiv Vihar",
]
_PINK_LINE_DIST_KM = [
    0.0, 2.1, 3.7, 5.1, 6.3, 7.7, 10.2, 11.3, 12.8, 14.3, 16.1, 19.7, 21.0, 22.6, 23.8,
    24.9, 26.1, 27.7, 29.1, 30.3, 32.2, 35.8, 36.6, 37.9, 38.7, 39.3, 40.3, 41.9, 42.9,
    44.0, 44.7, 45.7, 46.8, 48.0, 49.1, 50.4, 51.7, 52.6,
]

_MAGENTA_LINE_STATIONS = [
    "Janakpuri West", "Dabri Mor - Janakpuri South", "Dashrath Puri", "Palam",
    "Sadar Bazaar Cantonment", "Terminal 1 IGI Airport", "Shankar Vihar",
    "Vasant Vihar", "Munirka", "RK Puram", "IIT Delhi", "Hauz Khas", "Panchsheel Park",
    "Chirag Delhi", "Greater Kailash", "Nehru Enclave", "Kalkaji Mandir", "Okhla NSIC",
    "Sukhdev Vihar", "Jamia Millia Islamia", "Okhla Vihar",
    "Jasola Vihar Shaheen Bagh", "Kalindi Kunj", "Okhla Bird Sanctuary",
    "Botanical Garden",
]
_MAGENTA_LINE_DIST_KM = [
    0.0, 2.0, 3.1, 4.6, 7.2, 8.9, 10.7, 12.8, 14.0, 15.4, 16.3, 17.5, 19.0, 19.9, 20.8,
    22.1, 23.0, 23.8, 24.9, 26.1, 26.6, 28.4, 29.8, 31.4, 33.1,
]

_GREY_LINE_STATIONS = ["Dwarka", "Nangli", "Najafgarh"]
_GREY_LINE_DIST_KM = [0.0, 1.5, 3.9]

_ORANGE_LINE_STATIONS = [
    "New Delhi", "Shivaji Stadium", "Dhaula Kuan", "Delhi Aerocity", "IGI Airport",
    "Dwarka Sector 21",
]
_ORANGE_LINE_DIST_KM = [0.0, 1.9, 8.3, 14.5, 17.9, 20.8]

METRO_LINES = {
    "Red_Line": _RED_LINE_STATIONS,
    "Yellow_Line": _YELLOW_LINE_STATIONS,
    "Blue_Line": _BLUE_LINE_STATIONS,
    "Green_Line": _GREEN_LINE_STATIONS,
    "Violet_Line": _VIOLET_LINE_STATIONS,
    "Pink_Line": _PINK_LINE_STATIONS,
    "Magenta_Line": _MAGENTA_LINE_STATIONS,
    "Grey_Line": _GREY_LINE_STATIONS,
    "Orange_Line": _ORANGE_LINE_STATIONS,
}

# Real cumulative distance (km) from each line's first station, in the same
# order as METRO_LINES -- used to calibrate segment travel times below.
LINE_DISTANCES_KM = {
    "Red_Line": _RED_LINE_DIST_KM,
    "Yellow_Line": _YELLOW_LINE_DIST_KM,
    "Blue_Line": _BLUE_LINE_DIST_KM,
    "Green_Line": _GREEN_LINE_DIST_KM,
    "Violet_Line": _VIOLET_LINE_DIST_KM,
    "Pink_Line": _PINK_LINE_DIST_KM,
    "Magenta_Line": _MAGENTA_LINE_DIST_KM,
    "Grey_Line": _GREY_LINE_DIST_KM,
    "Orange_Line": _ORANGE_LINE_DIST_KM,
}

# Real scheduled end-to-end run times (DMRC), used to calibrate per-segment
# travel times proportionally to each segment's real share of the line's
# total real distance.
LINE_TOTAL_RUN_SECONDS = {
    "Red_Line": 67 * 60,
    "Yellow_Line": 76 * 60,
    "Blue_Line": 105 * 60,
    "Green_Line": 36 * 60,
    "Violet_Line": 85 * 60,
    "Pink_Line": 83 * 60,
    "Magenta_Line": 82 * 60,
    "Grey_Line": 6 * 60,
    "Orange_Line": 20 * 60,
}

LINE_CODES = {
    "Red_Line": "RD",
    "Yellow_Line": "YL",
    "Blue_Line": "BL",
    "Green_Line": "GR",
    "Violet_Line": "VI",
    "Pink_Line": "PK",
    "Magenta_Line": "MG",
    "Grey_Line": "GY",
    "Orange_Line": "OR",
}

# Real DMRC line colors.
LINE_COLORS = {
    "Red_Line": "#e2231a",
    "Yellow_Line": "#f2c200",
    "Blue_Line": "#0057b8",
    "Green_Line": "#00a651",
    "Violet_Line": "#92278f",
    "Pink_Line": "#f06ea9",
    "Magenta_Line": "#9c0651",
    "Grey_Line": "#8c8c8c",
    "Orange_Line": "#f7941d",
}

# Any station served by 2+ lines is a real interchange -- derived directly
# from METRO_LINES (which already uses identical names for the same physical
# station across lines) rather than a hand-typed list.
_station_line_counts = {}
for _line_name, _stations in METRO_LINES.items():
    for _station in _stations:
        _station_line_counts[_station] = _station_line_counts.get(_station, 0) + 1
HUB_STATIONS = {name for name, count in _station_line_counts.items() if count > 1}


def build_segment_times(line):
    """
    Real per-segment travel times (seconds), calibrated so each segment gets
    a share of the line's real total run time proportional to its real share
    of the line's real total distance.
    """
    dist_km = LINE_DISTANCES_KM[line]
    total_km = dist_km[-1]
    total_seconds = LINE_TOTAL_RUN_SECONDS[line]
    deltas = [dist_km[i + 1] - dist_km[i] for i in range(len(dist_km) - 1)]
    return [max(60, round(d / total_km * total_seconds)) for d in deltas]


SEGMENT_TIMES = {line: build_segment_times(line) for line in METRO_LINES}


def build_route(stations, segment_times, direction):
    """Ordered list of {station, next_station, travel_seconds} legs for a direction."""
    if direction == "UP":
        ordered, times = stations, segment_times
    else:
        ordered, times = list(reversed(stations)), list(reversed(segment_times))
    return [
        {"station": ordered[i], "next_station": ordered[i + 1], "travel_seconds": times[i]}
        for i in range(len(ordered) - 1)
    ]


def cumulative_times(times):
    """cum[i] = elapsed time to reach the start of leg i from the route's start."""
    cum = [0]
    for t in times:
        cum.append(cum[-1] + t)
    return cum


def leg_index_for_offset(cum, offset):
    """Which leg a train is on if it has been running for `offset` seconds."""
    total = cum[-1]
    offset = offset % total
    for i in range(len(cum) - 1):
        if cum[i] <= offset < cum[i + 1]:
            return i
    return len(cum) - 2
