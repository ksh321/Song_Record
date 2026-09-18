package com.ksh321.songrecord

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.media.MediaPlayer
import java.io.File
import androidx.core.content.ContextCompat
import com.ksh321.songrecord.recorder.RecorderService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var recorderEventSink: EventChannel.EventSink? = null
    private var mediaPlayer: MediaPlayer? = null
    private val recorderListener: (Map<String, Any?>) -> Unit = { state ->
        runOnUiThread { recorderEventSink?.success(state) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecorderService.restoreState(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORDER_COMMAND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(RecorderService.currentState())
                "getDeviceInfo" -> result.success(deviceInfo())
                "requestPermissions" -> requestRecorderPermissions(result)
                "start" -> startRecorder(result)
                "stop" -> stopRecorder(result)
                "playLatest" -> playLatest(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORDER_EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                recorderEventSink = events
                RecorderService.addListener(recorderListener)
            }

            override fun onCancel(arguments: Any?) {
                RecorderService.removeListener(recorderListener)
                recorderEventSink = null
            }
        })
    }

    private fun requestRecorderPermissions(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_ACTIVE", "권한 요청이 이미 진행 중입니다.", null)
            return
        }

        val missing = mutableListOf<String>()
        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) {
            missing += Manifest.permission.RECORD_AUDIO
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPermission(Manifest.permission.POST_NOTIFICATIONS)
        ) {
            missing += Manifest.permission.POST_NOTIFICATIONS
        }

        if (missing.isEmpty()) {
            result.success(permissionState())
            return
        }

        pendingPermissionResult = result
        requestPermissions(missing.toTypedArray(), RECORDER_PERMISSION_REQUEST)
    }

    private fun startRecorder(result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) {
            result.error("MICROPHONE_PERMISSION_DENIED", "마이크 권한이 필요합니다.", null)
            return
        }

        val intent = Intent(this, RecorderService::class.java)
            .setAction(RecorderService.ACTION_START)
        ContextCompat.startForegroundService(this, intent)
        result.success(null)
    }

    private fun stopRecorder(result: MethodChannel.Result) {
        val intent = Intent(this, RecorderService::class.java)
            .setAction(RecorderService.ACTION_STOP)
            .putExtra(
                RecorderService.EXTRA_STOP_REASON,
                RecorderService.STOP_REASON_APP_BUTTON,
            )
        startService(intent)
        result.success(null)
    }

    private fun playLatest(result: MethodChannel.Result) {
        val path = RecorderService.currentState()["outputPath"]?.toString()
        if (path.isNullOrBlank() || !File(path).isFile) {
            result.error("RECORDING_NOT_FOUND", "재생할 녹음 파일이 없습니다.", null)
            return
        }

        mediaPlayer?.release()
        try {
            val player = MediaPlayer().apply {
                setDataSource(path)
                setOnCompletionListener { completed ->
                    completed.release()
                    if (mediaPlayer === completed) mediaPlayer = null
                }
                prepare()
                start()
            }
            mediaPlayer = player
            result.success(null)
        } catch (error: Exception) {
            mediaPlayer?.release()
            mediaPlayer = null
            result.error("PLAYBACK_FAILED", error.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RECORDER_PERMISSION_REQUEST) return

        pendingPermissionResult?.success(permissionState())
        pendingPermissionResult = null
        mediaPlayer?.release()
        mediaPlayer = null
    }

    override fun onDestroy() {
        RecorderService.removeListener(recorderListener)
        recorderEventSink = null
        pendingPermissionResult = null
        super.onDestroy()
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun deviceInfo() = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "androidVersion" to Build.VERSION.RELEASE,
        "sdkInt" to Build.VERSION.SDK_INT,
    )

    private fun permissionState() = mapOf(
        "microphoneGranted" to hasPermission(Manifest.permission.RECORD_AUDIO),
        "notificationsGranted" to (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                hasPermission(Manifest.permission.POST_NOTIFICATIONS)
            ),
    )

    companion object {
        private const val RECORDER_COMMAND_CHANNEL =
            "com.ksh321.songrecord/recorder_commands"
        private const val RECORDER_EVENT_CHANNEL =
            "com.ksh321.songrecord/recorder_events"
        private const val RECORDER_PERMISSION_REQUEST = 2102
    }
}
