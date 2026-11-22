plugins { id("com.android.application") }

// Keep Android package versioning aligned with leqra releases.
val releaseVersion =
    providers
        .exec {
            workingDir(rootDir.parentFile)
            commandLine("sh", "scripts/version.sh")
        }
        .standardOutput
        .asText
        .get()
        .trim()

val versionMatch =
    requireNotNull(
        Regex("v([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-[0-9A-Za-z.-]+)?").matchEntire(releaseVersion),
    ) {
        "Invalid scripts/version.sh version"
    }
val parts = versionMatch.groupValues.drop(1).map(String::toInt)

require(parts[1] < 100 && parts[2] < 10000)

// Keep upload credentials in user Gradle properties or the CI environment.
val uploadSigningFields =
    mapOf(
        "leqraUploadStoreFile" to "LEQRA_UPLOAD_STORE_FILE",
        "leqraUploadStorePassword" to "LEQRA_UPLOAD_STORE_PASSWORD",
        "leqraUploadKeyAlias" to "LEQRA_UPLOAD_KEY_ALIAS",
        "leqraUploadKeyPassword" to "LEQRA_UPLOAD_KEY_PASSWORD",
    )
val uploadSigning = uploadSigningFields.mapValues { (property, environment) ->
    providers.gradleProperty(property).orElse(providers.environmentVariable(environment)).orNull
}
val uploadKeystore =
    uploadSigning["leqraUploadStoreFile"]?.takeIf { it.isNotEmpty() }?.let { rootProject.file(it) }
val validateReleaseSigning =
    tasks.register("validateReleaseSigning") {
        group = "verification"
        description = "Check that release upload signing credentials are configured."
        val missing =
            uploadSigningFields
                .filterKeys { uploadSigning[it].isNullOrEmpty() }
                .map { (property, environment) -> "$property ($environment)" }
        val keystore = uploadKeystore
        doLast {
            check(missing.isEmpty()) {
                "Missing release signing settings: ${missing.joinToString()}. See android/README.md."
            }
            check(keystore?.isFile == true) { "Release upload keystore does not exist: $keystore" }
        }
    }

// AGP can otherwise produce an unsigned release when its signing config is incomplete.
tasks
    .matching {
        it.name in
            setOf(
                "assembleRelease",
                "bundleRelease",
                "installRelease",
                "packageRelease",
                "packageReleaseBundle",
                "signReleaseBundle",
                "validateSigningRelease",
            )
    }
    .configureEach { dependsOn(validateReleaseSigning) }

android {
    namespace = "com.leqra.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.leqra"
        minSdk = 26
        targetSdk = 36
        versionName = releaseVersion
        // Keep the v5 -> v0 rename upgradeable and skip codes already used through 5090003.
        // This offset is permanent: v0.9.3 uses 5090004, and v1 starts at 6000001.
        versionCode = (parts[0] + 5) * 1000000 + parts[1] * 10000 + parts[2] + 1
        buildConfigField("String", "GAME_VERSION", "\"$releaseVersion\"")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { buildConfig = true }
    signingConfigs {
        create("release") {
            storeFile = uploadKeystore
            storePassword = uploadSigning["leqraUploadStorePassword"]
            keyAlias = uploadSigning["leqraUploadKeyAlias"]
            keyPassword = uploadSigning["leqraUploadKeyPassword"]
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
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
