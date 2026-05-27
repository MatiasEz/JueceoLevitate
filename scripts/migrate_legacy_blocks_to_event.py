#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import urllib.parse
from typing import Any

from import_excel_to_app_data import (
    delete_block_rows,
    load_env,
    role_for_person,
    stable_id,
    supabase_request,
    upsert_rows,
    with_required_people,
)


DEFAULT_SOURCE_SLUGS = [f"bloque-{number}" for number in range(2, 8)]


def fetch_rows(table: str, event_id: str) -> list[dict[str, Any]]:
    encoded = urllib.parse.quote(event_id)
    return supabase_request("GET", f"{table}?select=*&event_id=eq.{encoded}") or []


def parse_sort(value: str, fallback: int) -> int:
    match = re.search(r"(\d+)", value)
    return int(match.group(1)) if match else fallback


def upsert_parent_event(slug: str, name: str, activate: bool) -> str:
    if activate:
        supabase_request(
            "PATCH",
            "events?is_active=eq.true",
            {"is_active": False},
            prefer="return=minimal",
        )
    rows = supabase_request(
        "POST",
        "events?on_conflict=slug",
        [
            {
                "slug": slug,
                "name": name,
                "source_name": "Migracion de bloques legacy",
                "is_active": activate,
                "event_type": "event",
            }
        ],
        prefer="resolution=merge-duplicates,return=representation",
    )
    if not rows:
        raise RuntimeError("Supabase no devolvio el evento padre.")
    return rows[0]["id"]


def fetch_source_events(source_slugs: list[str]) -> list[dict[str, Any]]:
    rows = supabase_request(
        "GET",
        "events?select=id,slug,name,source_name,is_active,event_type&order=slug.asc",
    )
    by_slug = {row["slug"]: row for row in rows}
    return [by_slug[slug] for slug in source_slugs if slug in by_slug]


