#!/usr/bin/env python3
"""Shared helpers for branded app targets."""

from __future__ import annotations

import json
import math
import re
import struct
import subprocess
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = ROOT / "JueceoCoreografias.xcodeproj"
PROJECT_FILE = PROJECT_PATH / "project.pbxproj"
APP_DIR = ROOT / "JueceoCoreografias"
ASSETS_DIR = APP_DIR / "Assets.xcassets"
BRANDS_DIR = APP_DIR / "Config" / "Brands"
CORE_BRANDING_FILE = ROOT / "Packages" / "JueceoCore" / "Sources" / "JueceoCore" / "CompetitionBranding.swift"
PACKAGE_DIR = ROOT / "Packages" / "JueceoCore"

SHARED_XCCONFIGS = {
    "BrandShared.xcconfig",
    "GoogleOAuth.shared.xcconfig",
}

REQUIRED_BRAND_SETTINGS = [
    "APP_BRAND_ID",
    "APP_DISPLAY_NAME",
    "PRODUCT_NAME",
    "PRODUCT_BUNDLE_IDENTIFIER",
    "PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]",
    "GOOGLE_DRIVE_ROOT_FOLDER",
    "ASSETCATALOG_COMPILER_APPICON_NAME",
]

APP_ICON_SPECS = [
    ("iphone", "20x20", "2x", 40, "Icon-20@2x.png"),
    ("iphone", "20x20", "3x", 60, "Icon-20@3x.png"),
    ("iphone", "29x29", "2x", 58, "Icon-29@2x.png"),
    ("iphone", "29x29", "3x", 87, "Icon-29@3x.png"),
    ("iphone", "40x40", "2x", 80, "Icon-40@2x.png"),
    ("iphone", "40x40", "3x", 120, "Icon-40@3x.png"),
    ("iphone", "60x60", "2x", 120, "Icon-60@2x.png"),
    ("iphone", "60x60", "3x", 180, "Icon-60@3x.png"),
    ("ipad", "20x20", "1x", 20, "Icon-20-ipad@1x.png"),
    ("ipad", "20x20", "2x", 40, "Icon-20-ipad@2x.png"),
    ("ipad", "29x29", "1x", 29, "Icon-29-ipad@1x.png"),
    ("ipad", "29x29", "2x", 58, "Icon-29-ipad@2x.png"),
    ("ipad", "40x40", "1x", 40, "Icon-40-ipad@1x.png"),
    ("ipad", "40x40", "2x", 80, "Icon-40-ipad@2x.png"),
    ("ipad", "76x76", "1x", 76, "Icon-76@1x.png"),
    ("ipad", "76x76", "2x", 152, "Icon-76@2x.png"),
    ("ipad", "83.5x83.5", "2x", 167, "Icon-83.5@2x.png"),
    ("ios-marketing", "1024x1024", "1x", 1024, "Icon-1024.png"),
]

FONT_5X7 = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
}


@dataclass(frozen=True)
class BrandConfig:
    path: Path
    settings: Dict[str, str]

    @property
    def id(self) -> str:
        return self.settings["APP_BRAND_ID"]

    @property
    def scheme(self) -> str:
        return self.settings["PRODUCT_NAME"]

    @property
    def display_name(self) -> str:
        return self.settings["APP_DISPLAY_NAME"]

    @property
    def app_icon_name(self) -> str:
        return self.settings["ASSETCATALOG_COMPILER_APPICON_NAME"]


def parse_xcconfig(path: Path, seen: Optional[set] = None) -> Dict[str, str]:
    seen = seen or set()
    if path in seen:
        return {}
    seen.add(path)

    settings: Dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        include_match = re.match(r'#include\s+"([^"]+)"', line)
        if include_match:
            settings.update(parse_xcconfig(path.parent / include_match.group(1), seen))
            continue
        if "=" not in line:
            continue
        key, value = line.rsplit("=", 1)
        settings[key.strip()] = value.strip().rstrip(";").strip('"')
    return settings


def brand_config_paths() -> List[Path]:
    return sorted(
        path
        for path in BRANDS_DIR.glob("*.xcconfig")
        if path.name not in SHARED_XCCONFIGS
    )


def load_brand_configs() -> List[BrandConfig]:
    configs = []
    for path in brand_config_paths():
        settings = parse_xcconfig(path)
        configs.append(BrandConfig(path=path, settings=settings))
    return configs


def project_inventory() -> Dict[str, List[str]]:
    result = subprocess.run(
        ["xcodebuild", "-list", "-json", "-project", str(PROJECT_PATH)],
        cwd=str(ROOT),
        check=True,
        text=True,
        capture_output=True,
    )
    payload = json.loads(result.stdout)
    return payload["project"]


def swift_brand_assets() -> Dict[str, Dict[str, str]]:
    text = CORE_BRANDING_FILE.read_text()
    blocks = re.split(r"\n\s*static let ", text)
    assets: Dict[str, Dict[str, str]] = {}
    for block in blocks:
        if "CompetitionBranding(" not in block:
            continue
        id_match = re.search(r'id:\s*"([^"]+)"', block)
        logo_match = re.search(r'logoAssetName:\s*"([^"]+)"', block)
        hero_match = re.search(r'heroFallbackAssetName:\s*"([^"]+)"', block)
        if id_match:
            assets[id_match.group(1)] = {
                "logo": logo_match.group(1) if logo_match else "",
                "hero": hero_match.group(1) if hero_match else "",
            }
    return assets


