# Jueceo Coreografias Android Tablet

Companion Flutter app for Android tablets. It uses the same Supabase schema as the iPad app and keeps the same core workflow: event, judge, routines, score sheet, feedback, scores, dictamen and PDF share.

## First setup

Flutter is not installed in this workspace, so the generated Android host files are intentionally not committed here yet. On a machine with Flutter installed:

```bash
cd android_tablet_flutter
flutter create . --platforms=android
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://bozkbpirrwjtpmjqcexx.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_jZv2loPhbPvameq6bUOgqA_5hEQJ2tc
```

## Current parity surface

- Reads the active/shared Supabase event.
- Selects event and judge.
- Lists blocks/routines with search.
- Scores criteria and writes feedback.
- Stores local values with pending sync.
- Upserts scores/feedback to Supabase.
- Shows scores and dictamen with the same average/tie rules as iPad.
- Exports a basic results PDF from the tablet.
