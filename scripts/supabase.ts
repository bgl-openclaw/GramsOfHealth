/**
 * Supabase service-role client for the import scripts. Reads credentials from
 * the environment (.env is loaded automatically). The service-role key bypasses
 * RLS and must never ship to the browser — these scripts run server-side only.
 */
import "dotenv/config";
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const serviceKey =
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_SERVICE_KEY;

if (!url || !serviceKey) {
  throw new Error(
    "Missing SUPABASE_URL and/or SUPABASE_SERVICE_ROLE_KEY. " +
      "Copy .env.example to .env and fill them in (see Supabase project settings → API).",
  );
}

export const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
