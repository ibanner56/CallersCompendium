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
// loudly (see the task-graph guard below) — we deliberately do NOT fall back to
// debug signing, so a local release build can never silently ship debug-signed.
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
        // task-graph guard) rather than falling back to debug signing.
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
            // The failure itself is raised by the task-graph guard below so that
            // debug builds and `flutter test` — which never schedule release
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
// release signing config. This is gated on the resolved task graph (evaluated
// only when tasks are about to run, never at configuration time) so that:
//   * debug builds (`flutter run`, `flutter build apk --debug`) still work,
//   * `flutter test` — which runs the Dart VM and never invokes Gradle — is
//     unaffected,
//   * CI, which reconstructs key.properties from secrets, is never impacted
//     (hasKeystore is true there, so this guard is not even registered).
// Only a release build WITHOUT a keystore trips the exception.
if (!hasKeystore) {
    gradle.taskGraph.whenReady { graph ->
        val assemblingRelease = graph.allTasks.any { task ->
            val name = task.name
            name.contains("Release") &&
                (name.startsWith("package") ||
                    name.startsWith("assemble") ||
                    name.startsWith("bundle"))
        }
        if (assemblingRelease) {
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
