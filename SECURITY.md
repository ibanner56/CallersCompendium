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
  the maintainer at **isaac@banner.is** with "SECURITY" in the subject.

Helpful things to include: what you found, how to reproduce it, the affected
platform/version, and the impact you think it has. A proof of concept is great
but never required.

[pvr]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability

## What to expect

Caller's Compendium is maintained by one person in their spare time, so please
set your expectations accordingly:

- **Acknowledgement:** I aim to reply within about **7 days**.
- **Assessment & fix:** timelines depend on severity and my availability. I'll
  keep you updated on the advisory thread and let you know the plan.
- **Disclosure:** I prefer coordinated disclosure — let's agree on timing before
  any public write-up, and I'm happy to credit you (or keep you anonymous, your
  call).

If you don't hear back within a couple of weeks, a gentle nudge is welcome.

## Supported versions

This is a young, pre-1.0 project under active development. Security fixes land
on **`main`** and ship in the **latest release**; older releases are not
patched separately. The best way to stay secure is to run the most recent
version.

## No bug bounty

There's no paid bounty program — this is a free, open-source, solo-maintained
project. Responsible disclosure is genuinely appreciated, and I'm glad to
acknowledge reporters in the advisory and release notes.

## Privacy posture

Caller's Compendium is **local-first and offline by design**. Your dances,
programs, and settings live on your device; the app doesn't run analytics,
tracking, or telemetry, and it doesn't phone home. Online sources (e.g.
importing from community databases) are strictly **import-only** actions you
initiate — there's no background sync of your data off the device. That smaller
footprint is intentional and shapes how we think about security here.
