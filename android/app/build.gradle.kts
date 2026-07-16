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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
