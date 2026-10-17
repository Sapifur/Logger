#!/usr/bin/env bash
set -euo pipefail
ROOT="SensorDataLogger"
rm -rf "$ROOT"
mkdir -p "$ROOT"/app/src/main/java/com/example/sensordatalogger
mkdir -p "$ROOT"/app/src/main/res/{layout,values,drawable}
mkdir -p "$ROOT"/.github/workflows
mkdir -p "$ROOT"/.devcontainer
mkdir -p "$ROOT"/gradle/wrapper

##############################  ROOT FILES  ##############################
cat > "$ROOT/settings.gradle.kts" <<'EOF'
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
rootProject.name = "SensorDataLogger"
include(":app")
EOF

cat > "$ROOT/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.2.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.20" apply false
}
EOF

cat > "$ROOT/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

cat > "$ROOT/gradle/wrapper/gradle-wrapper.properties" <<'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

cat > "$ROOT/.gitignore" <<'EOF'
*.iml
.gradle
/local.properties
/.idea
.DS_Store
/build
/captures
.externalNativeBuild
.cxx
local.properties
EOF

##############################  APP MODULE  ##############################
cat > "$ROOT/app/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.sensordatalogger"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.sensordatalogger"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
EOF

cat > "$ROOT/app/proguard-rules.pro" <<'EOF'
# default proguard rules
EOF

cat > "$ROOT/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />

    <application
        android:allowBackup="true"
        android:icon="@drawable/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.SensorDataLogger">
        <activity
            android:name=".MainActivity"
            android:screenOrientation="portrait"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

##############################  KOTLIN  ##############################
cat > "$ROOT/app/src/main/java/com/example/sensordatalogger/CsvLogger.kt" <<'EOF'
package com.example.sensordatalogger

import android.content.Context
import android.util.Log
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class CsvLogger(private val context: Context) {

    private val executor = Executors.newSingleThreadExecutor()
    private var writer: BufferedWriter? = null
    private var file: File? = null

    fun start(): File {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        val dir = File(base, "SensorLogs").apply { mkdirs() }
        val newFile = File(dir, "sensor_data_$timestamp.csv")
        writer = BufferedWriter(FileWriter(newFile))
        writer?.write("timestamp_ns,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z\n")
        file = newFile
        return newFile
    }

    fun log(
        timestampNs: Long,
        accelX: Float, accelY: Float, accelZ: Float,
        gyroX: Float, gyroY: Float, gyroZ: Float
    ) {
        executor.execute {
            try {
                writer?.write(
                    "$timestampNs,$accelX,$accelY,$accelZ,$gyroX,$gyroY,$gyroZ\n"
                )
            } catch (e: Exception) {
                Log.e("CsvLogger", "Write failed", e)
            }
        }
    }

    fun stop() {
        executor.execute {
            try {
                writer?.flush(); writer?.close()
            } catch (e: Exception) {
                Log.e("CsvLogger", "Close failed", e)
            } finally {
                writer = null
            }
        }
        executor.shutdown()
    }

    fun getFile(): File? = file
}
EOF

cat > "$ROOT/app/src/main/java/com/example/sensordatalogger/MainActivity.kt" <<'EOF'
package com.example.sensordatalogger

import android.animation.ObjectAnimator
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import java.util.Locale

class MainActivity : AppCompatActivity(), SensorEventListener {

    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null

    private lateinit var csvLogger: CsvLogger
    private var isLogging = false
    private var currentDelayUs: Int = 10_000
    private var maxDurationMs: Long = 0L

    private lateinit var frequencySpinner: Spinner
    private lateinit var durationSpinner: Spinner
    private lateinit var toggleButton: Button
    private lateinit var statusText: TextView
    private lateinit var timerText: TextView
    private lateinit var limitText: TextView
    private lateinit var recIndicator: TextView
    private lateinit var recBlink: ObjectAnimator

    private val handler = Handler(Looper.getMainLooper())
    private var recordingStartElapsed: Long = 0L

    private var lastAccel: FloatArray? = null
    private var lastGyro: FloatArray? = null

