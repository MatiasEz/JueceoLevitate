#!/usr/bin/env python3
"""Validate branded app target configuration without touching backend state."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Dict, List, Set

from brand_support import (
    ASSETS_DIR,
    BRANDS_DIR,
    CORE_BRANDING_FILE,
    PROJECT_FILE,
    REQUIRED_BRAND_SETTINGS,
    ROOT,
    load_brand_configs,
    project_inventory,
    swift_brand_assets,
)


INFO_PLISTS = [
    ROOT / "JueceoCoreografias" / "Info.plist",
    ROOT / "JueceoCoreografias" / "Info-macOS.plist",
]


def add_unique_error(errors: List[str], message: str) -> None:
    if message not in errors:
        errors.append(message)


def validate_icon_set(icon_name: str, errors: List[str]) -> None:
    icon_dir = ASSETS_DIR / f"{icon_name}.appiconset"
    contents_path = icon_dir / "Contents.json"
    if not icon_dir.exists():
        add_unique_error(errors, f"Falta el app icon set {icon_dir.relative_to(ROOT)}.")
        return
    if not contents_path.exists():
        add_unique_error(errors, f"Falta {contents_path.relative_to(ROOT)}.")
        return

    try:
        contents = json.loads(contents_path.read_text())
    except json.JSONDecodeError as exc:
        add_unique_error(errors, f"{contents_path.relative_to(ROOT)} no es JSON valido: {exc}.")
        return

    images = contents.get("images", [])
    if not isinstance(images, list) or not images:
        add_unique_error(errors, f"{contents_path.relative_to(ROOT)} no declara imagenes.")
        return

    for image in images:
        filename = image.get("filename") if isinstance(image, dict) else None
        if not filename:
            add_unique_error(errors, f"{contents_path.relative_to(ROOT)} tiene una entrada sin filename.")
            continue
        if not (icon_dir / filename).exists():
            add_unique_error(errors, f"Falta {icon_dir.relative_to(ROOT)}/{filename}.")


def validate_assets(asset_map: Dict[str, Dict[str, str]], brand_id: str, errors: List[str]) -> None:
    assets = asset_map.get(brand_id)
    if not assets:
        add_unique_error(errors, f"CompetitionBranding no registra el brand id '{brand_id}'.")
        return

    for key, asset_name in assets.items():
        if not asset_name:
            add_unique_error(errors, f"El brand '{brand_id}' no tiene asset '{key}'.")
            continue
        if not (ASSETS_DIR / f"{asset_name}.imageset").exists():
            add_unique_error(errors, f"Falta el asset {asset_name}.imageset para el brand '{brand_id}'.")


def resolved_xcconfig_url(value: str) -> str:
    return value.replace(":/$()/", "://")


def main() -> int:
    errors: List[str] = []
    warnings: List[str] = []

    if not BRANDS_DIR.exists():
        errors.append(f"Falta {BRANDS_DIR.relative_to(ROOT)}.")
        return print_result(errors, warnings)

    configs = load_brand_configs()
    if not configs:
        errors.append("No hay .xcconfig de brands.")
        return print_result(errors, warnings)

    inventory = project_inventory()
    schemes: Set[str] = set(inventory.get("schemes", []))
    asset_map = swift_brand_assets()
    plist_text = "\n".join(path.read_text() for path in INFO_PLISTS if path.exists())
    project_text = PROJECT_FILE.read_text()

    if "APP_BRAND_ID" not in plist_text:
        errors.append("Info.plist/Info-macOS.plist no exponen APP_BRAND_ID.")

    if "$(SUPABASE_URL)" not in plist_text or "$(SUPABASE_PUBLISHABLE_KEY)" not in plist_text:
        errors.append("Info.plist/Info-macOS.plist deben leer Supabase desde build settings por brand.")

    if "AURORA_CIRCUIT" in project_text or "PRISMA_OPEN" in project_text:
        errors.append("El proyecto todavia contiene flags Swift de brand antiguos.")

    seen_brand_ids: Dict[str, Path] = {}
    seen_bundle_ids: Dict[str, Path] = {}
    google_clients: Set[str] = set()
    google_reversed_clients: Set[str] = set()
    supabase_urls: Dict[str, List[Path]] = {}

    for config in configs:
        relative_path = config.path.relative_to(ROOT)
        missing = [key for key in REQUIRED_BRAND_SETTINGS if not config.settings.get(key)]
        for key in missing:
            add_unique_error(errors, f"{relative_path} no define {key}.")
        if missing:
            continue

        if config.id in seen_brand_ids:
            add_unique_error(
                errors,
                f"APP_BRAND_ID duplicado '{config.id}' en {relative_path} y {seen_brand_ids[config.id].relative_to(ROOT)}.",
            )
        seen_brand_ids[config.id] = config.path

        bundle_id = config.settings["PRODUCT_BUNDLE_IDENTIFIER"]
        if bundle_id in seen_bundle_ids:
            add_unique_error(
                errors,
                f"PRODUCT_BUNDLE_IDENTIFIER duplicado '{bundle_id}' en {relative_path} y {seen_bundle_ids[bundle_id].relative_to(ROOT)}.",
            )
        seen_bundle_ids[bundle_id] = config.path

        if config.scheme not in schemes:
            add_unique_error(errors, f"No existe scheme '{config.scheme}' para {relative_path}.")

        validate_assets(asset_map, config.id, errors)
        validate_icon_set(config.app_icon_name, errors)

        google_client = config.settings.get("GOOGLE_CLIENT_ID")
        reversed_client = config.settings.get("GOOGLE_REVERSED_CLIENT_ID")
        if not google_client or not reversed_client:
            add_unique_error(errors, f"{relative_path} no resuelve credenciales OAuth de Google.")
        else:
            google_clients.add(google_client)
            google_reversed_clients.add(reversed_client)

        supabase_url = resolved_xcconfig_url(config.settings.get("SUPABASE_URL", ""))
        supabase_key = config.settings.get("SUPABASE_PUBLISHABLE_KEY", "")
        if not supabase_url or not supabase_key:
            warnings.append(
                f"{relative_path} no define Supabase completo; ese brand queda en modo local hasta configurar SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY."
            )
        else:
            if not supabase_url.startswith("https://") or not supabase_url.endswith(".supabase.co"):
                add_unique_error(errors, f"{relative_path} define SUPABASE_URL con formato inesperado.")
            if not supabase_key.startswith("sb_publishable_"):
                warnings.append(
                    f"{relative_path} no usa una publishable key moderna de Supabase (sb_publishable_...)."
                )
            supabase_urls.setdefault(supabase_url, []).append(config.path)

    if len(configs) > 1 and len(google_clients) == 1 and len(google_reversed_clients) == 1:
        warnings.append(
            "Todos los brands comparten Google OAuth por ahora. Esta permitido para desarrollo, pero cada bundle id necesita cliente propio antes de publicar."
        )

    for url, paths in sorted(supabase_urls.items()):
        if len(paths) > 1:
            brands = ", ".join(path.stem for path in paths)
            warnings.append(f"Los brands {brands} comparten Supabase ({url}). OK para staging, confirmar antes de produccion.")

    for brand_id in sorted(seen_brand_ids):
        if brand_id not in asset_map:
            add_unique_error(errors, f"El brand id '{brand_id}' esta en xcconfig pero no en CompetitionBranding.")

    return print_result(errors, warnings)


def print_result(errors: List[str], warnings: List[str]) -> int:
    for warning in warnings:
        print(f"WARNING: {warning}")

    if errors:
        print("Brand validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Brand validation OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
