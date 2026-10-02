# livery example

A Flutter app whose iOS, Android and Dart sides read the config that livery generates from one manifest. An `ENV` define picks the environment, overrides change the values per environment, and three outputs write an xcconfig, a Kotlin object for Gradle and a Dart file:

```yaml
# livery.yaml
version: 1

defines:
  ENV:
    values: [dev, staging, production]
    default: dev
  BUILD_TAG:

config:
  common:
    APP_NAME: Livery Dev
  ios:
    APP_BUNDLE_ID: dev.livery.example.dev
  android:
    APP_ID: dev.livery.example
    APP_ID_SUFFIX: .dev
    VERSION_CODE: 3
    MINIFY: false
  dart:
    api:
      url: https://dev.api.example.com
      timeout_seconds: 30

overrides:
  - when: {ENV: staging}
    set:
      common: {APP_NAME: Livery Staging}
      ios: {APP_BUNDLE_ID: dev.livery.example.staging}
      android: {APP_ID_SUFFIX: .staging}
      dart: {api: {url: https://staging.api.example.com}}
  - when: {ENV: production}
    set:
      common: {APP_NAME: Livery}
      ios: {APP_BUNDLE_ID: dev.livery.example}
      android: {APP_ID_SUFFIX: "", MINIFY: true}
      dart: {api: {url: https://api.example.com, timeout_seconds: 10}}

outputs:
  ios:
    format: xcconfig
    merge: [common, ios]
    files: ios/Flutter/livery.xcconfig
  android:
    format: kotlin
    merge: [common, android]
    files: android/livery/src/main/kotlin/LiveryConfig.kt
  dart:
    format: dart
    merge: [common, dart]
    files: lib/src/app_config.g.dart
```

The app is wired as the guides describe:

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