    private val timerRunnable = object : Runnable {
        override fun run() {
            if (!isLogging) return
            val elapsed = SystemClock.elapsedRealtime() - recordingStartElapsed
            if (maxDurationMs > 0 && elapsed >= maxDurationMs) {
                stopRecording(autoStopped = true); return
            }
            timerText.text = formatTime(elapsed)
            limitText.text = if (maxDurationMs > 0)
                "Remaining: ${formatTime((maxDurationMs - elapsed).coerceAtLeast(0))}"
            else "No time limit"
            handler.postDelayed(this, 100L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope     = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        frequencySpinner = findViewById(R.id.frequencySpinner)
        durationSpinner  = findViewById(R.id.durationSpinner)
        toggleButton     = findViewById(R.id.toggleButton)
        statusText       = findViewById(R.id.statusText)
        timerText        = findViewById(R.id.timerText)
        limitText        = findViewById(R.id.limitText)
        recIndicator     = findViewById(R.id.recIndicator)

        val frequencies = listOf(20, 30, 40, 50, 100)
        frequencySpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            frequencies.map { "$it Hz" }
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        frequencySpinner.setSelection(frequencies.indexOf(100))
        frequencySpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: android.view.View?, pos: Int, id: Long) {
                currentDelayUs = 1_000_000 / frequencies[pos]
                if (isLogging) { unregisterListeners(); registerListeners() }
            }
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }

        val durations = listOf(
            "No limit" to 0L,
            "10 seconds" to 10_000L,
            "30 seconds" to 30_000L,
            "1 minute" to 60_000L,
            "5 minutes" to 300_000L,
            "10 minutes" to 600_000L,
            "30 minutes" to 1_800_000L,
            "1 hour" to 3_600_000L
        )
        durationSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            durations.map { it.first }
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        durationSpinner.setSelection(0)
        durationSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: android.view.View?, pos: Int, id: Long) {
                maxDurationMs = durations[pos].second
                if (!isLogging) {
                    limitText.text = if (maxDurationMs > 0)
                        "Time limit: ${formatTime(maxDurationMs)}"
                    else "No time limit"
                }
            }
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }

        recBlink = ObjectAnimator.ofFloat(recIndicator, "alpha", 1f, 0.15f).apply {
            duration = 600
            repeatMode = ObjectAnimator.REVERSE
            repeatCount = ObjectAnimator.INFINITE
        }
        recIndicator.alpha = 0f

        csvLogger = CsvLogger(this)

        toggleButton.setOnClickListener {
            if (isLogging) stopRecording(autoStopped = false) else startRecording()
        }
    }

    private fun startRecording() {
        if (accelerometer == null || gyroscope == null) {
            statusText.text = "Accelerometer or gyroscope not available"; return
        }
        lastAccel = null; lastGyro = null

        val file = csvLogger.start()
        recordingStartElapsed = SystemClock.elapsedRealtime()
        isLogging = true

        frequencySpinner.isEnabled = false
        durationSpinner.isEnabled  = false
        toggleButton.text          = "Stop Recording"
        statusText.text            = "Recording to ${file.name}"

        recIndicator.alpha = 1f
        recBlink.start()
        timerText.text = formatTime(0)
        limitText.text = if (maxDurationMs > 0)
            "Remaining: ${formatTime(maxDurationMs)}" else "No time limit"
        handler.post(timerRunnable)

        registerListeners()
    }

    private fun stopRecording(autoStopped: Boolean) {
        isLogging = false
        handler.removeCallbacks(timerRunnable)

        recBlink.cancel()
        recIndicator.alpha = 0f

        unregisterListeners()
        csvLogger.stop()

        val elapsed = SystemClock.elapsedRealtime() - recordingStartElapsed
        toggleButton.text          = "Start Recording"
        frequencySpinner.isEnabled = true
        durationSpinner.isEnabled  = true
        timerText.text             = formatTime(elapsed)

        val prefix = if (autoStopped) "Auto-stopped (time limit)" else "Stopped"
        statusText.text = "$prefix — ${elapsed / 1000}s recorded\nFile: ${csvLogger.getFile()?.absolutePath}"
    }

    private fun registerListeners() {
        accelerometer?.let { sensorManager.registerListener(this, it, currentDelayUs) }
        gyroscope?.let     { sensorManager.registerListener(this, it, currentDelayUs) }
    }

    private fun unregisterListeners() { sensorManager.unregisterListener(this) }

    override fun onSensorChanged(event: SensorEvent?) {
        if (!isLogging || event == null) return
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> { lastAccel = event.values.clone(); tryWriteSample(event.timestamp) }
            Sensor.TYPE_GYROSCOPE     -> { lastGyro  = event.values.clone(); tryWriteSample(event.timestamp) }
        }
    }

    private fun tryWriteSample(eventTimestampNs: Long) {
        val accel = lastAccel ?: return
        val gyro  = lastGyro  ?: return
        val epochNs = System.currentTimeMillis() * 1_000_000 +
                (eventTimestampNs - SystemClock.elapsedRealtimeNanos())
        csvLogger.log(epochNs,
            accel[0], accel[1], accel[2],
            gyro[0],  gyro[1],  gyro[2])
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun formatTime(ms: Long): String {
        val totalSec = ms / 1000
        val h = totalSec / 3600
        val m = (totalSec % 3600) / 60
        val s = totalSec % 60
        val tenths = (ms % 1000) / 100
        return if (h > 0)
            String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else
            String.format(Locale.US, "%02d:%02d.%d", m, s, tenths)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isLogging) stopRecording(autoStopped = false)
        handler.removeCallbacksAndMessages(null)
    }
}
EOF

