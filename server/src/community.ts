// Topluluk öneri havuzu: seyahati biten kullanıcıların onayla paylaştığı yerler ve "A'dan sonra B" geçişleri.
// Bir yer ya da geçiş, en az MIN_CONTRIBUTORS farklı kişi katkı verdiyse dışarı verilir (k-anonimlik).

export const MIN_CONTRIBUTORS = 3;
export const DAILY_QUOTA = 300;
/// Aynı yer sayılacak en büyük uzaklık (metre).
const SAME_PLACE_METERS = 60;

/** D1 ile Node'un sqlite'ı arasında ortak en küçük arayüz (testlerde node:sqlite kullanılır). */
export interface Database {
  prepare(sql: string): Statement;
}
export interface Statement {
  bind(...values: unknown[]): Statement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  run(): Promise<unknown>;
}

const KINDS = new Set(["sight", "food", "activity", "transport", "stay"]);

export interface ContributedPlace {
  ref: string;
  name: string;
  lat: number;
  lon: number;
  kind: string;
  category?: string;
  /** 1 beğendi, -1 beğenmedi, 0 belirtmedi. */
  liked: number;
  /** Fotoğraflarla gidildiği doğrulandı mı. */
  verified: boolean;
}

export interface Contribution {
  country: string;
  places: ContributedPlace[];
  /** Aynı gün art arda gidilen yerlerin `ref` çiftleri. */
  transitions: [string, string][];
}

export function validate(body: unknown): Contribution | string {
  const c = body as Partial<Contribution>;
  if (typeof c?.country !== "string" || !/^[A-Z]{2}$/.test(c.country)) return "country";
  if (!Array.isArray(c.places) || c.places.length === 0 || c.places.length > 60) return "places";
  const refs = new Set<string>();
  for (const p of c.places) {
    if (typeof p?.ref !== "string" || p.ref.length > 64 || refs.has(p.ref)) return "ref";
    refs.add(p.ref);
    if (typeof p.name !== "string" || !isPlausibleName(p.name)) return "name";
    if (typeof p.lat !== "number" || typeof p.lon !== "number" || Math.abs(p.lat) > 90 || Math.abs(p.lon) > 180) return "coordinate";
    if (!KINDS.has(p.kind)) return "kind";
    if (![1, 0, -1].includes(p.liked)) return "liked";
    if (typeof p.verified !== "boolean") return "verified";
    if (p.category !== undefined && (typeof p.category !== "string" || p.category.length > 60)) return "category";
  }
  const transitions = c.transitions ?? [];
  if (!Array.isArray(transitions) || transitions.length > 60) return "transitions";
  for (const t of transitions) {
    if (!Array.isArray(t) || t.length !== 2 || !refs.has(t[0]) || !refs.has(t[1]) || t[0] === t[1]) return "transition";
  }
  return { country: c.country, places: c.places, transitions };
}

