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
# Completa SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY.
python3 scripts/import_excel_to_app_data.py "/ruta/al/bloque.xlsx" --supabase --event-slug "bloque-2-2024" --event-name "Bloque 2 2024"
```

## Backend Supabase

La migracion inicial esta en `supabase/migrations/0001_initial_schema.sql`. Crea las tablas `events`, `routines`, `judges`, `criteria_templates`, `criteria`, `scores` y `feedback`.

La app iPad funciona en modo local si no hay claves configuradas. Si `SUPABASE_URL` y `SUPABASE_ANON_KEY` estan disponibles en el esquema de Xcode o en `Info.plist`, carga eventos desde Supabase y sincroniza puntajes/feedback pendientes.

## Android tablets

La base Flutter esta en `android_tablet_flutter`. En esta maquina no esta instalado Flutter, asi que primero completa los archivos host de Android en una maquina con Flutter:

```bash
cd android_tablet_flutter
flutter create . --platforms=android
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-public-key
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
