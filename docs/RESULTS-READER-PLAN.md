# Results reader: plan (22 October 2026)

Reads the values from a bloods or DEXA PDF into the client's file. **Not built yet.** It starts after the owner's blood and DEXA logic (marker list, units, ranges and decision rules) arrives from the other workstream.

## Owner decisions (22 Oct 2026)

1. **No outside service sees the files.** No Anthropic, no AI service. The reader runs inside our system:
   - in the browser of the person viewing the result, which already downloads the file from Supabase to show it;
   - using open-source tools: a PDF text reader (pdf.js) and, for photos and scans, text recognition (tesseract.js, with its language data hosted in the app).
   - Files stay in the private `clinical-records` bucket; values are saved to Supabase.
2. **Values the reader is sure of go straight into the client's file.** The dietitian looks at uploads anyway, so they don't confirm those one by one.
3. **Only numbers the reader isn't 100% sure of are flagged** ("Please check"), for a dietitian to confirm or correct.
4. **Build after the blood/DEXA logic.** Values are then filed under the right markers from day one.

## What counts as "100% sure" (proposed; owner to confirm)

A value is auto-accepted only when ALL of these hold:
1. It came from the PDF's own text layer. Values read from photos or scans by text recognition are always flagged, because recognition can confuse 8 and 3, or 1 and 7.
2. The test name exactly matches a name or synonym on the marker list.
3. The unit is recognised: the marker's standard unit, or one with an exact conversion.
4. The number reads cleanly: no stray characters, no ambiguous decimal point.
5. It's within the plausible limits for that marker.
6. The lab's reference range and H/L flag agree with the number.
7. The test date was found on the report.

Anything else is "Please check". Every value, sure or not, keeps where it came from (page, and the line as printed), plus who confirmed or corrected it, and can be corrected later.

## Needed before building

- The blood and DEXA logic:
  - markers and the names and abbreviations labs print for them
  - standard units and conversions
  - plausible limits
  - ranges and decision rules
- **De-identified** sample reports (names, dates of birth and Medicare numbers removed), or demo reports, from the labs and DEXA clinics seen most often. Anything shared in a Claude chat is processed by Anthropic, so no real client reports in chat.

## Rough build outline

1. **Database:** a values table linked to the clinical record:
   - marker
   - value, and the unit as printed and standardised
   - the lab's range and flag
   - page and line as printed
   - how it was read (text or recognition)
   - status: auto-accepted / please check / confirmed / corrected
   - who and when

   Only accepted, confirmed or corrected values feed trends and decisions.
2. **Reader:** a browser module in the Lovable app, with:
   - the text-layer parser
   - text recognition for images
   - the rules above
   - lab-specific layouts for the most common labs
3. **Screens:** the Clinical record shows the values beside the PDF with "Please check" items first; trends per marker.
4. **Small fix to fold in:** `src/lib/client-results.test.ts` imports `bun:test`; the rest of the app uses vitest.
