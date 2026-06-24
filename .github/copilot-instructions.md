# Copilot Instructions for chef_kart

## Project Overview
- **chef_kart** is a Flutter application integrating Firebase services (Auth, Firestore, Storage).
- The codebase follows standard Flutter/Dart conventions, with main logic in `lib/` and platform-specific code in `android/`, `ios/`, `web/`, `windows/`, `macos/`, and `linux/`.

## Architecture & Key Patterns
- **Entry Point:** `lib/main.dart` initializes the app and Firebase.
- **Feature Organization:**
  - `lib/models/`: Data models.
  - `lib/services/`: Business logic and Firebase interactions.
  - `lib/screens/`: UI screens/pages.
  - `lib/widgets/`: Reusable UI components.
- **Firebase Integration:**
  - Credentials/config: `lib/firebase_options.dart`, `android/app/google-services.json`.
  - Rules: `firestore.rules`, `firestore.indexes.json`.

## Developer Workflows
- **Build:**
  - Run: `flutter run` (auto-detects platform)
  - Android: `flutter build apk`
  - iOS: `flutter build ios`
  - Web: `flutter build web`
- **Test:**
  - Unit/widget tests in `test/` (e.g., `test/widget_test.dart`)
  - Run: `flutter test`
- **Firebase Emulators:**
  - Use `firebase.json` for local emulator config.
- **Debugging:**
  - Use Flutter DevTools (`flutter pub global activate devtools` then `flutter pub global run devtools`)

## Conventions & Patterns
- **State Management:**
  - No explicit state management package detected; likely using basic Flutter state or Provider.
- **Naming:**
  - Files and classes use lower_snake_case and UpperCamelCase respectively.
- **Navigation:**
  - Standard Flutter `Navigator` for screen transitions.
- **Localization:**
  - Uses `intl` package for internationalization.

## Integration Points
- **Firebase:**
  - Auth, Firestore, Storage via respective packages in `pubspec.yaml`.
- **Platform Assets:**
  - Android: `android/app/google-services.json`
  - iOS: `ios/Runner/` and `ios/Flutter/`
  - Web: `web/`

## Examples
- **Adding a new screen:**
  - Create in `lib/screens/`, update navigation in `main.dart` or relevant parent screen.
- **Adding a service:**
  - Place in `lib/services/`, inject/use in screens/widgets as needed.

## References
- `pubspec.yaml`: Dependency management.
- `README.md`: Basic project info.
- `lib/main.dart`: App entry and setup.
- `lib/services/`, `lib/models/`, `lib/screens/`, `lib/widgets/`: Main code structure.

---

_If any conventions or workflows are unclear, please ask for clarification or provide examples from the codebase to improve these instructions._
