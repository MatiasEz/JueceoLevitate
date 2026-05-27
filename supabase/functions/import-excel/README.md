# import-excel Edge Function

Procesa un `.xlsx` de programa desde la app y crea/actualiza `events`, `blocks`, `routines`, `judges`, `criteria_templates` y `criteria` directamente en Supabase.

## Deploy

```bash
supabase login
supabase link --project-ref bozkbpirrwjtpmjqcexx
supabase secrets set IMPORT_SECRET="una-clave-larga-para-admins"
supabase functions deploy import-excel
```

La app envia la clave en `x-import-secret`. La Function valida esa clave contra `IMPORT_SECRET` antes de usar permisos admin en Supabase.
