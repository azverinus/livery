---
name: livery-setup
description: Sets up and maintains livery, the build-time config tool for Flutter apps. Use when the user wants to create a livery.yaml, wire iOS and Android (xcconfig, Gradle) and Dart to generated config, or change an existing livery setup by adding a key, a define, a define value, an override or an app.
---

# livery setup and maintenance

livery reads one manifest, `livery.yaml`, and generates config files from it: an xcconfig for Xcode, a Kotlin object for Gradle build scripts and a Dart file for the app. The native projects refer to the generated values; livery never edits Xcode or Gradle files itself. You do that wiring once, by the recipes below.

Run it with `dart run livery`, passing the same defines as to Flutter: `dart run livery -D ENV=staging` goes with `flutter run --dart-define=ENV=staging`. `dart run livery --help` lists the options; `--dry-run` prints the files instead of writing them.

## Ground rules

- **Never invent values.** Read identity values from the project. Ask the user for anything you cannot read: the defines and their values, which values differ per environment, the team id when the project has none, the names of new apps. A placeholder like `com.example.app` in a manifest is a bug.
- **Never edit generated files.** Change `livery.yaml` (or its config files) and run livery again.
- **Run livery after every manifest change**, and fix what it reports before touching native files. It checks everything before writing anything, so a failing run leaves the old files in place.
- **Keep key names valid everywhere they go.** Keys in sections that reach the xcconfig must match `[A-Za-z_][A-Za-z0-9_]*`. Use UPPER_SNAKE with an `APP_` prefix, such as `APP_BUNDLE_ID`, so no key collides with one of Xcode's own build settings. The Kotlin object uses the same name; the Dart file turns it into lowerCamel, `AppConfig.appBundleId`.
- **Quote strings YAML would read as numbers**: `"1.10"`, `"007"`. A value's YAML type is its type in Kotlin and Dart, and an override cannot change it.

## Set up livery in a project

### 1. Check the project

It must be a Flutter app: `pubspec.yaml` depends on `flutter`, and there is `ios/`, `android/`, or both. Wire only the platforms that exist. If `android/app/build.gradle` (Groovy) exists instead of `build.gradle.kts`, stop and tell the user: the Android recipe here covers the Kotlin DSL only.

If `livery.yaml` already exists, this is maintenance, not setup; see the procedures further down.

### 2. Add the dev dependency

```sh
flutter pub add --dev livery
```

If the user names another source, use it instead: `flutter pub add 'dev:livery:{"path":"../livery"}'` for a path, `{"git":"<url>"}` for a git repository.

### 3. Collect the identity values

Read them; do not ask for what you can read.

| Value | Where | Key |
| --- | --- | --- |
| Android application id | `applicationId = "…"` in `android/app/build.gradle.kts` | `APP_ID` in `android` |
| iOS bundle identifier | `PRODUCT_BUNDLE_IDENTIFIER` of the Runner target in `ios/Runner.xcodeproj/project.pbxproj`, in its Debug, Release and Profile configurations | `APP_BUNDLE_ID` in `ios` |
| iOS team | `DEVELOPMENT_TEAM` of the same configurations | `APP_TEAM_ID` in `ios` |
| Display name | `CFBundleDisplayName` in `ios/Runner/Info.plist`, `android:label` in `android/app/src/main/AndroidManifest.xml` | `APP_NAME` in `common` |

- The Runner target's configurations are the `XCBuildConfiguration` blocks listed by the `XCConfigurationList` named `Build configuration list for PBXNativeTarget "Runner"`. If they disagree with each other, ask which value is meant.
- Leave `CFBundleName` in `Info.plist` alone: it is the short bundle name, not the name users see.
- Leave `namespace` in `build.gradle.kts` alone: it names the Kotlin package, not the app.
- With no `DEVELOPMENT_TEAM`, ask the user for the team id, or leave `APP_TEAM_ID` out and skip its wiring.
- `flutter create` gives Android the package name as its label (`my_app`) and iOS a title (`My App`). When the two differ, ask the user which name the app should have on both. If they want two names, put `APP_NAME` in `ios` and in `android` instead of `common`.

### 4. Ask for the defines

Ask the user which build inputs the app has, such as the environments (`ENV` with `dev`, `staging`, `production`) or a flavor, which values each accepts, and which is the default. Then ask which identity values differ by define value, such as a bundle identifier per environment, and what they are. A per-environment iOS bundle identifier is a whole value: `config` holds the one for the default define values, such as `com.acme.app.dev`, and overrides hold the others. Android has `applicationIdSuffix` for that, so its suffix gets a key of its own, `APP_ID_SUFFIX`. Do not assume an `ENV` define: a project may have none.

Define names are matched exactly as written, as `String.fromEnvironment` matches them, so use the names the user passes to `--dart-define`.

### 5. Draft `livery.yaml`

Put it next to `pubspec.yaml`. The shape, with values from a project the user answered for:

