package com.ksh321.songrecord.recorder

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.security.MessageDigest

internal data class RecorderJournalEntry(
    val recordingId: String,
    val accountScope: String,
    val pendingPath: String,
    val finalPath: String,
    val phase: String,
    val startedAtWallClockMs: Long,
    val elapsedMs: Long = 0L,
    val stopReason: String? = null,
    val sizeBytes: Long? = null,
    val durationMs: Long? = null,
    val sha256: String? = null,
    val actualMime: String? = null,
    val actualSampleRate: Int? = null,
    val actualChannels: Int? = null,
    val actualAacProfile: Int? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
    val localState: String = "INPUT_PENDING",
    val interruptionReason: String? = null,
)

internal data class RecorderAudioInspection(
    val mime: String,
    val sampleRate: Int?,
    val channels: Int?,
    val aacProfile: Int?,
    val durationMs: Long?,
)

internal class RecorderRecoveryJournal(context: Context) {
    private val preferences = context.getSharedPreferences(
        RecorderAccount.journalName(),
        Context.MODE_PRIVATE,
    )

    fun read(): RecorderJournalEntry? {
        val recordingId = preferences.getString(KEY_RECORDING_ID, null) ?: return null
        val pendingPath = preferences.getString(KEY_PENDING_PATH, null) ?: return null
        val finalPath = preferences.getString(KEY_FINAL_PATH, null) ?: return null
        val phase = preferences.getString(KEY_PHASE, null) ?: return null
        return RecorderJournalEntry(
            recordingId = recordingId,
            accountScope = preferences.getString(KEY_ACCOUNT_SCOPE, PROTOTYPE_ACCOUNT_SCOPE)
                ?: PROTOTYPE_ACCOUNT_SCOPE,
            pendingPath = pendingPath,
            finalPath = finalPath,
            phase = phase,
            startedAtWallClockMs = preferences.getLong(KEY_STARTED_AT_WALL_CLOCK_MS, 0L),
            elapsedMs = preferences.getLong(KEY_ELAPSED_MS, 0L),
            stopReason = preferences.getString(KEY_STOP_REASON, null),
            sizeBytes = preferences.longOrNull(KEY_SIZE_BYTES),
            durationMs = preferences.longOrNull(KEY_DURATION_MS),
            sha256 = preferences.getString(KEY_SHA256, null),
            actualMime = preferences.getString(KEY_ACTUAL_MIME, null),
            actualSampleRate = preferences.intOrNull(KEY_ACTUAL_SAMPLE_RATE),
            actualChannels = preferences.intOrNull(KEY_ACTUAL_CHANNELS),
            actualAacProfile = preferences.intOrNull(KEY_ACTUAL_AAC_PROFILE),
            errorCode = preferences.getString(KEY_ERROR_CODE, null),
            errorMessage = preferences.getString(KEY_ERROR_MESSAGE, null),
            localState = preferences.getString(KEY_LOCAL_STATE, LOCAL_STATE_INPUT_PENDING)
                ?: LOCAL_STATE_INPUT_PENDING,
            interruptionReason = preferences.getString(KEY_INTERRUPTION_REASON, null),
        )
    }

    fun write(entry: RecorderJournalEntry) {
        preferences.edit()
            .clear()
            .putInt(KEY_SCHEMA_VERSION, SCHEMA_VERSION)
            .putString(KEY_RECORDING_ID, entry.recordingId)
            .putString(KEY_ACCOUNT_SCOPE, entry.accountScope)
            .putString(KEY_PENDING_PATH, entry.pendingPath)
            .putString(KEY_FINAL_PATH, entry.finalPath)
            .putString(KEY_PHASE, entry.phase)
            .putLong(KEY_STARTED_AT_WALL_CLOCK_MS, entry.startedAtWallClockMs)
            .putLong(KEY_ELAPSED_MS, entry.elapsedMs)
            .putNullableString(KEY_STOP_REASON, entry.stopReason)
            .putNullableLong(KEY_SIZE_BYTES, entry.sizeBytes)
            .putNullableLong(KEY_DURATION_MS, entry.durationMs)
            .putNullableString(KEY_SHA256, entry.sha256)
            .putNullableString(KEY_ACTUAL_MIME, entry.actualMime)
            .putNullableInt(KEY_ACTUAL_SAMPLE_RATE, entry.actualSampleRate)
            .putNullableInt(KEY_ACTUAL_CHANNELS, entry.actualChannels)
            .putNullableInt(KEY_ACTUAL_AAC_PROFILE, entry.actualAacProfile)
            .putNullableString(KEY_ERROR_CODE, entry.errorCode)
            .putNullableString(KEY_ERROR_MESSAGE, entry.errorMessage)
            .putString(KEY_LOCAL_STATE, entry.localState)
            .putNullableString(KEY_INTERRUPTION_REASON, entry.interruptionReason)
            .commit()
    }