##############################  RESOURCES  ##############################
cat > "$ROOT/app/src/main/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@android:color/black"
    android:fillViewport="true">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="24dp"
        android:gravity="center_horizontal">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Sensor Data Logger"
            android:textSize="24sp"
            android:textColor="@android:color/white"
            android:textStyle="bold"
            android:layout_marginBottom="32dp" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Sampling frequency (Hz)"
            android:textColor="@android:color/white"
            android:textSize="16sp"
            android:layout_marginBottom="8dp" />

        <Spinner
            android:id="@+id/frequencySpinner"
            android:layout_width="200dp"
            android:layout_height="wrap_content"
            android:backgroundTint="@android:color/white"
            android:layout_marginBottom="24dp" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Recording duration"
            android:textColor="@android:color/white"
            android:textSize="16sp"
            android:layout_marginBottom="8dp" />

        <Spinner
            android:id="@+id/durationSpinner"
            android:layout_width="200dp"
            android:layout_height="wrap_content"
            android:backgroundTint="@android:color/white"
            android:layout_marginBottom="32dp" />

        <LinearLayout
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical">

            <TextView
                android:id="@+id/recIndicator"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="●"
                android:textColor="#FF3B30"
                android:textSize="36sp"
                android:layout_marginEnd="10dp" />

            <TextView
                android:id="@+id/timerText"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="00:00.0"
                android:textSize="48sp"
                android:fontFamily="monospace"
                android:textColor="@android:color/white" />
        </LinearLayout>

        <TextView
            android:id="@+id/limitText"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="No time limit"
            android:textColor="@android:color/darker_gray"
            android:textSize="14sp"
            android:layout_marginBottom="32dp" />

        <Button
            android:id="@+id/toggleButton"
            android:layout_width="220dp"
            android:layout_height="wrap_content"
            android:text="Start Recording"
            android:textColor="@android:color/black"
            android:backgroundTint="@android:color/white"
            android:layout_marginBottom="24dp" />

        <TextView
            android:id="@+id/statusText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Ready"
            android:textColor="@android:color/white"
            android:textSize="12sp"
            android:gravity="center" />
    </LinearLayout>
</ScrollView>
EOF

cat > "$ROOT/app/src/main/res/values/themes.xml" <<'EOF'
<resources>
    <style name="Theme.SensorDataLogger" parent="Theme.Material3.Dark.NoActionBar">
        <item name="android:windowBackground">@android:color/black</item>
        <item name="android:colorBackground">@android:color/black</item>
        <item name="android:textColorPrimary">@android:color/white</item>
        <item name="android:textColorSecondary">@android:color/white</item>
        <item name="colorPrimary">@android:color/white</item>
        <item name="colorOnPrimary">@android:color/black</item>
    </style>
</resources>
EOF

cat > "$ROOT/app/src/main/res/values/strings.xml" <<'EOF'
<resources>
    <string name="app_name">Sensor Data Logger</string>
</resources>
EOF

cat > "$ROOT/app/src/main/res/drawable/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#000000"
        android:pathData="M0,0h108v108h-108z" />
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M14,54 L34,54 L42,30 L54,78 L64,54 L94,54 L94,58 L67,58 L54,92 L42,40 L37,58 L14,58 Z" />
</vector>
EOF

##############################  GITHUB ACTIONS  ##############################
cat > "$ROOT/.github/workflows/android.yml" <<'EOF'
name: Android CI

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

# Cancel superseded runs on the same branch to save minutes.
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build debug APK
    runs-on: ubuntu-latest
    timeout-minutes: 25

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      # Installs Gradle 8.2 and wires up caching.
      # Using this action means the repo does NOT need gradle-wrapper.jar.
      - name: Set up Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.2'

      # The ubuntu-latest runner already has the Android SDK preinstalled.
      # This step is defensive: it re-accepts licenses in case of policy changes.
      - name: Accept Android SDK licenses
        run: yes | sdkmanager --licenses > /dev/null 2>&1 || true

      - name: Build debug APK
        run: gradle assembleDebug --no-daemon --stacktrace

      - name: Upload debug APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: app/build/outputs/apk/debug/*.apk
          if-no-files-found: warn
          retention-days: 14
EOF

##############################  DEVCONTAINER  ##############################
cat > "$ROOT/.devcontainer/devcontainer.json" <<'EOF'
{
    "name": "Android Sensor Logger",
    "image": "mcr.microsoft.com/devcontainers/universal:2",
    "features": {
        "ghcr.io/devcontainers/features/java:1": {
            "version": "17",
            "jdkDistro": "tem"
        },
        "ghcr.io/devcontainers/features/gradle:1": {
            "version": "8.2"
        }
    },
    "postCreateCommand": "echo 'Ready. Run: gradle assembleDebug --no-daemon'",
    "customizations": {
        "vscode": {
            "extensions": [
                "fwcd.kotlin",
                "vscjava.vscode-gradle",
                "redhat.vscode-yaml"
            ]
        }
    },
    "remoteUser": "codespace"
}
EOF

echo "✅  Project generated at: $ROOT/"
echo ""
echo "Next steps (inside the Codespace):"
echo "  cd $ROOT"
echo "  git init && git add . && git commit -m 'Initial commit'"
echo "  git remote add origin <your-repo-url>"
echo "  git push -u origin main"
echo ""
echo "The GitHub Actions workflow runs automatically on push."
echo "Download the APK from the run's 'Artifacts' section."