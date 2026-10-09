pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "CoachApp"
include(":app")
// the watch app (Wear OS) and the phone ↔ watch protocol both sides share
include(":wear")
include(":watchlink")
