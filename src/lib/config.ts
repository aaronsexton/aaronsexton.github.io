function requireEnv(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing ${name}. Set it in .env.development locally, or as a GitHub repository variable for builds.`);
  return value;
}

const supabaseUrl = requireEnv('PUBLIC_SUPABASE_URL', import.meta.env.PUBLIC_SUPABASE_URL);

export const SNAPSHOT_URL = `${supabaseUrl}/storage/v1/object/public/map-data/plantings.json`;
export const SUBMIT_URL = `${supabaseUrl}/functions/v1/submit-planting`;
export const TURNSTILE_SITE_KEY = requireEnv('PUBLIC_TURNSTILE_SITE_KEY', import.meta.env.PUBLIC_TURNSTILE_SITE_KEY);

// lower Manhattan, as [lng, lat]
export const MAP_CENTER: [number, number] = [-74.009, 40.7075];
export const MAP_ZOOM = 12;
export const MAP_STYLE = 'https://tiles.openfreemap.org/styles/bright';

// satellite imagery, shown beneath the style's labels when toggled on
export const SATELLITE_TILES = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
export const SATELLITE_ATTRIBUTION = 'Imagery © Esri, Maxar, Earthstar Geographics';
