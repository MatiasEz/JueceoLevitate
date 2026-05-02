# Supabase Backend

## Crear el backend

1. Create a Supabase project.
2. Open the SQL editor.
3. Run `supabase/migrations/0001_initial_schema.sql`.
4. Copy `.env.example` to `.env` at the repo root and fill:

```bash
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-public-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-for-imports-only
```

The first migration enables permissive pilot RLS policies: anonymous clients can read event data and upsert scores/feedback. This is deliberate for the event pilot. Tighten this with per-event codes or judge auth before production.

## Importar Excel

```bash
python3 scripts/import_excel_to_app_data.py "JueceoCoreografias/Resources/Bloque2.xlsx"
python3 scripts/import_excel_to_app_data.py "JueceoCoreografias/Resources/Bloque2.xlsx" --supabase --event-slug bloque-2-2024 --event-name "Bloque 2 2024"
```

Use `SUPABASE_SERVICE_ROLE_KEY` for imports because event/routine/template tables are admin-owned. The mobile apps only need `SUPABASE_ANON_KEY`.
