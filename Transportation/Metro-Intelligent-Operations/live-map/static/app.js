const map = L.map("map");
// Muted basemap (CARTO Positron) so the metro lines/stations are the clear
// focal point -- default OSM tiles are too busy (bright road colors, dense
// city labels, parks) and compete with the metro's own colors/labels. Unlike
// the fully label-free variant, this keeps a handful of place names/roads for
// geographic orientation.
L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
  maxZoom: 20,
  subdomains: "abcd",
  attribution: "&copy; OpenStreetMap contributors &copy; CARTO",
}).addTo(map);

let STATIONS = {};
let LINE_NAMES = []; // e.g. ["Red_Line", "Yellow_Line", ...]
let LINE_STATIONS = {}; // line -> [station names in order]
let LINE_COLORS = {};
let HOP_SECONDS = {};
let visibleLines = new Set(); // populated once /api/lines resolves (see DEFAULT_VISIBLE_LINES)
const DEFAULT_VISIBLE_LINES = ["Red_Line", "Yellow_Line", "Blue_Line", "Green_Line"];
let lastSnapshot = null; // re-rendered immediately when line visibility toggles

const stationMarkers = {}; // name -> marker
const lineLayers = {}; // line -> { polylines: [...], flow: polyline }
const trainMarkers = {}; // train_id -> { marker, fromLL, toLL, hopSeconds, elapsedAtReceipt, clientReceiptTime, metro_line }
const segmentLabels = {}; // "line|direction|from|to" -> marker
const surgeMarkers = {}; // "line|direction|station" -> marker (real, detected surges only -- see server.py's SURGE_TOPIC)
const flowLines = []; // animated "current flowing along the track" overlays, all lines
const STATION_LABEL_MIN_ZOOM = 13;

// A handful of big, always-visible area names for orientation -- independent
// of (and larger than) the station name labels, and of which lines are shown.
const AREA_LABELS = [
  { name: "NEW DELHI", lat: 28.6139, lng: 77.209 },
  { name: "ROHINI", lat: 28.7495, lng: 77.0565 },
  { name: "DWARKA", lat: 28.5921, lng: 77.046 },
  { name: "GURUGRAM", lat: 28.47, lng: 77.07 },
  { name: "NOIDA", lat: 28.57, lng: 77.35 },
];

function lineDisplayName(line) {
  return line.replace(/_Line$/, "");
}

function stationLatLng(name) {
  const s = STATIONS[name];
  return s ? [s.lat, s.lng] : null;
}

function isStationVisible(name) {
  const s = STATIONS[name];
  return s && s.lines.some((l) => visibleLines.has(l));
}

async function init() {
  const [stationsRes, linesRes] = await Promise.all([
    fetch("/api/stations"),
    fetch("/api/lines"),
  ]);
  STATIONS = await stationsRes.json();
  const linesData = await linesRes.json();
  LINE_STATIONS = linesData.lines;
  LINE_COLORS = linesData.colors;
  HOP_SECONDS = linesData.hop_seconds;
  LINE_NAMES = Object.keys(LINE_STATIONS);
  // Only lines actually present count as "default visible" -- guards against
  // a DEFAULT_VISIBLE_LINES entry that doesn't (yet, or anymore) exist.
  visibleLines = new Set(DEFAULT_VISIBLE_LINES.filter((l) => LINE_NAMES.includes(l)));

  drawLines();
  drawAreaLabels();
  buildLineSelector();
  applyLineVisibility();
  fitToBounds();
  connectWebSocket();
  map.on("zoomend", updateStationLabelVisibility);
  updateStationLabelVisibility();
  requestAnimationFrame(animate);
}

function drawAreaLabels() {
  for (const a of AREA_LABELS) {
    L.marker([a.lat, a.lng], {
      // iconSize: [0, 0] disables Leaflet's own default-12x12 anchor math
      // entirely, so our CSS transform:translate(-50%,-50%) is the only
      // thing centering this (variable-width text) label -- otherwise the
      // two centering calculations stack and the label drifts off-point.
      icon: L.divIcon({ className: "area-label", html: a.name, iconSize: [0, 0] }),
      interactive: false,
    }).addTo(map);
  }
}

