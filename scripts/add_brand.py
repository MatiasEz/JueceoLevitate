#!/usr/bin/env python3
"""Scaffold a new branded app shell."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional, Tuple

from brand_support import (
    ASSETS_DIR,
    BRANDS_DIR,
    CORE_BRANDING_FILE,
    PROJECT_PATH,
    ROOT,
    generate_app_icon_set,
    normalize_identifier,
    parse_rgb,
    slugify,
)


BRAND_KEYS = {
    "APP_DISPLAY_NAME",
    "ASSETCATALOG_COMPILER_APPICON_NAME",
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]",
    "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER",
    "GENERATE_INFOPLIST_FILE",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_DRIVE_ROOT_FOLDER",
    "GOOGLE_REVERSED_CLIENT_ID",
    "INFOPLIST_FILE",
    "INFOPLIST_FILE[sdk=macosx*]",
    "PRODUCT_BUNDLE_IDENTIFIER",
    "PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]",
    "PRODUCT_NAME",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
}


def initials(display_name: str) -> str:
    words = [word for word in display_name.replace("-", " ").split() if word]
    if not words:
        return "BR"
    return "".join(word[0].upper() for word in words[:2])


def write_xcconfig(path: Path, args: argparse.Namespace) -> None:
    text = "\n".join(
        [
            '#include "BrandShared.xcconfig"',
            '#include "GoogleOAuth.shared.xcconfig"',
            "",
            f"APP_BRAND_ID = {args.brand_id}",
            f"APP_DISPLAY_NAME = {args.display_name}",
            f"PRODUCT_NAME = {args.product_name}",
            f"PRODUCT_BUNDLE_IDENTIFIER = {args.bundle_id}",
            f"PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*] = {args.mac_bundle_id}",
            f"ASSETCATALOG_COMPILER_APPICON_NAME = {args.app_icon_name}",
            f"GOOGLE_DRIVE_ROOT_FOLDER = {args.drive_folder}",
            "",
        ]
    )
    path.write_text(text)


def write_imageset(asset_name: str, filename: str, svg: str) -> None:
    imageset = ASSETS_DIR / f"{asset_name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    (imageset / filename).write_text(svg)
    contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def svg_color(rgb: Tuple[int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def scaffold_assets(args: argparse.Namespace) -> None:
    primary = parse_rgb(args.primary)
    secondary = parse_rgb(args.secondary)
    generate_app_icon_set(args.app_icon_name, primary, secondary, args.icon_letters)

    primary_hex = svg_color(primary)
    secondary_hex = svg_color(secondary)
    logo_filename = f"{args.brand_id}-logo.svg"
    hero_filename = f"{args.brand_id}-hero.svg"
    write_imageset(
        args.logo_asset,
        logo_filename,
        f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 280">
  <rect width="720" height="280" rx="44" fill="{primary_hex}"/>
  <path d="M0 220 C180 130 300 330 720 120 L720 280 L0 280 Z" fill="{secondary_hex}" opacity="0.82"/>
  <text x="360" y="166" text-anchor="middle" font-family="Avenir Next, Arial, sans-serif" font-size="64" font-weight="800" fill="white">{args.display_name}</text>
</svg>
""",
    )
    write_imageset(
        args.hero_asset,
        hero_filename,
        f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1440 900">
  <defs>
    <linearGradient id="g" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="{primary_hex}"/>
      <stop offset="1" stop-color="{secondary_hex}"/>
    </linearGradient>
  </defs>
  <rect width="1440" height="900" fill="url(#g)"/>
  <path d="M-120 740 C240 520 520 880 940 590 C1130 460 1260 450 1540 560 L1540 900 L-120 900 Z" fill="white" opacity="0.18"/>
  <text x="110" y="745" font-family="Avenir Next, Arial, sans-serif" font-size="84" font-weight="800" fill="white">{args.display_name}</text>
</svg>
""",
    )


def insert_competition_branding(args: argparse.Namespace) -> None:
    text = CORE_BRANDING_FILE.read_text()
    if f'id: "{args.brand_id}"' in text:
        return

    swift_name = args.swift_name
    brand_block = f"""
    static let {swift_name} = CompetitionBranding(
        id: "{args.brand_id}",
        displayName: "{args.display_name}",
        logoAssetName: "{args.logo_asset}",
        heroFallbackAssetName: "{args.hero_asset}",
        driveRootFolderName: "{args.drive_folder}",
        colorPalette: .{args.color_palette},
        adminJudgeIDs: ["admin"],
        defaultAdminScoringJudgeNames: ["JUEZ 1", "JUEZ 2", "JUEZ 3"]
    )
"""

    marker = "    static let allBrands = ["
    if marker not in text:
        raise RuntimeError("No pude encontrar allBrands en CompetitionBranding.swift.")

    text = text.replace(marker, brand_block + "\n" + marker, 1)
    list_item = f"        {swift_name},\n"
    text = text.replace(marker + "\n", marker + "\n" + list_item, 1)
    CORE_BRANDING_FILE.write_text(text)


def ensure_xcode_target(args: argparse.Namespace, xcconfig_path: Path) -> str:
    payload = {
        "project": str(PROJECT_PATH),
        "template_target": args.template_target,
        "target_name": args.target_name,
        "xcconfig_filename": xcconfig_path.name,
        "brand_keys": sorted(BRAND_KEYS),
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(payload, handle)
        payload_path = handle.name

    ruby = r'''
require "json"
require "xcodeproj"

payload = JSON.parse(File.read(ARGV.fetch(0)))
project = Xcodeproj::Project.open(payload.fetch("project"))
template = project.targets.find { |target| target.name == payload.fetch("template_target") }
raise "Template target not found: #{payload.fetch('template_target')}" unless template

app_group = project.main_group["JueceoCoreografias"] || project.main_group.new_group("JueceoCoreografias", "JueceoCoreografias")
config_group = app_group["Config"] || app_group.new_group("Config", "Config")
brands_group = config_group["Brands"] || config_group.new_group("Brands", "Brands")
config_ref = brands_group.files.find { |file| file.path == payload.fetch("xcconfig_filename") } || brands_group.new_file(payload.fetch("xcconfig_filename"))
config_ref.last_known_file_type = "text.xcconfig"

target = project.targets.find { |candidate| candidate.name == payload.fetch("target_name") }
unless target
  target = project.new_target(:application, payload.fetch("target_name"), :ios, "17.0")

  template.source_build_phase.files.each do |build_file|
    target.source_build_phase.add_file_reference(build_file.file_ref, true) if build_file.file_ref
  end

  template.resources_build_phase.files.each do |build_file|
    target.resources_build_phase.add_file_reference(build_file.file_ref, true) if build_file.file_ref
  end

  template.frameworks_build_phase.files.each do |build_file|
    if build_file.product_ref
      target.frameworks_build_phase.add_file_reference(build_file.product_ref, true)
    elsif build_file.file_ref
      target.frameworks_build_phase.add_file_reference(build_file.file_ref, true)
    end
  end
end

brand_keys = payload.fetch("brand_keys")
target.build_configurations.each do |configuration|
  template_config = template.build_configurations.find { |candidate| candidate.name == configuration.name }
  if template_config
    configuration.build_settings.update(template_config.build_settings)
  end
  brand_keys.each { |key| configuration.build_settings.delete(key) }
  configuration.base_configuration_reference = config_ref
end

project.save
puts target.uuid
'''
    try:
        result = subprocess.run(
            ["ruby", "-e", ruby, payload_path],
            cwd=str(ROOT),
            check=True,
            text=True,
            capture_output=True,
        )
    finally:
        Path(payload_path).unlink(missing_ok=True)

    return result.stdout.strip().splitlines()[-1]


def write_scheme(args: argparse.Namespace, target_uuid: str) -> None:
    schemes_dir = PROJECT_PATH / "xcshareddata" / "xcschemes"
    schemes_dir.mkdir(parents=True, exist_ok=True)
    path = schemes_dir / f"{args.product_name}.xcscheme"
    buildable_name = f"{args.product_name}.app"
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1620"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_uuid}"
               BuildableName = "{buildable_name}"
               BlueprintName = "{args.target_name}"
               ReferencedContainer = "container:JueceoCoreografias.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uuid}"
            BuildableName = "{buildable_name}"
            BlueprintName = "{args.target_name}"
            ReferencedContainer = "container:JueceoCoreografias.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_uuid}"
            BuildableName = "{buildable_name}"
            BlueprintName = "{args.target_name}"
            ReferencedContainer = "container:JueceoCoreografias.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    path.write_text(xml)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Scaffold a branded app target and scheme.")
    parser.add_argument("--id", dest="brand_id", required=True, help="Stable brand id, for example skyline-open.")
    parser.add_argument("--display-name", required=True, help="User-facing app name.")
    parser.add_argument("--target-name", help="Xcode target name. Defaults to PascalCase display name.")
    parser.add_argument("--product-name", help="Product/scheme name. Defaults to target name.")
    parser.add_argument("--bundle-id", help="iOS bundle id.")
    parser.add_argument("--mac-bundle-id", help="Mac Catalyst bundle id.")
    parser.add_argument("--bundle-prefix", default="com.goldencrowvs.jueceo", help="Prefix used when --bundle-id is omitted.")
    parser.add_argument("--drive-folder", help="Google Drive root folder.")
    parser.add_argument("--primary", default="#2563eb", help="Primary icon color as #RRGGBB or r,g,b.")
    parser.add_argument("--secondary", default="#f59e0b", help="Secondary icon color as #RRGGBB or r,g,b.")
    parser.add_argument("--icon-letters", help="Letters drawn on generated app icons.")
    parser.add_argument("--app-icon-name", help="Asset catalog app icon name.")
    parser.add_argument("--logo-asset", help="Logo imageset name.")
    parser.add_argument("--hero-asset", help="Hero imageset name.")
    parser.add_argument("--swift-name", help="CompetitionBranding static property name.")
    parser.add_argument("--color-palette", default="levitate", help="CompetitionColorPalette static property to use initially.")
    parser.add_argument("--template-target", default="JueceoCoreografias", help="Target to clone sources/resources from.")
    parser.add_argument("--force", action="store_true", help="Overwrite scaffold files when safe.")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be created without writing.")
    return parser


def finalize_args(args: argparse.Namespace) -> argparse.Namespace:
    args.brand_id = slugify(args.brand_id)
    args.target_name = args.target_name or normalize_identifier(args.display_name)
    args.product_name = args.product_name or args.target_name
    compact_id = "".join(args.brand_id.split("-"))
    args.bundle_id = args.bundle_id or f"{args.bundle_prefix}{compact_id}"
    args.mac_bundle_id = args.mac_bundle_id or f"{args.bundle_id}.mac"
    args.drive_folder = args.drive_folder or f"FEEDBACK {args.display_name.upper()}"
    args.logo_asset = args.logo_asset or f"{args.target_name}Logo"
    args.hero_asset = args.hero_asset or f"{args.target_name}Hero"
    args.app_icon_name = args.app_icon_name or f"AppIcon{args.target_name}"
    args.icon_letters = args.icon_letters or initials(args.display_name)
    args.swift_name = args.swift_name or args.target_name[0].lower() + args.target_name[1:]
    return args


def main() -> int:
    args = finalize_args(build_parser().parse_args())
    xcconfig_path = BRANDS_DIR / f"{args.target_name}.xcconfig"

    planned = [
        xcconfig_path.relative_to(ROOT),
        (ASSETS_DIR / f"{args.app_icon_name}.appiconset").relative_to(ROOT),
        (ASSETS_DIR / f"{args.logo_asset}.imageset").relative_to(ROOT),
        (ASSETS_DIR / f"{args.hero_asset}.imageset").relative_to(ROOT),
        CORE_BRANDING_FILE.relative_to(ROOT),
        PROJECT_PATH.relative_to(ROOT),
        (PROJECT_PATH / "xcshareddata" / "xcschemes" / f"{args.product_name}.xcscheme").relative_to(ROOT),
    ]
    if args.dry_run:
        print("Would scaffold:")
        for path in planned:
            print(f"- {path}")
        return 0

    if xcconfig_path.exists() and not args.force:
        raise SystemExit(f"{xcconfig_path.relative_to(ROOT)} ya existe. Usa --force si queres reemplazarlo.")

    BRANDS_DIR.mkdir(parents=True, exist_ok=True)
    write_xcconfig(xcconfig_path, args)
    scaffold_assets(args)
    insert_competition_branding(args)
    target_uuid = ensure_xcode_target(args, xcconfig_path)
    write_scheme(args, target_uuid)

    print(f"Brand '{args.display_name}' scaffolded as scheme {args.product_name}.")
    print("Revisa CompetitionBranding para ajustar paleta, jueces admin y reglas por bloque.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
