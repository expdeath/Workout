plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Firebase reads app/google-services.json when it's there (an Android app
// registered in the heath-9a322 Firebase project); without it, Cloud.kt
// configures Firebase from the same public project settings the web app
// uses. See android/README.md → "Firebase + Google sign-in".
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.expdeath.coach"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.expdeath.coach"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-process:2.11.0")

    implementation(platform("com.google.firebase:firebase-bom:35.0.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Google sign-in (Credential Manager)
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.2.1")

    // Health Connect — the Android twin of HealthKit
    implementation("androidx.health.connect:connect-client:1.1.0")

    // The COACH watch app (../wear): Wear OS Data Layer + opening it from the phone
    implementation(project(":watchlink"))
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    implementation("androidx.wear:wear-remote-interactions:1.2.0")

    // COACH Pro: Google Play subscriptions through RevenueCat (docs/subscriptions.md)
    implementation("com.revenuecat.purchases:purchases:10.26.0")

    testImplementation("junit:junit:4.13.2")
}
