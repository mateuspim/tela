import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real signing keys, if this machine has them. `android/key.properties` is
// gitignored (along with *.jks) because a keystore in a repo is a keystore
// everyone has. Absent, the release build falls back to the debug key and says
// so — see the `release` build type below.
//
// To sign for real, create the keystore and point this file at it:
//
//   keytool -genkey -v -keystore ~/tela-release.jks -keyalg RSA \
//     -keysize 2048 -validity 10000 -alias tela
//
//   # android/key.properties
//   storeFile=/home/you/tela-release.jks
//   storePassword=…
//   keyAlias=tela
//   keyPassword=…
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "cc.pym.tela"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cc.pym.tela"
        // Pinned to 29, not flutter.minSdkVersion: below API 29 there is no scoped
        // storage, so the sharedGallery and filesOutsideGallery tiers would need
        // WRITE_EXTERNAL_STORAGE plus a legacy write path inside the one adapter
        // that enforces the NSFW non-indexing rule. One path, no permission. PLAN.md §5.3.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "edition"
    productFlavors {
        create("play") {
            dimension = "edition"
            applicationId = "cc.pym.tela.play"
            resValue("string", "app_name", "tela")
        }
        create("wallhaven") {
            dimension = "edition"
            applicationId = "cc.pym.tela.wallhaven"
            resValue("string", "app_name", "tela Wallhaven")
        }
        create("safe") {
            dimension = "edition"
            applicationId = "cc.pym.tela.safe"
            resValue("string", "app_name", "tela Safe")
        }
        create("full") {
            dimension = "edition"
            // Preserve update compatibility with the existing owner build.
            applicationId = "cc.pym.tela"
            resValue("string", "app_name", "tela Full")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")

                // v3 is off by default in AGP, and it is the one that matters
                // here: it carries a signing-certificate *lineage*, which is
                // the only way to move this app to a new key without asking
                // every user to uninstall — the exact wall this project hit on
                // 2026-08-11, when the debug key that had signed the tablet's
                // build was lost with a Docker volume and the update was
                // refused with INSTALL_FAILED_UPDATE_INCOMPATIBLE.
                //
                // It cannot rescue a key that is already gone (rotation is
                // authorised by signing with the *old* key), so it buys nothing
                // retroactively. It is here so the next key change is an
                // update rather than a reinstall.
                //
                // What the built APK actually carries, measured with
                // `apksigner verify -v`: **v3 only**. Asking for v2 as well is
                // a no-op at minSdk 29 — v3 supersedes it from API 28, so AGP
                // emits one block rather than both, and every device this app
                // runs on verifies it. v1 (JAR signing) is only needed below
                // API 24. v4 is for incremental ADB install and needs a
                // matching .idsig beside the APK, which `make deploy` does not
                // carry.
                enableV3Signing = true
            }
        }
    }

    // Robolectric needs the packaged resources and a real manifest to stand up a
    // Context; without this every test that touches one fails at construction.
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    buildTypes {
        release {
            // The real key when this machine has one, the debug key otherwise so
            // `flutter run --release` and a size measurement still work on a
            // fresh clone. A debug-signed APK cannot be shipped: Play refuses it,
            // and it shares the signature of every other debug build — so the
            // fallback announces itself rather than passing for the real thing.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "tela: no android/key.properties — signing the release build " +
                        "with the DEBUG key. Not shippable; see build.gradle.kts."
                )
                signingConfigs.getByName("debug")
            }

            // R8 and resource shrinking. Without these the release APK was ~62MB,
            // roughly 3x a normal Flutter release, because nothing was stripping
            // unused classes or resources. Shrinking resources requires code
            // shrinking, so the two travel together.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// `isIncludeAndroidResources` above makes the unit-test task package the merged
// assets — a directory Flutter's own `copyFlutterAssets<Variant>` also writes.
// Gradle sees two tasks on one output with no ordering between them and refuses
// the build outright, so this is not optional polish: without it there is no
// Kotlin suite at all under the Flutter Gradle plugin. Declaring the dependency
// is the first of the three fixes Gradle itself suggests.
tasks.matching { it.name.endsWith("UnitTestForUnitTest") }.configureEach {
    val variant = name.removePrefix("package").removeSuffix("UnitTestForUnitTest")
    dependsOn("copyFlutterAssets$variant")
}

// The native half of tela was verifiable only by hand on a device until this
// landed. These are JVM unit tests (`src/test`), not `androidTest`: they run in
// the toolchain container with no emulator and no phone, which is what makes
// them cheap enough to actually run. Robolectric supplies the Android
// framework classes the storage tiers are built out of.
//
// Run them with `make kotlin-test`. `flutter test` does NOT reach these — it
// runs the Dart suite only, so both commands are needed before a commit.
dependencies {
    // Auto-rotate. The platform's own scheduler, and the one PLAN.md names:
    // it survives reboots and doze, which an AlarmManager loop does not
    // without re-implementing both by hand.
    implementation("androidx.work:work-runtime-ktx:2.10.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.test:core:1.7.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
