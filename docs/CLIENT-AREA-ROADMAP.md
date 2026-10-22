# Client area roadmap (My table) — 21 Oct 2026

What the client app does today, what's switched on next, and the "coming soon" areas already showing as locked tiles. Built from the owner's documents (see Sources) and the product brief (docs/PRODUCT-BRIEF-2026-10-21.md).

## 1. Live now (database 0039–0040; screens P1a + P1c-a/b)

| Area | What the client sees | Staff side |
|---|---|---|
| Sign up | Two ways in: **invite link** from the dietitian (create a password, or sign in if they already have an account) or **/join** on their own | "Add & invite" (name + email minimum) → Send invite dialog (email / text / copy link) |
| Own file straight away | A /join sign-up gets its own client file (status **New**) — never attached to someone else's file by email | **New sign-ups** panel: accept, open, or merge a duplicate ("same email / phone / name") |
| Tell us about you (intake) | 6 short steps: About you, Goals, Food, Health, Lifestyle, Consent. Save as you go, finish later, send to dietitian | **Intake** section on the client page: answers, what the client changed, Mark reviewed / Ask to update / Edit answers. Interns don't see health answers |
| Home | Plan card, today's meals, "Tell us about you" progress, 4-step timeline for new clients, coming-soon tiles | — |
| My plan, recipes, shopping | Published plan only, numbers hidden unless the dietitian allows and the client chooses | Publish plan, allow numbers |
| Me | Details, goal, food needs, supplements; editable until reviewed, then "send a change request" (adding an allergy always allowed) | — |

Rules that protect clinical data:
- Clients can remove only what **they** added. Anything the dietitian set stays and shows "Set by your dietitian".
- Every client edit is logged; the dietitian sees "N changes since review".
- Funding numbers (Medicare, NDIS, DVA, health fund) are **not** collected in the app yet.
- Intake questions live in the database (`intake_questions`) — admins can reword, add, reorder or switch off questions in Settings without a code change.

## 2. Coming soon (locked tiles — `client_areas`, admins can hide any of them)

In suggested build order. "Staff input" = what the practice must provide before it can go live.

| # | Area | What it does for the client | Source | Staff input / dependency |
|---|---|---|---|---|
| 1 | **Weekly check-ins** | 1-minute weekly form: feeling, hunger, energy, sleep, bowels, wins, what to change. Writes back to the plan | Blueprint (Grace's 10-minute script); `client_checkins` table already exists | Choose the questions/day; dietitian reply time ("within 24 h, Mon–Fri" pattern) |
| 2 | **Progress** | Weight trend (already stored), optional waist/measurements, wins, progress photos (opt-in) | Blueprint; marketing strategy | Media consent wording (separate opt-in for sharing) |
| 3 | **Documents** | Upload bloods, referral letters, GP care plan, DEXA/InBody before the consult (upload only, never shown back) | Website ("bring recent blood tests"); Enriching Health intake | Private storage bucket + dietitian review step (reuse `client_clinical_records`) |
| 4 | **Your next steps** | After each consult: "three things to focus on + three links" | Future Health / Mae pattern | Dietitian writes it (AI draft later: AI roadmap) |
| 5 | **Meal swaps** | Swap a meal for a dietitian pre-approved spare | Blueprint ("spares"); plans roadmap P2 | Spares per plan (plan templates P2) |
| 6 | **Messages** | Message the dietitian between consults; "not for emergencies" note (000 / Lifeline 13 11 14) | Mae; Altum | Reply-time promise; 7-year record keeping; HighLevel or in-app decision |
| 7 | **Appointments** | Upcoming consults; book a review (review link sent at ~10 weeks) | Website (Discovery call · Initial $198 · Review $121); Mae | Calendar integration (HighLevel / booking system) |
| 8 | **Food photos** | 3-day photo snapshot at the start; per-meal photo + symptoms diary (gut health) | Altum day-2 snapshot; Blueprint (IBS case) | Reviewed at consult; storage |
| 9 | **Learn** | Handouts, guides, short videos by condition; recipe collection | Mae; marketing; website | Curate the first 10–20 resources |
| 10 | **Programs** | Week-by-week unlocking modules (e.g. a nutrition module inside Enriching Health programs) | Enriching Health operating plan | Program content |
| 11 | **Cooking classes** | Book a class, get the recipes within 24 h | Website; marketing; Notion structure | Class schedule + payments |
| 12 | **Community** | Member catch-ups, live Q&A, challenges | Marketing strategy (membership) | Moderation; membership pricing |

Also on the list, not yet tiles: consents/agreements page (privacy, telehealth, cancellation, media, AI processing), funding details (admin-verified), referral/review ask (never review-gated), surveys (NPS), payments/packages.

## 3. Client journey (Grams of Health)

Enquiry (Facebook / Google / cooking class / lead magnet) → discovery call → **invite or /join → Tell us about you** → initial consult (60 min) → dietitian reviews intake, builds profile + plan → **plan published to My table** → weekly check-ins → review consults "until it holds" → retention (membership, classes, referrals).

Borrowed timing worth copying (from the sister businesses, not GoH docs): day 0 welcome + login · day 1 "one job today" · day 2 three-day food photo snapshot · day 7 first check-in · week 4 mini review · ~10 weeks send the review-booking link · ~12 weeks review.

## 4. Decisions needed from the owner

1. **Automatic emails** (invites, password reset, magic link, email confirmation): Resend or HighLevel? Needs the sending domain (gramsofhealth.com DNS) — until then invites go out from the dietitian's own email app.
2. **Custom domain / subdomain** for the app (affects sign-in redirect links) — decide before automatic emails.
3. **Copy style**: the website plan says avoid "journey, wellness, empower…", the marketing strategy uses them. The app currently follows the website rule.
4. **Privacy / consent wording** and a privacy-policy link for the consent step (currently a plain "I agree" statement).
5. Which coming-soon areas to show at launch (hide the rest in Settings → Client app).

## 5. Sources

- Grams of Health — Product Blueprint (9 Oct): client-facing side, check-in script, spares, change requests.
- Grams of Health marketing strategy; Grams of Health website (services, fees, "How it works"); Notion structure; Neurodivergent nutrition workshop.
- Enriching Health operating plan + private intake form + NDIS onboarding form (best intake field templates).
- Altum new-client six-week sequence; Future Health / Mae client journey (Dr Kate's practice) — patterns only, not GoH.
- Not used: patient records and exports (deliberately not opened).
