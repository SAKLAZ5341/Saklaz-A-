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

    buildFeatures {
        buildConfig = true
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
            // Yerel test için debug imzası. Mağaza yayını için ayrı anahtar gerekir (depo dışında).
            signingConfig = signingConfigs.getByName("debug")
            // Galaxy Z Fold 7 = arm64. Diğer ABI'ler APK'yı gereksiz büyütür.
            ndk { abiFilters += listOf("arm64-v8a") }
        }
    }

    packaging {
        jniLibs {
            // LiteRT-LM yerel kütüphanesi sıkıştırılmadan, hizalı paketlenir (mmap ile yüklenir).
            useLegacyPackaging = false
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.core:core-ktx:1.17.0")
    // Gerçek yerel LLM motoru (Google LiteRT-LM). Model APK'da DEĞİL; uygulama içinden indirilir.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.19.1")
    // Cihaz içi OCR ve görüntü etiketleme (Google Play Hizmetleri, model indirmesi sistemce yapılır).
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.2")
    implementation("com.google.android.gms:play-services-mlkit-image-labeling:16.0.8")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
