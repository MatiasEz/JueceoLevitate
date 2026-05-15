#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import datetime
import tempfile
from pathlib import Path
from typing import Any

from import_excel_to_app_data import load_env, parse_workbook, supabase_request, upload_to_supabase


def fetch_pending_imports(limit: int) -> list[dict[str, Any]]:
    return supabase_request(
        "GET",
        "excel_imports?"
        "select=id,event_slug,event_name,filename,payload_base64"
        f"&status=eq.pending&order=created_at.asc&limit={limit}",
    )


def update_import(import_id: str, status: str, error_message: str = "") -> None:
    payload: dict[str, Any] = {"status": status}
    if status in {"processed", "failed"}:
        payload["processed_at"] = datetime.datetime.now(datetime.UTC).isoformat()
    if error_message:
        payload["error_message"] = error_message[:1000]

    supabase_request(
        "PATCH",
        f"excel_imports?id=eq.{import_id}",
        payload,
        prefer="return=minimal",
    )


def process_import(row: dict[str, Any], *, allow_errors: bool, activate: bool, force_replace: bool) -> str:
    import_id = row["id"]
    update_import(import_id, "processing")

    with tempfile.TemporaryDirectory() as temp_dir:
        filename = Path(row["filename"]).name or "import.xlsx"
        source = Path(temp_dir) / filename
        source.write_bytes(base64.b64decode(row["payload_base64"]))

        result = parse_workbook(source)
        if result.errors and not allow_errors:
            raise RuntimeError("; ".join(result.errors))

        return upload_to_supabase(
            result.app_data,
            slug=row["event_slug"],
            name=row["event_name"],
            activate=activate,
            force_replace=force_replace,
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Procesa Excel subidos desde la app y los importa a Supabase.")
    parser.add_argument("--limit", type=int, default=5, help="Cantidad maxima de importaciones pendientes.")
    parser.add_argument("--allow-errors", action="store_true", help="Importa aunque el Excel tenga errores de validacion.")
    parser.add_argument("--no-activate", action="store_true", help="No marcar el evento importado como activo.")
    parser.add_argument("--force-replace", action="store_true", help="Permite reemplazar bloques que ya tienen puntajes o feedback.")
    return parser


def main() -> int:
    load_env()
    args = build_parser().parse_args()
    rows = fetch_pending_imports(args.limit)
    if not rows:
        print("No hay importaciones pendientes.")
        return 0

    failed = 0
    for row in rows:
        try:
            event_id = process_import(
                row,
                allow_errors=args.allow_errors,
                activate=not args.no_activate,
                force_replace=args.force_replace,
            )
            update_import(row["id"], "processed")
            print(f"Procesado {row['filename']} -> {row['event_name']} ({event_id}).")
        except Exception as error:  # noqa: BLE001 - script admin, preserve visible failure.
            failed += 1
            update_import(row["id"], "failed", str(error))
            print(f"ERROR {row['filename']}: {error}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
