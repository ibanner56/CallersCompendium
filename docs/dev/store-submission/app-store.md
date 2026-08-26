# Apple App Store & TestFlight — submission checklist

Goal: take **Caller's Compendium** into **open beta on iOS/iPadOS** — which on
Apple means **TestFlight external testing with a public join link** — and lay the
groundwork for a later public App Store release.

Read [`README.md`](README.md) first for the shared prerequisites and the two
policy landmines (AGPL-vs-App-Store, export compliance). Paste-ready listing text
and form answers are in [`listing-copy.md`](listing-copy.md).

> **Where we already are.** The Apple Developer Program membership is active, the
> App Store Connect app record exists (SKU `CallersCompendiumApp`, bundle id
> `org.callerscompendium.compendiumApp`), and CI already archives, signs, and
> uploads a build to **TestFlight internal testing** on every `v*` tag
> (see [`../releasing.md`](../releasing.md#ios-testflight-via-app-store-connect-api)).
> So a lot of Section 0–2 below is **confirm, not do**. The genuinely new work is
> **Section 4 (external testing + Beta App Review)**.

Legend: **[Gate]** = must pass before you can move on. **[Confirm]** = likely
already true, verify it. **[One-time]** = account/setup step you do once.

---

## 0. Accounts & identity — [mostly One-time, Confirm]

- [x] **[Confirm]** You can sign in to <https://appstoreconnect.apple.com> with the
  Apple ID that owns the membership, and the **Apple Developer Program** is
  active (not expired — it renews yearly at $99).
- [x] **[Confirm]** Your role is **Account Holder**, **Admin**, or **App Manager**.
  Only these roles can enable TestFlight public links and submit for review.
- [x] **[Confirm]** The **App Store Connect API key** used by CI has the **App
  Manager** role (Developer role can build/sign but cannot upload). This is the
  `APPLE_API_KEY_*` secret set already used by the release pipeline.
- [x] **[One-time]** Under **Business** in App Store Connect, confirm the
  **Agreements** are all "Active." The **Free Apps** (Paid Apps not needed) legal
  agreement must be accepted or *nothing* can go to external testing or the store.
  A first-time account often has this pending — check it early.

## 1. The app record & bundle — [Confirm]

- [x] **[Confirm]** App record exists in ASC: name **Caller's Compendium**, bundle
  id `org.callerscompendium.compendiumApp`, SKU `CallersCompendiumApp`.
- [x] **[Confirm]** Bundle id in the record matches `app/ios/Runner.xcodeproj`
  (`PRODUCT_BUNDLE_IDENTIFIER`) and the manifest — all `org.callerscompendium.compendiumApp`.
- [x] **[Confirm]** Primary language set (English). You can add localized listings
  later once the base-language set ships.
- [x] **[Confirm]** Platform availability includes **iPhone and iPad** (we support
  both — the `UISupportedInterfaceOrientations~ipad` keys and iPad screenshots
  matter here).

## 2. Build upload & signing — [Confirm]

- [x] **[Confirm]** A build has landed in **ASC → TestFlight → iOS builds**.
  CI uploads it via `xcrun altool --upload-app` on a real `v*` tag (a
  `workflow_dispatch` builds+signs but does **not** upload). Cut a bare beta tag
  such as `vX.Y.Z-beta`
  and confirm the build appears and finishes **processing**.
- [x] **[Confirm]** CI manually signs the export with the configured Apple
  Distribution certificate and app/Share Extension provisioning profiles.
- [x] **[Confirm]** CI's tag-derived `CFBundleVersion` is unique. It uses the
  bounded SemVer core plus a channel bit (beta below stable for the same core);
  TestFlight rejects duplicates.
- [x] **[Gate]** **Export compliance.** `Info.plist` sets
  `ITSAppUsesNonExemptEncryption = false`, so ASC skips the per-build
  "Missing Compliance" prompt. This is the honest answer: the app uses only
  exempt cryptography (Ed25519 update signatures + SHA-256 backup integrity
  checksum — no confidentiality encryption; see [`README.md`](README.md) →
  export compliance). Only revisit if confidentiality crypto is ever
  reintroduced — then update `Info.plist` and be ready to file the annual
  self-classification, **before** external testing, not after.

## 3. Store listing metadata (needed for review, even for beta) — [Gate]

Even TestFlight external testing pulls from the app record's metadata, and you'll
need all of this for the eventual public release. Fill these in ASC → your app →
**App Information** and the version's **App Store** tab. All text is drafted in
[`listing-copy.md`](listing-copy.md).

- [x] **[Gate]** **App name** (30 chars max): "Caller's Compendium".
- [x] **[Gate]** **Subtitle** (30 chars max): see draft.
- [x] **[Gate]** **Privacy Policy URL** — required. Publish
  [`privacy-policy.md`](privacy-policy.md) first and paste its URL.
- [x] **[Gate]** **Category** — Primary: **Productivity**; Secondary: **Reference**.
- [x] **[Gate]** **Promotional text** + **Description** + **Keywords** — from draft.
- [x] **[Gate]** **Support URL** and **Marketing URL** — from the app-facts table.
- [x] **[Gate]** **Copyright** — "© 2026 Isaac Banner".
- [ ] **[Gate]** **Screenshots** at the required device sizes (see below). Missing
  screenshots block both external testing metadata and App Review.
- [x] **[Gate]** **App Privacy** ("nutrition label") completed as **Data Not
  Linked to You → User Content → Other User Content → Used for App
  Functionality** — answers in
  [`listing-copy.md`](listing-copy.md#app-privacy-apple). This disclosure
  anticipates the planned opt-in Device Sync; the current release has no sync.
- [x] **[Gate]** **Age rating** questionnaire completed → expected **4+**. Answers
  in [`listing-copy.md`](listing-copy.md#age--content-rating).
- [x] **[Confirm]** **Sign-in not required** to review the app (there is no login).
  Note this in the review notes so a reviewer isn't blocked.

### Screenshot sizes (Apple, current)

You must upload at least one screenshot set for **each device family you ship**:

- [ ] **iPhone** — a **6.9-inch** display set (e.g. iPhone 16 Pro Max class); one
  6.9" set now satisfies the iPhone requirement. 1320×2868 or 2868×1320.
- [ ] **iPad** — a **13-inch** display set (iPad Pro 12.9"/13" class):
  2064×2752 or 2752×2064 (or the 2048×2732 legacy size).
- Capture 3–10 shots per set from **Perform mode, Collection (search), Programs
  (matrix), Dialect, and Imports**. Use the Simulator at the exact device to get
  pixel-perfect frames.

## 4. Open beta = TestFlight external testing — [the new work]

Internal testing (≤100 teammates, instant) is already live. "Open beta" is
**external testing**, which adds Beta App Review and unlocks a **public link**.

- [x] **[Gate]** In **ASC → TestFlight → Test Information**, fill the **beta app
  description**, **feedback email** (compendium@contra.dance), **marketing URL**, and
  **privacy policy URL**. This is required before any external testing.
- [x] **[Gate]** Provide **Beta App Review information**: what to test, how to
  reach every feature without an account, and demo steps. Reuse the review notes
  in [`listing-copy.md`](listing-copy.md#reviewer-notes-both-stores).
- [x] Create an **External Testers** group: TestFlight → Groups → **+**. Name it
  e.g. "Public Beta – Callers".
- [ ] Assign the processed **build** to that group.
- [ ] **[Gate]** Submit the build for **Beta App Review** (happens automatically
  when you add the first build to an external group). Typical turnaround < 24h.
  A build stays usable for external testing for **90 days** from upload — plan to
  push fresh betas before expiry.
- [ ] After approval, in the group's settings **Enable Public Link** and (optionally)
  cap the tester count (max 10,000). Copy the link.
- [ ] **[Confirm]** Test the public link on a device that has the **TestFlight**
  app installed — tapping the link should offer to install the beta with no
  UDID/email needed.
- [ ] Publish the link where callers will find it — the beta guide, the project
  site, and Discussions. Update
  [`docs/beta/beta-guide.md`](../../beta/beta-guide.md) and the README's iOS
  install note, which currently say iOS is "invited testers via TestFlight."
- [ ] **[Optional]** Turn on **automatic distribution** so each new CI-uploaded
  build (after any required review) reaches external testers without manual steps.

### Common Beta App Review rejections to pre-empt

- [x] **Broken/placeholder content** — make sure the seeded "Baby Rose" dance and
  all tabs work on a clean install.
- [ ] **Reviewer can't reach a feature** — spell out that everything is offline and
  login-free; give steps to trigger an import (paste a ContraDB link) so the one
  network feature is demonstrable.
- [x] **Privacy string / permission mismatch** — we request no runtime permissions
  (no camera/mic/location/contacts), so there should be **no `NS*UsageDescription`
  prompts**. Confirm none are triggered; if a plugin adds one, add the matching
  `Info.plist` purpose string or the build is rejected.
- [x] **Support URL / privacy URL must resolve** — dead links are an easy reject.

## 5. Path to the public App Store (after beta) — [later]

Open beta does not require full App Review; the public store does. When ready:

- [ ] Resolve the **AGPL-vs-App-Store licensing** decision (README landmine #1) —
  do this before public submission if not before beta.
- [ ] In the version's **App Store** tab, set **"Version Release"** (manual or
  automatic) and complete any remaining metadata.
- [ ] Answer **"Sign-in required?" = No**, **"Uses IDFA / advertising?" = No**.
- [ ] Complete the **App Review Information** (contact, notes, no demo account
  needed).
- [ ] Click **Add for Review → Submit**. Full App Review typically takes 1–3 days.
- [ ] Watch for review messages in ASC; respond in Resolution Center if asked.
- [ ] On approval, choose your **release** (immediate, scheduled, or manual).

## 6. Post-submission monitoring — [ongoing]

- [ ] Watch **ASC → TestFlight → Feedback** and crash reports (testers can send
  screenshots + notes from within TestFlight).
- [ ] Keep builds fresh (90-day TestFlight expiry).
- [ ] Keep the privacy policy URL and support URL alive.
- [ ] When you bump the app version, re-check the App Privacy answers still hold
  and continue to describe the features actually available in that build.

---

## Quick reference — Apple facts for this app

| Thing | Value |
|-------|-------|
| Console | App Store Connect — <https://appstoreconnect.apple.com> |
| Bundle id | `org.callerscompendium.compendiumApp` |
| SKU | `CallersCompendiumApp` |
| Program | Apple Developer Program ($99/yr, active) |
| Upload path | CI: unsigned `xcodebuild archive`, manually signed `xcodebuild -exportArchive`, then `xcrun altool --upload-app` on a release tag |
| Signing | Manual export with the App Store Connect API key (App Manager role), Apple Distribution certificate, and app/Share Extension provisioning profiles |
| Export compliance | `ITSAppUsesNonExemptEncryption=false` — exempt (signatures + SHA-256 checksum only, no confidentiality crypto) |
| Open beta = | TestFlight **external** testing + **public link** (after Beta App Review) |
| Internal testers | ≤100, no review (already live) |
| External testers | ≤10,000, Beta App Review, public link |
| Build validity | 90 days per build for testing |
