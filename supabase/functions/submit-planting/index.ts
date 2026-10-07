// The only write path for plantings: verifies a Cloudflare Turnstile token,
// validates the form, uploads the photo, inserts via the submit_planting RPC,
// and rewrites the public map snapshot.
// See docs/submission-edge-function-plan.md.

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

const ALLOWED_ORIGINS = ["https://aaronsexton.github.io", "http://localhost:4321"];
const MAX_PHOTO_BYTES = 15 * 1024 * 1024;
const PHOTO_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
const SEED_MIXTURES = ["full_sun", "partial_sun"];

// service role bypasses RLS; it is injected by the runtime and never leaves the server
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

async function verifyTurnstile(token: string, ip: string | null): Promise<boolean> {
  const secret = Deno.env.get("TURNSTILE_SECRET");
  if (!secret) {
    console.error("TURNSTILE_SECRET is not set");
    return false;
  }
  const body = new FormData();
  body.append("secret", secret);
  body.append("response", token);
  if (ip) body.append("remoteip", ip);
  try {
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body });
    const json = await res.json();
    return json.success === true;
  } catch (err) {
    console.error("Turnstile verification error", err);
    return false;
  }
}

// rewrites map-data/plantings.json from the public view; the map fetches this
// file instead of querying the database, so anon needs no database access
async function writeMapSnapshot(): Promise<void> {
  const { data, error } = await supabase
    .from("public_planting_map")
    .select("id, title, created_at, lat, lng");
  if (error) throw error;

  const geojson = {
    type: "FeatureCollection",
    features: data.map((p) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: [p.lng, p.lat] },
      properties: { id: p.id, title: p.title, created_at: p.created_at },
    })),
  };

  const { error: uploadError } = await supabase.storage
    .from("map-data")
    .upload("plantings.json", JSON.stringify(geojson), {
      contentType: "application/json",
      upsert: true,
      cacheControl: "60", // seconds the CDN and browsers may cache it
    });
  if (uploadError) throw uploadError;
}

function optionalString(form: FormData, key: string): string | null {
  const value = form.get(key);
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

export default {
  async fetch(req: Request): Promise<Response> {
    const headers = corsHeaders(req.headers.get("origin"));
    if (req.method === "OPTIONS") return new Response("ok", { headers });

    const json = (body: unknown, status: number) =>
      new Response(JSON.stringify(body), { status, headers: { ...headers, "Content-Type": "application/json" } });
    const fail = (error: string, status = 400) => json({ error }, status);

    if (req.method !== "POST") return fail("Method not allowed", 405);

    let form: FormData;
    try {
      form = await req.formData();
    } catch {
      return fail("Invalid form data");
    }

    // 1. Bot check
    const ip = req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? null;
    const token = form.get("cf-turnstile-response");
    if (typeof token !== "string" || !(await verifyTurnstile(token, ip))) {
      return fail("Verification failed", 403);
    }

    // 2. Validate fields (all required)
    const title = optionalString(form, "title") ?? "";
    const seedMixture = optionalString(form, "seed_mixture") ?? "";
    const lat = Number(form.get("lat"));
    const lng = Number(form.get("lng"));
    const plantedOn = optionalString(form, "planted_on");
    const natureConnectionRaw = optionalString(form, "nature_connection");
    const natureConnection = natureConnectionRaw === null ? null : Number(natureConnectionRaw);
    const email = optionalString(form, "email");

    if (title.length < 1 || title.length > 100) return fail("Title must be 1–100 characters");
    if (!SEED_MIXTURES.includes(seedMixture)) return fail("Invalid seed mixture");
    if (form.get("lat") === null || !Number.isFinite(lat) || lat < -90 || lat > 90) return fail("Invalid latitude");
    if (form.get("lng") === null || !Number.isFinite(lng) || lng < -180 || lng > 180) return fail("Invalid longitude");
    if (plantedOn === null || !/^\d{4}-\d{2}-\d{2}$/.test(plantedOn) || Number.isNaN(Date.parse(plantedOn))) {
      return fail("Invalid date");
    }
    if (natureConnection === null || !(Number.isInteger(natureConnection) && natureConnection >= 1 && natureConnection <= 7)) {
      return fail("Invalid nature connection");
    }
    if (email === null || email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return fail("Invalid email");
    }
    const photo = form.get("photo");
    if (!(photo instanceof File) || photo.size === 0) return fail("Photo is required");
    const ext = PHOTO_TYPES[photo.type];
    if (!ext) return fail("Photo must be JPEG, PNG, or WebP");
    if (photo.size > MAX_PHOTO_BYTES) return fail("Photo is too large");

    // 3. Upload photo; the path is generated here, never taken from the client
    const photoPath = `${crypto.randomUUID()}.${ext}`;
    const { error: uploadError } = await supabase.storage
      .from("planting-photos")
      .upload(photoPath, photo, { contentType: photo.type });
    if (uploadError) {
      console.error("Photo upload failed", uploadError);
      return fail("Photo upload failed", 500);
    }

    // 4. Insert planting + contact in one transaction
    const { data: id, error } = await supabase.rpc("submit_planting", {
      p_title: title,
      p_seed_mixture: seedMixture,
      p_lat: lat,
      p_lng: lng,
      p_planted_on: plantedOn,
      p_nature_connection: natureConnection,
      p_photo_path: photoPath,
      p_email: email,
    });

    if (error) {
      console.error("submit_planting failed", error);
      // don't leave an orphaned file behind
      await supabase.storage.from("planting-photos").remove([photoPath]);
      return fail("Could not save planting", 500);
    }

    // the planting is saved either way; a failed snapshot is fixed by the next submission
    try {
      await writeMapSnapshot();
    } catch (err) {
      console.error("Map snapshot failed", err);
    }

    return json({ id }, 201);
  },
};
