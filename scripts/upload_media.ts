/**
 * One-time bulk upload of Cowork's recipe photos into the `recipe-images`
 * Supabase Storage bucket. Idempotent (upsert), so safe to re-run.
 *
 * The importer already set recipes.image_url_1/2 to
 *   <SUPABASE_URL>/storage/v1/object/public/recipe-images/<filename>
 * so we upload each file under its existing basename and the app picks them up
 * automatically — no Lovable change needed.
 *
 * Needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env (service-role bypasses
 * the authenticated-only insert policy for this server-side batch).
 *
 *   npx tsx scripts/upload_media.ts
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { supabase } from "./supabase";

const HERE = dirname(fileURLToPath(import.meta.url));
const MEDIA_DIR = process.env.GOH_MEDIA_DIR ?? join(HERE, "..", "full_library", "media");
const BUCKET = "recipe-images";

const CONTENT_TYPE: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".gif": "image/gif",
};

async function main(): Promise<void> {
  const files = readdirSync(MEDIA_DIR).filter((f) => {
    const p = join(MEDIA_DIR, f);
    return statSync(p).isFile() && extname(f).toLowerCase() in CONTENT_TYPE;
  });
  console.log(`Uploading ${files.length} file(s) to ${BUCKET} …`);

  let ok = 0;
  let failed = 0;
  for (const name of files) {
    const ext = extname(name).toLowerCase();
    const body = readFileSync(join(MEDIA_DIR, name));
    const { error } = await supabase.storage.from(BUCKET).upload(name, body, {
      contentType: CONTENT_TYPE[ext],
      upsert: true,
    });
    if (error) {
      failed++;
      console.error(`  ✗ ${name}: ${error.message}`);
    } else {
      ok++;
      if (ok % 50 === 0) console.log(`  …${ok}/${files.length}`);
    }
  }
  console.log(`Done. ${ok} uploaded, ${failed} failed.`);
  if (failed) process.exit(1);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
