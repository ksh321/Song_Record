package com.ksh321.songrecord.recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaRecorder
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import java.io.File
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet

class RecorderService : Service() {
    private var recorder: MediaRecorder? = null
    private var recordingId: String? = null
    private var outputFile: File? = null
    private var startedAtElapsedMs = 0L
    private val handler = Handler(Looper.getMainLooper())

    private val ticker = object : Runnable {
        override fun run() {
            if (recorder == null) return
            val elapsedMs = SystemClock.elapsedRealtime() - startedAtElapsedMs
            publish(recordingState(elapsedMs))
            notifyProgress(elapsedMs)
            handler.postDelayed(this, 1_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopRecording()
            else -> startRecording()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (recorder != null) stopRecording()
        super.onDestroy()
    }

    private fun startRecording() {
        if (recorder != null) {
            publish(recordingState(SystemClock.elapsedRealtime() - startedAtElapsedMs))
            return
        }

        publish(mapOf("phase" to "starting"))
        startAsForeground(buildNotification("녹음 준비 중", false))

        val id = UUID.randomUUID().toString()
        val directory = File(filesDir, "recordings").apply { mkdirs() }
        val file = File(directory, "$id.m4a")

        try {
            val newRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            newRecorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(AUDIO_BIT_RATE)
                setAudioSamplingRate(AUDIO_SAMPLE_RATE)
                setAudioChannels(AUDIO_CHANNELS)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }

            recorder = newRecorder
            recordingId = id
            outputFile = file
            startedAtElapsedMs = SystemClock.elapsedRealtime()
            publish(recordingState(0L))
            handler.post(ticker)
        } catch (error: Exception) {
            recorder?.release()
            recorder = null
            file.delete()
            publishError("RECORDER_START_FAILED", error)
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun stopRecording() {
        val activeRecorder = recorder ?: run {
            stopForegroundCompat()
            stopSelf()
            return
        }

        handler.removeCallbacks(ticker)
        val elapsedMs = SystemClock.elapsedRealtime() - startedAtElapsedMs
        publish(recordingState(elapsedMs, "stopping"))

        try {
            activeRecorder.stop()
            activeRecorder.release()
            recorder = null

            val file = outputFile
            val inspection = file?.let(::inspectAudio)
            publish(
                mapOf(
                    "phase" to "completed",
                    "recordingId" to recordingId,
                    "outputPath" to file?.absolutePath,
                    "elapsedMs" to elapsedMs,
                    "sizeBytes" to (file?.length() ?: 0L),
                    "container" to "M4A",
                    "codec" to "AAC-LC",
                    "bitRate" to AUDIO_BIT_RATE,
                    "sampleRate" to AUDIO_SAMPLE_RATE,
                    "channels" to AUDIO_CHANNELS,
                    "actualMime" to inspection?.mime,
                    "actualSampleRate" to inspection?.sampleRate,
                    "actualChannels" to inspection?.channels,
                    "actualAacProfile" to inspection?.aacProfile,
                ),
            )
        } catch (error: RuntimeException) {
            activeRecorder.release()
            recorder = null
            outputFile?.delete()
            publishError("RECORDER_STOP_FAILED", error)
        } finally {
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun recordingState(elapsedMs: Long, phase: String = "recording") = mapOf(
        "phase" to phase,
        "recordingId" to recordingId,
        "outputPath" to outputFile?.absolutePath,
        "elapsedMs" to elapsedMs,
        "container" to "M4A",
        "codec" to "AAC-LC",
        "bitRate" to AUDIO_BIT_RATE,
        "sampleRate" to AUDIO_SAMPLE_RATE,
        "channels" to AUDIO_CHANNELS,
    )

    private fun publishError(code: String, error: Exception) {
        publish(
            mapOf(
                "phase" to "error",
                "recordingId" to recordingId,
                "outputPath" to outputFile?.absolutePath,
                "errorCode" to code,
                "errorMessage" to (error.message ?: error.javaClass.simpleName),
            ),
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "녹음 진행",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "잠금 상태에서도 진행되는 녹음 상태"
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String, includeStop: Boolean): Notification {
        val stopIntent = Intent(this, RecorderService::class.java).setAction(ACTION_STOP)
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle("노래기록 녹음 중")
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setSound(null).setVibrate(null)
        }
        if (includeStop) {
            builder.addAction(Notification.Action.Builder(0, "녹음 종료", stopPendingIntent).build())
        }
        return builder.build()
    }

    private fun inspectAudio(file: File): AudioInspection? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            (0 until extractor.trackCount).firstNotNullOfOrNull { index ->
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") != true) return@firstNotNullOfOrNull null
                AudioInspection(
                    mime = mime,
                    sampleRate = format.integerOrNull(MediaFormat.KEY_SAMPLE_RATE),
                    channels = format.integerOrNull(MediaFormat.KEY_CHANNEL_COUNT),
                    aacProfile = format.integerOrNull(MediaFormat.KEY_AAC_PROFILE),
                )
            }
        } catch (_: Exception) {
            null
        } finally {
            extractor.release()
        }
    }

    private fun MediaFormat.integerOrNull(key: String): Int? =
        if (containsKey(key)) getInteger(key) else null

    private data class AudioInspection(
        val mime: String,
        val sampleRate: Int?,
        val channels: Int?,
        val aacProfile: Int?,
    )

    private fun notifyProgress(elapsedMs: Long) {
        val totalSeconds = elapsedMs / 1_000L
        val text = "%02d:%02d / 06:00".format(totalSeconds / 60, totalSeconds % 60)
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text, true))
    }

    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    companion object {
        const val ACTION_START = "com.ksh321.songrecord.recorder.START"
        const val ACTION_STOP = "com.ksh321.songrecord.recorder.STOP"
        private const val CHANNEL_ID = "song_record_recording"
        private const val NOTIFICATION_ID = 2102
        private const val AUDIO_BIT_RATE = 96_000
        private const val AUDIO_SAMPLE_RATE = 48_000
        private const val AUDIO_CHANNELS = 1

        private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()

        @Volatile
        private var lastState: Map<String, Any?> = mapOf("phase" to "idle")

        fun currentState(): Map<String, Any?> = lastState

        fun addListener(listener: (Map<String, Any?>) -> Unit) {
            listeners.add(listener)
            listener(lastState)
        }

        fun removeListener(listener: (Map<String, Any?>) -> Unit) {
            listeners.remove(listener)
        }

        private fun publish(state: Map<String, Any?>) {
            lastState = state
            listeners.forEach { it(state) }
        }
    }
}
