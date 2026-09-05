// convex/lib/geo.ts
// ═══════════════════════════════════════════════════════════════════════
// Geospatial Utilities: Geohash encoding + Haversine distance calculation
// Used by rides.ts, realEstateListings.ts, vehicleListings.ts
// ═══════════════════════════════════════════════════════════════════════

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/**
 * Encode latitude/longitude into a geohash string.
 * @param lat  Latitude (-90 to 90)
 * @param lng  Longitude (-180 to 180)
 * @param precision  Number of geohash characters (default 7 ≈ ±76m)
 *   Precision reference:
 *     4 → ±20km   (country-level filter)
 *     5 → ±2.4km  (city district)
 *     6 → ±610m   (neighborhood)
 *     7 → ±76m    (street block)
 *     8 → ±19m    (building)
 */
export function encodeGeohash(
  lat: number,
  lng: number,
  precision: number = 7
): string {
  let minLat = -90,
    maxLat = 90;
  let minLng = -180,
    maxLng = 180;
  let hash = "";
  let isLng = true;
  let bit = 0;
  let charIdx = 0;

  while (hash.length < precision) {
    if (isLng) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) {
        charIdx = (charIdx << 1) | 1;
        minLng = mid;
      } else {
        charIdx = charIdx << 1;
        maxLng = mid;
      }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) {
        charIdx = (charIdx << 1) | 1;
        minLat = mid;
      } else {
        charIdx = charIdx << 1;
        maxLat = mid;
      }
    }
    isLng = !isLng;
    bit++;
    if (bit === 5) {
      hash += BASE32[charIdx];
      bit = 0;
      charIdx = 0;
    }
  }
  return hash;
}

/**
 * Get neighboring geohash cells (8 neighbors + center = 9 cells).
 * This eliminates edge-case misses when a point is near a geohash boundary.
 */
export function geohashNeighbors(hash: string): string[] {
  if (hash.length === 0) return [hash];

  const { lat, lng } = decodeGeohash(hash);
  const precision = hash.length;

  // Approximate cell dimensions based on precision
  const latDelta = 180 / Math.pow(2, Math.ceil((precision * 5) / 2));
  const lngDelta = 360 / Math.pow(2, Math.floor((precision * 5) / 2));

  const offsets = [
    [0, 0],
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ];

  const neighbors = new Set<string>();
  for (const [dLat, dLng] of offsets) {
    const nLat = Math.max(-90, Math.min(90, lat + dLat * latDelta));
    const nLng = ((lng + dLng * lngDelta + 540) % 360) - 180;
    neighbors.add(encodeGeohash(nLat, nLng, precision));
  }
  return Array.from(neighbors);
}

/**
 * Decode a geohash back to approximate center lat/lng.
 */
export function decodeGeohash(hash: string): { lat: number; lng: number } {
  let minLat = -90,
    maxLat = 90;
  let minLng = -180,
    maxLng = 180;
  let isLng = true;

  for (const char of hash) {
    const idx = BASE32.indexOf(char);
    for (let bit = 4; bit >= 0; bit--) {
      const mask = 1 << bit;
      if (isLng) {
        const mid = (minLng + maxLng) / 2;
        if (idx & mask) {
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        const mid = (minLat + maxLat) / 2;
        if (idx & mask) {
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      isLng = !isLng;
    }
  }

  return {
    lat: (minLat + maxLat) / 2,
    lng: (minLng + maxLng) / 2,
  };
}

/**
 * Haversine formula: compute the great-circle distance between two points
 * on the Earth's surface.
 * @returns Distance in kilometers.
 */
export function haversineDistanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const EARTH_RADIUS_KM = 6371;
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return EARTH_RADIUS_KM * c;
}

/**
 * Determine geohash precision based on search radius.
 * Larger radius → coarser precision (fewer cells to search).
 */
export function precisionForRadiusKm(radiusKm: number): number {
  if (radiusKm <= 0.019) return 8;
  if (radiusKm <= 0.076) return 7;
  if (radiusKm <= 0.61) return 6;
  if (radiusKm <= 2.4) return 5;
  if (radiusKm <= 20) return 4;
  if (radiusKm <= 78) return 3;
  return 2;
}

/**
 * Validate latitude value.
 */
export function isValidLatitude(lat: number): boolean {
  return typeof lat === "number" && !isNaN(lat) && lat >= -90 && lat <= 90;
}

/**
 * Validate longitude value.
 */
export function isValidLongitude(lng: number): boolean {
  return typeof lng === "number" && !isNaN(lng) && lng >= -180 && lng <= 180;
}
