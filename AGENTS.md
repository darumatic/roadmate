# Repository Guidelines

## Project Structure & Module Organization

RoadMate is a Flutter app with Firebase-backed data. Main application code lives in `lib/`: `features/` contains screens, `widgets/` reusable UI, `models/` data types, `services/` repositories/providers/startup logic, and `router.dart` navigation. Tests live in `test/`, grouped by feature or service behavior. Static seed data is in `sites/nhvr_national_inspection_sites.json`. Web shell files are in `web/`; Android and iOS platform projects are in `android/` and `ios/`. Firebase Hosting, Firestore rules, and indexes are configured by `firebase.json`, `firestore.rules`, and `firestore.indexes.json`.

## Build, Test, and Development Commands

- `flutter pub get` installs dependencies.
- `flutter run -d chrome` runs the web app locally.
- `flutter analyze` runs Dart/Flutter static analysis.
- `flutter test` runs the full test suite.
- `flutter test test/feature_screens_test.dart` runs focused widget coverage.
- `flutter build web` creates `build/web` for Firebase Hosting.
- `firebase deploy --only hosting --project roadmate-b1551` deploys the web build.
- Android release bundles are built from `android/` with `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:bundleRelease`.

## Coding Style & Naming Conventions

Use Dart defaults from `package:flutter_lints/flutter.yaml`; format with `dart format`. Prefer two-space indentation, `UpperCamelCase` for classes/widgets, `lowerCamelCase` for methods and variables, and `snake_case.dart` filenames. Keep screen-specific code under `lib/features/<feature>/`; shared UI belongs in `lib/widgets/`, and shared logic in `lib/services/`.

## Testing Guidelines

Use `flutter_test` for unit and widget tests. Name test files by subject, such as `status_logic_test.dart` or `feature_screens_test.dart`. Add focused tests for route changes, form behavior, repository logic, and status calculations. Firestore emulator tests are skipped by default; run them only with `FIREBASE_EMULATOR_TESTS=true` and active Firebase emulators.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries, for example `Enable Firebase Analytics tracking` and `Add site action to state pages`. Keep commits scoped and include tests with behavior changes. Pull requests should describe the change, list verification commands, mention Firebase/Play deployment impact, and include screenshots for visible UI updates.

## Security & Configuration Tips

Never commit signing keys, service account JSON, `android/key.properties`, or generated secret history files. Keep Firebase project identifiers consistent with `roadmate-b1551`. When changing analytics, auth, Firestore, or release signing, verify both web build and relevant platform behavior before deployment.

## Ask for questions


## Dev Cycle

When requirements are not clear, ask questions first. Write pending tasks in a simple list in "AGENT-TODO.MD" 

After implementing changes, test them with the available tests and then commit and push the code. Verify the results of the Github checks as well. After all of that is successful, the task is done. If there is any issue, please retry.

Anything you learn about the business rules and business logic must be written and kept-updated in specs.md
