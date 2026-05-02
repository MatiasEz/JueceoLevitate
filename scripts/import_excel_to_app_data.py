#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "JueceoCoreografias" / "Resources" / "app_data.json"
DEFAULT_XLSX = ROOT / "JueceoCoreografias" / "Resources" / "Bloque2.xlsx"
DEFAULT_ENV = ROOT / ".env"

REQUIRED_BLOCK_COLUMNS = {
    "name": "COREOGRAFIA",
    "academy": "ACADEMIA",
    "division": "DIVISION",
    "genre": "GENERO",
    "category": "CATEGORIA",
}


@dataclass
class ImportResult:
    app_data: dict[str, Any]
    warnings: list[str]
    errors: list[str]


def normalized(value: Any) -> str:
    text = str(value or "").strip().upper()
    return "".join(
        character
        for character in unicodedata.normalize("NFD", text)
        if unicodedata.category(character) != "Mn"
    )


def stable_id(value: Any) -> str:
    base = normalized(value).lower()
    base = re.sub(r"[^a-z0-9]+", "-", base)
    base = re.sub(r"-+", "-", base).strip("-")
    return base or "sin-dato"


def cell_value(value: Any) -> Any:
    if value is None:
        return ""
    if isinstance(value, datetime.time):
        return f"{value.hour:02d}:{value.minute:02d}"
    if isinstance(value, datetime.datetime):
        if value.year == 1900:
            return str(value.day)
        return value.isoformat()
    return value


def sheet_rows(sheet) -> list[list[Any]]:
    return [
        [cell_value(sheet.cell(row_index, column_index).value) for column_index in range(1, sheet.max_column + 1)]
        for row_index in range(1, sheet.max_row + 1)
    ]


def load_env(path: Path = DEFAULT_ENV) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        clean = line.strip()
        if not clean or clean.startswith("#") or "=" not in clean:
            continue
        key, value = clean.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def parse_block(sheet) -> tuple[dict[str, Any] | None, list[str], list[str]]:
    warnings: list[str] = []
    errors: list[str] = []
    rows = sheet_rows(sheet)
    header_index = None
    for index, row in enumerate(rows):
        headers = [normalized(value) for value in row]
        if "COREOGRAFIA" in headers and "ACADEMIA" in headers:
            header_index = index
            break
    if header_index is None:
        return None, warnings, errors

    column_map: dict[str, int] = {}
    for index, value in enumerate(rows[header_index]):
        key = normalized(value)
        if "COREOGRAFIA" in key:
            column_map["name"] = index
        if "ACADEMIA" in key:
            column_map["academy"] = index
        if "DIVISION" in key:
            column_map["division"] = index
        if "GENERO" in key:
            column_map["genre"] = index
        if "NIVEL" in key:
            column_map["level"] = index
        if "CATEGORIA" in key:
            column_map["category"] = index
        if "COREOGRAFO" in key:
            column_map["choreographer"] = index
        if "ESTADO" in key:
            column_map["state"] = index
        if "HORARIO" in key:
            column_map["time"] = index
        if "DURACION" in key:
            column_map["duration"] = index

    missing = [label for key, label in REQUIRED_BLOCK_COLUMNS.items() if key not in column_map]
    if missing:
        warnings.append(f"{sheet.title}: parece una hoja auxiliar, se omite como bloque; faltan {', '.join(missing)}.")
        return None, warnings, errors

    routines: list[dict[str, Any]] = []
    for row_number, row in enumerate(rows[header_index + 1 :], start=header_index + 2):
        if not row or not str(row[0]).strip():
            continue
        name = str(row[column_map["name"]] or "").strip()
        if not name:
            warnings.append(f"{sheet.title} fila {row_number}: coreografia vacia, se omite.")
            continue
        routine_id = str(row[0]).replace(".0", "").strip()
        if not routine_id:
            warnings.append(f"{sheet.title} fila {row_number}: numero de rutina vacio, se omite.")
            continue
        routines.append(
            {
                "id": routine_id,
                "block": sheet.title,
                "name": name.title(),
                "academy": str(row[column_map.get("academy", 0)] or "").strip(),
                "division": str(row[column_map.get("division", 0)] or "").strip(),
                "genre": str(row[column_map.get("genre", 0)] or "").strip(),
                "level": str(row[column_map.get("level", 0)] or "").strip(),
                "category": str(row[column_map.get("category", 0)] or "").strip(),
                "choreographer": str(row[column_map.get("choreographer", 0)] or "").strip(),
                "state": str(row[column_map.get("state", 0)] or "").strip(),
                "time": str(row[column_map.get("time", 0)] or "").strip(),
                "duration": str(row[column_map.get("duration", 0)] or "").strip(),
            }
        )

    if not routines:
        return None, warnings, errors

    title = " · ".join(str(value) for row in rows[:header_index] for value in row if value)
    return {"name": sheet.title, "title": title, "routines": routines}, warnings, errors


