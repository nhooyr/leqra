plugins { id("com.android.application"); kotlin("android") }

// Keep the native client handshake and package version tied to the server.
val releaseVersion = providers.exec {
    workingDir(rootDir.parentFile)
    commandLine("sh", "scripts/version.sh")
}.standardOutput.asText.get().trim()
require(Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(releaseVersion)) { "Invalid scripts/version.sh version" }
val parts = releaseVersion.split('.').map(String::toInt)
require(parts[1] < 100 && parts[2] < 10000)

android {
    namespace = "com.leqra.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.leqra"
        minSdk = 26
        targetSdk = 36
        versionName = releaseVersion
        versionCode = parts[0] * 1000000 + parts[1] * 10000 + parts[2]
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { buildConfig = true }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    testOptions { unitTests.isReturnDefaultValues = true }
    lint { abortOnError = true }
}
kotlin { jvmToolchain(17) }
dependencies {
    implementation(project(":core"))
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