function drawLines() {
  for (const lineName of LINE_NAMES) {
    const stations = LINE_STATIONS[lineName];
    const color = LINE_COLORS[lineName];
    const latlngs = stations.map(stationLatLng).filter(Boolean);

    // Dark outline underneath the colored line so it reads clearly against
    // any basemap, then the line color on top, then an animated thin white
    // dashed overlay suggesting live movement along the track.
    const outline = L.polyline(latlngs, { color: "#1a1a1a", weight: 8, opacity: 0.5 }).addTo(map);
    const colored = L.polyline(latlngs, { color, weight: 5, opacity: 0.95 }).addTo(map);
    const flow = L.polyline(latlngs, { color: "#ffffff", weight: 2, opacity: 0.9, dashArray: "1 14" }).addTo(map);
    flowLines.push(flow);
    lineLayers[lineName] = { polylines: [outline, colored, flow] };

    stations.forEach((name) => {
      const ll = stationLatLng(name);
      if (!ll || stationMarkers[name]) return;
      const marker = L.circleMarker(ll, {
        radius: 5,
        color: "#1a1a1a",
        weight: 2,
        fillColor: "white",
        fillOpacity: 1,
      })
        .addTo(map)
        .bindTooltip(name, { className: "station-tooltip", direction: "top", offset: [0, -6] });
      stationMarkers[name] = marker;
    });
  }
}

// Rebuilds map visibility (lines, stations, trains, segment labels) from the
// current `visibleLines` set -- called on every checkbox toggle.
function applyLineVisibility() {
  for (const lineName of LINE_NAMES) {
    const show = visibleLines.has(lineName);
    for (const layer of lineLayers[lineName].polylines) {
      if (show) {
        if (!map.hasLayer(layer)) layer.addTo(map);
      } else if (map.hasLayer(layer)) {
        map.removeLayer(layer);
      }
    }
  }

  for (const [name, marker] of Object.entries(stationMarkers)) {
    const show = isStationVisible(name);
    if (show && !map.hasLayer(marker)) marker.addTo(map);
    else if (!show && map.hasLayer(marker)) map.removeLayer(marker);
  }

  if (lastSnapshot) handleSnapshot(lastSnapshot, { skipCache: true });
}

function buildLineSelector() {
  const container = document.getElementById("line-selector");
  container.innerHTML = "";

  const allRow = document.createElement("label");
  allRow.className = "line-toggle line-toggle-all";
  const allCheckbox = document.createElement("input");
  allCheckbox.type = "checkbox";
  allCheckbox.checked = visibleLines.size === LINE_NAMES.length;
  allCheckbox.addEventListener("change", () => {
    const lineCheckboxes = container.querySelectorAll(".line-toggle:not(.line-toggle-all) input");
    lineCheckboxes.forEach((cb) => { cb.checked = allCheckbox.checked; });
    visibleLines = allCheckbox.checked ? new Set(LINE_NAMES) : new Set();
    applyLineVisibility();
  });
  allRow.appendChild(allCheckbox);
  allRow.appendChild(document.createTextNode("All lines"));
  container.appendChild(allRow);

  for (const lineName of LINE_NAMES) {
    const row = document.createElement("label");
    row.className = "line-toggle";

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = visibleLines.has(lineName);
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) visibleLines.add(lineName);
      else visibleLines.delete(lineName);
      allCheckbox.checked = visibleLines.size === LINE_NAMES.length;
      applyLineVisibility();
    });

    const swatch = document.createElement("span");
    swatch.className = "line-swatch";
    swatch.style.background = LINE_COLORS[lineName];

    row.appendChild(checkbox);
    row.appendChild(swatch);
    row.appendChild(document.createTextNode(lineDisplayName(lineName)));
    container.appendChild(row);
  }
}

function updateStationLabelVisibility() {
  const showPermanent = map.getZoom() >= STATION_LABEL_MIN_ZOOM;
  for (const marker of Object.values(stationMarkers)) {
    const tooltip = marker.getTooltip();
    if (!tooltip) continue;
    if (tooltip.options.permanent === showPermanent) continue;
    const name = tooltip.getContent();
    marker.unbindTooltip();
    marker.bindTooltip(name, {
      className: showPermanent ? "station-label-permanent" : "station-tooltip",
      direction: "top",
      offset: [0, -6],
      permanent: showPermanent,
    });
  }
}