def normalize_identifier(value: str) -> str:
    parts = re.split(r"[^A-Za-z0-9]+", value.strip())
    cleaned = "".join(part[:1].upper() + part[1:] for part in parts if part)
    if not cleaned:
        raise ValueError("El identificador no puede estar vacio.")
    if cleaned[0].isdigit():
        cleaned = "Brand" + cleaned
    return cleaned


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.strip().lower()).strip("-")
    if not slug:
        raise ValueError("El id del brand no puede estar vacio.")
    return slug


def parse_rgb(value: str) -> Tuple[int, int, int]:
    raw = value.strip()
    if raw.startswith("#"):
        raw = raw[1:]
    if len(raw) == 6:
        return tuple(int(raw[index:index + 2], 16) for index in range(0, 6, 2))  # type: ignore[return-value]
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 3:
        raise ValueError("Los colores deben venir como #RRGGBB o r,g,b.")
    numbers = []
    for part in parts:
        if "." in part:
            numbers.append(round(float(part) * 255))
        else:
            numbers.append(int(part))
    return tuple(max(0, min(255, number)) for number in numbers)  # type: ignore[return-value]


def app_icon_contents() -> Dict[str, object]:
    return {
        "images": [
            {
                "idiom": idiom,
                "size": size,
                "scale": scale,
                "filename": filename,
            }
            for idiom, size, scale, _pixels, filename in APP_ICON_SPECS
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, pixels: Sequence[Tuple[int, int, int, int]]) -> None:
    raw_rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(pixels[y * width + x])
        raw_rows.append(bytes(row))

    payload = b"".join(raw_rows)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(payload, 9))
        + _png_chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def _mix(a: int, b: int, amount: float) -> int:
    return round(a * (1 - amount) + b * amount)


def _draw_rect(pixels: List[Tuple[int, int, int, int]], width: int, height: int, x0: int, y0: int, x1: int, y1: int, color: Tuple[int, int, int, int]) -> None:
    for y in range(max(0, y0), min(height, y1)):
        for x in range(max(0, x0), min(width, x1)):
            pixels[y * width + x] = color


def _draw_letters(pixels: List[Tuple[int, int, int, int]], width: int, height: int, letters: str) -> None:
    glyphs = [FONT_5X7.get(char) for char in letters.upper() if char != " "]
    glyphs = [glyph for glyph in glyphs if glyph]
    if not glyphs:
        return

    glyph_width = 5
    glyph_height = 7
    spacing = 2
    total_columns = len(glyphs) * glyph_width + (len(glyphs) - 1) * spacing
    scale = max(1, int(width * 0.45 / total_columns))
    total_width = total_columns * scale
    total_height = glyph_height * scale
    start_x = (width - total_width) // 2
    start_y = (height - total_height) // 2
    color = (255, 255, 255, 255)

    cursor_x = start_x
    for glyph in glyphs:
        for row_index, row in enumerate(glyph):
            for column_index, bit in enumerate(row):
                if bit == "1":
                    _draw_rect(
                        pixels,
                        width,
                        height,
                        cursor_x + column_index * scale,
                        start_y + row_index * scale,
                        cursor_x + (column_index + 1) * scale,
                        start_y + (row_index + 1) * scale,
                        color,
                    )
        cursor_x += (glyph_width + spacing) * scale


def render_icon(size: int, primary: Tuple[int, int, int], secondary: Tuple[int, int, int], letters: str) -> List[Tuple[int, int, int, int]]:
    pixels: List[Tuple[int, int, int, int]] = []
    center_x = size * 0.55
    center_y = size * 0.42
    for y in range(size):
        for x in range(size):
            diagonal = (x + y) / max(1, (size - 1) * 2)
            radial = min(1.0, math.hypot(x - center_x, y - center_y) / max(1, size * 0.82))
            amount = min(1.0, diagonal * 0.72 + radial * 0.28)
            r = _mix(primary[0], secondary[0], amount)
            g = _mix(primary[1], secondary[1], amount)
            b = _mix(primary[2], secondary[2], amount)
            if x > y + size * 0.18:
                r = _mix(r, 255, 0.10)
                g = _mix(g, 255, 0.10)
                b = _mix(b, 255, 0.10)
            pixels.append((r, g, b, 255))

    ring = max(1, size // 28)
    inset = max(2, size // 9)
    border = (255, 255, 255, 255)
    _draw_rect(pixels, size, size, inset, inset, size - inset, inset + ring, border)
    _draw_rect(pixels, size, size, inset, size - inset - ring, size - inset, size - inset, border)
    _draw_rect(pixels, size, size, inset, inset, inset + ring, size - inset, border)
    _draw_rect(pixels, size, size, size - inset - ring, inset, size - inset, size - inset, border)
    _draw_letters(pixels, size, size, letters)
    return pixels


def generate_app_icon_set(icon_name: str, primary: Tuple[int, int, int], secondary: Tuple[int, int, int], letters: str) -> Path:
    icon_dir = ASSETS_DIR / f"{icon_name}.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    (icon_dir / "Contents.json").write_text(json.dumps(app_icon_contents(), indent=2) + "\n")
    for _idiom, _size, _scale, pixels, filename in APP_ICON_SPECS:
        write_png(icon_dir / filename, pixels, pixels, render_icon(pixels, primary, secondary, letters))
    return icon_dir


def run(command: Sequence[str], cwd: Path = ROOT) -> None:
    printable = " ".join(command)
    print(f"$ {printable}")
    subprocess.run(list(command), cwd=str(cwd), check=True)