    private fun android.content.SharedPreferences.longOrNull(key: String): Long? =
        if (contains(key)) getLong(key, 0L) else null

    private fun android.content.SharedPreferences.intOrNull(key: String): Int? =
        if (contains(key)) getInt(key, 0) else null

    private fun android.content.SharedPreferences.Editor.putNullableString(
        key: String,
        value: String?,
    ) = apply { if (value == null) remove(key) else putString(key, value) }

    private fun android.content.SharedPreferences.Editor.putNullableLong(
        key: String,
        value: Long?,
    ) = apply { if (value == null) remove(key) else putLong(key, value) }

    private fun android.content.SharedPreferences.Editor.putNullableInt(
        key: String,
        value: Int?,
    ) = apply { if (value == null) remove(key) else putInt(key, value) }

    companion object {
        const val PHASE_PREPARING = "preparing"
        const val PHASE_RECORDING = "recording"
        const val PHASE_FINALIZING = "finalizing"
        const val PHASE_VERIFIED = "verified"
        const val PHASE_COMPLETED = "completed"
        const val PHASE_FAILED = "failed"
        const val LOCAL_STATE_CAPTURING = "CAPTURING"
        const val LOCAL_STATE_INPUT_PENDING = "INPUT_PENDING"
        const val LOCAL_STATE_SAVED = "SAVED"
        const val LOCAL_STATE_INTERRUPTED = "INTERRUPTED"
        const val LOCAL_STATE_CORRUPT = "CORRUPT"
        const val PROTOTYPE_ACCOUNT_SCOPE = "prototype_device"

        private const val SCHEMA_VERSION = 1
        private const val PREFERENCES_NAME = "recorder_recovery_journal_v1"
        private const val KEY_SCHEMA_VERSION = "schema_version"
        private const val KEY_RECORDING_ID = "recording_id"
        private const val KEY_ACCOUNT_SCOPE = "account_scope"
        private const val KEY_PENDING_PATH = "pending_path"
        private const val KEY_FINAL_PATH = "final_path"
        private const val KEY_PHASE = "phase"
        private const val KEY_STARTED_AT_WALL_CLOCK_MS = "started_at_wall_clock_ms"
        private const val KEY_ELAPSED_MS = "elapsed_ms"
        private const val KEY_STOP_REASON = "stop_reason"
        private const val KEY_SIZE_BYTES = "size_bytes"
        private const val KEY_DURATION_MS = "duration_ms"
        private const val KEY_SHA256 = "sha256"
        private const val KEY_ACTUAL_MIME = "actual_mime"
        private const val KEY_ACTUAL_SAMPLE_RATE = "actual_sample_rate"
        private const val KEY_ACTUAL_CHANNELS = "actual_channels"
        private const val KEY_ACTUAL_AAC_PROFILE = "actual_aac_profile"
        private const val KEY_ERROR_CODE = "error_code"
        private const val KEY_ERROR_MESSAGE = "error_message"
        private const val KEY_LOCAL_STATE = "local_state"
        private const val KEY_INTERRUPTION_REASON = "interruption_reason"
    }
}

internal object RecorderFileTools {
    fun inspect(file: File): RecorderAudioInspection? {
        if (!file.isFile || file.length() <= 0L) return null
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            (0 until extractor.trackCount).firstNotNullOfOrNull { index ->
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") != true) return@firstNotNullOfOrNull null
                RecorderAudioInspection(
                    mime = mime,
                    sampleRate = format.integerOrNull(MediaFormat.KEY_SAMPLE_RATE),
                    channels = format.integerOrNull(MediaFormat.KEY_CHANNEL_COUNT),
                    aacProfile = format.integerOrNull(MediaFormat.KEY_AAC_PROFILE),
                    durationMs = format.longOrNull(MediaFormat.KEY_DURATION)?.div(1_000L),
                )
            }
        } catch (_: Exception) {
            null
        } finally {
            extractor.release()
        }
    }

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    fun moveToFinal(pendingFile: File, finalFile: File): File {
        finalFile.parentFile?.mkdirs()
        if (pendingFile.absolutePath == finalFile.absolutePath) return finalFile
        if (finalFile.exists() && !finalFile.delete()) {
            throw IOException("기존 완료 파일을 교체할 수 없습니다.")
        }
        if (!pendingFile.renameTo(finalFile)) {
            pendingFile.copyTo(finalFile, overwrite = false)
            if (!pendingFile.delete()) {
                finalFile.delete()
                throw IOException("임시 녹음 파일을 정리할 수 없습니다.")
            }
        }
        return finalFile
    }

    private fun MediaFormat.integerOrNull(key: String): Int? =
        if (containsKey(key)) getInteger(key) else null

    private fun MediaFormat.longOrNull(key: String): Long? =
        if (containsKey(key)) getLong(key) else null
}

