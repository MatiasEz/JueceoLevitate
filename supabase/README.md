# Supabase Backend

## Crear el backend

1. Create a Supabase project.
2. Open the SQL editor.
3. Run `supabase/migrations/0001_initial_schema.sql`.
4. Run `supabase/migrations/0002_excel_imports.sql` only if you want to keep the legacy pending Excel queue.
5. Run `supabase/migrations/0003_blocks_model.sql` to enable the event -> blocks -> routines model.
6. Run `supabase/migrations/0004_judge_roles.sql` to persist judge/admin roles.
7. Run `supabase/migrations/0005_routine_favorites.sql` to persist favorite routine picks.
8. Run `supabase/migrations/0006_routine_penalties.sql` to persist penalties.
9. Run `supabase/migrations/0007_routine_participants.sql` to persist program participants.
10. Run `supabase/migrations/0008_judge_hero_images.sql` to persist judge hero image names.
11. Run `supabase/migrations/0009_default_judges.sql` to seed the active program with Levitate's default judges.
12. Copy `.env.example` to `.env` at the repo root and fill:

```bash
SUPABASE_URL=https://bozkbpirrwjtpmjqcexx.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_jZv2loPhbPvameq6bUOgqA_5hEQJ2tc
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-for-imports-only
IMPORT_SECRET=levitate2026
```

The first migration enables permissive pilot RLS policies: anonymous clients can read event data and upsert scores/feedback. Later migrations extend the same pilot policy to favorites and penalties. Tighten this with per-event codes or judge auth before production.

## Importar Excel desde la app

La app llama a `supabase/functions/import-excel` y la Function escribe el evento directamente en Supabase. El usuario admin debe ingresar la misma clave que guardaste como `IMPORT_SECRET`.

```bash
supabase login
supabase link --project-ref bozkbpirrwjtpmjqcexx
supabase secrets set IMPORT_SECRET="levitate2026"
supabase functions deploy import-excel
supabase functions deploy archive-event
supabase functions deploy delete-routine
supabase functions deploy delete-judge
supabase functions deploy upsert-judge
```

`supabase/config.toml` deja `verify_jwt = false` para `import-excel`, `archive-event`, `delete-routine`, `delete-judge` y `upsert-judge` porque esta app todavia no usa Supabase Auth. `import-excel` y `delete-routine` validan el header `x-import-secret`; para esta instalacion esa clave es `levitate2026`. `archive-event`, `delete-judge` y `upsert-judge` no piden clave desde la app. Despues usan una secret key disponible en el runtime de Supabase para escribir tablas admin. No pongas esa secret key en iOS.

By default, the importer replaces only the blocks present in the Excel and refuses to replace blocks that already have scores, feedback or penalties. Use `force_replace` only for deliberate admin resets.

Program-only Excels can omit judging-template sheets. In that case the Edge Function uses embedded templates generated from `JueceoCoreografias/Resources/Bloque2.xlsx` and creates aliases such as `TELA`, `ARO`, `OPEN:*` and `URBANOS`.

## Importar Excel local

```bash
python3 scripts/import_excel_to_app_data.py "JueceoCoreografias/Resources/Bloque2.xlsx"
python3 scripts/import_excel_to_app_data.py "JueceoCoreografias/Resources/Bloque2.xlsx" --supabase --event-slug levitate-segunda-edicion-2024 --event-name "Levitate Segunda Edicion 2024"
```

Use `SUPABASE_SERVICE_ROLE_KEY` for imports because event/routine/template tables are admin-owned. The mobile apps only need `SUPABASE_PUBLISHABLE_KEY`.

By default, the importer replaces only the blocks present in the Excel and refuses to replace blocks that already have scores, feedback or penalties. Use `--force-replace` only for deliberate admin resets.

Program-only Excels can omit judging-template sheets. In that case the importer uses `JueceoCoreografias/Resources/Bloque2.xlsx` as the default template source and creates aliases such as `TELA`, `ARO`, `OPEN:*` and `URBANOS`.

## Migrar bloques legacy ya cargados

Si la base ya tiene `bloque-2`, `bloque-3`, etc. como eventos separados, run:

```bash
python3 scripts/migrate_legacy_blocks_to_event.py
```

This creates/updates `Levitate Segunda Edicion 2024`, copies blocks 2-7 into `blocks`, preserves the legacy events as backup, and marks the parent event active.

## Roles

`judges.role` supports:

- `judge`: can score routines only.
- `admin`: can access event, blocks, ranking, dictamen, Excel import, and scoring.

`ATI` is inserted/updated as `admin` by `0004_judge_roles.sql`.

## Procesar Excels legacy

El camino viejo guarda los Excel en `excel_imports` con estado `pending`. El procesamiento admin lee esos archivos y los convierte en eventos reales:

```bash
python3 scripts/process_excel_imports.py --allow-errors
```
