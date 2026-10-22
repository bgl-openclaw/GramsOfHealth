# Document intake: plan (22 October 2026)

**Goal (owner):** upload a client's documents at the start, and have everything that can be read pulled out and filled in. That includes:
- client details;
- referral pathway;
- GP details;
- clinical details.

Many kinds of document: GP and specialist letters, pathology, DEXA, transcripts, and others. **Not built yet.**

## Owner answers (22 Oct 2026)

- **Free text:** the owner wants what "works every time without fault" and is stored privately. No reader is fault-free:
  - rules miss things but never invent;
  - AI reads more but can invent.
  So:
  - **template documents** (GP and specialist letters, pathology, DEXA) are read **by rules in the browser** (option A);
  - **transcripts** are stored privately and searchable, with a **"highlight and add" tool**: the dietitian selects text and adds it to the file, linked to its source. No AI.
  - Browser AI (option B) stays a possible later speed-up, never fault-free.
- **First readers:** GP referral letters, specialist letters, transcripts.
- **Medicare numbers:** store them (admins and dietitians only), validated with the card's check digit. Invalid numbers are flagged, not saved.

## How it would work

1. **Upload.** On a new client ("Start from documents") or in an existing client file, drop in any number of files: PDF, photos, Word (.docx), text transcripts.
2. **Sort.** Each file is classified: pathology · DEXA · GP referral/letter · specialist letter · discharge summary · transcript · intake form · other. Staff can change the type.
3. **Read.** Each type has its own reader, with the same rules as the pathology reader:
   - it runs privately;
   - every item keeps the line it came from;
   - items the reader is sure of are filled in;
   - the rest are flagged "Please check".
4. **Fill in, safely.**
   - Sure items fill **empty** fields automatically.
   - Nothing already in the file is overwritten: a difference (e.g. another phone number or DOB) is shown side by side for staff to choose.
   - Every filled item links back to its document.
5. **New client from documents.** The referral letter creates the client (name, DOB, sex, contact). The rest attaches to that client.

## What can be read, and where it goes

| From | Items | Goes to |
|---|---|---|
| GP / specialist letter | Client: name, DOB, sex, address, phone, email (and Medicare number, if the practice wants it stored) | `clients` (exists) |
| | Referral: pathway (Medicare chronic condition plan, NDIS, DVA, private, self), date, reason, sessions, expiry | **new** `client_referrals` |
| | GP and specialists: name, practice, address, phone, fax, email, provider number | **new** `client_care_team` |
| | Current medications (name, strength, dose, frequency) | **new** `client_medications` |
| | Past medical history / conditions, with dates | **new** `client_conditions` |
| | Allergies and intolerances | **new** `client_allergies` (food ones can also become food rules after review) |
| | Height, weight, BMI if stated | `clients`, `client_weights` (exist) |
| Pathology | Results | `client_result_values` (built, reader 0.2.0) |
| DEXA | Body composition, bone density | Same, once the DEXA workbook arrives |
| Transcript | Goals, eating pattern, likes and dislikes, supplements, symptoms, weight mentioned | `client_goals`, `client_food_rules`, `client_supplements`, check-ins (exist), *if* a reader for free text is chosen (see the decision below) |

## The decision: free-text documents

**Letters from clinical software** (Best Practice, Medical Director, Genie, Zedmed …) follow templates. They use headings like "Current medications", "Allergies", "Past Medical History", "RE:", "DOB:", and a provider number. A rules-based reader handles these well, privately, like the pathology reader.

**Transcripts and free-form letters** have no structure. Without AI, they can only be stored and searched, not read into fields. The options:
- **A. No AI** (current rule). Template letters, pathology and DEXA are read. Transcripts are stored but not extracted.
- **B. AI in the browser.** A small model downloads to the staff computer and runs there; nothing leaves the device.
  - Private, but needs a recent computer.
  - A large download (about 2 GB, once).
  - Slow.
  - Moderate quality.
- **C. AI in the practice's own Australian cloud account,** e.g. Claude on Amazon Bedrock in Sydney.
  - The best quality.
  - Data stays in Australia under the practice's AWS agreement, and Anthropic doesn't see it.
  - But it is an outside service: the privacy policy and client consent need to cover it.

## Staged build

1. **Stage 1 (no AI needed):**
   - a documents area with types;
   - the new client file sections (referral, care team, medications, conditions, allergies);
   - the GP/specialist letter reader for common clinical-software layouts;
   - "Start from documents";
   - fill-empty / never-overwrite rules.
2. **Stage 2:**
   - the DEXA reader (after its workbook);
   - Word documents;
   - photos and scans (text recognition, always "Please check").
3. **Stage 3:** transcripts and free-form letters, per the decision above.

## Needed from the owner

- The free-text decision (A, B or C).
- Which documents come most often, to build those readers first.
- Whether to store Medicare numbers (needed for billing; sensitive).
- **Test documents with fake details,** like the GP letter shared on 22 Oct: one or two of each common type and clinical-software layout. Never real client documents in chat.