/** Yer adı gibi görünüyor mu: bağlantı, e-posta, telefon numarası ya da yalnızca rakam/simge değil. */
export function isPlausibleName(name: string): boolean {
  const text = name.trim();
  if (text.length < 2 || text.length > 80 || !/\p{L}/u.test(text)) return false;
  if (/https?:|www\.|\.(com|net|org|io|ru|xyz)\b|@|t\.me\//i.test(text)) return false;
  if ((text.match(/\d/g) ?? []).length >= 7) return false; // telefon numarası
  return !/(.)\1{5,}/.test(text); // "!!!!!!", "aaaaaa"
}

/** Bildirimle gizlenme: en az 3 farklı kişi bildirdiyse ya da bildiren sayısı katkı verenlerin yarısına ulaştıysa. */
export const REPORT_FILTER = "(SELECT COUNT(*) FROM reports r WHERE r.place_id = p.id)";
const VISIBLE = `${REPORT_FILTER} < 3 AND ${REPORT_FILTER} * 2 < COUNT(*)`;

export const REPORT_REASONS = new Set(["wrong", "closed", "spam", "offensive"]);

export async function report(db: Database, contributor: string, placeID: number, reason: string, now = Date.now()): Promise<boolean> {
  if (!Number.isInteger(placeID) || !REPORT_REASONS.has(reason)) return false;
  const exists = await db.prepare("SELECT id FROM places WHERE id = ?").bind(placeID).first<{ id: number }>();
  if (!exists) return false;
  await db.prepare(
    `INSERT INTO reports (place_id, contributor, reason, created_at) VALUES (?, ?, ?, ?)
     ON CONFLICT (place_id, contributor) DO UPDATE SET reason = excluded.reason, created_at = excluded.created_at`,
  ).bind(placeID, contributor, reason, now).run();
  return true;
}

export async function contributorHash(rawID: string, salt: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}:${rawID}`));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function metersBetween(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const r = 6_371_000, toRad = Math.PI / 180;
  const dLat = (lat2 - lat1) * toRad, dLon = (lon2 - lon1) * toRad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function normalize(name: string): string {
  return name.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

/** Aynı yer: 60 m içinde ve adları örtüşüyor (dil farkı olabilir; çok yakınsa ad şartı aranmaz). */
async function findOrCreatePlace(db: Database, country: string, p: ContributedPlace, now: number): Promise<number> {
  const dLat = 0.001, dLon = 0.001 / Math.max(0.2, Math.cos((p.lat * Math.PI) / 180));
  const { results } = await db.prepare(
    "SELECT id, name, lat, lon FROM places WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
  ).bind(p.lat - dLat, p.lat + dLat, p.lon - dLon, p.lon + dLon).all<{ id: number; name: string; lat: number; lon: number }>();
  const target = normalize(p.name);
  const match = results
    .map((r) => ({ ...r, distance: metersBetween(p.lat, p.lon, r.lat, r.lon) }))
    .filter((r) => r.distance <= SAME_PLACE_METERS &&
      (r.distance <= 15 || normalize(r.name).split(" ").some((w) => w.length > 2 && target.includes(w))))
    .sort((a, b) => a.distance - b.distance)[0];
  if (match) return match.id;
  const row = await db.prepare(
    "INSERT INTO places (country, name, lat, lon, kind, category, created_at) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id",
  ).bind(country, p.name.trim(), p.lat, p.lon, p.kind, p.category ?? "", now).first<{ id: number }>();
  return row!.id;
}

/** Katkıyı kaydeder; günlük kota aşılırsa false. */
export async function contribute(db: Database, contributor: string, c: Contribution, now = Date.now()): Promise<boolean> {
  const day = new Date(now).toISOString().slice(0, 10);
  const used = await db.prepare("SELECT count FROM quotas WHERE contributor = ? AND day = ?")
    .bind(contributor, day).first<{ count: number }>();
  const cost = c.places.length + c.transitions.length;
  if ((used?.count ?? 0) + cost > DAILY_QUOTA) return false;
  await db.prepare(
    "INSERT INTO quotas (contributor, day, count) VALUES (?, ?, ?) ON CONFLICT (contributor, day) DO UPDATE SET count = count + excluded.count",
  ).bind(contributor, day, cost).run();

  const ids = new Map<string, number>();
  for (const p of c.places) {
    const id = await findOrCreatePlace(db, c.country, p, now);
    ids.set(p.ref, id);
    // Aynı kişi tekrar katkı verirse oyu güncellenir; "gidildi" bir kez doğrulandıysa öyle kalır.
    await db.prepare(
      `INSERT INTO votes (place_id, contributor, liked, verified, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (place_id, contributor) DO UPDATE SET liked = excluded.liked,
         verified = MAX(verified, excluded.verified), updated_at = excluded.updated_at`,
    ).bind(id, contributor, p.liked, p.verified ? 1 : 0, now).run();
  }
  for (const [from, to] of c.transitions) {
    const a = ids.get(from), b = ids.get(to);
    if (a === undefined || b === undefined || a === b) continue;
    await db.prepare(
      `INSERT INTO transitions (from_id, to_id, contributor, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (from_id, to_id, contributor) DO UPDATE SET updated_at = excluded.updated_at`,
    ).bind(a, b, contributor, now).run();
  }
  return true;
}

export interface CommunityPlace {
  id: number;
  name: string;
  lat: number;
  lon: number;
  kind: string;
  category: string;
  /** Katkı veren farklı kişi sayısı. */
  contributors: number;
  likes: number;
  dislikes: number;
  verified: number;
  score: number;
}

/** Puan: fotoğrafla doğrulanmış ziyaret 2, beğeni 3, beğenmeme -3, düz katkı 1. */
const SCORE_SQL = "SUM(1 + v.verified + CASE v.liked WHEN 1 THEN 3 WHEN -1 THEN -3 ELSE 0 END)";

export async function nearby(db: Database, lat: number, lon: number, radiusMeters = 8000, limit = 40): Promise<CommunityPlace[]> {
  const dLat = radiusMeters / 111_000, dLon = radiusMeters / (111_000 * Math.max(0.2, Math.cos((lat * Math.PI) / 180)));
  const { results } = await db.prepare(
    `SELECT p.id, p.name, p.lat, p.lon, p.kind, p.category,
            COUNT(*) AS contributors,
            SUM(v.liked = 1) AS likes, SUM(v.liked = -1) AS dislikes, SUM(v.verified) AS verified,
            ${SCORE_SQL} AS score
       FROM places p JOIN votes v ON v.place_id = p.id
      WHERE p.lat BETWEEN ? AND ? AND p.lon BETWEEN ? AND ?
      GROUP BY p.id
     HAVING contributors >= ? AND likes >= dislikes AND ${VISIBLE}
      ORDER BY score DESC
      LIMIT ?`,
  ).bind(lat - dLat, lat + dLat, lon - dLon, lon + dLon, MIN_CONTRIBUTORS, limit).all<CommunityPlace>();
  return results;
}

export interface NextPlace extends CommunityPlace {
  /** Bu yerden sonra buraya giden farklı kişi sayısı. */
  followers: number;
}

/** Verilen konumdaki yerden (60 m) sonra aynı gün en sık gidilen yerler. */
export async function nextPlaces(db: Database, lat: number, lon: number, limit = 5): Promise<NextPlace[]> {
  const d = 0.0006;
  const { results } = await db.prepare(
    `SELECT p.id, p.name, p.lat, p.lon, p.kind, p.category,
            COUNT(DISTINCT t.contributor) AS followers
       FROM transitions t
       JOIN places f ON f.id = t.from_id
       JOIN places p ON p.id = t.to_id
      WHERE f.lat BETWEEN ? AND ? AND f.lon BETWEEN ? AND ?
      GROUP BY p.id
     HAVING followers >= ? AND ${REPORT_FILTER} < 3
      ORDER BY followers DESC
      LIMIT ?`,
  ).bind(lat - d, lat + d, lon - d * 1.5, lon + d * 1.5, MIN_CONTRIBUTORS, limit)
    .all<NextPlace>();
  return results.map((r) => ({ ...r, contributors: r.followers, likes: 0, dislikes: 0, verified: 0, score: r.followers }));
}