internal object RecorderRecovery {
    fun restore(context: Context): Map<String, Any?> {
        val journal = RecorderRecoveryJournal(context)
        val entry = journal.read() ?: return mapOf("phase" to "idle")
        if (entry.accountScope != RecorderAccount.scope ||
            !RecorderAccount.contains(context, entry.finalPath) ||
            !RecorderAccount.contains(context, entry.pendingPath)) return mapOf("phase" to "idle")
        val finalFile = File(entry.finalPath)
        val pendingFile = File(entry.pendingPath)
        val candidate = when {
            finalFile.isFile -> finalFile
            pendingFile.isFile -> pendingFile
            else -> return errorState(
                entry = entry,
                code = entry.errorCode ?: "RECORDER_RECOVERY_FILE_MISSING",
                message = entry.errorMessage
                    ?: "프로세스가 종료되어 녹음 파일을 찾을 수 없습니다.",
                localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                interruptionReason = entry.interruptionReason ?: "process_terminated",
            )
        }
        val inspection = RecorderFileTools.inspect(candidate)
            ?: return errorState(
                entry = entry,
                code = "RECORDER_FILE_CORRUPT",
                message = "녹음 파일을 재생 가능한 M4A로 확인하지 못했습니다.",
                localState = RecorderRecoveryJournal.LOCAL_STATE_CORRUPT,
                interruptionReason = entry.interruptionReason ?: "process_terminated",
            )

        return try {
            val recoveredFile = RecorderFileTools.moveToFinal(candidate, finalFile)
            val recoveredEntry = entry.copy(
                phase = RecorderRecoveryJournal.PHASE_COMPLETED,
                stopReason = entry.stopReason ?: "process_recovery",
                sizeBytes = recoveredFile.length(),
                durationMs = inspection.durationMs,
                sha256 = RecorderFileTools.sha256(recoveredFile),
                actualMime = inspection.mime,
                actualSampleRate = inspection.sampleRate,
                actualChannels = inspection.channels,
                actualAacProfile = inspection.aacProfile,
                errorCode = null,
                errorMessage = null,
                localState = RecorderRecoveryJournal.LOCAL_STATE_INPUT_PENDING,
                interruptionReason = if (
                    entry.phase == RecorderRecoveryJournal.PHASE_COMPLETED
                ) null else "process_terminated",
            )
            journal.write(recoveredEntry)
            completedState(recoveredEntry, recovered = true)
        } catch (error: Exception) {
            errorState(
                entry = entry,
                code = "RECORDER_WRITE_FAILED",
                message = "복구된 녹음 파일을 최종 위치에 저장하지 못했습니다.",
                localState = RecorderRecoveryJournal.LOCAL_STATE_INTERRUPTED,
                interruptionReason = "write_failed",
            )
        }
    }

    fun completedState(
        entry: RecorderJournalEntry,
        recovered: Boolean,
    ): Map<String, Any?> = mapOf(
        "phase" to "completed",
        "recordingId" to entry.recordingId,
        "outputPath" to entry.finalPath,
        "elapsedMs" to (entry.durationMs ?: entry.elapsedMs),
        "sizeBytes" to entry.sizeBytes,
        "durationMs" to entry.durationMs,
        "sha256" to entry.sha256,
        "actualMime" to entry.actualMime,
        "actualSampleRate" to entry.actualSampleRate,
        "actualChannels" to entry.actualChannels,
        "actualAacProfile" to entry.actualAacProfile,
        "stopReason" to entry.stopReason,
        "localState" to entry.localState,
        "interruptionReason" to entry.interruptionReason,
        "recovered" to recovered,
        "recoveryState" to if (recovered) "recovered" else "not_needed",
        "accountScope" to entry.accountScope,
        "container" to "M4A",
        "codec" to "AAC-LC",
        "bitRate" to 96_000,
        "sampleRate" to 48_000,
        "channels" to 1,
    )

    private fun errorState(
        entry: RecorderJournalEntry,
        code: String,
        message: String,
        localState: String,
        interruptionReason: String,
    ): Map<String, Any?> = mapOf(
        "phase" to "error",
        "recordingId" to entry.recordingId,
        "outputPath" to when {
            File(entry.finalPath).isFile -> entry.finalPath
            File(entry.pendingPath).isFile -> entry.pendingPath
            else -> null
        },
        "elapsedMs" to entry.elapsedMs,
        "errorCode" to code,
        "errorMessage" to message,
        "localState" to localState,
        "interruptionReason" to interruptionReason,
        "recovered" to true,
        "recoveryState" to "interrupted",
        "accountScope" to entry.accountScope,
    )
}
