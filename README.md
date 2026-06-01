# Jueceo Coreografias

App nativa de iPad creada en Xcode/SwiftUI a partir del Excel original.

## Abrir en Xcode

Abre `JueceoCoreografias.xcodeproj`, elige un simulador o iPad físico y ejecuta el esquema `JueceoCoreografias`.

## Arquitectura multi competencia

El dominio compartido vive en el package local `Packages/JueceoCore`. Ahi estan los modelos base (`Routine`, `DanceBlock`, `JudgingTemplate`, resultados, favoritos, premios, errores y helpers de ids) y `CompetitionBranding`, que define parametros reutilizables por competencia.

La app actual es el shell de marca Levitate. `JueceoCoreografias/AppBrand.swift` selecciona `CompetitionBranding.levitate`, y la UI/servicios leen de esa config para logo, nombre visible, hero fallback, carpeta de Drive, jueces admin por bloque y paleta de colores. Tambien hay dos brands de ejemplo listos para usar: `CompetitionBranding.auroraCircuit` y `CompetitionBranding.prismaOpen`.

Las paletas quedan separadas por competencia:

- `Levitate`: magenta/rosa, la identidad original.
- `Aurora Circuit`: teal/cian con verdes frios.
- `Prisma Open`: violeta con acento ambar.

Para otro brand, el camino esperado es crear otro target/app shell que consuma `JueceoCore` y apunte `AppBrand.competition` a otra configuracion.

## macOS para descarga directa

El proyecto tambien compila como app de macOS usando Mac Catalyst. En Xcode elegi el esquema `JueceoCoreografias` y el destino `My Mac (Mac Catalyst)`.

Build local:

```bash
xcodebuild \
  -project JueceoCoreografias.xcodeproj \
  -scheme JueceoCoreografias \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Release \
  build
```

Para publicar por descarga directa, genera un archive de Mac Catalyst, exportalo firmado con Developer ID, notarizalo y empaquetalo como `.dmg`:

```bash
xcodebuild archive \
  -project JueceoCoreografias.xcodeproj \
  -scheme JueceoCoreografias \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -archivePath build/JueceoCoreografias-macOS.xcarchive
```

La distribucion publica fuera del Mac App Store requiere certificado `Developer ID Application` y notarizacion de Apple antes de subir el `.dmg` a la web.

### Versionado iOS/macOS

Apple usa dos valores para identificar cada build:

- `MARKETING_VERSION`: version visible, por ejemplo `1.0.4`.
- `CURRENT_PROJECT_VERSION`: build interno, siempre incremental, por ejemplo `5`.

El archivo `apple_version.txt` mantiene el valor actual en formato `version+build`. Para verlo:

```bash
python3 scripts/set_apple_version.py
```

Para preparar un nuevo build sin cambiar la version visible:

```bash
python3 scripts/set_apple_version.py --bump-build
```

Para una nueva version patch y build nuevo:

```bash
python3 scripts/set_apple_version.py --bump-patch
```

Para fijar una version especifica:

```bash
python3 scripts/set_apple_version.py 1.0.4+5
```

## Cargar otro Excel local

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

## Importar Excel desde la app

La pestaña `Importar Excel` ya no deja el archivo en cola. La app llama a la Edge Function `import-excel`, la Function procesa el `.xlsx` en Supabase con permisos admin y devuelve el evento creado para que la Home lo refresque al momento.

Para habilitarlo en Supabase:

```bash
supabase login
supabase link --project-ref bozkbpirrwjtpmjqcexx
supabase secrets set IMPORT_SECRET="levitate2026"
supabase functions deploy import-excel
supabase functions deploy upsert-judge
supabase functions deploy update-routine
```

La app pide esa `IMPORT_SECRET` como `Clave de importación`; para esta instalacion la clave es `levitate2026`. Solo aparece la seccion a usuarios admin de la app, y la Function vuelve a validar la clave antes de escribir en `events`, `blocks`, `routines`, `judges` y `criteria`. No pongas la service role key dentro de la app.

El flujo legacy sigue disponible para cargas manuales: `scripts/process_excel_imports.py` procesa filas pendientes de `excel_imports`, pero ya no es el camino principal desde la app.

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

Los favoritos de vestuario/coreografia/musica se migran con `supabase/migrations/0014_routine_favorite_votes.sql`. La tabla nueva mantiene votos por evento, bloque, coreografia, juez y tipo de favorito, permitiendo mas de una favorita por categoria dentro del mismo bloque.

Las penalizaciones por rutina y juez se guardan en `supabase/migrations/0006_routine_penalties.sql` y se aplican al total final.

La columna `participant` para guardar el/la participante del programa esta en `supabase/migrations/0007_routine_participants.sql`.

La app iPad funciona en modo local si no hay claves configuradas. Si `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` estan disponibles en el esquema de Xcode o en `Info.plist`, carga eventos desde Supabase y sincroniza puntajes/feedback/penalizaciones/favoritos pendientes.

La importacion directa desde la app requiere la Edge Function `supabase/functions/import-excel`, `supabase/config.toml` desplegado con `verify_jwt = false`, y el secreto `IMPORT_SECRET` configurado en Supabase.

Para Excels que son solo programa (bloques/rutinas sin hojas de jueceo), el importador completa plantillas desde `JueceoCoreografias/Resources/Bloque2.xlsx` por defecto. Se puede cambiar con `--template-source`.

## Exportar a Google Drive

El panel `Admin` incluye `Exportar Drive`. La app inicia sesion con Google, crea la carpeta `FEEDBACK LEVITATE MX`, luego una subcarpeta del bloque, subcarpetas por academia y una carpeta por coreografia. Dentro de cada coreografia sube una hoja de jueceo PDF por juez; `PENALIZACION` se lee desde Supabase/local y se resta del total.

Para habilitarlo:

1. En Google Cloud habilita Google Drive API.
2. Crea un OAuth Client tipo iOS con bundle id `com.goldencrowvs.jueceolevitate`.
3. En Xcode reemplaza los build settings `GOOGLE_CLIENT_ID` y `GOOGLE_REVERSED_CLIENT_ID` con los valores de Google.
4. Si el OAuth consent screen esta en testing, agrega la cuenta que usara la app como test user.

## Funciones

- Bloques de coreografías desde Excel.
- Hojas de jueceo por juez, con jueces editables.
- Guardado local de puntajes y feedback en el iPad.
- Calificaciones por juez y promedio final.
- Dictamen final por género, división y categoría.
- Exportación y compartir PDF.
- Sincronización Supabase opcional con modo offline/pending.