```yaml
# livery.yaml
version: 1

defines:
  ENV:
    values: [dev, staging, production]
    default: dev

config:
  common:
    APP_NAME: Acme Dev
  ios:
    APP_BUNDLE_ID: com.acme.app.dev
    APP_TEAM_ID: ABCDE12345
  android:
    APP_ID: com.acme.app
    APP_ID_SUFFIX: .dev

overrides:
  - when: {ENV: staging}
    set:
      common: {APP_NAME: Acme Staging}
      ios: {APP_BUNDLE_ID: com.acme.app.staging}
      android: {APP_ID_SUFFIX: .staging}
  - when: {ENV: production}
    set:
      common: {APP_NAME: Acme}
      ios: {APP_BUNDLE_ID: com.acme.app}
      android: {APP_ID_SUFFIX: ""}

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
    merge: [common]
    files: lib/src/app_config.g.dart
```

- `config` holds the values of the default define values; `overrides` hold what changes for others. An override can only set keys `config` already has, with the same type.
- Leave out `overrides`, `APP_ID_SUFFIX` and the `defines` the user did not ask for. With no per-environment values there are no overrides.
- Drop the output, and its section, of a platform the project does not have.
- The Dart output merges `common` only, and is gitignored with the other generated files, so a fresh clone analyzes only after livery has run. Add a `dart` section, and `dart` to its `merge`, once the app has Dart-only values such as an API URL.

Run `dart run livery --dry-run` and fix what it reports.

### 6. Wire iOS

1. Include the xcconfig at the end of every xcconfig the Runner target's configurations are based on: the files their `baseConfigurationReference` names. In a `flutter create` project those are `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig`, Profile using `Release.xcconfig`; flavored projects have more. Keep any `Pods` line above as it is:

   ```text
   #include "Generated.xcconfig"
   #include "livery.xcconfig"
   ```

   Keep it after `Generated.xcconfig`, so its values win. Use `#include`, not `#include?`: Xcode then warns when a fresh clone has not run livery yet, instead of building with empty values.

2. In `ios/Runner.xcodeproj/project.pbxproj`, in each of the Runner target's `XCBuildConfiguration` blocks (Debug, Release, Profile; found as in step 3), replace the values, quotes included:

   ```text
   PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_ID)";
   DEVELOPMENT_TEAM = "$(APP_TEAM_ID)";
   ```

   A value set on the target wins over the xcconfig, so this replacement is what makes the key take effect. Leave the `RunnerTests` blocks alone: that target does not include Flutter's xcconfig files. Without `APP_TEAM_ID`, leave `DEVELOPMENT_TEAM` as it is.

3. In `ios/Runner/Info.plist`:

   ```xml
   <key>CFBundleDisplayName</key>
   <string>$(APP_NAME)</string>
   ```

### 7. Wire Android

1. Add the livery build, two files that are written once and never change. `android/livery/build.gradle.kts`:

   ```kotlin
   plugins {
       `kotlin-dsl`
   }

   repositories {
       mavenCentral()
   }
   ```

   `android/livery/src/main/kotlin/livery.gradle.kts`: an empty file. It defines the plugin `livery`, which puts `LiveryConfig` on the app build script's classpath.

2. In `android/settings.gradle.kts`, inside `pluginManagement`, after Flutter's own `includeBuild`:

   ```kotlin
       includeBuild("livery")
   ```

3. In `android/app/build.gradle.kts`, add the plugin last in `plugins`:

   ```kotlin
       id("livery")
   ```

   and read the values in `defaultConfig`, replacing the literal `applicationId` and the `TODO` comment above it:

   ```kotlin
   applicationId = LiveryConfig.APP_ID
   applicationIdSuffix = LiveryConfig.APP_ID_SUFFIX.ifEmpty { null }
   manifestPlaceholders["appLabel"] = LiveryConfig.APP_NAME
   ```

   Drop the suffix line when the manifest has no `APP_ID_SUFFIX`. Leave `versionCode` and `versionName` reading `flutter.versionCode` and `flutter.versionName` unless the user moves them into livery.

4. In `android/app/src/main/AndroidManifest.xml`, on `<application>`:

   ```xml
   android:label="${appLabel}"
   ```

### 8. Update `.gitignore`

The generated files hold one environment's values, so they are not committed. Append to the project's `.gitignore`, for the outputs you added:

```gitignore
# Generated by livery: run `dart run livery` after a fresh clone.
ios/Flutter/livery.xcconfig
android/livery/src/main/kotlin/LiveryConfig.kt
android/livery/.gradle/
android/livery/.kotlin/
android/livery/build/
lib/src/app_config.g.dart
```

`Debug.xcconfig`, `Release.xcconfig`, `android/livery/build.gradle.kts` and the empty `livery.gradle.kts` stay committed.

### 9. Generate

```sh
dart run livery -v
```

livery prints nothing on success without `-v`; with it, it lists the resolved defines and every file written. A non-zero exit code is a failure, and the message names the problem.

Then run it once with `--dry-run -D <define>=<value>` for every other value of each define, and compare the printed values with what the user asked for.

### 10. Verify

Use the platform tools that exist on this machine; say which checks you could not run.