function fitToBounds() {
  const all = Object.values(STATIONS).map((s) => [s.lat, s.lng]);
  map.fitBounds(all, { padding: [20, 20] });
}

function connectWebSocket() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onopen = () => setStatus("live", true);
  ws.onclose = () => {
    setStatus("disconnected — retrying…", false);
    setTimeout(connectWebSocket, 2000);
  };
  ws.onerror = () => ws.close();
  ws.onmessage = (evt) => handleSnapshot(JSON.parse(evt.data));
}

function setStatus(text, isLive) {
  document.getElementById("status-text").textContent = text;
  document.getElementById("status-dot").className = `status-dot ${isLive ? "live" : "down"}`;
}

function tooltipHtml(t) {
  return `<b>${t.train_id}</b> (${t.direction})<br>${t.current_station} → ${t.next_station}<br>Headcount: <b>${t.headcount}</b>`;
}

// A train's own marker is a numbered badge (its live headcount), not a bare
// dot -- the count should be readable on the map without hovering. Color is
// applied inline (from LINE_COLORS) rather than via a per-line CSS class, so
// this scales to any number of lines without touching style.css.
function trainIcon(t) {
  const color = LINE_COLORS[t.metro_line] || "#333";
  return L.divIcon({
    className: "train-marker",
    html: `<div class="train-badge" style="background:${color}">${t.headcount}</div>`,
    // Fixed, exact size + matching anchor: Leaflet's own inline width/height/
    // margin fully control placement here, with zero CSS transform involved,
    // so there is nothing left that can silently fight the anchor math.
    iconSize: [32, 20],
    iconAnchor: [16, 10],
  });
}

function handleSnapshot(snapshot, opts) {
  if (!(opts && opts.skipCache)) lastSnapshot = snapshot;

  const clientReceiptTime = Date.now() / 1000;
  const seenTrainIds = new Set();

  for (const t of snapshot.trains) {
    if (!visibleLines.has(t.metro_line)) continue;
    const fromLL = stationLatLng(t.current_station);
    const toLL = stationLatLng(t.next_station);
    if (!fromLL || !toLL) continue;
    seenTrainIds.add(t.train_id);

    const hopSeconds = HOP_SECONDS[t.metro_line] || 130;
    const elapsedAtReceipt = Math.max(0, snapshot.server_time - t.received_at);

    let entry = trainMarkers[t.train_id];
    if (!entry) {
      const marker = L.marker(fromLL, { icon: trainIcon(t) }).addTo(map);
      entry = { marker };
      trainMarkers[t.train_id] = entry;
    } else {
      entry.marker.setIcon(trainIcon(t));
      if (!map.hasLayer(entry.marker)) entry.marker.addTo(map);
    }

    entry.fromLL = fromLL;
    entry.toLL = toLL;
    entry.hopSeconds = hopSeconds;
    entry.elapsedAtReceipt = elapsedAtReceipt;
    entry.clientReceiptTime = clientReceiptTime;

    if (entry.marker.getTooltip()) {
      entry.marker.setTooltipContent(tooltipHtml(t));
    } else {
      entry.marker.bindTooltip(tooltipHtml(t));
    }
  }

  for (const id of Object.keys(trainMarkers)) {
    if (!seenTrainIds.has(id)) {
      map.removeLayer(trainMarkers[id].marker);
      delete trainMarkers[id];
    }
  }

  updateSegmentLabels(snapshot.segments);
  updateSurges(snapshot.surges || []);
  updateStats(snapshot);
}

function surgeIcon() {
  return L.divIcon({
    className: "surge-marker",
    html: `<div class="surge-ring"></div>`,
    // Small, fixed exact-size anchor (matches the .surge-marker CSS width/
    // height exactly) -- the visible pulsing ring is a larger, absolutely
    // positioned child (see .surge-ring in style.css).
    iconSize: [20, 20],
    iconAnchor: [10, 10],
  });
}

function surgeTooltipHtml(s) {
  const ratio = s.baseline_avg > 0 ? (s.total_headcount / s.baseline_avg).toFixed(1) : "?";
  return `<b>Surge at ${s.current_station}</b><br>${lineDisplayName(s.metro_line)} (${s.direction})<br>` +
         `${s.total_headcount} passengers vs normal ~${Math.round(s.baseline_avg)} (${ratio}x)`;
}

