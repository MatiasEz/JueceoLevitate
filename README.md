# Jueceo Coreografias

App nativa de iPad creada en Xcode/SwiftUI a partir del Excel original.

## Abrir en Xcode

Abre `JueceoCoreografias.xcodeproj`, elige un simulador o iPad físico y ejecuta el esquema `JueceoCoreografias`.

## Cargar otro Excel

Para reemplazar el contenido base por otro Excel con la misma estructura:

```bash
python3 scripts/import_excel_to_app_data.py "/ruta/al/bloque.xlsx"
```

Después vuelve a compilar en Xcode. El archivo generado es `JueceoCoreografias/Resources/app_data.json`.

El importador ahora valida columnas obligatorias, rutinas duplicadas, generos sin plantilla, criterios sin puntaje maximo y jueces repetidos. Para publicar el evento en Supabase:

```bash
cp .env.example .env
# Completa SUPABASE_SERVICE_ROLE_KEY para importar datos admin.
python3 scripts/import_excel_to_app_data.py "/ruta/al/bloque.xlsx" --supabase --event-slug "bloque-2-2024" --event-name "Bloque 2 2024"
```

Con el modelo nuevo, `event-slug` representa la competencia/evento padre y la hoja del Excel representa el bloque. Ejemplo:

```bash
python3 scripts/import_excel_to_app_data.py "/ruta/Bloque3.xlsx" --supabase --event-slug "levitate-segunda-edicion-2024" --event-name "Levitate Segunda Edicion 2024"
```

El importador reemplaza solo el bloque incluido en el Excel y corta si ese bloque ya tiene puntajes o feedback. Para un reset admin deliberado, usa `--force-replace`.

## Backend Supabase

La migracion inicial esta en `supabase/migrations/0001_initial_schema.sql`. Crea las tablas `events`, `routines`, `judges`, `criteria_templates`, `criteria`, `scores` y `feedback`.

El modelo de bloques esta en `supabase/migrations/0003_blocks_model.sql`. Agrega `blocks`, `events.event_type` y `block_id` en rutinas/puntajes/feedback para que la estructura quede:

```text
events -> blocks -> routines -> scores/feedback
```

Si la BD ya tiene `bloque-2` a `bloque-7` como eventos separados, despues de correr la migracion 0003 podes consolidarlos sin perder los legacy:

```bash
python3 scripts/migrate_legacy_blocks_to_event.py
```

Los roles de personas estan en `supabase/migrations/0004_judge_roles.sql`. `ATI` queda como `admin`; los demas quedan como `judge`. En la app, los jueces solo acceden a calificacion, mientras que admin puede entrar a bloques, ranking, dictamen e importacion Excel.

Los favoritos de vestuario/coreografia/musica se guardan en `supabase/migrations/0005_routine_favorites.sql`. La tabla mantiene una seleccion por evento, bloque, juez y tipo de favorito.

La app iPad funciona en modo local si no hay claves configuradas. Si `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` estan disponibles en el esquema de Xcode o en `Info.plist`, carga eventos desde Supabase y sincroniza puntajes/feedback/favoritos pendientes.

La tab `Excel` sube archivos a `excel_imports` como importaciones pendientes. Para habilitarla, corre tambien `supabase/migrations/0002_excel_imports.sql`. Luego procesa esas cargas con una key admin:

```bash
python3 scripts/process_excel_imports.py --allow-errors
```

## Android tablets

La base Flutter esta en `android_tablet_flutter`. En esta maquina no esta instalado Flutter, asi que primero completa los archivos host de Android en una maquina con Flutter:

```bash
cd android_tablet_flutter
flutter create . --platforms=android
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://bozkbpirrwjtpmjqcexx.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_jZv2loPhbPvameq6bUOgqA_5hEQJ2tc
```

## Funciones

- Bloques de coreografías desde Excel.
- Hojas de jueceo por juez, con jueces editables.
- Guardado local de puntajes y feedback en el iPad.
- Calificaciones por juez y promedio final.
- Dictamen final por género, división y categoría.
- Exportación y compartir PDF.
- Sincronización Supabase opcional con modo offline/pending.
- App Flutter para Android tablets conectada al mismo contrato de datos.
