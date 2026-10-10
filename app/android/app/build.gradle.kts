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
    namespace = "dev.suletetes.threshold"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Core library desugaring is kept on so the deferred flutter_local_notifications
        // adapter (FR-3.3 alerts) can use java.time on API 26 without churn when it is
        // re-added. It is harmless with no desugared consumer today (LOW-16).
        isCoreLibraryDesugaringEnabled = true
    }

    // KGP 2.2.x deprecates kotlinOptions in favour of the compilerOptions DSL (LOW-15).
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        // Real reverse-DNS application id (HIGH-14). com.example is blocked by Play
        // and is permanent once published.
        applicationId = "dev.suletetes.threshold"
        // minSdk is pinned to 26 explicitly to match NFR-8 and the spec: notification
        // channels and several APIs the product relies on only exist from API 26, and
        // nobody has tested API 24/25 (MED-16).
        minSdk = 26
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
    // produce a store-signable APK/AAB. The keystore presence is captured here at
    // configuration time (not via Task.project at execution) so this stays
    // configuration-cache compatible for Gradle 9+ (MED-20).
    val releaseKeyConfigured = releaseSigningValue("storeFile", "THRESHOLD_KEYSTORE_FILE") != null
    tasks.matching { it.name.startsWith("package") && it.name.contains("Release") }
        .configureEach {
            doFirst {
                if (!releaseKeyConfigured) {
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

flutter {
    source = "../.."
}

dependencies {
    // Backs isCoreLibraryDesugaringEnabled above (LOW-16). Bumped to a current
    // release; re-pin alongside flutter_local_notifications when that adapter lands.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
