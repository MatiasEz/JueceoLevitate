# Release Readiness

This repo is not configured to publish anything automatically. The current
release-readiness work is passive: it documents what is missing before a real
distribution decision and prints local warnings.

## What This Does Not Do

- Does not create TestFlight builds.
- Does not upload to App Store Connect.
- Does not archive, notarize, or export signed apps.
- Does not change signing, provisioning profiles, certificates, or teams.
- Does not touch Supabase, migrations, tables, Edge Functions, or data.

## Local Readiness Check

Run:

```bash
python3 scripts/validate_release_readiness.py
```

The script exits `0` by default even when it prints warnings. Use this only for
manual review right now:

```bash
python3 scripts/validate_release_readiness.py --strict
```

`--strict` exits `1` when warnings exist, but it is not wired into CI yet.

## Current Expected Warnings

- Google OAuth is shared through `GoogleOAuth.shared.xcconfig`.
- Generated app icons are still marked as placeholders.
- `AuroraCircuit` and `PrismaOpen` logo/hero assets are generated placeholders.
- Bundle IDs have not been marked final.
- `AuroraCircuit` and `PrismaOpen` currently share the new Supabase sandbox project.

## Before Any Real Distribution

- Replace placeholder icons, logos, and hero assets with final brand artwork.
- Create a dedicated Google OAuth client per final bundle ID.
- Confirm iOS and Mac Catalyst bundle IDs for each brand.
- Decide the final multi-competition data strategy before separating real production data.
- Only then decide signing, provisioning, App Store Connect, TestFlight, or direct-download flows.

## Marking Items Final

Each brand `.xcconfig` has release-readiness flags:

```text
APP_ICON_PLACEHOLDER = YES
BRAND_ASSETS_PLACEHOLDER = YES
BUNDLE_ID_FINAL_CONFIRMED = NO
GOOGLE_OAUTH_FINAL = NO
SUPABASE_URL = https:/$()/...
SUPABASE_PUBLISHABLE_KEY = sb_publishable_...
```

After replacing or confirming each item, flip the corresponding flag. Keep this
as a manual gate until we intentionally decide to make release readiness part of
CI.
