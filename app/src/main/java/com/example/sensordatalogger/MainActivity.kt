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
