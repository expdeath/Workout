plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// COACH for Wear OS — the wrist half of a workout (docs/watch.md). The
// application id matches the phone app's on purpose: the Wear OS Data Layer
// only connects apps with the same package name and signing key.
android {
    namespace = "com.expdeath.coach.wear"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.expdeath.coach"
        minSdk = 30 // Wear OS 3
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
    }
}

dependencies {
    implementation(project(":watchlink"))

    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.wear.compose:compose-material3:1.7.1")
    implementation("androidx.wear.compose:compose-foundation:1.7.1")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")

    // talking to the phone
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    implementation("androidx.wear:wear-remote-interactions:1.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")

    // heart rate + energy during the workout, and the watch-face chip while it runs
    implementation("androidx.health:health-services-client:1.1.0")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.3.0")
    implementation("androidx.wear:wear-ongoing:1.1.0")

    testImplementation("junit:junit:4.13.2")
}
