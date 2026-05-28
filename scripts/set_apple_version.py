#!/usr/bin/env python3
"""Manage iOS/macOS bundle versions using a Flutter-like version+build value."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = ROOT / "JueceoCoreografias.xcodeproj" / "project.pbxproj"
VERSION_FILE = ROOT / "apple_version.txt"

VERSION_PATTERN = re.compile(r"^\d+(?:\.\d+){1,2}$")
BUILD_PATTERN = re.compile(r"^\d+$")


def parse_combined(value: str) -> tuple[str, str | None]:
    raw = value.strip()
    if "+" in raw:
        version, build = raw.split("+", 1)
        return version.strip(), build.strip()
    return raw, None


def validate_version(version: str) -> None:
    if not VERSION_PATTERN.match(version):
        raise ValueError("La version debe tener formato tipo 1.0 o 1.0.3.")


def validate_build(build: str) -> None:
    if not BUILD_PATTERN.match(build):
        raise ValueError("El build debe ser un numero entero.")


def read_project_setting(name: str, text: str) -> str:
    match = re.search(rf"{re.escape(name)} = ([^;]+);", text)
    if not match:
        raise ValueError(f"No pude encontrar {name} en {PROJECT_FILE}.")
    return match.group(1).strip().strip('"')


def current_values() -> tuple[str, str]:
    text = PROJECT_FILE.read_text()
    return (
        read_project_setting("MARKETING_VERSION", text),
        read_project_setting("CURRENT_PROJECT_VERSION", text),
    )


def bump_patch(version: str) -> str:
    parts = [int(part) for part in version.split(".")]
    while len(parts) < 3:
        parts.append(0)
    parts[-1] += 1
    return ".".join(str(part) for part in parts)


def write_project_values(version: str, build: str) -> None:
    text = PROJECT_FILE.read_text()
    text, version_count = re.subn(
        r"MARKETING_VERSION = [^;]+;",
        f"MARKETING_VERSION = {version};",
        text,
    )
    text, build_count = re.subn(
        r"CURRENT_PROJECT_VERSION = [^;]+;",
        f"CURRENT_PROJECT_VERSION = {build};",
        text,
    )
    if version_count == 0 or build_count == 0:
        raise ValueError("No pude actualizar las versiones del proyecto Xcode.")

    PROJECT_FILE.write_text(text)
    VERSION_FILE.write_text(f"{version}+{build}\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Set or bump the iOS/macOS app version in Xcode."
    )
    parser.add_argument(
        "version",
        nargs="?",
        help="Version value, for example 1.0.4 or 1.0.4+5.",
    )
    parser.add_argument(
        "--build",
        help="Build number to use when the positional version does not include +build.",
    )
    parser.add_argument(
        "--bump-build",
        action="store_true",
        help="Increment only CURRENT_PROJECT_VERSION.",
    )
    parser.add_argument(
        "--bump-patch",
        action="store_true",
        help="Increment the patch version and the build number.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    current_version, current_build = current_values()
    version = current_version
    build = current_build

    if args.version:
        version, parsed_build = parse_combined(args.version)
        build = parsed_build or args.build or current_build
    elif args.build:
        build = args.build

    if args.bump_patch:
        version = bump_patch(version)
        build = str(int(build) + 1)
    elif args.bump_build:
        build = str(int(build) + 1)

    validate_version(version)
    validate_build(build)

    if not any([args.version, args.build, args.bump_patch, args.bump_build]):
        print(f"Apple version: {version}+{build}")
        return 0

    write_project_values(version, build)
    print(f"Apple version updated: {version}+{build}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
