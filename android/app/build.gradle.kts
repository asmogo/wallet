import org.gradle.api.tasks.testing.Test

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.screenshot)
}

screenshotTests {
    // References are rendered on macOS, CI renders on Linux: faint gradient
    // bands (the scroll edge fade) round 1/255 differently between the two —
    // a handful of pixels per image. The threshold is a percent of differing
    // pixels, so 0.01 passes that platform jitter (worst observed: 0.0007%)
    // while any real layout change still fails by orders of magnitude.
    imageDifferenceThreshold = 0.01f
}

android {
    experimentalProperties["android.experimental.enableScreenshotTest"] = true
    namespace = "com.cashu.me"
    // 37: required by the compose 1.12/material3 1.5 alpha line (M3 Expressive).
    compileSdk = 37

    defaultConfig {
        applicationId = "com.cashu.me"
        minSdk = 26
        targetSdk = 36
        versionCode = 4
        versionName = "1.0"
        testInstrumentationRunner = "com.cashu.me.test.CashuUiTestRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        testInstrumentationRunnerArguments["useTestStorageService"] = "true"
        vectorDrawables {
            useSupportLibrary = true
        }

        // Shared with iOS (SentryService.swift) — one Sentry project for both platforms.
        // Override with -PsentryDsn=... (or gradle.properties); default keeps builds zero-setup.
        val sentryDsn = providers.gradleProperty("sentryDsn").getOrElse(
            "https://aff293071a9e53305e76990761d4b38f@o4511625394061312.ingest.de.sentry.io/4511625402712144"
        )
        buildConfigField("String", "SENTRY_DSN", "\"$sentryDsn\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
        compilerOptions {
            // The app adopts M3 Expressive wholesale (theme, motion, components).
            freeCompilerArgs.add("-opt-in=androidx.compose.material3.ExperimentalMaterial3ExpressiveApi")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
        animationsDisabled = true
        managedDevices {
            localDevices {
                create("pixel2Api35") {
                    device = "Pixel 2"
                    apiLevel = 35
                    systemImageSource = "aosp"
                }
                create("compactApi26") {
                    device = "Pixel 2"
                    apiLevel = 26
                    // ATD images are not published for API 26.
                    systemImageSource = "aosp"
                }
                create("modernApi36") {
                    device = "Pixel 6"
                    apiLevel = 36
                    systemImageSource = "aosp"
                }
                create("tabletApi35") {
                    device = "Pixel Tablet"
                    apiLevel = 35
                    systemImageSource = "aosp-atd"
                }
            }
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.biometric)
    implementation(libs.androidx.concurrent.futures)
    implementation(libs.androidx.concurrent.futures.ktx)
    implementation(libs.androidx.metrics.performance)
    implementation(libs.androidx.profileinstaller)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.datetime)
    implementation(libs.zxing.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.mlkit.barcode.scanning)
    implementation(libs.okhttp)
    implementation(libs.bcprov)
    implementation(libs.bcur.kotlin)
    implementation(libs.cdk.android)
    implementation(libs.coil.compose)
    implementation(libs.sentry.android)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.test.core.ktx)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.test.uiautomator)
    androidTestImplementation(libs.androidx.concurrent.futures)
    androidTestImplementation(libs.androidx.concurrent.futures.ktx)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.compose.ui.test.junit4.accessibility)
    androidTestUtil(libs.androidx.test.orchestrator)
    androidTestUtil(libs.androidx.test.services)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    screenshotTestImplementation(libs.screenshot.validation.api)
    screenshotTestImplementation(libs.androidx.compose.ui.tooling)
}

tasks.register<Test>("androidLocalMintIntegrationTest") {
    group = "verification"
    description = "Runs Android JVM integration coverage against local Nutshell/CDK test mints."
    val debugUnitTest = tasks.named<Test>("testDebugUnitTest")
    dependsOn("compileDebugUnitTestKotlin", "compileDebugUnitTestJavaWithJavac", "processDebugUnitTestJavaRes")
    shouldRunAfter(debugUnitTest)
    testClassesDirs = debugUnitTest.get().testClassesDirs
    classpath = debugUnitTest.get().classpath
    systemProperty("cashu.localMintIntegration", "true")
    systemProperty(
        "cashu.nutshellMintUrl",
        providers.gradleProperty("nutshellMintUrl").getOrElse("http://localhost:3338"),
    )
    systemProperty(
        "cashu.cdkMintUrl",
        providers.gradleProperty("cdkMintUrl").getOrElse("http://localhost:3339"),
    )
    filter {
        includeTestsMatching("com.cashu.me.liveintegration.*")
    }
}
