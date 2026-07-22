import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load the upload keystore config from android/key.properties when present.
// The file is gitignored and reconstructed in CI from secrets (see
// docs/dev/releasing.md). When it is absent (contributors, CI debug builds,
// `flutter build apk --release` without a keystore) the release signing config
// is left unset and any attempt to actually assemble a release artifact fails
// loudly (see the release-task guard below) — we deliberately do NOT fall back
// to debug signing, so a local release build can never silently ship debug-signed.
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
        // it stays empty and unused, and buildTypes.release below leaves signing
        // unset so a release build without a keystore fails loudly (see the
        // release-task guard) rather than falling back to debug signing.
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
            // key.properties (contributors who set one up, and CI). When it is
            // absent we intentionally leave the release signing config unset
            // instead of falling back to the debug keys: a release build with no
            // keystore must fail, not silently produce a debug-signed "release".
            // The failure itself is raised by the release-task guard below so
            // that debug builds and `flutter test` — which never run release
            // packaging tasks — remain completely unaffected.
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

// Fail loudly when a release artifact is actually being assembled without a
// release signing config. We attach a `doFirst` guard to the release
// packaging/assemble/bundle tasks (via the lazy `configureEach`) rather than
// using `gradle.taskGraph.whenReady`, because throwing from `whenReady` is not a
// reliable way to fail a build on modern Gradle. This means:
//   * the guard fires only when a matching *Release packaging task actually
//     executes, so debug builds (`flutter run`, `flutter build apk --debug`)
//     and `flutter test` (pure Dart, never runs Gradle) are unaffected;
//   * it is never even registered when a keystore is present, so CI — which
//     reconstructs key.properties from secrets — is not impacted;
//   * nothing is thrown at configuration time.
// Only a release build WITHOUT a keystore trips the exception, and it aborts
// before the artifact is packaged/signed.
if (!hasKeystore) {
    tasks.configureEach {
        val isReleaseArtifactTask = name.contains("Release") &&
            (name.startsWith("package") ||
                name.startsWith("assemble") ||
                name.startsWith("bundle"))
        if (isReleaseArtifactTask) {
            doFirst {
                throw GradleException(
                    "Refusing to build an Android release without a release signing " +
                        "config: app/android/key.properties was not found. A release " +
                        "must be signed with the upload keystore, not the debug key. " +
                        "Copy app/android/key.properties.example to " +
                        "app/android/key.properties and fill in the real values (see " +
                        "docs/dev/releasing.md), then rebuild. Debug builds and " +
                        "`flutter test` do not require a keystore.",
                )
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