// Only ever reflects real, already-detected surges from Flink's own
// ML_DETECT_ANOMALIES + 1.5x-baseline pipeline (metro_station_surge_anomalies,
// via server.py) -- never computed client-side.
function updateSurges(surges) {
  const seenKeys = new Set();
  for (const s of surges) {
    if (!visibleLines.has(s.metro_line)) continue;
    const key = `${s.metro_line}|${s.direction}|${s.current_station}`;
    seenKeys.add(key);

    let marker = surgeMarkers[key];
    if (!marker) {
      marker = L.marker([s.lat, s.lng], { icon: surgeIcon() }).addTo(map);
      surgeMarkers[key] = marker;
    } else if (!map.hasLayer(marker)) {
      marker.addTo(map);
    }

    if (marker.getTooltip()) marker.setTooltipContent(surgeTooltipHtml(s));
    else marker.bindTooltip(surgeTooltipHtml(s));
  }

  for (const key of Object.keys(surgeMarkers)) {
    if (!seenKeys.has(key)) {
      map.removeLayer(surgeMarkers[key]);
      delete surgeMarkers[key];
    }
  }
}

// Only label segments with 2+ trains sharing them -- a single train already
// shows its own headcount on its marker, so a duplicate label there is just
// clutter. A shared-segment total is genuinely new information.
function updateSegmentLabels(segments) {
  const seenKeys = new Set();
  for (const s of segments) {
    if (s.trains_counted < 2 || !visibleLines.has(s.metro_line)) continue;
    const key = `${s.metro_line}|${s.direction}|${s.current_station}|${s.next_station}`;
    const fromLL = stationLatLng(s.current_station);
    const toLL = stationLatLng(s.next_station);
    if (!fromLL || !toLL) continue;
    seenKeys.add(key);

    const mid = [(fromLL[0] + toLL[0]) / 2, (fromLL[1] + toLL[1]) / 2];
    const color = LINE_COLORS[s.metro_line] || "#999";
    const html =
      `<div class="segment-label" style="border-left-color:${color}">` +
      `${s.headcount} <span class="segment-label-sub">(${s.trains_counted} trains)</span></div>`;
    // iconSize: [0, 0] -- see the comment in drawAreaLabels() for why.
    const icon = L.divIcon({ className: "segment-label-wrap", html, iconSize: [0, 0] });

    let marker = segmentLabels[key];
    if (!marker) {
      marker = L.marker(mid, { icon, interactive: false }).addTo(map);
      segmentLabels[key] = marker;
    } else {
      marker.setLatLng(mid);
      marker.setIcon(icon);
    }
  }

  for (const key of Object.keys(segmentLabels)) {
    if (!seenKeys.has(key)) {
      map.removeLayer(segmentLabels[key]);
      delete segmentLabels[key];
    }
  }
}

function updateStats(snapshot) {
  const visibleTrains = snapshot.trains.filter((t) => visibleLines.has(t.metro_line));
  const totalHeadcount = visibleTrains.reduce((sum, t) => sum + t.headcount, 0);
  document.getElementById("stats").innerHTML =
    `Active trains: <b>${visibleTrains.length}</b><br>Total onboard: <b>${totalHeadcount}</b>`;
}

let flowOffset = 0;

function animate() {
  const now = Date.now() / 1000;
  for (const id of Object.keys(trainMarkers)) {
    const e = trainMarkers[id];
    if (!e.fromLL) continue;
    const elapsed = e.elapsedAtReceipt + (now - e.clientReceiptTime);
    const frac = Math.max(0, Math.min(1, elapsed / e.hopSeconds));
    const lat = e.fromLL[0] + (e.toLL[0] - e.fromLL[0]) * frac;
    const lng = e.fromLL[1] + (e.toLL[1] - e.fromLL[1]) * frac;
    e.marker.setLatLng([lat, lng]);
  }

  flowOffset = (flowOffset + 0.35) % 15;
  for (const flow of flowLines) {
    flow.setStyle({ dashOffset: String(flowOffset) });
  }

  requestAnimationFrame(animate);
}

init();
