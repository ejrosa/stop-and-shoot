/* Stop & Shoot - single-file PWA logic. No framework. */
(function () {
"use strict";
const CFG = window.APP_CONFIG || { APP_NAME: "Stop & Shoot", VERSION: "1" };
const APP_NAME = CFG.APP_NAME;
const KEY = "sas.pins.v1";
const TAGS = ["Photo spot", "Scenic", "Food", "Rest stop", "Hazard"];
const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
  "https://overpass.private.coffee/api/interpreter"
];
const NREL = "https://developer.nlr.gov/api/alt-fuel-stations/v1/nearest.json";
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
const isStandalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
const $ = (s, el) => (el || document).querySelector(s);
const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const view = $("#view");

document.title = APP_NAME;
$("#appTitle").textContent = APP_NAME;

/* ---------- storage ---------- */
function loadPins() { try { return JSON.parse(localStorage.getItem(KEY)) || []; } catch (e) { return []; } }
function savePins(p) { localStorage.setItem(KEY, JSON.stringify(p)); }
function getPin(id) { return loadPins().find(p => p.id === id); }
function updatePin(id, fn) {
  const pins = loadPins(); const i = pins.findIndex(p => p.id === id);
  if (i < 0) return null; fn(pins[i]); savePins(pins); return pins[i];
}
if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});

// One real first pin, imported once (not fake data).
if (!localStorage.getItem("sas.seeded")) {
  const pins = loadPins();
  if (!pins.some(p => p.id === "first-southpointe")) {
    pins.push({ id: "first-southpointe", ts: Date.parse("2026-11-01T09:10:00Z"), lat: 33.02755, lon: -80.15110, acc: null,
      name: "South Pointe, Summerville, SC", tags: ["Test"], note: "", parking: "", nearby: null, weather: null, place: null });
    savePins(pins);
  }
  localStorage.setItem("sas.seeded", "1");
}

