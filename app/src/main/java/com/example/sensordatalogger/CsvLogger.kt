package com.example.sensordatalogger

import android.content.Context
import android.os.Environment
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
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            .also { it.mkdirs() }
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
