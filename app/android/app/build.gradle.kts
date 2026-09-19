plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.threshold"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (FR-3.3 alerts) requires core library
        // desugaring for java.time APIs on older Android API levels.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.threshold"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Shrink the release build to cut APK/AAB size. R8 removes unused
            // code and resource shrinking strips unused resources. The native
            // plugins (flutter_webrtc, ML Kit, flutter_local_notifications,
            // flutter_tts) use JNI/reflection, so the keep rules in
            // proguard-rules.pro protect the classes R8 cannot see. See
            // docs/hackathon/APK_SIZE.md for measured before/after sizes.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by isCoreLibraryDesugaringEnabled above so flutter_local_notifications
    // can use java.time on older API levels (minSdk 26+, NFR-8).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
