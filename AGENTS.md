# Repository Guidelines
## Project Structure & Module Organization
lib/main.dart boots the app and loads firebase_options.dart. Feature code lives in lib/src: data/models and data/repositories hold domain logic, services integrate Firebase, and pages/ui/widgets deliver presentation.
Theme tokens live in lib/src/theme, while dialogs and the app shell stay in their respective folders. Store imagery in assets/ and register it in pubspec.yaml; keep platform glue in android/ and ios/ and exclude build/ from git.

## Build, Test & Development Commands
Run `flutter pub get` after dependency updates and `flutter analyze` before pushing. Use `flutter test` for unit and widget coverage; add `--coverage` for CI parity.
Manual smoke tests run with `flutter run -d chrome` or `flutter run -d ios`/`-d android`. Codemagic handles release builds; if you must ship locally, mirror the pipeline with `flutter build ipa` or `flutter build apk` plus signing assets from secure storage.

## Coding Style & Naming Conventions
Follow analysis_options.yaml defaults: two-space indentation, trailing commas, camelCase members, UpperCamelCase types.
Keep each shared widget in a file named after the widget (example: invoice_overview.dart). Run `dart format lib test` and fix analyzer warnings instead of suppressing them. Limit UI files to view logic and route Firebase work through repositories or services.

## Testing Guidelines
Place tests under test/ and name them `_test.dart`. Prefer golden or widget tests for UI and repository unit tests with Firebase fakes.
Start bug fixes with a regression test. CI runs `flutter test --coverage`; keep new code at least on par with nearby coverage and explain gaps in the PR.

## Commit & Pull Request Guidelines
Write imperative commit subjects (see `git log` entries like 'Fix PKCS#12 import') and stay under roughly 70 characters.
Squash work-in-progress commits before review. PRs need a punchy summary, linked issue or ticket, UI screenshots when relevant, and a checklist of `flutter analyze` and `flutter test`. Request review from the data, services, or UI owner you touched.

## Security & Configuration Tips
Firebase config is generated in firebase_options.dart; rerun `flutterfire configure` instead of editing by hand.
Keep secrets and provisioning material out of git -- store them in environment variables or Codemagic secure groups. Document any new setup steps in README.md or AGENTS.md before merging.
