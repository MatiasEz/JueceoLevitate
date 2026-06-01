#!/usr/bin/env python3
"""Report passive release-readiness warnings for branded app shells.

This script does not archive, sign, upload, create TestFlight builds, or touch
backend state. By default it exits 0 even when warnings are present.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
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


def plist_text() -> str:
    return "\n".join(path.read_text() for path in INFO_PLISTS if path.exists())


def supabase_is_hardcoded_in_plist() -> bool:
    text = plist_text()
    return ("https://" in text and ".supabase.co" in text) or "sb_publishable_" in text


def supabase_build_settings_missing() -> bool:
    text = plist_text()
    return "$(SUPABASE_URL)" not in text or "$(SUPABASE_PUBLISHABLE_KEY)" not in text


def brand_names(paths: List[Path]) -> str:
    return ", ".join(path.stem for path in paths)


def shared_supabase_urls(configs) -> List[tuple[str, List[Path]]]:
    urls: dict[str, List[Path]] = {}
    for config in configs:
        url = resolved_xcconfig_url(config.settings.get("SUPABASE_URL", ""))
        if url:
            urls.setdefault(url, []).append(config.path)
    return [(url, paths) for url, paths in urls.items() if len(paths) > 1]


def resolved_xcconfig_url(value: str) -> str:
    return value.replace(":/$()/", "://")


def supabase_key_missing(settings: dict[str, str]) -> bool:
    return not settings.get("SUPABASE_URL") or not settings.get("SUPABASE_PUBLISHABLE_KEY")


def supabase_key_looks_publishable(settings: dict[str, str]) -> bool:
    return settings.get("SUPABASE_PUBLISHABLE_KEY", "").startswith("sb_publishable_")


def supabase_url_label(url: str) -> str:
    return url.replace("https://", "").rstrip("/")


def info_plist_uses_supabase_build_settings() -> bool:
    text = plist_text()
    return "$(SUPABASE_URL)" in text and "$(SUPABASE_PUBLISHABLE_KEY)" in text


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

        if supabase_key_missing(settings):
            findings.append(
                Finding(
                    brand=label,
                    severity="warning",
                    message="Supabase is not fully configured for this brand.",
                    next_step="Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in the brand xcconfig, or intentionally keep the brand local-only.",
                )
            )
        elif not supabase_key_looks_publishable(settings):
            findings.append(
                Finding(
                    brand=label,
                    severity="warning",
                    message="Supabase key is not a modern publishable key.",
                    next_step="Use the Supabase sb_publishable_ key for client app configuration.",
                )
            )

    if not info_plist_uses_supabase_build_settings() or supabase_is_hardcoded_in_plist() or supabase_build_settings_missing():
        findings.append(
            Finding(
                brand="Global",
                severity="warning",
                message="Info.plist/Info-macOS.plist do not cleanly use per-brand Supabase build settings.",
                next_step="Keep SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY as build setting placeholders, then define values in each brand xcconfig.",
            )
        )

    for url, paths in shared_supabase_urls(configs):
        findings.append(
            Finding(
                brand="Global",
                severity="info",
                message=f"Multiple brands share Supabase {supabase_url_label(url)}: {brand_names(paths)}.",
                next_step="This is fine for staging. Before production, confirm whether those brands should share data or use separate Supabase projects.",
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