def parse_template(sheet) -> tuple[dict[str, Any] | None, list[str], list[str]]:
    warnings: list[str] = []
    errors: list[str] = []
    rows = sheet_rows(sheet)
    title = next(
        (str(value) for row in rows for value in row if "HOJA DE JUECEO" in normalized(value)),
        None,
    )
    if not title:
        return None, warnings, errors

    section = "General"
    criteria: list[dict[str, Any]] = []
    for row_number, row in enumerate(rows, start=1):
        number_value = row[1] if len(row) > 1 else ""
        label = str(row[2] if len(row) > 2 else "").strip()
        max_value = row[3] if len(row) > 3 else ""
        try:
            number = float(str(number_value).replace(",", "."))
        except ValueError:
            number = 0
        try:
            maximum = float(str(max_value).replace(",", "."))
        except ValueError:
            maximum = 0

        if number_value and not number and normalized(number_value) not in ["-", "JUEZ", "FEEDBACK"]:
            section = str(number_value).strip()
        if number > 0 and label:
            if maximum <= 0:
                errors.append(f"{sheet.title} fila {row_number}: criterio '{label}' sin puntaje maximo.")
                continue
            criteria.append(
                {"id": int(number), "section": section, "label": label, "maxScore": maximum}
            )

    if not criteria:
        errors.append(f"{sheet.title}: hoja de jueceo sin criterios validos.")
        return None, warnings, errors

    return {
        "genre": sheet.title,
        "title": title,
        "maxScore": sum(item["maxScore"] for item in criteria),
        "criteria": criteria,
    }, warnings, errors


def parse_judges(workbook) -> tuple[list[str], list[str], list[str]]:
    warnings: list[str] = []
    errors: list[str] = []
    judges: list[str] = []
    seen: set[str] = set()
    duplicate_count = 0
    if "CALIFICACIONES" in workbook.sheetnames:
        sheet = workbook["CALIFICACIONES"]
        for row_index in range(1, sheet.max_row + 1):
            value = sheet.cell(row_index, 3).value
            if not value or normalized(value) == "JUEZ" or str(value).startswith("="):
                continue
            judge = str(value).strip().upper()
            key = normalized(judge)
            if not key:
                continue
            if key in seen:
                duplicate_count += 1
                continue
            seen.add(key)
            judges.append(judge)
    if not judges:
        judges = ["DAVE", "EVA", "DANIEL"]
        warnings.append("No se encontraron jueces en CALIFICACIONES; se usan jueces demo.")
    elif duplicate_count:
        warnings.append(f"CALIFICACIONES: {duplicate_count} jueces duplicados omitidos.")
    return judges, warnings, errors


