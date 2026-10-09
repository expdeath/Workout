plugins {
    id("com.android.library")
}

// The phone ↔ watch protocol (docs/watch.md), shared by :app and :wear so
// both sides read and write exactly the same JSON. Pure Kotlin — the
// workout logic the watch needs offline (next set, optimistic updates) is
// unit-tested on the JVM.
android {
    namespace = "com.expdeath.coach.watchlink"
    compileSdk = 37

    defaultConfig {
        minSdk = 28
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    testImplementation("junit:junit:4.13.2")
}