def migrate(args: argparse.Namespace) -> None:
    source_events = fetch_source_events(args.source_slugs)
    if not source_events:
        raise RuntimeError("No encontre eventos legacy para migrar.")
    if not any(event.get("is_active", False) for event in source_events):
        source_events[0]["is_active"] = True
    parent_id = upsert_parent_event(args.event_slug, args.event_name, activate=not args.no_activate)

    block_rows: list[dict[str, Any]] = []
    routine_rows: list[dict[str, Any]] = []
    judge_rows_by_id: dict[str, dict[str, Any]] = {}
    template_rows_by_id: dict[str, dict[str, Any]] = {}
    criterion_rows_by_key: dict[tuple[str, int], dict[str, Any]] = {}
    score_rows: list[dict[str, Any]] = []
    feedback_rows: list[dict[str, Any]] = []
    imported_block_ids: list[str] = []

    for source_index, event in enumerate(source_events, start=1):
        routines = fetch_rows("routines", event["id"])
        if not routines:
            continue

        first_routine = sorted(routines, key=lambda row: row.get("sort_order", 0))[0]
        block_name = first_routine.get("block") or event["name"]
        block_id = first_routine.get("block_id") or stable_id(block_name)
        block_sort = parse_sort(event["slug"], source_index)
        imported_block_ids.append(block_id)
        block_rows.append(
            {
                "event_id": parent_id,
                "block_id": block_id,
                "legacy_event_id": event["id"],
                "name": block_name,
                "title": first_routine.get("block_title", ""),
                "sort_order": block_sort,
                "is_active": event.get("is_active", False),
            }
        )

        source_judges = fetch_rows("judges", event["id"])
        names_by_id = {judge["judge_id"]: judge["name"] for judge in source_judges}
        for name in with_required_people(list(names_by_id.values())):
            judge_id = stable_id(name)
            judge_rows_by_id.setdefault(
                judge_id,
                {
                    "event_id": parent_id,
                    "judge_id": judge_id,
                    "name": name,
                    "role": role_for_person(name),
                    "sort_order": len(judge_rows_by_id) + 1,
                },
            )

        for template in fetch_rows("criteria_templates", event["id"]):
            template_id = template["template_id"]
            template_rows_by_id.setdefault(
                template_id,
                {
                    "event_id": parent_id,
                    "template_id": template_id,
                    "genre": template["genre"],
                    "title": template["title"],
                    "max_score": template.get("max_score", 0),
                    "sort_order": template.get("sort_order", len(template_rows_by_id) + 1),
                },
            )

        for criterion in fetch_rows("criteria", event["id"]):
            key = (criterion["template_id"], int(criterion["criterion_id"]))
            criterion_rows_by_key.setdefault(
                key,
                {
                    "event_id": parent_id,
                    "template_id": criterion["template_id"],
                    "criterion_id": criterion["criterion_id"],
                    "section": criterion.get("section", ""),
                    "label": criterion["label"],
                    "max_score": criterion["max_score"],
                    "sort_order": criterion.get("sort_order", len(criterion_rows_by_key) + 1),
                },
            )

        for routine in routines:
            routine_rows.append(
                {
                    "event_id": parent_id,
                    "routine_id": routine["routine_id"],
                    "block_id": block_id,
                    "block": block_name,
                    "block_title": routine.get("block_title", ""),
                    "sort_order": block_sort * 10000 + int(routine.get("sort_order", 0)),
                    "name": routine["name"],
                    "academy": routine.get("academy", ""),
                    "division": routine.get("division", ""),
                    "genre": routine.get("genre", ""),
                    "level": routine.get("level", ""),
                    "category": routine.get("category", ""),
                    "choreographer": routine.get("choreographer", ""),
                    "participant": routine.get("participant", ""),
                    "state": routine.get("state", ""),
                    "scheduled_time": routine.get("scheduled_time", ""),
                    "duration": routine.get("duration", ""),
                }
            )

        for score in fetch_rows("scores", event["id"]):
            score_rows.append(
                {
                    "event_id": parent_id,
                    "routine_id": score["routine_id"],
                    "block_id": block_id,
                    "judge_id": score["judge_id"],
                    "criterion_id": score["criterion_id"],
                    "value": score["value"],
                    "device_id": score.get("device_id", ""),
                }
            )

        for item in fetch_rows("feedback", event["id"]):
            feedback_rows.append(
                {
                    "event_id": parent_id,
                    "routine_id": item["routine_id"],
                    "block_id": block_id,
                    "judge_id": item["judge_id"],
                    "body": item.get("body", ""),
                    "device_id": item.get("device_id", ""),
                }
            )

    delete_block_rows(parent_id, imported_block_ids, force_replace=args.force_replace)
    upsert_rows("blocks", block_rows, "event_id,block_id")
    upsert_rows("judges", list(judge_rows_by_id.values()), "event_id,judge_id")
    upsert_rows("criteria_templates", list(template_rows_by_id.values()), "event_id,template_id")
    upsert_rows("criteria", list(criterion_rows_by_key.values()), "event_id,template_id,criterion_id")
    upsert_rows("routines", routine_rows, "event_id,routine_id")
    upsert_rows("scores", score_rows, "event_id,routine_id,judge_id,criterion_id")
    upsert_rows("feedback", feedback_rows, "event_id,routine_id,judge_id")

    source_ids = ",".join(urllib.parse.quote(event["id"]) for event in source_events)
    supabase_request(
        "PATCH",
        f"events?id=in.({source_ids})",
        {"event_type": "legacy_block", "is_active": False},
        prefer="return=minimal",
    )

    print(
        f"Migrado {args.event_name} ({args.event_slug}) con "
        f"{len(block_rows)} bloques, {len(routine_rows)} rutinas, "
        f"{len(judge_rows_by_id)} jueces, {len(template_rows_by_id)} templates."
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Consolida eventos legacy bloque-N dentro de un evento padre.")
    parser.add_argument("--event-slug", default="levitate-segunda-edicion-2024")
    parser.add_argument("--event-name", default="Levitate Segunda Edicion 2024")
    parser.add_argument("--source-slugs", nargs="+", default=DEFAULT_SOURCE_SLUGS)
    parser.add_argument("--no-activate", action="store_true", help="No marcar el evento padre como activo.")
    parser.add_argument("--force-replace", action="store_true", help="Permite reemplazar bloques ya puntuados en el evento padre.")
    return parser


def main() -> int:
    load_env()
    migrate(build_parser().parse_args())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