/* ---------- helpers ---------- */
function toast(msg, ms) { const t = $("#toast"); t.textContent = msg; t.classList.add("show"); clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove("show"), ms || 2600); }
function speak(msg) { try { if (!("speechSynthesis" in window)) return; speechSynthesis.cancel(); const u = new SpeechSynthesisUtterance(msg); u.rate = 1; speechSynthesis.speak(u); } catch (e) {} }
function buzz(p) { try { navigator.vibrate && navigator.vibrate(p || [60, 40, 60]); } catch (e) {} }
function uid() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }
function fmtTime(ts) { return new Date(ts).toLocaleString([], { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" }); }
function hm(d) { return d && !isNaN(d) ? d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "—"; }
function miles(lat1, lon1, lat2, lon2) {
  const R = 3958.8, r = Math.PI / 180, dLa = (lat2 - lat1) * r, dLo = (lon2 - lon1) * r;
  const a = Math.sin(dLa / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
function navUrl(lat, lon, label) {
  return isIOS ? `https://maps.apple.com/?daddr=${lat},${lon}&q=${encodeURIComponent(label || "Spot")}`
               : `https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}`;
}
function viewUrl(lat, lon, label) {
  return isIOS ? `https://maps.apple.com/?ll=${lat},${lon}&q=${encodeURIComponent(label || "Spot")}`
               : `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;
}
async function fetchT(url, opts, ms) {
  const c = new AbortController(); const h = setTimeout(() => c.abort(), ms || 15000);
  try { const r = await fetch(url, Object.assign({}, opts, { signal: c.signal })); if (!r.ok) throw new Error("HTTP " + r.status); return r; }
  finally { clearTimeout(h); }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

/* ---------- sun (SunCalc-style formulas, computed on device) ---------- */
const rad = Math.PI / 180, J1970 = 2440588, J2000 = 2451545, e = rad * 23.4397, J0 = 0.0009;
const toDays = d => d.valueOf() / 86400000 - 0.5 + J1970 - J2000;
const fromJ = j => new Date((j + 0.5 - J1970) * 86400000);
const meanAnom = d => rad * (357.5291 + 0.98560028 * d);
function eclLon(M) { const C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M)); return M + C + rad * 102.9372 + Math.PI; }
function sunTimes(date, lat, lon) {
  const lw = rad * -lon, phi = rad * lat, d = toDays(date);
  const n = Math.round(d - J0 - lw / (2 * Math.PI));
  const ds = J0 + lw / (2 * Math.PI) + n, M = meanAnom(ds), L = eclLon(M), dec = Math.asin(Math.sin(e) * Math.sin(L));
  const transit = (dsx) => J2000 + dsx + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L);
  const Jnoon = transit(ds);
  const at = (h) => {
    const w = Math.acos((Math.sin(h * rad) - Math.sin(phi) * Math.sin(dec)) / (Math.cos(phi) * Math.cos(dec)));
    const Jset = transit(J0 + (w + lw) / (2 * Math.PI) + n);
    return [fromJ(Jnoon - (Jset - Jnoon)), fromJ(Jset)];
  };
  const [sunrise, sunset] = at(-0.833), [ghEndAM, ghStartPM] = at(6), [blueStartAM, blueEndPM] = at(-6), [blueMidAM, blueMidPM] = at(-4);
  return { sunrise, sunset, solarNoon: fromJ(Jnoon), goldenMorningEnd: ghEndAM, goldenEveningStart: ghStartPM,
           blueMorning: [blueStartAM, blueMidAM], blueEvening: [blueMidPM, blueEndPM] };
}

/* ---------- geolocation ---------- */
let lastFix = null, watchId = null;
function startWatch() {
  if (!("geolocation" in navigator) || watchId != null) return;
  watchId = navigator.geolocation.watchPosition(p => { lastFix = p; }, () => {}, { enableHighAccuracy: true, maximumAge: 5000, timeout: 30000 });
}
function stopWatch() { if (watchId != null) { navigator.geolocation.clearWatch(watchId); watchId = null; } }
function getFix() {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) return reject(new Error("This browser has no location access."));
    if (lastFix && Date.now() - lastFix.timestamp < 15000) return resolve(lastFix);
    navigator.geolocation.getCurrentPosition(resolve, err => {
      if (err.code === 1) return reject(new Error("Location permission is off. Allow location for this site in Settings."));
      navigator.geolocation.getCurrentPosition(resolve, e2 => reject(new Error("Couldn't get a GPS fix (" + (e2.message || "timeout") + ").")),
        { enableHighAccuracy: false, maximumAge: 60000, timeout: 15000 });
    }, { enableHighAccuracy: true, maximumAge: 10000, timeout: 15000 });
  });
}

let marking = false;
async function markSpot(extra) {
  if (marking) return; marking = true;
  const b = $("#markBtn"); if (b) { b.disabled = true; b.firstChild.textContent = "Getting GPS…"; }
  try {
    const pos = await getFix();
    const pin = { id: uid(), ts: Date.now(), lat: +pos.coords.latitude.toFixed(6), lon: +pos.coords.longitude.toFixed(6),
      acc: pos.coords.accuracy ? Math.round(pos.coords.accuracy) : null, name: "", tags: (extra && extra.tags) || [],
      note: (extra && extra.note) || "", parking: "", nearby: null, weather: null, place: null };
    const pins = loadPins(); pins.push(pin); savePins(pins);
    buzz(); speak("Spot saved"); toast("📍 Spot saved");
    location.hash = "#/pin/" + pin.id;
    enrich(pin.id);
  } catch (err) {
    buzz([200]); speak("Couldn't save the spot"); toast(err.message, 5000);
    if (b) { b.disabled = false; b.firstChild.textContent = "Mark this spot"; }
  } finally { marking = false; }
}

/* ---------- nearby lookups ---------- */
function osmName(t) { return t.name || t.brand || t.operator || null; }
function osmAddr(t) { return [t["addr:housenumber"], t["addr:street"], t["addr:city"]].filter(Boolean).join(" "); }
function shapeOSM(el, lat, lon, kind) {
  const la = el.lat != null ? el.lat : el.center && el.center.lat, lo = el.lon != null ? el.lon : el.center && el.center.lon;
  const t = el.tags || {};
  const facts = [];
  if (t.opening_hours) facts.push("Hours: " + t.opening_hours);
  if (kind === "wc") { if (t.access) facts.push("Access: " + t.access); if (t.fee) facts.push("Fee: " + t.fee); if (t.wheelchair) facts.push("Wheelchair: " + t.wheelchair); }
  if (kind === "ev") { if (t.socket && false) {} const s = Object.keys(t).filter(k => /^socket:[^:]+$/.test(k)).map(k => k.slice(7)); if (s.length) facts.push("Plugs: " + s.join(", ")); if (t.fee) facts.push("Fee: " + t.fee); }
  if (kind === "parking") { ["fee", "access", "maxstay", "parking", "capacity", "supervised"].forEach(k => t[k] && facts.push(k + ": " + t[k])); }
  return { name: osmName(t) || ({ ev: "EV charger", fuel: "Gas station", wc: "Restroom", parking: "Parking" }[kind]) + (osmName(t) ? "" : " (unnamed)"),
    lat: la, lon: lo, addr: osmAddr(t), facts, mi: miles(lat, lon, la, lo), src: "OpenStreetMap" };
}
async function overpass(lat, lon) {
  const q = `[out:json][timeout:25];(
nwr["amenity"="charging_station"](around:16000,${lat},${lon});
nwr["amenity"="fuel"](around:10000,${lat},${lon});
nwr["amenity"="toilets"](around:8000,${lat},${lon});
nwr["amenity"="parking"](around:800,${lat},${lon});
);out center tags;`;
  let lastErr;
  for (let round = 0; round < 1; round++) {
    for (const m of OVERPASS) {
      try {
        const r = await fetchT(m, { method: "POST", body: "data=" + encodeURIComponent(q), headers: { "Content-Type": "application/x-www-form-urlencoded" } }, 12000);
        const j = await r.json(); if (!j.elements) throw new Error("bad response");
        const out = { ev: [], fuel: [], wc: [], parking: [] };
        for (const el of j.elements) {
          const a = (el.tags || {}).amenity;
          const k = a === "charging_station" ? "ev" : a === "fuel" ? "fuel" : a === "toilets" ? "wc" : a === "parking" ? "parking" : null;
          if (k) out[k].push(shapeOSM(el, lat, lon, k));
        }
        for (const k in out) out[k] = out[k].filter(x => x.lat != null).sort((a, b) => a.mi - b.mi).slice(0, 3);
        return out;
      } catch (err) { lastErr = err; }
    }
  }
  throw lastErr || new Error("Overpass unavailable");
}
async function nrelEV(lat, lon) {
  const url = `${NREL}?api_key=DEMO_KEY&latitude=${lat}&longitude=${lon}&radius=15&fuel_type=ELEC&status=E&limit=3`;
  const r = await fetchT(url, {}, 12000); const j = await r.json();
  return (j.fuel_stations || []).map(s => {
    const facts = [];
    if (s.access_days_time) facts.push("Hours: " + s.access_days_time);
    if (s.ev_connector_types) facts.push("Plugs: " + s.ev_connector_types.join(", "));
    const lv = [s.ev_dc_fast_num ? s.ev_dc_fast_num + " DC fast" : "", s.ev_level2_evse_num ? s.ev_level2_evse_num + " Level 2" : ""].filter(Boolean).join(", ");
    if (lv) facts.push(lv); if (s.ev_pricing) facts.push("Price: " + s.ev_pricing); if (s.ev_network) facts.push("Network: " + s.ev_network);
    return { name: s.station_name, lat: s.latitude, lon: s.longitude, addr: [s.street_address, s.city].filter(Boolean).join(", "),
      facts, mi: s.distance != null ? s.distance : miles(lat, lon, s.latitude, s.longitude), src: "U.S. DOE AFDC" };
  });
}
async function nominatimNearby(lat, lon, amenity, kind) {
  const d = 0.12, vb = [lon - d, lat + d, lon + d, lat - d].join(",");
  const r = await fetchT(`https://nominatim.openstreetmap.org/search?format=jsonv2&amenity=${amenity}&viewbox=${vb}&bounded=1&limit=10&addressdetails=0`, {}, 12000);
  const j = await r.json();
  return j.map(x => ({ name: x.name || ({ ev: "EV charger", fuel: "Gas station", wc: "Restroom" }[kind]), lat: +x.lat, lon: +x.lon,
    addr: (x.display_name || "").split(",").slice(0, 3).join(","), facts: [], mi: miles(lat, lon, +x.lat, +x.lon), src: "OpenStreetMap (Nominatim)" }))
    .sort((a, b) => a.mi - b.mi).slice(0, 3);
}
async function reverseGeocode(lat, lon) {
  const r = await fetchT(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lon}&zoom=16&addressdetails=1`, {}, 12000);
  const j = await r.json(); const a = j.address || {};
  const short = [a.road || a.neighbourhood || a.suburb || a.hamlet, a.city || a.town || a.village || a.county, a.state].filter(Boolean).join(", ");
  return { short: short || j.display_name, full: j.display_name };
}
async function weather(lat, lon) {
  const r = await fetchT(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,wind_gusts_10m,precipitation,visibility,is_day&daily=precipitation_probability_max,uv_index_max&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch&timezone=auto&forecast_days=1`, {}, 12000);
  const j = await r.json(); const c = j.current || {}, dl = j.daily || {};
  return { t: c.temperature_2m, feels: c.apparent_temperature, code: c.weather_code, wind: c.wind_speed_10m, gust: c.wind_gusts_10m,
    precip: c.precipitation, vis: c.visibility, rainChance: dl.precipitation_probability_max && dl.precipitation_probability_max[0],
    uv: dl.uv_index_max && dl.uv_index_max[0], at: Date.now() };
}
const WMO = { 0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast", 45: "Fog", 48: "Freezing fog", 51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle", 61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains", 80: "Rain showers", 81: "Rain showers", 82: "Violent rain showers", 85: "Snow showers", 86: "Snow showers", 95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail" };

const enriching = new Set();
async function enrich(id, force) {
  if (enriching.has(id)) return; const pin = getPin(id); if (!pin) return;
  if (!navigator.onLine) { updatePin(id, p => { p.nearby = p.nearby || { status: "offline" }; }); rerender(id); return; }
  enriching.add(id);
  const { lat, lon } = pin;
  updatePin(id, p => { p.nearby = Object.assign({}, p.nearby || {}, { status: "loading" }); }); rerender(id);
  // Place name (one Nominatim reverse call per pin)
  if (!pin.place || force) {
    try { const pl = await reverseGeocode(lat, lon); updatePin(id, p => { p.place = pl; if (!p.name) p.name = pl.short; }); } catch (e) {}
    rerender(id);
  }
  try { const w = await weather(lat, lon); updatePin(id, p => { p.weather = w; }); } catch (e) {}
  rerender(id);
  let out = { ev: [], fuel: [], wc: [], parking: [] }, errors = [], sources = [];
  const mergeEV = (a, b) => a.concat(b.filter(o => !a.some(n => miles(n.lat, n.lon, o.lat, o.lon) < 0.05))).sort((x, y) => x.mi - y.mi).slice(0, 3);
  try { const ev = await nrelEV(lat, lon); if (ev.length) { out.ev = ev; sources.push("U.S. DOE AFDC"); updatePin(id, p => { p.nearby = Object.assign({}, out, { status: "loading" }); }); rerender(id); } }
  catch (e) { errors.push("DOE EV list"); }
  try { const o = await overpass(lat, lon); o.ev = mergeEV(out.ev, o.ev); out = o; sources.push("OpenStreetMap (Overpass)"); } catch (e) { errors.push("OpenStreetMap Overpass (parking lots, full hours)"); }
  // Fallback for empty categories when Overpass failed (spaced to respect Nominatim's 1 req/sec policy)
  if (!sources.includes("OpenStreetMap (Overpass)")) {
    for (const [k, am] of [["fuel", "fuel"], ["wc", "toilets"], ["ev", "charging_station"]]) {
      if (out[k].length) continue;
      await sleep(1100);
      try { out[k] = await nominatimNearby(lat, lon, am, k); if (!sources.includes("OpenStreetMap (Nominatim)")) sources.push("OpenStreetMap (Nominatim)"); } catch (e) {}
    }
  }
  updatePin(id, p => { p.nearby = Object.assign(out, { status: sources.length ? "ok" : "error", errors, sources, at: Date.now() }); });
  enriching.delete(id); rerender(id);
}

/* ---------- cautions (only things we actually know) ---------- */
function cautions(pin) {
  const L = [], now = new Date(), s = sunTimes(now, pin.lat, pin.lon), w = pin.weather;
  if (!isNaN(s.sunset)) {
    if (now > s.sunset || now < s.sunrise) L.push("It's dark now (sunset " + hm(s.sunset) + "). Pick a lit, open pull-off and keep your hazards and headlights in mind.");
    else if ((s.sunset - now) / 60000 < 75) L.push("Sunset at " + hm(s.sunset) + ", less than 75 minutes away. Plan how you'll get back to the car in low light.");
  }
  if (w) {
    if ([95, 96, 99].includes(w.code)) L.push("Thunderstorm reported. Lightning risk: stay in the car, skip exposed spots and tripods.");
    if ([45, 48].includes(w.code) || (w.vis != null && w.vis < 1600)) L.push("Low visibility (fog/haze). Pull fully off the road and use lights when stopping.");
    if ([56, 57, 66, 67, 71, 73, 75, 77, 85, 86].includes(w.code) || (w.t != null && w.t <= 34)) L.push("Near or below freezing: shoulders and bridges may be icy.");
    if (w.gust != null && w.gust >= 25) L.push("Gusts around " + Math.round(w.gust) + " mph. Watch car doors and weigh down the tripod.");
    if (w.precip > 0 || (w.rainChance != null && w.rainChance >= 60)) L.push("Rain likely (" + (w.rainChance != null ? w.rainChance + "%" : "now") + "). Soft shoulders can be muddy; protect gear.");
    if (w.feels != null && w.feels >= 95) L.push("Feels like " + Math.round(w.feels) + "°F. Bring water; don't leave pets or gear in a hot car.");
    if (w.uv != null && w.uv >= 7) L.push("High UV today (" + Math.round(w.uv) + ").");
  }
  if (pin.acc && pin.acc > 100) L.push("GPS accuracy was about " + pin.acc + " m, so the pin may be off. Double-check on the map.");
  return L;
}
function weatherLine(w) {
  if (!w) return "";
  const parts = [WMO[w.code] || "", w.t != null ? Math.round(w.t) + "°F" : "", w.feels != null ? "feels " + Math.round(w.feels) + "°F" : "",
    w.wind != null ? "wind " + Math.round(w.wind) + " mph" + (w.gust ? " (gusts " + Math.round(w.gust) + ")" : "") : "",
    w.rainChance != null ? w.rainChance + "% rain today" : ""].filter(Boolean);
  return parts.join(" · ");
}

/* ---------- voice input ---------- */
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
function dictate(btn, target, onDone) {
  if (!SR) { target.focus(); toast(isIOS ? "Tap the text box, then the 🎤 on your keyboard." : "Voice not supported here; type or use keyboard mic.", 4000); return; }
  if (btn._rec) { btn._rec.stop(); return; }
  const rec = new SR(); rec.lang = navigator.language || "en-US"; rec.interimResults = true; rec.continuous = false;
  const base = target.value ? target.value.replace(/\s*$/, " ") : "";
  rec.onresult = ev => { let t = ""; for (let i = 0; i < ev.results.length; i++) t += ev.results[i][0].transcript; target.value = base + t; };
  rec.onerror = ev => { toast("Mic: " + (ev.error === "not-allowed" ? "permission denied" : ev.error), 3500); };
  rec.onend = () => { btn._rec = null; btn.classList.remove("on"); btn.textContent = btn.dataset.label; onDone && onDone(target.value); };
  btn._rec = rec; btn.classList.add("on"); btn.textContent = "■ Stop listening";
  buzz(40);
  try { rec.start(); } catch (e) { btn._rec = null; btn.classList.remove("on"); btn.textContent = btn.dataset.label; toast("Mic couldn't start", 3000); }
}

/* ---------- rendering ---------- */
function poiList(items, pin, empty) {
  if (!items || !items.length) return `<p class="mut small">${empty}</p>`;
  return items.map(x => `<div class="poi"><div class="t"><b>${esc(x.name)}</b><span class="mut small">${x.mi.toFixed(1)} mi${x.addr ? " · " + esc(x.addr) : ""}${x.facts.length ? "<br>" + x.facts.map(esc).join(" · ") : ""}<br>Source: ${esc(x.src)}</span></div>
    <a class="btn acc" href="${navUrl(x.lat, x.lon, x.name)}" target="_blank" rel="noopener">Navigate</a></div>`).join("");
}
function renderHome() {
  $("#backBtn").hidden = true;
  const pins = loadPins().sort((a, b) => b.ts - a.ts);
  const showSafety = !localStorage.getItem("sas.safetyOK");
  view.innerHTML = `
  ${showSafety ? `<div class="card safety"><b>Drive safe.</b> Don't tap this app while the car is moving. Use the Siri / Google shortcut (see <a href="#/help" style="color:inherit">Setup</a>) or hand the phone to a passenger.<div class="row" style="margin-top:10px"><button class="btn" id="okSafety">Got it</button></div></div>` : ""}
  <button class="mark" id="markBtn"><span>Mark this spot</span><small>Saves GPS + time instantly</small></button>
  <div class="card"><h2>Quick tag for the next spot <span class="mut small">(optional)</span></h2>
    <div class="chips" id="preTags">${TAGS.map(t => `<button class="chip" data-t="${esc(t)}">${esc(t)}</button>`).join("")}</div></div>
  <h2 style="margin:18px 4px 6px">Saved spots (${pins.length})</h2>
  ${pins.length ? pins.map(p => `<a class="pin" href="#/pin/${p.id}"><b>${esc(p.name || "Spot " + p.lat.toFixed(4) + ", " + p.lon.toFixed(4))}</b><br>
    <span class="mut">${fmtTime(p.ts)}</span><br>${(p.tags || []).map(t => `<span class="tag">${esc(t)}</span>`).join("")}${p.note ? `<span class="mut small"> ${esc(p.note.slice(0, 80))}</span>` : ""}</a>`).join("")
    : `<p class="mut">No spots yet. Tap the big button when you stop somewhere worth remembering.</p>`}
  <div class="card"><h2>Backup & export</h2><div class="row">
    <button class="btn" data-exp="gpx">GPX</button><button class="btn" data-exp="csv">CSV</button><button class="btn" data-exp="json">JSON</button>
    <label class="btn" style="cursor:pointer">Import<input type="file" id="imp" accept=".json,application/json" hidden></label></div>
    <p class="mut small">GPX opens in most map apps. JSON is a full backup you can import on another phone or browser.</p></div>
  <p class="mut small" style="text-align:center">${esc(APP_NAME)} v${esc(CFG.VERSION)} · Data stays on this phone · Map data © OpenStreetMap contributors · EV data: U.S. DOE AFDC · Weather: Open-Meteo</p>`;
  const pre = new Set();
  $("#markBtn").onclick = () => markSpot({ tags: [...pre] });
  view.querySelectorAll("#preTags .chip").forEach(c => c.onclick = () => { const t = c.dataset.t; pre.has(t) ? pre.delete(t) : pre.add(t); c.classList.toggle("sel"); buzz(20); });
  const ok = $("#okSafety"); if (ok) ok.onclick = () => { localStorage.setItem("sas.safetyOK", "1"); renderHome(); };
  view.querySelectorAll("[data-exp]").forEach(b => b.onclick = () => exportPins(b.dataset.exp));
  $("#imp").onchange = ev => importPins(ev.target.files[0]);
}
function renderPin(id) {
  const p = getPin(id); if (!p) { location.hash = "#/"; return; }
  $("#backBtn").hidden = false;
  const s = sunTimes(new Date(), p.lat, p.lon), nb = p.nearby || {}, cs = cautions(p);
  const label = p.name || "Spot";
  const status = nb.status === "loading" ? `<p class="warn">Looking up nearby places… (can take up to a minute on a weak signal)</p>`
    : nb.status === "offline" ? `<p class="warn">You're offline. The spot is saved; nearby info will load when you reconnect.</p>`
    : nb.status === "error" ? `<p class="warn">Couldn't load nearby places. The spot is still saved.</p>` : "";
  view.innerHTML = `
  <div class="card"><div class="big">${esc(label)}</div>
    <div class="mut">${fmtTime(p.ts)}</div>
    <div class="mut small">${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}${p.acc ? " · ±" + p.acc + " m" : ""}</div>
    <div class="row" style="margin-top:12px">
      <a class="btn acc" href="${navUrl(p.lat, p.lon, label)}" target="_blank" rel="noopener">Navigate here</a>
      <a class="btn" href="${viewUrl(p.lat, p.lon, label)}" target="_blank" rel="noopener">Open in Maps</a>
      <button class="btn" id="shareBtn">Share</button></div></div>

  <div class="card"><h2>Tags</h2><div class="chips" id="tags">${TAGS.concat((p.tags || []).filter(t => !TAGS.includes(t))).map(t => `<button class="chip ${(p.tags || []).includes(t) ? "sel" : ""}" data-t="${esc(t)}">${esc(t)}</button>`).join("")}</div></div>

  <div class="card"><h2>Voice note</h2>
    <textarea id="note" placeholder="What's here? Best angle, time to come back…">${esc(p.note)}</textarea>
    <div class="row" style="margin-top:10px"><button class="btn acc" id="noteMic" data-label="🎤 Speak note">🎤 Speak note</button></div></div>

  <div class="card"><h2>Parking &amp; cautions</h2>
    <p class="small"><b>Parking rules aren't in any reliable public data.</b> Always confirm on posted signs (no-parking zones, hours, permits, towing, private property). Write what you see below.</p>
    <textarea id="parking" placeholder="e.g. 2-hr limit, free lot behind church, no stopping on shoulder">${esc(p.parking)}</textarea>
    <div class="row" style="margin-top:10px"><button class="btn acc" id="parkMic" data-label="🎤 Speak parking/cautions">🎤 Speak parking/cautions</button></div>
    <h3>Nearby parking in OpenStreetMap</h3>${nb.status === "ok" && (nb.sources || []).includes("OpenStreetMap (Overpass)") ? poiList(nb.parking, p, "No mapped parking lots within ½ mile.") : `<p class="mut small">${nb.status === "loading" ? "Loading…" : "Not loaded (needs the OpenStreetMap Overpass service). Tap Refresh below."}</p>`}
    <h3>Be aware right now</h3>${cs.length ? `<ul class="check">${cs.map(c => `<li>${esc(c)}</li>`).join("")}</ul>` : `<p class="mut small">Nothing flagged from weather, light, or GPS.</p>`}
    <h3>Every stop</h3><ul class="check small">
      <li>Pull fully off the road; shoulders are for emergencies in many states.</li>
      <li>Watch for No Trespassing / private property signs before walking in.</li>
      <li>Check footing near water, ditches, and soft shoulders; mind traffic when you get out.</li>
      <li>Lock the car and keep gear out of sight.</li></ul></div>

  <div class="card"><h2>Light for photos</h2>
    <div>${p.weather ? esc(weatherLine(p.weather)) : `<span class="mut small">Weather loads when online.</span>`}</div>
    <ul class="check">
      <li>Sunrise ${hm(s.sunrise)} · golden hour until ${hm(s.goldenMorningEnd)}</li>
      <li>Golden hour from ${hm(s.goldenEveningStart)} · sunset ${hm(s.sunset)}</li>
      <li>Blue hour ${hm(s.blueMorning[0])}–${hm(s.blueMorning[1])} and ${hm(s.blueEvening[0])}–${hm(s.blueEvening[1])}</li></ul>
    <p class="mut small">Times for today at this spot, shown in your phone's time zone. Calculated on the phone.</p></div>

  <div class="card"><h2>Nearby</h2>${status}
    <h3>⚡ EV charging</h3>${nb.status === "ok" || (nb.ev && nb.ev.length) ? poiList(nb.ev, p, "None found within 10 miles.") : ""}
    <h3>⛽ Gas</h3>${nb.status === "ok" ? poiList(nb.fuel, p, "None found nearby.") : ""}
    <h3>🚻 Restroom</h3>${nb.status === "ok" ? poiList(nb.wc, p, "No public restroom mapped nearby. Gas stations and fast food are your best bet.") : ""}
    ${nb.status === "ok" ? `<p class="mut small">From ${esc((nb.sources || []).join(", ") || "—")}, ${nb.at ? fmtTime(nb.at) : ""}. Hours and access aren't guaranteed; call ahead if it matters.${nb.errors && nb.errors.length ? "<br>Didn't respond: " + nb.errors.map(esc).join("; ") + ". Tap Refresh to try again." : ""}</p>` : ""}
    <div class="row" style="margin-top:8px"><button class="btn" id="retry" ${nb.status === "loading" ? "disabled" : ""}>${nb.status === "error" || nb.status === "offline" ? "Retry" : "Refresh"}</button></div></div>

  <div class="card"><div class="row"><button class="btn" id="copyBtn">Copy coordinates</button><button class="btn bad" id="delBtn">Delete spot</button></div></div>`;

  $("#shareBtn").onclick = () => sharePin(p);
  $("#copyBtn").onclick = () => copy(`${p.lat}, ${p.lon}`);
  $("#delBtn").onclick = () => { if (confirm("Delete this spot?")) { savePins(loadPins().filter(x => x.id !== p.id)); toast("Deleted"); location.hash = "#/"; } };
  $("#retry").onclick = () => enrich(p.id, true);
  view.querySelectorAll("#tags .chip").forEach(c => c.onclick = () => {
    const t = c.dataset.t; updatePin(p.id, x => { x.tags = x.tags || []; x.tags.includes(t) ? x.tags.splice(x.tags.indexOf(t), 1) : x.tags.push(t); });
    c.classList.toggle("sel"); buzz(20);
  });
  const save = (field) => (val) => { updatePin(p.id, x => { x[field] = val; }); };
  const note = $("#note"), park = $("#parking");
  note.oninput = () => save("note")(note.value); park.oninput = () => save("parking")(park.value);
  $("#noteMic").onclick = ev => dictate(ev.currentTarget, note, v => { save("note")(v); speak("Note saved"); });
  $("#parkMic").onclick = ev => dictate(ev.currentTarget, park, v => { save("parking")(v); speak("Saved"); });
  if (!p.nearby || (p.nearby.status === "offline" && navigator.onLine)) enrich(p.id);
}
function renderHelp() {
  $("#backBtn").hidden = false;
  const url = new URL("./?mark=1", location.href).href;
  view.innerHTML = `
  <div class="card safety"><b>Safety first.</b> Never tap or read the app while the car is moving. Use a voice shortcut, wait until you're parked, or hand it to a passenger.</div>
  <div class="card"><h2>1. Install on your phone</h2>
    <p><b>iPhone (Safari):</b> tap Share <span class="mut">(square with arrow)</span> → <b>Add to Home Screen</b> → Add.</p>
    <p><b>Android (Chrome):</b> tap ⋮ → <b>Add to Home screen</b> or <b>Install app</b>. Then long-press the icon for a <b>Mark spot</b> shortcut.</p>
    <p class="mut small">${isStandalone ? "✅ You're using the installed app." : "You're in the browser right now."}</p></div>
  <div class="card"><h2>2. "Hey Siri, mark spot" (iPhone)</h2>
    <ol class="steps"><li>Open the <b>Shortcuts</b> app → <b>+</b>.</li>
      <li>Optional, for a spoken note: add <b>Dictate Text</b>.</li>
      <li>Add <b>Open URLs</b> and paste this link:<br><code id="mk">${esc(url)}</code><br><button class="btn" id="copyMk" style="margin-top:8px">Copy link</button><br>
        <span class="small mut">For a spoken note, use <code>${esc(url)}&amp;note=</code> and then insert the <b>Dictated Text</b> variable at the end.</span></li>
      <li>Name the shortcut <b>Mark spot</b>. Now say <b>"Hey Siri, mark spot."</b></li></ol>
    <p class="small warn">On iPhone, Siri opens the link in Safari, and Safari keeps its own list separate from the Home Screen app. Pick one place to keep your spots, or move them with Export JSON → Import.</p></div>
  <div class="card"><h2>3. Google Assistant (Android)</h2>
    <ol class="steps"><li>Install the app (step 1). Long-press its icon → drag <b>Mark spot</b> to your home screen for one-tap marking.</li>
      <li>Hands-free: say <b>"Hey Google, open ${esc(APP_NAME)}"</b>, or set up a Google Assistant routine that opens the link above.</li></ol></div>
  <div class="card"><h2>Good to know</h2><ul class="check small">
    <li>Spots are saved on this phone only. Export a JSON backup now and then.</li>
    <li>The app can't listen in the background or hear "Hey Grok". Use Siri or Google for wake words.</li>
    <li>Voice notes use your browser's speech recognition. If 🎤 doesn't work, tap the text box and use the keyboard mic.</li>
    <li>Saved spots work offline. Nearby places and weather need a connection, and they load automatically when you're back online.</li></ul></div>`;
  $("#copyMk").onclick = () => copy(url);
}
function rerender(id) { const m = location.hash.match(/^#\/pin\/(.+)$/); if (m && m[1] === id) { const a = document.activeElement; if (a && a.tagName === "TEXTAREA") return; renderPin(id); } }
function route() {
  const h = location.hash; window.scrollTo(0, 0);
  const m = h.match(/^#\/pin\/(.+)$/);
  if (m) renderPin(m[1]); else if (h === "#/help") renderHelp(); else renderHome();
}

/* ---------- share / export / import ---------- */
async function copy(t) { try { await navigator.clipboard.writeText(t); toast("Copied"); } catch (e) { prompt("Copy:", t); } }
async function sharePin(p) {
  const text = `${p.name || "Spot"} (${p.lat}, ${p.lon})${p.note ? "\n" + p.note : ""}`;
  const url = `https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lon}`;
  if (navigator.share) { try { await navigator.share({ title: p.name || "Spot", text, url }); } catch (e) {} } else copy(text + "\n" + url);
}
function xml(s) { return esc(s); }
function exportPins(kind) {
  const pins = loadPins().sort((a, b) => a.ts - b.ts); let body, type, ext = kind;
  if (kind === "json") { body = JSON.stringify({ app: APP_NAME, exported: new Date().toISOString(), pins }, null, 2); type = "application/json"; }
  else if (kind === "csv") {
    const q = v => `"${String(v == null ? "" : v).replace(/"/g, '""')}"`;
    body = "time_iso,lat,lon,accuracy_m,name,tags,note,parking_cautions\n" + pins.map(p => [new Date(p.ts).toISOString(), p.lat, p.lon, p.acc, p.name, (p.tags || []).join("; "), p.note, p.parking].map(q).join(",")).join("\n");
    type = "text/csv";
  } else {
    body = `<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="${xml(APP_NAME)}" xmlns="http://www.topografix.com/GPX/1/1">\n` +
      pins.map(p => `<wpt lat="${p.lat}" lon="${p.lon}"><time>${new Date(p.ts).toISOString()}</time><name>${xml(p.name || "Spot")}</name><desc>${xml([(p.tags || []).join(", "), p.note, p.parking && "Parking: " + p.parking].filter(Boolean).join(" | "))}</desc></wpt>`).join("\n") + "\n</gpx>";
    type = "application/gpx+xml";
  }
  const name = `spots-${new Date().toISOString().slice(0, 10)}.${ext}`;
  const file = new File([body], name, { type });
  if (navigator.canShare && navigator.canShare({ files: [file] })) { navigator.share({ files: [file], title: name }).catch(() => {}); return; }
  const a = document.createElement("a"); a.href = URL.createObjectURL(file); a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}
function importPins(f) {
  if (!f) return; const r = new FileReader();
  r.onload = () => {
    try {
      const j = JSON.parse(r.result); const incoming = Array.isArray(j) ? j : j.pins; if (!Array.isArray(incoming)) throw 0;
      const pins = loadPins(); let n = 0;
      for (const p of incoming) if (p && p.id && typeof p.lat === "number" && typeof p.lon === "number" && !pins.some(x => x.id === p.id)) { pins.push(p); n++; }
      savePins(pins); toast(`Imported ${n} spot${n === 1 ? "" : "s"}`); renderHome();
    } catch (e) { toast("That file isn't a spots backup", 3500); }
  };
  r.readAsText(f);
}

/* ---------- boot ---------- */
function net() { $("#netDot").classList.toggle("off", !navigator.onLine); $("#netDot").title = navigator.onLine ? "Online" : "Offline"; }
addEventListener("online", () => { net(); loadPins().filter(p => !p.nearby || p.nearby.status === "offline" || p.nearby.status === "error").forEach(p => enrich(p.id)); });
addEventListener("offline", net); net();
addEventListener("hashchange", route);
$("#backBtn").onclick = () => { location.hash = "#/"; };
$("#helpBtn").onclick = () => { location.hash = "#/help"; };
document.addEventListener("visibilitychange", () => document.hidden ? stopWatch() : startWatch());
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});

const params = new URLSearchParams(location.search);
route();
startWatch();
if (params.get("mark") === "1") {
  const note = params.get("note") || ""; const tag = params.get("tag");
  history.replaceState(null, "", location.pathname + location.hash);
  markSpot({ note, tags: tag ? [tag] : [] });
}
})();
