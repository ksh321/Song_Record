import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Private properties are created only for a local release build, never committed.
val releasePropertiesPath = providers.environmentVariable("SONGRECORD_SIGNING_PROPERTIES").orNull
val releaseProperties = Properties()
if (releasePropertiesPath != null) {
    val source = file(releasePropertiesPath)
    require(source.isFile) { "Song_Record release signing configuration is unavailable" }
    source.inputStream().use { releaseProperties.load(it) }
    require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        !releaseProperties.getProperty(it).isNullOrBlank()
    }) { "Song_Record release signing configuration is incomplete" }
    require(file(releaseProperties.getProperty("storeFile")).isFile) {
        "Song_Record release keystore is unavailable"
    }
}

// Flutter supplies the same public SDK setting to Dart and the Android callback.
val dartDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(',').filter { it.isNotEmpty() }.associate {
        val entry = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
        entry.substringBefore('=') to entry.substringAfter('=', "")
    }
val stagingKakaoKey = dartDefines["KAKAO_NATIVE_APP_KEY"].orEmpty()
require(stagingKakaoKey.isEmpty() || Regex("[a-fA-F0-9]{32}").matches(stagingKakaoKey)) {
    "Song_Record public Kakao SDK configuration is invalid"
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
        // Separate identity avoids replacing older verification signatures/data.
        create("searchVerification") {
            dimension = "environment"
            applicationIdSuffix = ".searchverification"
            resValue("string", "app_name", "노래기록 검색 검증")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            manifestPlaceholders["kakaoScheme"] =
                if (stagingKakaoKey.isEmpty()) "kakao-unconfigured" else "kakao$stagingKakaoKey"
            resValue("string", "app_name", "노래기록 STAGING")
        }
        // Same staging service environment, separate installation/signing identity.
        create("beta") {
            dimension = "environment"
            applicationIdSuffix = ".beta"
            manifestPlaceholders["kakaoScheme"] =
                if (stagingKakaoKey.isEmpty()) "kakao-unconfigured" else "kakao$stagingKakaoKey"
            resValue("string", "app_name", "노래기록 베타")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "노래기록")
        }
    }

    signingConfigs {
        if (releasePropertiesPath != null) {
            create("upload") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (releasePropertiesPath != null) signingConfigs.getByName("upload") else null
        }
    }
}

gradle.taskGraph.whenReady {
    val packagesSignedRelease = allTasks.any { it.name in setOf(
        "assembleProdRelease", "bundleProdRelease", "packageProdRelease",
        "signProdReleaseBundle", "validateSigningProdRelease",
        "assembleBetaRelease", "bundleBetaRelease", "packageBetaRelease",
        "signBetaReleaseBundle", "validateSigningBetaRelease"
    ) }
    require(!packagesSignedRelease || releasePropertiesPath != null) {
        "Song_Record beta/production release requires a private upload key; debug signing is prohibited"
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
