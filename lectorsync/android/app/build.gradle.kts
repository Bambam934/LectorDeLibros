import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing properties if present. Falls back to debug signing
// for development. See ../key.properties (gitignored — do not commit).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.lectorsync.lectorsync"
    // compileSdk y targetSdk van por separado a propósito.
    //
    // compileSdk solo dice contra qué APIs se compila; subirlo no cambia
    // ningún comportamiento en tiempo de ejecución. Está en 36 porque pdfrx
    // arrastra androidx.core:core:1.17.0, que se niega a compilar contra
    // menos de 36.
    //
    // targetSdk sí cambia el comportamiento y es lo que miran los
    // instaladores: sigue clavado en 34 (ver defaultConfig) porque
    // instaladores como Motorola Secure rechazan APKs cuyo target es más
    // nuevo que el Android del dispositivo.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.lectorsync.lectorsync"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                // Multi-scheme signing: v1 (JAR) + v2 + v3 covers every Android
                // installer, including OEM ones (Motorola, Xiaomi) that still
                // require the legacy v1 signature for sideload.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Solo arquitecturas ARM para release; x86_64 solo se usa en
            // emuladores y excluirlo ahorra unos 27 MiB en el APK final.
            ndk {
                abiFilters.clear()
                abiFilters += listOf("armeabi-v7a", "arm64-v8a")
            }
        }
    }
}

flutter {
    source = "../.."
}
