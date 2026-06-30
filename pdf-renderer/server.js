/**
 * Grams of Health — PDF renderer.
 *
 * A small headless-Chrome service that prints the Lovable app's print routes to
 * pixel-perfect, vector A4 PDFs (real Chrome print engine — crisp selectable
 * text, correct pagination, fonts and Supabase images load properly).
 *
 * Flow:
 *   1. The web app calls POST /render with the signed-in user's Supabase session
 *      (access + refresh token) and { type: 'recipe'|'plan', id }.
 *   2. We verify the access token against Supabase (must be a real logged-in user).
 *   3. We open a headless page, inject that session so the print route loads data
 *      as the user (RLS intact — no service-role in the browser), navigate to the
 *      print route, wait for fonts + images, and return the PDF.
 *
 * The card layout stays in the React app (single source of truth) — this service
 * only drives Chrome. Reuses one browser instance across requests.
 *
 * Env: PORT, SUPABASE_URL, SUPABASE_ANON_KEY, APP_BASE_URL, ALLOWED_ORIGIN.
 */
import express from "express";
import puppeteer from "puppeteer";

const {
  PORT = 8080,
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  APP_BASE_URL,
  ALLOWED_ORIGIN = "*",
} = process.env;

for (const [k, v] of Object.entries({ SUPABASE_URL, SUPABASE_ANON_KEY, APP_BASE_URL })) {
  if (!v) throw new Error(`Missing env ${k}`);
}
const PROJECT_REF = new URL(SUPABASE_URL).hostname.split(".")[0];
const STORAGE_KEY = `sb-${PROJECT_REF}-auth-token`;

const app = express();
app.use(express.json({ limit: "256kb" }));
app.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", ALLOWED_ORIGIN);
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

let browserP;
const getBrowser = async () => {
  if (!browserP) {
    browserP = puppeteer.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox", "--font-render-hinting=none"],
    });
  }
  return browserP;
};

// Confirm the access token belongs to a real Supabase user before rendering.
async function verifyUser(accessToken) {
  const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${accessToken}` },
  });
  return r.ok;
}

const PATHS = {
  recipe: (id) => `/recipes/${id}/print`,
  plan: (id) => `/plans/${id}/print`,
};

app.post("/render", async (req, res) => {
  try {
    const { type, id, filename, access_token, refresh_token } = req.body ?? {};
    if (!PATHS[type] || !id) return res.status(400).json({ error: "type ('recipe'|'plan') and id required" });
    if (!access_token) return res.status(401).json({ error: "access_token required" });
    if (!(await verifyUser(access_token))) return res.status(401).json({ error: "invalid session" });

    const browser = await getBrowser();
    const page = await browser.newPage();
    try {
      // Seed the Supabase session so the print route loads data as this user.
      const session = JSON.stringify({
        access_token,
        refresh_token: refresh_token ?? "",
        token_type: "bearer",
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      });
      await page.evaluateOnNewDocument(
        (key, value) => window.localStorage.setItem(key, value),
        STORAGE_KEY,
        session,
      );

      const url = `${APP_BASE_URL}${PATHS[type](id)}`;
      await page.goto(url, { waitUntil: "networkidle0", timeout: 60_000 });
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all(
          [...document.images].map((img) =>
            img.complete ? null : new Promise((r) => { img.onload = img.onerror = r; }),
          ),
        );
      });

      const pdf = await page.pdf({ format: "A4", printBackground: true, preferCSSPageSize: true });
      res.set("Content-Type", "application/pdf");
      res.set("Content-Disposition", `attachment; filename="${(filename || type + "-" + id).replace(/[^\w.-]/g, "_")}.pdf"`);
      res.send(Buffer.from(pdf));
    } finally {
      await page.close();
    }
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: String(err?.message ?? err) });
  }
});

app.get("/healthz", (_req, res) => res.json({ ok: true }));
app.listen(PORT, () => console.log(`pdf-renderer on :${PORT}`));
