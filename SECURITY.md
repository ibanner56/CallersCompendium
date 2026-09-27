# Security Policy

Thanks for helping keep Caller's Compendium and its users safe. This document
explains how to report a security problem and what to expect afterward.

## Reporting a vulnerability

Please report suspected vulnerabilities **privately** — don't open a public
issue, PR, or discussion for something exploitable.

- **Preferred:** GitHub's [private vulnerability reporting][pvr]. Go to the
  repository's **Security** tab → **Report a vulnerability**, and file a private
  advisory. This keeps the report confidential and threads the whole
  conversation in one place.
- **Fallback:** if you can't use that (or aren't sure it's enabled yet), email
  the maintainer at **compendium@contra.dance** with "SECURITY" in the subject.

Helpful things to include: what you found, how to reproduce it, the affected
platform/version, and the impact you think it has. A proof of concept is great
but never required.

[pvr]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability

## What to expect

Caller's Compendium is independently maintained by a single maintainer, so
response times reflect that:

- **Acknowledgement:** I aim to reply within about **7 days**.
- **Assessment & fix:** timelines depend on severity and my availability. I'll
  keep you updated on the advisory thread and let you know the plan.
- **Disclosure:** I prefer coordinated disclosure — let's agree on timing before
  any public write-up, and I'm happy to credit you (or keep you anonymous, your
  call).

If you don't hear back within a couple of weeks, a gentle nudge is welcome.

## Supported versions

Caller's Compendium is pre-1.0 and under active development. Security fixes
land on **`main`** and ship in the **latest release**; older releases are not
patched separately. The best way to stay secure is to run the most recent
version.

## No bug bounty

There is no paid bounty program. Responsible disclosure is genuinely
appreciated, and I'm glad to acknowledge reporters in the advisory and release
notes.

## Privacy posture

Caller's Compendium is **local-first and offline by design**. Your dances,
programs, and settings live on your device; the app doesn't run analytics,
tracking, or telemetry, and it doesn't phone home. Online sources (for example,
importing from community databases) are strictly **import-only** actions you
initiate. The one feature that sends library data to a server is
**Device Sync**, which is experimental, off by default, and runs only after you
connect a sync store yourself; its design and threat model are in
[ADR-004](docs/adr/004-device-sync-and-athenaeum.md), and the sync server in
[`server/`](server/) is in scope for reports. That smaller footprint is
intentional and shapes how we think about security here.
