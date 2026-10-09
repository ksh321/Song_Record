plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ksh321.songrecord"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.ksh321.songrecord"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["kakaoScheme"] = "kakao-unconfigured"
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            manifestPlaceholders["kakaoScheme"] = "kakao710c5008600b80c7d0cb8010e8f031d6"
            resValue("string", "app_name", "노래기록 DEV")
        }
        // Dedicated local-only verification app: never replaces dev user data.
        create("verification") {
            dimension = "environment"
            applicationIdSuffix = ".verification"
            resValue("string", "app_name", "노래기록 동기화 검증")
        }
        // Separate identity preserves older verification signatures and data.
        create("preservation") {
            dimension = "environment"
            applicationIdSuffix = ".preservation"
            resValue("string", "app_name", "노래기록 보존 검증")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "노래기록 STAGING")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "노래기록")
        }
    }

    buildTypes {
        release {
            // P24 배포 준비에서 운영 서명 설정으로 교체한다.
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

// Match the versions already used by google_sign_in_android 7.2.17.
dependencies {
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.2.0")
}
