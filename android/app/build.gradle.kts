plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rikai.mobile"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.rikai.mobile"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        // Product-facing version for the 1.1 release; keep the build number
        // from pubspec (1.1.0+2) as versionCode.
        versionName = "1.1"
    }

    packaging {
        jniLibs {
            // ONNX Runtime and MeCab native assets may both provide libc++_shared.
            pickFirsts += setOf("**/libc++_shared.so")
        }
    }

    buildTypes {
        release {
            // TODO: replace with a real release keystore before distribution.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
