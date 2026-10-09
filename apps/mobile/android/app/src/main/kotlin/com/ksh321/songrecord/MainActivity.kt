package com.ksh321.songrecord

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.net.Uri
import android.media.MediaPlayer
import java.io.File
import androidx.core.content.ContextCompat
import com.ksh321.songrecord.recorder.RecorderService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val playbackBridge by lazy { PlaybackBridge(this) }
    private val accountBridge by lazy { AccountBridge(this) { mediaPlayer?.release(); mediaPlayer = null; playbackBridge.stop() } }
    private val identityLinkBridge by lazy { IdentityLinkBridge(this) }
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var recorderEventSink: EventChannel.EventSink? = null
    private var mediaPlayer: MediaPlayer? = null
    private val recorderListener: (Map<String, Any?>) -> Unit = { state ->
        runOnUiThread { recorderEventSink?.success(state) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "song_record/playback")
            .setMethodCallHandler(playbackBridge::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "song_record/playback_events")
            .setStreamHandler(object: EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { playbackBridge.events=sink }
                override fun onCancel(arguments: Any?) { playbackBridge.events=null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "song_record/identity_link")
            .setMethodCallHandler(identityLinkBridge::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "song_record/account")
            .setMethodCallHandler(accountBridge::handle)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORDER_COMMAND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(RecorderService.currentState())
                "getDeviceInfo" -> result.success(deviceInfo())
                "openAppSettings" -> openAppSettings(result)
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
        if (missing.contains(Manifest.permission.RECORD_AUDIO)) {
            getSharedPreferences(PERMISSION_PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_MICROPHONE_REQUESTED, true)
                .apply()
        }
        requestPermissions(missing.toTypedArray(), RECORDER_PERMISSION_REQUEST)
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val packageUri = Uri.parse("package:$packageName")
        val permissionsIntent = Intent(APP_PERMISSIONS_SETTINGS_ACTION, packageUri)
        val fallbackIntent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            packageUri,
        )

        try {
            startActivity(permissionsIntent)
        } catch (_: ActivityNotFoundException) {
            startActivity(fallbackIntent)
        }
        result.success(null)
    }

    private fun startRecorder(result: MethodChannel.Result) {
        if (com.ksh321.songrecord.recorder.RecorderAccount.scope == null || com.ksh321.songrecord.recorder.RecorderAccount.exporting) {
            result.error("ACCOUNT_UNAVAILABLE", "로그인 및 백업 상태를 확인해 주세요.", null)
            return
        }
        if (RecorderService.isCapturing()) { result.success(null); return }
        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) {
            result.error("MICROPHONE_PERMISSION_DENIED", "마이크 권한이 필요합니다.", null)
            return
        }

        val intent = Intent(this, RecorderService::class.java)
            .setAction(RecorderService.ACTION_START)
        intent.putExtra("accountScope", com.ksh321.songrecord.recorder.RecorderAccount.scope)
        RecorderService.reserveStart()
        try {
            ContextCompat.startForegroundService(this, intent)
            result.success(null)
        } catch (_: Exception) {
            RecorderService.resetAccountState(this)
            result.error("RECORDER_START_FAILED", "녹음을 시작하지 못했어요.", null)
        }
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
        if (path.isNullOrBlank() || !com.ksh321.songrecord.recorder.RecorderAccount.contains(this, path) || !File(path).isFile) {
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        accountBridge.onResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        playbackBridge.close()
        accountBridge.close()
        mediaPlayer?.release()
        mediaPlayer = null
        identityLinkBridge.close()
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

    private fun permissionState(): Map<String, Any> {
        val microphoneGranted = hasPermission(Manifest.permission.RECORD_AUDIO)
        val microphoneRequested = getSharedPreferences(
            PERMISSION_PREFERENCES,
            MODE_PRIVATE,
        ).getBoolean(KEY_MICROPHONE_REQUESTED, false)
        val microphoneCanAskAgain = microphoneGranted ||
            !microphoneRequested ||
            shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)

        return mapOf(
        "microphoneGranted" to microphoneGranted,
        "microphoneCanAskAgain" to microphoneCanAskAgain,
        "notificationsGranted" to (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                hasPermission(Manifest.permission.POST_NOTIFICATIONS)
            ),
        )
    }

    companion object {
        private const val RECORDER_COMMAND_CHANNEL =
            "com.ksh321.songrecord/recorder_commands"
        private const val RECORDER_EVENT_CHANNEL =
            "com.ksh321.songrecord/recorder_events"
        private const val RECORDER_PERMISSION_REQUEST = 2102
        private const val PERMISSION_PREFERENCES = "recorder_permissions"
        private const val KEY_MICROPHONE_REQUESTED = "microphone_requested"
        private const val APP_PERMISSIONS_SETTINGS_ACTION =
            "android.settings.APP_PERMISSIONS_SETTINGS"
    }
}
