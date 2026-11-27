import java.net.URI

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun apiUrl(value: String, development: Boolean): String {
    val base = value.trim().trimEnd('/')
    if (base.isNotEmpty()) {
        val uri = URI(base)
        val emulator = development && uri.scheme == "http" &&
            uri.host in listOf("10.0.2.2", "127.0.0.1", "localhost")
        require((uri.scheme == "https" || emulator) && uri.host != null &&
            uri.userInfo == null && uri.rawQuery == null && uri.rawFragment == null) {
            "Transit API must be an HTTPS base URL, or an emulator address for debug."
        }
    }
    return '"' + base + '"'
}

val liveApi = providers.gradleProperty("TRANSIT_API_URL")
    .orElse(providers.environmentVariable("TRANSIT_API_URL")).getOrElse("")
val debugApi = providers.gradleProperty("TRANSIT_DEBUG_API_URL")
    .orElse(providers.environmentVariable("TRANSIT_DEBUG_API_URL")).getOrElse(liveApi)

android {
    namespace = "com.example.smart_public_transportation"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.smart_public_transportation"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "TRANSIT_API_URL", apiUrl(liveApi, false))
    }

    buildTypes {
        debug {
            buildConfigField("String", "TRANSIT_API_URL", apiUrl(debugApi, true))
        }
        release {
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
