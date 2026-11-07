plugins {
    id("com.android.application")
    // Flutter Gradle eklentisi Android eklentisinden sonra uygulanmalıdır.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.saklaz.assistant"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.saklaz.assistant"
        // Android 12 (API 31): createOnDeviceSpeechRecognizer ve RoleManager için alt sınır.
        minSdk = 31
        // Hedef: Android 16 (Samsung Galaxy Z Fold 7)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Phase 7'de gerçek imzalama anahtarı eklenecek (depo dışında saklanacak).
            // Şimdilik yalnızca yerel test için debug imzası.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Pigeon 29'un ürettiği Kotlin kodu coroutine kullanır.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // Yerel AI: Gemini Nano (sistem AICore). Model APK içinde DEĞİL; sistem yönetir.
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta1")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
