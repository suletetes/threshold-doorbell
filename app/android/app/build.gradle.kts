import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is loaded from android/key.properties (gitignored) or, in CI,
// from the matching environment variables. There is deliberately NO debug-key
// fallback for release: a release build without a real upload key must fail loudly
// rather than ship an unpublishable, debug-signed APK (HIGH-12). See
// android/key.properties.example for the template.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun releaseSigningValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

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

    signingConfigs {
        create("release") {
            val storeFilePath = releaseSigningValue("storeFile", "THRESHOLD_KEYSTORE_FILE")
            val storePasswordValue = releaseSigningValue("storePassword", "THRESHOLD_KEYSTORE_PASSWORD")
            val keyAliasValue = releaseSigningValue("keyAlias", "THRESHOLD_KEY_ALIAS")
            val keyPasswordValue = releaseSigningValue("keyPassword", "THRESHOLD_KEY_PASSWORD")

            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Use the real release key. There is NO debug fallback: if the key is
            // missing, verifyReleaseSigning below fails the build before packaging
            // so an unpublishable debug-signed APK can never ship (HIGH-12).
            signingConfig = signingConfigs.getByName("release")

            // Shrink the release build to cut APK/AAB size. R8 removes unused
            // code and resource shrinking strips unused resources. The keep rules
            // in proguard-rules.pro are narrowed to the plugins that remain
            // (MED-19). See docs/hackathon/APK_SIZE.md for measured sizes.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Fail a release build loudly when the upload key is not configured, instead
    // of silently signing with the debug key (HIGH-12). A real keystore plus
    // android/key.properties (or the THRESHOLD_* CI env vars) is required to
    // produce a store-signable APK/AAB.
    afterEvaluate {
        tasks.matching { it.name.startsWith("package") && it.name.contains("Release") }
            .configureEach {
                doFirst {
                    val release = signingConfigs.getByName("release")
                    if (release.storeFile == null) {
                        throw GradleException(
                            "No release signing key configured. Create android/key.properties " +
                                "from android/key.properties.example (or set THRESHOLD_KEYSTORE_FILE, " +
                                "THRESHOLD_KEYSTORE_PASSWORD, THRESHOLD_KEY_ALIAS and THRESHOLD_KEY_PASSWORD " +
                                "in CI). Release builds must not fall back to the debug key.",
                        )
                    }
                }
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