def parse_workbook(source: Path) -> ImportResult:
    workbook = load_workbook(source, data_only=False)
    warnings: list[str] = []
    errors: list[str] = []
    blocks: list[dict[str, Any]] = []
    templates: list[dict[str, Any]] = []

    for sheet in workbook.worksheets:
        block, block_warnings, block_errors = parse_block(sheet)
        warnings.extend(block_warnings)
        errors.extend(block_errors)
        if block:
            blocks.append(block)

        template, template_warnings, template_errors = parse_template(sheet)
        warnings.extend(template_warnings)
        errors.extend(template_errors)
        if template:
            templates.append(template)

    routines = [routine for block in blocks for routine in block["routines"]]
    judges, judge_warnings, judge_errors = parse_judges(workbook)
    warnings.extend(judge_warnings)
    errors.extend(judge_errors)

    routine_ids: set[str] = set()
    for routine in routines:
        if routine["id"] in routine_ids:
            errors.append(f"Rutina duplicada: #{routine['id']}.")
        routine_ids.add(routine["id"])

    template_genres = {normalized(template["genre"]) for template in templates}
    for genre in sorted({routine["genre"] for routine in routines}, key=normalized):
        if normalized(genre) not in template_genres:
            errors.append(f"Genero sin hoja de jueceo: {genre}.")

    app_data = {
        "sourceName": source.name,
        "blocks": blocks,
        "routines": routines,
        "templates": templates,
        "judges": judges,
    }
    return ImportResult(app_data=app_data, warnings=warnings, errors=errors)


def write_json(app_data: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(app_data, ensure_ascii=False, indent=2), encoding="utf-8")


def supabase_request(
    method: str,
    path: str,
    payload: Any | None = None,
    *,
    prefer: str | None = None,
) -> Any:
    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_ANON_KEY")
    if not base_url or not key:
        raise RuntimeError("Faltan SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY/SUPABASE_ANON_KEY.")

    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(f"{base_url}/rest/v1/{path.lstrip('/')}", data=data, method=method)
    request.add_header("apikey", key)
    request.add_header("Authorization", f"Bearer {key}")
    request.add_header("Content-Type", "application/json")
    if prefer:
        request.add_header("Prefer", prefer)

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8")
        raise RuntimeError(f"Supabase {method} {path} fallo: {error.code} {detail}") from error


def chunked(items: list[dict[str, Any]], size: int = 500):
    for index in range(0, len(items), size):
        yield items[index : index + size]


def upsert_rows(table: str, rows: list[dict[str, Any]], conflict: str) -> None:
    if not rows:
        return
    query = urllib.parse.urlencode({"on_conflict": conflict})
    for chunk in chunked(rows):
        supabase_request(
            "POST",
            f"{table}?{query}",
            chunk,
            prefer="resolution=merge-duplicates,return=minimal",
        )


def delete_event_rows(event_id: str) -> None:
    encoded = urllib.parse.quote(event_id)
    for table in ["feedback", "scores", "criteria", "criteria_templates", "judges", "routines"]:
        supabase_request("DELETE", f"{table}?event_id=eq.{encoded}", prefer="return=minimal")


