import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load the upload keystore config from android/key.properties when present.
// The file is gitignored and reconstructed in CI from secrets (see
// docs/dev/releasing.md). When it is absent (contributors, CI debug builds,
// `flutter build apk --release` without a keystore) we fall back to the debug
// signing config below, so nothing breaks.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "org.callerscompendium.compendiumApp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.callerscompendium.compendiumApp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only populate the release config when key.properties exists; otherwise
        // it stays empty and unused (buildTypes.release falls back to debug below).
        create("release") {
            if (hasKeystore) {
                // Fail loudly with a clear message if a required field is missing,
                // and resolve a relative storeFile from android/ (rootProject) so it
                // sits next to key.properties, matching key.properties.example.
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("keyAlias missing from key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("keyPassword missing from key.properties")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
                    ?: error("storeFile missing from key.properties")
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("storePassword missing from key.properties")
            }
        }
    }

    buildTypes {
        release {
            // Use the release signing config when a keystore is configured via
            // key.properties; otherwise sign with the debug keys so
            // `flutter run --release` and CI builds keep working without secrets.
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
