// convex/lib/slLocations.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Sierra Leone administrative locations (regions → districts → towns).
//
// Used for (a) location pickers at registration / listing creation and (b) building the ONLY
// public location shown for a listing: "Inside <Town>, Sierra Leone". Public text is always
// taken from this allow-list, never from user-typed text, so an exact street address typed into
// a "city" field can never leak.
// Extend the town lists freely; keep names in their common English spelling.
// ═══════════════════════════════════════════════════════════════════════

export type SlDistrict = { district: string; region: string; towns: string[] };

export const SL_DISTRICTS: SlDistrict[] = [
  // Western Area
  {
    district: "Western Area Urban",
    region: "Western Area",
    towns: [
      "Freetown", "Aberdeen", "Lumley", "Goderich", "Wilberforce", "Hill Station", "Murray Town",
      "Congo Town", "Brookfields", "Tengbeh Town", "Kingtom", "Cline Town", "Fourah Bay", "Kissy",
      "Wellington", "Calaba Town", "Allen Town", "Mountain Cut", "Signal Hill", "Juba",
    ],
  },
  {
    district: "Western Area Rural",
    region: "Western Area",
    towns: [
      "Waterloo", "Hastings", "Grafton", "Regent", "Kent", "York", "Tombo", "Lakka", "Hamilton",
      "Sussex", "Bureh Town", "Kerry Town", "Newton", "Jui", "Leicester", "Gloucester", "Bathurst",
      "Charlotte", "Benguema", "Lumpa",
    ],
  },
  // North West Province
  { district: "Kambia", region: "North West Province", towns: ["Kambia", "Rokupr", "Kassiri", "Mange"] },
  { district: "Port Loko", region: "North West Province", towns: ["Port Loko", "Lunsar", "Lungi", "Pepel", "Masiaka", "Rokel"] },
  { district: "Karene", region: "North West Province", towns: ["Kamakwie", "Batkanu", "Kagbere"] },
  // Northern Province
  { district: "Bombali", region: "Northern Province", towns: ["Makeni", "Kamabai", "Binkolo", "Karina"] },
  { district: "Falaba", region: "Northern Province", towns: ["Bendugu", "Musaia"] },
  { district: "Koinadugu", region: "Northern Province", towns: ["Kabala", "Fadugu", "Alikalia"] },
  { district: "Tonkolili", region: "Northern Province", towns: ["Magburaka", "Mile 91", "Bumbuna", "Yele", "Masingbi", "Matotoka"] },
  // Southern Province
  { district: "Bo", region: "Southern Province", towns: ["Bo", "Gerihun", "Sumbuya", "Telu", "Baoma", "Koribundu", "Tikonko"] },
  { district: "Bonthe", region: "Southern Province", towns: ["Bonthe", "Mattru Jong", "Tihun"] },
  { district: "Moyamba", region: "Southern Province", towns: ["Moyamba", "Shenge", "Rotifunk", "Njala", "Taiama", "Mano"] },
  { district: "Pujehun", region: "Southern Province", towns: ["Pujehun", "Zimmi", "Potoru", "Bandajuma"] },
  // Eastern Province
  { district: "Kailahun", region: "Eastern Province", towns: ["Kailahun", "Segbwema", "Pendembu", "Daru", "Koindu", "Buedu"] },
  { district: "Kenema", region: "Eastern Province", towns: ["Kenema", "Blama", "Tongo Field", "Hangha", "Panguma"] },
  { district: "Kono", region: "Eastern Province", towns: ["Koidu", "Yengema", "Tombodu", "Motema", "Jaiama"] },
];

const norm = (s: string) => s.trim().toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

const TOWN_INDEX = new Map<string, { town: string; district: string; region: string }>();
const DISTRICT_INDEX = new Map<string, SlDistrict>();
for (const d of SL_DISTRICTS) {
  DISTRICT_INDEX.set(norm(d.district), d);
  for (const t of d.towns) TOWN_INDEX.set(norm(t), { town: t, district: d.district, region: d.region });
}
// Common aliases
TOWN_INDEX.set(norm("Koidu Town"), TOWN_INDEX.get(norm("Koidu"))!);
TOWN_INDEX.set(norm("Kono"), TOWN_INDEX.get(norm("Koidu"))!);
TOWN_INDEX.set(norm("Freetown City"), TOWN_INDEX.get(norm("Freetown"))!);

export function findTown(name: string | undefined | null) {
  return name ? TOWN_INDEX.get(norm(name)) : undefined;
}
export function findDistrict(name: string | undefined | null) {
  return name ? DISTRICT_INDEX.get(norm(name)) : undefined;
}

/**
 * The public, generalized location for a listing. Built ONLY from the allow-list above:
 *   known town      -> "Inside <Town>, Sierra Leone"
 *   known district  -> "Inside <District>, Sierra Leone"
 *   anything else   -> "Inside Sierra Leone"
 */
export function publicLocation(city?: string | null, district?: string | null): string {
  const t = findTown(city);
  if (t) return `Inside ${t.town}, Sierra Leone`;
  const d = findDistrict(district) ?? findDistrict(city);
  if (d) return `Inside ${d.district}, Sierra Leone`;
  return "Inside Sierra Leone";
}

/** The canonical public town name (or undefined). */
export function publicTown(city?: string | null): string | undefined {
  return findTown(city)?.town;
}