def upload_to_supabase(app_data: dict[str, Any], *, slug: str, name: str, activate: bool) -> str:
    if activate:
        supabase_request(
            "PATCH",
            "events?is_active=eq.true",
            {"is_active": False},
            prefer="return=minimal",
        )

    event_rows = supabase_request(
        "POST",
        "events?on_conflict=slug",
        [
            {
                "slug": slug,
                "name": name,
                "source_name": app_data["sourceName"],
                "is_active": activate,
            }
        ],
        prefer="resolution=merge-duplicates,return=representation",
    )
    if not event_rows:
        raise RuntimeError("Supabase no devolvio el evento importado.")
    event_id = event_rows[0]["id"]
    delete_event_rows(event_id)

    block_titles = {block["name"]: block.get("title", "") for block in app_data["blocks"]}
    routine_rows = [
        {
            "event_id": event_id,
            "routine_id": routine["id"],
            "block": routine["block"],
            "block_title": block_titles.get(routine["block"], ""),
            "sort_order": index,
            "name": routine["name"],
            "academy": routine["academy"],
            "division": routine["division"],
            "genre": routine["genre"],
            "level": routine["level"],
            "category": routine["category"],
            "choreographer": routine["choreographer"],
            "state": routine["state"],
            "scheduled_time": routine["time"],
            "duration": routine["duration"],
        }
        for index, routine in enumerate(app_data["routines"], start=1)
    ]
    judge_rows = [
        {"event_id": event_id, "judge_id": stable_id(judge), "name": judge, "sort_order": index}
        for index, judge in enumerate(app_data["judges"], start=1)
    ]
    template_rows = []
    criterion_rows = []
    for template_index, template in enumerate(app_data["templates"], start=1):
        template_id = stable_id(template["genre"])
        template_rows.append(
            {
                "event_id": event_id,
                "template_id": template_id,
                "genre": template["genre"],
                "title": template["title"],
                "max_score": template["maxScore"],
                "sort_order": template_index,
            }
        )
        for criterion_index, criterion in enumerate(template["criteria"], start=1):
            criterion_rows.append(
                {
                    "event_id": event_id,
                    "template_id": template_id,
                    "criterion_id": criterion["id"],
                    "section": criterion["section"],
                    "label": criterion["label"],
                    "max_score": criterion["maxScore"],
                    "sort_order": criterion_index,
                }
            )

    upsert_rows("routines", routine_rows, "event_id,routine_id")
    upsert_rows("judges", judge_rows, "event_id,judge_id")
    upsert_rows("criteria_templates", template_rows, "event_id,template_id")
    upsert_rows("criteria", criterion_rows, "event_id,template_id,criterion_id")
    return event_id


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Importa el Excel de jueceo a JSON local y opcionalmente Supabase.")
    parser.add_argument("source", nargs="?", default=str(DEFAULT_XLSX), help="Ruta al .xlsx de origen.")
    parser.add_argument("output", nargs="?", default=str(DEFAULT_OUTPUT), help="Ruta del JSON de salida.")
    parser.add_argument("--supabase", action="store_true", help="Tambien sube el evento a Supabase.")
    parser.add_argument("--event-slug", default=os.environ.get("JUECEO_EVENT_SLUG", ""), help="Slug estable del evento.")
    parser.add_argument("--event-name", default=os.environ.get("JUECEO_EVENT_NAME", ""), help="Nombre visible del evento.")
    parser.add_argument("--no-activate", action="store_true", help="No marcar este evento como activo.")
    parser.add_argument("--allow-errors", action="store_true", help="Escribe/sube aunque haya errores de validacion.")
    parser.add_argument("--strict", action="store_true", help="Cancela tambien la salida JSON local si hay errores.")
    return parser


def main() -> int:
    load_env()
    parser = build_parser()
    args = parser.parse_args()

    source = Path(args.source).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()
    slug = args.event_slug or stable_id(source.stem)
    name = args.event_name or source.stem

    result = parse_workbook(source)
    for warning in result.warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    for error in result.errors:
        print(f"ERROR: {error}", file=sys.stderr)

    should_cancel = result.errors and (args.strict or (args.supabase and not args.allow_errors))
    if should_cancel:
        print("Import cancelado por errores de validacion. Usa --allow-errors solo para pruebas.", file=sys.stderr)
        return 2

    write_json(result.app_data, output)
    print(
        f"Wrote {output} with "
        f"{len(result.app_data['routines'])} routines, "
        f"{len(result.app_data['templates'])} templates, "
        f"{len(result.app_data['judges'])} judges."
    )

    if args.supabase:
        event_id = upload_to_supabase(result.app_data, slug=slug, name=name, activate=not args.no_activate)
        print(f"Uploaded Supabase event '{name}' ({slug}) with id {event_id}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
