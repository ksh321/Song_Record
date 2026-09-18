package com.ksh321.songrecord.recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.os.StatFs
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import com.ksh321.songrecord.MainActivity

private class RecorderClassifiedException(
    val code: String,
    val localState: String,
    val interruptionReason: String,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

class RecorderService : Service() {
    private var recorder: MediaRecorder? = null
    private var recordingId: String? = null
    private var outputFile: File? = null
    private var journalEntry: RecorderJournalEntry? = null
    private var startedAtElapsedMs = 0L
    private var startedAtWallClockMs = 0L
    private var stopping = false
    private val handler = Handler(Looper.getMainLooper())

    private val ticker = object : Runnable {
        override fun run() {
            if (recorder == null || stopping) return

            val elapsedMs = currentElapsedMs()
            if (elapsedMs >= MAX_DURATION_MS) {
                requestStop(STOP_REASON_TIME_LIMIT)
                return
            }

            publish(recordingState(elapsedMs))
            notifyProgress(elapsedMs)
            handler.postDelayed(this, nextTickDelayMs(elapsedMs))
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording()
            ACTION_STOP -> requestStop(
                intent.getStringExtra(EXTRA_STOP_REASON) ?: STOP_REASON_APP_BUTTON,
            )
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (recorder != null) requestStop(STOP_REASON_SERVICE_DESTROYED)
        super.onDestroy()
    }

    private fun startRecording() {
        if (stopping) return

        if (recorder != null) {
            publish(recordingState(currentElapsedMs()))
            return
        }

        publish(mapOf("phase" to "starting"))
        startAsForeground(buildNotification("00:00 / 06:00", true))

        var pendingFile: File? = null
        var newRecorder: MediaRecorder? = null
        try {
            detectInputBlockReason()?.let { reason ->
                throw RecorderClassifiedException(
                    code = "RECORDER_INPUT_BLOCKED",
                    localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                    interruptionReason = reason,
                    message = if (reason == INTERRUPTION_PHONE_OR_COMMUNICATION) {
                        "통화 또는 음성 통신 중에는 녹음을 시작할 수 없습니다."
                    } else {
                        "다른 앱이 마이크를 사용 중이어서 녹음을 시작할 수 없습니다."
                    },
                )
            }

            val id = UUID.randomUUID().toString()
            val recordingsDirectory = File(filesDir, "recordings")
            ensureRecordingStorage(recordingsDirectory)
            val pendingDirectory = File(recordingsDirectory, ".pending")
            ensureRecordingStorage(pendingDirectory)
            val candidatePendingFile = File(pendingDirectory, "$id.m4a")
            pendingFile = candidatePendingFile
            val finalFile = File(recordingsDirectory, "$id.m4a")
            val entry = RecorderJournalEntry(
                recordingId = id,
                accountScope = RecorderRecoveryJournal.PROTOTYPE_ACCOUNT_SCOPE,
                pendingPath = candidatePendingFile.absolutePath,
                finalPath = finalFile.absolutePath,
                phase = RecorderRecoveryJournal.PHASE_PREPARING,
                startedAtWallClockMs = System.currentTimeMillis(),
                localState = RecorderRecoveryJournal.LOCAL_STATE_INPUT_PENDING,
            )
            recordingId = id
            outputFile = pendingFile
            journalEntry = entry
            startedAtWallClockMs = entry.startedAtWallClockMs
            RecorderRecoveryJournal(this).write(entry)

            val candidate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            newRecorder = candidate
            try {
                candidate.apply {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(AUDIO_BIT_RATE)
                    setAudioSamplingRate(AUDIO_SAMPLE_RATE)
                    setAudioChannels(AUDIO_CHANNELS)
                    setOutputFile(candidatePendingFile.absolutePath)
                    prepare()
                    start()
                }
            } catch (error: Exception) {
                throw RecorderClassifiedException(
                    code = "RECORDER_INPUT_BLOCKED",
                    localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                    interruptionReason = INTERRUPTION_OTHER_APP,
                    message = "마이크 입력을 시작하지 못했습니다. 통화나 다른 녹음 앱을 종료한 뒤 다시 시도하세요.",
                    cause = error,
                )
            }

            recorder = candidate
            startedAtElapsedMs = SystemClock.elapsedRealtime()
            val recordingEntry = entry.copy(
                phase = RecorderRecoveryJournal.PHASE_RECORDING,
                localState = RecorderRecoveryJournal.LOCAL_STATE_CAPTURING,
                interruptionReason = null,
            )
            journalEntry = recordingEntry
            RecorderRecoveryJournal(this).write(recordingEntry)
            publish(recordingState(0L))
            notifyProgress(0L)
            handler.post(ticker)
        } catch (failure: RecorderClassifiedException) {
            runCatching { newRecorder?.release() }
            recorder = null
            pendingFile?.delete()
            persistFailure(
                failure.code,
                failure.message,
                null,
                failure.localState,
                failure.interruptionReason,
            )
            publishFailure(
                failure.code,
                failure.message,
                failure.localState,
                failure.interruptionReason,
            )
            stopForegroundCompat()
            stopSelf()
        } catch (error: Exception) {
            runCatching { newRecorder?.release() }
            recorder = null
            pendingFile?.delete()
            val message = "녹음을 시작하지 못했습니다. 마이크를 사용하는 다른 앱을 확인하세요."
            persistFailure(
                "RECORDER_INPUT_BLOCKED",
                message,
                null,
                RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                INTERRUPTION_OTHER_APP,
            )
            publishFailure(
                "RECORDER_INPUT_BLOCKED",
                message,
                RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                INTERRUPTION_OTHER_APP,
            )
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun requestStop(stopReason: String) {
        if (stopping) return

        val activeRecorder = recorder ?: run {
            stopForegroundCompat()
            stopSelf()
            return
        }

        stopping = true
        handler.removeCallbacks(ticker)
        val elapsedMs = currentElapsedMs()
        publish(recordingState(elapsedMs, "stopping", stopReason))
        updateJournal(
            phase = RecorderRecoveryJournal.PHASE_FINALIZING,
            elapsedMs = elapsedMs,
            stopReason = stopReason,
        )

        try {
            try {
                activeRecorder.stop()
            } catch (error: RuntimeException) {
                throw RecorderClassifiedException(
                    code = "RECORDER_FILE_CORRUPT",
                    localState = RecorderRecoveryJournal.LOCAL_STATE_CORRUPT,
                    interruptionReason = INTERRUPTION_FINALIZATION_FAILED,
                    message = "녹음 파일을 정상적으로 마무리하지 못해 재생 불가로 분류했습니다.",
                    cause = error,
                )
            }
            runCatching { activeRecorder.release() }
            recorder = null

            val pendingFile = outputFile
                ?: throw RecorderClassifiedException(
                    code = "RECORDER_WRITE_FAILED",
                    localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                    interruptionReason = INTERRUPTION_WRITE_FAILED,
                    message = "임시 녹음 파일 경로를 찾지 못했습니다.",
                )
            val inspection = runCatching { RecorderFileTools.inspect(pendingFile) }
                .getOrNull()
                ?: throw RecorderClassifiedException(
                    code = "RECORDER_FILE_CORRUPT",
                    localState = RecorderRecoveryJournal.LOCAL_STATE_CORRUPT,
                    interruptionReason = INTERRUPTION_PLAYBACK_VALIDATION_FAILED,
                    message = "오디오 트랙 검증에 실패해 재생 불가로 분류했습니다.",
                )
            val verifiedEntry = requireNotNull(journalEntry).copy(
                phase = RecorderRecoveryJournal.PHASE_VERIFIED,
                elapsedMs = elapsedMs,
                stopReason = stopReason,
                sizeBytes = pendingFile.length(),
                durationMs = inspection.durationMs,
                sha256 = RecorderFileTools.sha256(pendingFile),
                actualMime = inspection.mime,
                actualSampleRate = inspection.sampleRate,
                actualChannels = inspection.channels,
                actualAacProfile = inspection.aacProfile,
                localState = RecorderRecoveryJournal.LOCAL_STATE_INPUT_PENDING,
                interruptionReason = null,
            )
            journalEntry = verifiedEntry
            RecorderRecoveryJournal(this).write(verifiedEntry)

            val finalFile = RecorderFileTools.moveToFinal(
                pendingFile,
                File(verifiedEntry.finalPath),
            )
            outputFile = finalFile
            val completedEntry = verifiedEntry.copy(
                phase = RecorderRecoveryJournal.PHASE_COMPLETED,
                sizeBytes = finalFile.length(),
            )
            journalEntry = completedEntry
            RecorderRecoveryJournal(this).write(completedEntry)
            publish(RecorderRecovery.completedState(completedEntry, recovered = false))
        } catch (failure: RecorderClassifiedException) {
            runCatching { activeRecorder.release() }
            recorder = null
            persistFailure(
                failure.code,
                failure.message,
                stopReason,
                failure.localState,
                failure.interruptionReason,
            )
            publishFailure(
                failure.code,
                failure.message,
                failure.localState,
                failure.interruptionReason,
                stopReason,
            )
        } catch (error: Exception) {
            runCatching { activeRecorder.release() }
            recorder = null
            val message = "녹음 파일을 저장하지 못했습니다."
            persistFailure(
                "RECORDER_WRITE_FAILED",
                message,
                stopReason,
                RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                INTERRUPTION_WRITE_FAILED,
            )
            publishFailure(
                "RECORDER_WRITE_FAILED",
                message,
                RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                INTERRUPTION_WRITE_FAILED,
                stopReason,
            )
        } finally {
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun updateJournal(
        phase: String,
        elapsedMs: Long,
        stopReason: String?,
    ) {
        val updated = journalEntry?.copy(
            phase = phase,
            elapsedMs = elapsedMs,
            stopReason = stopReason,
        ) ?: return
        journalEntry = updated
        RecorderRecoveryJournal(this).write(updated)
    }

    private fun persistFailure(
        code: String,
        message: String,
        stopReason: String?,
        localState: String,
        interruptionReason: String,
    ) {
        val failed = journalEntry?.copy(
            phase = RecorderRecoveryJournal.PHASE_FAILED,
            elapsedMs = if (startedAtElapsedMs == 0L) 0L else currentElapsedMs(),
            stopReason = stopReason,
            errorCode = code,
            errorMessage = message,
            localState = localState,
            interruptionReason = interruptionReason,
        ) ?: return
        journalEntry = failed
        RecorderRecoveryJournal(this).write(failed)
    }

    private fun recordingState(
        elapsedMs: Long,
        phase: String = "recording",
        stopReason: String? = null,
    ) = mapOf(
        "phase" to phase,
        "recordingId" to recordingId,
        "outputPath" to outputFile?.absolutePath,
        "elapsedMs" to elapsedMs,
        "remainingMs" to (MAX_DURATION_MS - elapsedMs).coerceAtLeast(0L),
        "limitWarning" to limitWarning(elapsedMs),
        "stopReason" to stopReason,
        "container" to "M4A",
        "codec" to "AAC-LC",
        "bitRate" to AUDIO_BIT_RATE,
        "sampleRate" to AUDIO_SAMPLE_RATE,
        "channels" to AUDIO_CHANNELS,
        "accountScope" to RecorderRecoveryJournal.PROTOTYPE_ACCOUNT_SCOPE,
        "localState" to RecorderRecoveryJournal.LOCAL_STATE_CAPTURING,
    )

    private fun publishFailure(
        code: String,
        message: String,
        localState: String,
        interruptionReason: String,
        stopReason: String? = null,
    ) {
        publish(
            mapOf(
                "phase" to "error",
                "recordingId" to recordingId,
                "outputPath" to outputFile?.absolutePath,
                "errorCode" to code,
                "errorMessage" to message,
                "stopReason" to stopReason,
                "recoveryState" to "interrupted",
                "localState" to localState,
                "interruptionReason" to interruptionReason,
            ),
        )
    }

    private fun detectInputBlockReason(): String? {
        val audioManager = getSystemService(AudioManager::class.java)
        return when (audioManager.mode) {
            AudioManager.MODE_IN_CALL,
            AudioManager.MODE_IN_COMMUNICATION -> INTERRUPTION_PHONE_OR_COMMUNICATION
            else -> null
        }
    }

    private fun ensureRecordingStorage(directory: File) {
        try {
            if (!directory.exists() && !directory.mkdirs()) {
                throw IOException("녹음 저장 폴더를 만들 수 없습니다.")
            }
            if (!directory.isDirectory || !directory.canWrite()) {
                throw IOException("녹음 저장 폴더에 쓸 수 없습니다.")
            }
            if (StatFs(directory.absolutePath).availableBytes < MIN_FREE_SPACE_BYTES) {
                throw RecorderClassifiedException(
                    code = "RECORDER_STORAGE_LOW",
                    localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                    interruptionReason = INTERRUPTION_STORAGE_LOW,
                    message = "저장 공간이 부족해 녹음을 시작할 수 없습니다.",
                )
            }
            val probe = File.createTempFile(".write-check-", ".tmp", directory)
            if (!probe.delete()) probe.deleteOnExit()
        } catch (failure: RecorderClassifiedException) {
            throw failure
        } catch (error: Exception) {
            throw RecorderClassifiedException(
                code = "RECORDER_WRITE_FAILED",
                localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                interruptionReason = INTERRUPTION_WRITE_FAILED,
                message = "녹음 파일을 저장할 공간을 준비하지 못했습니다.",
                cause = error,
            )
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "녹음 진행",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "잠금 화면에서도 녹음 상태와 종료 버튼을 표시합니다."
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String, includeStop: Boolean): Notification {
        val stopPendingIntent = stopPendingIntent(FOREGROUND_STOP_REQUEST_CODE)
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
            .setContentIntent(openAppPendingIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(
                if (includeStop) Notification.CATEGORY_STOPWATCH
                else Notification.CATEGORY_SERVICE,
            )
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_HIGH)
            .setShowWhen(true)
            .setWhen(
                if (includeStop && startedAtWallClockMs > 0L) startedAtWallClockMs
                else System.currentTimeMillis(),
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setDefaults(0).setSound(null).setVibrate(longArrayOf())
        }
        if (includeStop) {
            builder
                .setUsesChronometer(true)
                .addExtras(
                    Bundle().apply {
                        // Android 16.1+ Live Update API. Older Android versions ignore it.
                        putBoolean(PROMOTED_ONGOING_EXTRA, true)
                    },
                )
                .addAction(
                    Notification.Action.Builder(
                        applicationInfo.icon,
                        "녹음 종료",
                        stopPendingIntent,
                    ).build(),
                )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                builder.setChronometerCountDown(false)
            }
        }
        return builder.build()
    }

    private fun openAppPendingIntent(): PendingIntent {
        val openAppIntent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            OPEN_APP_REQUEST_CODE,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopPendingIntent(requestCode: Int): PendingIntent {
        val stopIntent = Intent(this, RecorderService::class.java)
            .setAction(ACTION_STOP)
            .putExtra(EXTRA_STOP_REASON, STOP_REASON_NOTIFICATION_BUTTON)
        return PendingIntent.getService(
            this,
            requestCode,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notifyProgress(elapsedMs: Long) {
        val totalSeconds = (elapsedMs / 1_000L).coerceAtMost(MAX_DURATION_SECONDS)
        val progress = "%02d:%02d / 06:00".format(
            totalSeconds / 60,
            totalSeconds % 60,
        )
        val remainingSeconds =
            ((MAX_DURATION_MS - elapsedMs).coerceAtLeast(0L) + 999L) / 1_000L
        val text = if (limitWarning(elapsedMs) == null) {
            progress
        } else {
            "$progress · ${remainingSeconds}초 후 자동 종료"
        }
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text, true))
    }

    private fun currentElapsedMs(): Long =
        (SystemClock.elapsedRealtime() - startedAtElapsedMs).coerceAtLeast(0L)

    private fun nextTickDelayMs(elapsedMs: Long): Long =
        (TICK_INTERVAL_MS - (elapsedMs % TICK_INTERVAL_MS))
            .coerceIn(1L, TICK_INTERVAL_MS)

    private fun limitWarning(elapsedMs: Long): String? = when {
        elapsedMs >= TEN_SECOND_WARNING_AT_MS -> LIMIT_WARNING_TEN_SECONDS
        elapsedMs >= THIRTY_SECOND_WARNING_AT_MS -> LIMIT_WARNING_THIRTY_SECONDS
        else -> null
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
        const val EXTRA_STOP_REASON = "com.ksh321.songrecord.recorder.STOP_REASON"
        const val STOP_REASON_APP_BUTTON = "app_button"
        const val STOP_REASON_NOTIFICATION_BUTTON = "notification_button"
        const val STOP_REASON_TIME_LIMIT = "time_limit"

        private const val STOP_REASON_SERVICE_DESTROYED = "service_destroyed"
        private const val INTERRUPTION_PHONE_OR_COMMUNICATION = "phone_or_communication"
        private const val INTERRUPTION_OTHER_APP = "other_app"
        private const val INTERRUPTION_STORAGE_LOW = "storage_low"
        private const val INTERRUPTION_WRITE_FAILED = "write_failed"
        private const val INTERRUPTION_FINALIZATION_FAILED = "finalization_failed"
        private const val INTERRUPTION_PLAYBACK_VALIDATION_FAILED =
            "playback_validation_failed"
        private const val LIMIT_WARNING_THIRTY_SECONDS = "thirty_seconds"
        private const val LIMIT_WARNING_TEN_SECONDS = "ten_seconds"
        // Android keeps a channel's original importance and lock-screen settings.
        // A new ID applies the lock-screen-visible defaults to existing installs too.
        private const val CHANNEL_ID = "song_record_recording_lockscreen_v3"
        private const val PROMOTED_ONGOING_EXTRA = "android.requestPromotedOngoing"
        private const val NOTIFICATION_ID = 2102
        private const val FOREGROUND_STOP_REQUEST_CODE = 1
        private const val OPEN_APP_REQUEST_CODE = 2
        private const val AUDIO_BIT_RATE = 96_000
        private const val AUDIO_SAMPLE_RATE = 48_000
        private const val AUDIO_CHANNELS = 1
        private const val TICK_INTERVAL_MS = 1_000L
        private const val THIRTY_SECOND_WARNING_AT_MS = 5L * 60L * 1_000L + 30_000L
        private const val TEN_SECOND_WARNING_AT_MS = 5L * 60L * 1_000L + 50_000L
        private const val MAX_DURATION_MS = 6L * 60L * 1_000L
        private const val MAX_DURATION_SECONDS = MAX_DURATION_MS / 1_000L
        private const val MIN_FREE_SPACE_BYTES = 16L * 1024L * 1024L

        private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()

        @Volatile
        private var lastState: Map<String, Any?> = mapOf("phase" to "idle")

        @Synchronized
        fun restoreState(context: Context): Map<String, Any?> {
            if (lastState["phase"] == "idle") {
                publish(RecorderRecovery.restore(context.applicationContext))
            }
            return lastState
        }

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
