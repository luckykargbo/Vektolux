import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) points at the production keystore.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// A release artifact is NEVER silently signed with the debug key. Without android/key.properties a
// release build fails, unless the caller opts in explicitly with -PvektoluxAllowDebugSigning=true
// (local smoke builds only: such an artifact must not be distributed).
val allowDebugSigning = (project.findProperty("vektoluxAllowDebugSigning") as String?) == "true"
gradle.taskGraph.whenReady {
    val releaseArtifactRequested = allTasks.any {
        val n = it.name
        n.endsWith("Release") && (n.startsWith("assemble") || n.startsWith("bundle") || n.startsWith("package"))
    }
    if (releaseArtifactRequested && !hasReleaseKey && !allowDebugSigning) {
        throw GradleException(
            "Release signing is not configured: android/key.properties is missing. Create it from the " +
                "owner's keystore (see README), or pass -PvektoluxAllowDebugSigning=true for a local, " +
                "non-distributable build."
        )
    }
}

android {
    namespace = "com.vektolux.app"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.vektolux.app"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Production key when key.properties exists. The debug key is reachable ONLY through the
            // explicit -PvektoluxAllowDebugSigning=true opt-in (see the task-graph check above).
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: release build signed with the DEBUG key (explicit opt-in). Do not distribute.")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
