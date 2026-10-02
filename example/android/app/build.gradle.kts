plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("livery")
}

android {
    namespace = "dev.livery.livery_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = LiveryConfig.APP_ID
        applicationIdSuffix = LiveryConfig.APP_ID_SUFFIX.ifEmpty { null }
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = LiveryConfig.VERSION_CODE
        versionName = flutter.versionName
        versionNameSuffix = LiveryConfig.BUILD_TAG?.let { "-$it" }
        manifestPlaceholders["appLabel"] = LiveryConfig.APP_NAME
    }

    buildTypes {
        release {
            isMinifyEnabled = LiveryConfig.MINIFY
            isShrinkResources = LiveryConfig.MINIFY
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
