#!/usr/bin/env python3
"""Report passive release-readiness warnings for branded app shells.

This script does not archive, sign, upload, create TestFlight builds, or touch
backend state. By default it exits 0 even when warnings are present.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from typing import List

from brand_support import APP_DIR, ROOT, load_brand_configs, swift_brand_assets


INFO_PLISTS = [
    APP_DIR / "Info.plist",
    APP_DIR / "Info-macOS.plist",
]


@dataclass(frozen=True)
class Finding:
    brand: str
    severity: str
    message: str
    next_step: str


def truthy(value: str | None) -> bool:
    return (value or "").strip().upper() in {"1", "YES", "TRUE"}


def final(value: str | None) -> bool:
    return truthy(value)


def placeholder(value: str | None) -> bool:
    return truthy(value)


def supabase_is_shared() -> bool:
    plist_text = "\n".join(path.read_text() for path in INFO_PLISTS if path.exists())
    return "SUPABASE_URL" in plist_text or "SUPABASE_PUBLISHABLE_KEY" in plist_text


def collect_findings(selected_brand: str | None = None) -> List[Finding]:
    findings: List[Finding] = []
    asset_map = swift_brand_assets()
    configs = load_brand_configs()
    if selected_brand:
        configs = [
            config
            for config in configs
            if config.id == selected_brand or config.scheme == selected_brand or config.display_name == selected_brand
        ]
        if not configs:
            return []

    for config in configs:
        settings = config.settings
        label = f"{config.display_name} ({config.id})"
        assets = asset_map.get(config.id, {})

        if placeholder(settings.get("APP_ICON_PLACEHOLDER")):
            findings.append(
                Finding(
                    brand=label,
                    severity="warning",
                    message=f"App icon '{config.app_icon_name}' is still marked as generated placeholder.",
                    next_step="Replace the icon set with final brand artwork, then set APP_ICON_PLACEHOLDER = NO.",
                )
            )

        if placeholder(settings.get("BRAND_ASSETS_PLACEHOLDER")):
            asset_names = ", ".join(value for value in [assets.get("logo"), assets.get("hero")] if value) or "logo/hero"
            findings.append(
                Finding(
                    brand=label,
                    severity="warning",
                    message=f"Brand visual assets are still marked as placeholders: {asset_names}.",
                    next_step="Replace logo and hero assets with final artwork, then set BRAND_ASSETS_PLACEHOLDER = NO.",
                )
            )

        if settings.get("GOOGLE_OAUTH_SHARED_PLACEHOLDER") == "YES" or not final(settings.get("GOOGLE_OAUTH_FINAL")):
            findings.append(
                Finding(
                    brand=label,
                    severity="warning",
                    message="Google OAuth is not marked final for this brand.",
                    next_step="Create a dedicated OAuth client for the final bundle id, update the brand xcconfig, then set GOOGLE_OAUTH_FINAL = YES.",
                )
            )

        if not final(settings.get("BUNDLE_ID_FINAL_CONFIRMED")):
            findings.append(
                Finding(
                    brand=label,
                    severity="warning",
                    message=f"Bundle id is not marked final: {settings.get('PRODUCT_BUNDLE_IDENTIFIER', 'missing')}.",
                    next_step="Confirm the final iOS and Mac Catalyst bundle ids, then set BUNDLE_ID_FINAL_CONFIRMED = YES.",
                )
            )

    if supabase_is_shared():
        findings.append(
            Finding(
                brand="Global",
                severity="info",
                message="Supabase configuration is shared in Info.plist/Info-macOS.plist.",
                next_step="Before using multiple real competitions, decide whether data stays shared with filtering or moves to per-brand config. No database change is made by this script.",
            )
        )

    findings.append(
        Finding(
            brand="Global",
            severity="info",
            message="Distribution actions are intentionally out of scope.",
            next_step="This script does not create archives, upload builds, change signing, create TestFlight releases, or call App Store Connect.",
        )
    )

    return findings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Print passive release-readiness warnings for app brands.")
    parser.add_argument(
        "--brand",
        help="Limit output to a brand id, display name, or scheme.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 when warning findings exist. Not used by CI yet.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    findings = collect_findings(args.brand)
    warnings = [finding for finding in findings if finding.severity == "warning"]
    infos = [finding for finding in findings if finding.severity == "info"]

    if args.brand and not findings:
        print(f"No release-readiness data found for brand '{args.brand}'.")
        return 1

    print("Release readiness report")
    print("No archives, uploads, signing changes, TestFlight actions, or database changes are performed.")
    print("")

    for title, items in [("Warnings", warnings), ("Notes", infos)]:
        print(title + ":")
        if not items:
            print("- none")
        for item in items:
            print(f"- [{item.brand}] {item.message}")
            print(f"  Next: {item.next_step}")
        print("")

    if warnings:
        print(f"Release readiness has {len(warnings)} warning(s). This is expected until final credentials and assets are in place.")
    else:
        print("Release readiness has no warnings.")

    if args.strict and warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