- **Android**, with the Android SDK and a JDK: `flutter build apk --debug`, then read `applicationId` from `build/app/outputs/apk/debug/output-metadata.json`. It must equal `APP_ID` plus the suffix of the default define values.
- **iOS**, on macOS with Xcode:

  ```sh
  flutter build ios --config-only
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -showBuildSettings
  ```

  `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` and `APP_NAME` in the output must hold the configured values. Repeat with `-configuration Debug` and `-configuration Profile`, so a block missed in step 6 shows up.
- If `lib/` uses the Dart file, `flutter analyze` must pass.

Finish by telling the user how to build from now on: run `dart run livery` with the same defines before every `flutter build` or `flutter run`, and after every fresh clone. In Xcode, after switching environments, **Product > Clean Build Folder** if old values stick.

## Maintain an existing setup

Read `livery.yaml` first. Its config may live in a `config_file`, or, for several apps, in one file per app named by `apps` or `app_pattern`; edit the files the config is in. After every change, run `dart run livery` and the matching check from step 10.

### Add a key

1. Ask for the value, and for its value under every define value where it differs.
2. Pick the section by who reads it: `common` for every platform and Dart, `ios`, `android`, or `dart` for Dart-only values (add the section to the `dart` output's `merge` if it is not there). Name it by the ground rules above.
3. Add it to `config`, with the value of the default define values. With several apps, add it to every app file with the same value type: every app must have the same keys.
4. Add the differing values to the matching overrides, or a new override.
5. Wire it, see below.

### Wire a key into native files

| Consumer | Recipe |
| --- | --- |
| iOS build setting | In the Runner target's Debug, Release and Profile blocks of `project.pbxproj`: `SETTING = "$(KEY)";`. |
| Info.plist or entitlements | `<string>$(KEY)</string>`, also in nested values such as `CFBundleURLTypes`. |
| Gradle build script | `LiveryConfig.KEY` in `android/app/build.gradle.kts`, typed: `Int` for `versionCode`, `Boolean` for `isMinifyEnabled`. |
| Android manifest | `manifestPlaceholders["name"] = LiveryConfig.KEY` in `defaultConfig`, `${name}` in the manifest. |
| Android app code | `buildConfigField("String", "KEY", "\"${LiveryConfig.KEY}\"")`, which needs `buildFeatures { buildConfig = true }`; or `resValue("string", "key", LiveryConfig.KEY)`, which needs `resValues = true`. |
| Dart | `AppConfig.keyInLowerCamel`, from `lib/src/app_config.g.dart`. |

An xcconfig key that is not defined is an empty string with no warning, so check the spelling on both sides. `android/settings.gradle.kts` cannot read `LiveryConfig`.

### Add a define

1. Ask for its name, its values (or none, for a free-form value such as a build tag), and its default or whether it is required.
2. Declare it under `defines`:

   ```yaml
   defines:
     FLAVOR:
       values: [free, paid]
       default: free
     BUILD_TAG:
   ```

3. It now appears in the Kotlin object and the Dart file: `LiveryConfig.FLAVOR` and `FlavorDefine.current` for a define with `values`, `LiveryConfig.BUILD_TAG` and `AppConfig.buildTag` for a free-form one. In Kotlin a define with neither `default` nor `required` is nullable, such as `String?`. Use it where the user wants it.
4. Tell the user to pass it to both tools: `dart run livery -D FLAVOR=paid` and `flutter build … --dart-define=FLAVOR=paid`, including in CI.

### Add a define value

1. Add it to the define's `values`.
2. Ask which config values differ for it, and add an override, or add it to an existing selector list, such as `when: {ENV: [staging, qa]}`.
3. If the define selects the app, see "Add an app".
4. Run livery with `-D NAME=<new value>`.

### Add an override

```yaml
overrides:
  - when: {ENV: production, FLAVOR: paid}
    set:
      android: {APP_ID_SUFFIX: .paid}
```

- `when` names declared defines and their declared values. A list matches any of its values; several defines must all match. Quote values YAML reads as numbers or booleans.
- `set` is keyed by section, like `config`, and may only set existing keys with their existing value types.
- All matching overrides apply in list order, so a later one wins. Put the specific ones after the general ones.

### Add an app

Several apps from one codebase are selected by a define, `APP` by default.

**From one app to several**, once:

1. Ask for the app names. Move `config` and `overrides` from the manifest into `config/apps/<first app>.yaml`, unchanged.
2. In the manifest, declare the app define and point at the files:

   ```yaml
   defines:
     APP:
       values: [demo, kiosk]
       required: true

   app_pattern: config/apps/{APP}.yaml
   ```

**Adding an app:**

1. Add its name to the app define's `values`.
2. Copy the first app's file to `config/apps/<new app>.yaml` and ask the user for every value in it. Keep every key and value type; livery fails when apps differ in shape. The first value of the app define is the reference shape, so add new apps after it.
3. Run livery with `-D APP=<new app>`, and once for every other app with `--dry-run`.

The native wiring stays the same for every app: it refers to keys, and every app has the same keys.
