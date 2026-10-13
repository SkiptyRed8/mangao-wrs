// Map helpers for the address pin: the Quezon City barangay list, "Pinned: near ..." text for a pin,
// and street / place search. Pin text and search use OpenStreetMap Nominatim (free) from the server,
// with a short cache; if it cannot be reached, the app still works with the pin alone.
const { Router } = require('express');
const { HttpError, bad } = require('../utils/errors');
const { text } = require('../utils/validate');
const { BARANGAYS, inArea } = require('../services/addresses');

const router = Router();
const NOMINATIM = 'https://nominatim.openstreetmap.org';
const HEADERS = { 'User-Agent': 'MangaoWRS/1.0 (school project, Quezon City)', 'Accept-Language': 'en' };
const cache = new Map();

async function nominatim(path) {
  if (cache.has(path)) return cache.get(path);
  let res;
  try {
    res = await fetch(`${NOMINATIM}${path}`, { headers: HEADERS, signal: AbortSignal.timeout(6000) });
  } catch {
    throw new HttpError(503, 'MAP_OFFLINE', 'Map search not available', 'Move the pin by hand, or type the address.');
  }
  if (!res.ok) throw new HttpError(503, 'MAP_OFFLINE', 'Map search not available', 'Move the pin by hand, or type the address.');
  const data = await res.json();
  if (cache.size > 500) cache.clear();
  cache.set(path, data);
  return data;
}

/** Nominatim address -> our fields (barangay = the QC barangay when the name matches). */
function fields(addr = {}) {
  const lower = new Map(BARANGAYS.map((b) => [b.toLowerCase(), b]));
  const candidates = [addr.quarter, addr.neighbourhood, addr.suburb, addr.village, addr.city_district].filter(Boolean);
  const barangay = candidates.map((c) => lower.get(String(c).replace(/^barangay /i, '').toLowerCase())).find(Boolean) || candidates[0] || '';
  return { house: addr.house_number || '', street: addr.road || addr.pedestrian || addr.residential || '', barangay };
}

// GET /api/geo/barangays -> { barangays } (A to Z)
router.get('/barangays', (req, res) => res.json({ barangays: BARANGAYS, city: 'Quezon City' }));

// GET /api/geo/reverse?lat=&lng= -> { street, barangay, label }
router.get('/reverse', async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !inArea(lat, lng)) throw bad('OUTSIDE_AREA', 'Outside delivery area', 'Place the pin in Quezon City.');
  const key = `/reverse?format=jsonv2&zoom=18&addressdetails=1&lat=${lat.toFixed(5)}&lon=${lng.toFixed(5)}`;
  const d = await nominatim(key);
  const f = fields(d.address);
  const label = [[f.house, f.street].filter(Boolean).join(' '), f.barangay].filter(Boolean).join(', ');
  res.json({ ...f, label: label || 'the map pin' });
});

// GET /api/geo/search?q= -> { results: [{ label, lat, lng }] } (Quezon City only)
router.get('/search', async (req, res) => {
  const q = text(req.query.q, 100);
  if (q.length < 3) return res.json({ results: [] });
  const key = `/search?format=jsonv2&addressdetails=1&limit=6&countrycodes=ph&bounded=1&viewbox=120.98,14.78,121.14,14.58&q=${encodeURIComponent(q)}`;
  const d = await nominatim(key);
  res.json({
    results: d.map((r) => ({
      label: r.display_name.split(', ').slice(0, 3).join(', '),
      lat: Number(r.lat),
      lng: Number(r.lon),
    })),
  });
});

module.exports = router;
