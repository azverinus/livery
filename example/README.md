# livery example

A Flutter app whose iOS, Android and Dart sides read the config that livery generates from [`livery.yaml`](livery.yaml), wired as the guides describe:

- **iOS**, per the [iOS guide](../doc/ios.md): `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` include `livery.xcconfig`, the Runner target's bundle identifier is `$(APP_BUNDLE_ID)`, and `Info.plist` takes its display name from `$(APP_NAME)`.
- **Android**, per the [Android guide](../doc/android.md): the livery build in `android/livery/`, included from `android/settings.gradle.kts`, and `android/app/build.gradle.kts` reading `LiveryConfig` for the application id and its suffix, the version code, the release build's minification and the app label.
- **Dart**, per the [Dart guide](../doc/dart.md): `lib/main.dart` shows the values of `lib/src/app_config.g.dart`.

The generated files are gitignored, so run livery once before building:

```sh
flutter pub get
dart run livery -D ENV=staging
flutter run --dart-define=ENV=staging
```

[`multi_app/`](multi_app/) holds a manifest for two apps that share this codebase and one schema, each with its own config file.
