package com.ksh321.songrecord

import android.app.Activity
import android.content.Intent
import android.os.StatFs
import com.ksh321.songrecord.recorder.RecorderAccount
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/** SAF grants one read. Copy only into a new owned cache directory. */
internal class BackupImportBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var scope: String? = null
    @Volatile private var closed = false
    @Volatile private var input: java.io.InputStream? = null
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pickZip") { result.notImplemented(); return }
        if (closed || pending != null || RecorderAccount.scope == null) {
            result.error("IMPORT_UNAVAILABLE", "현재 계정 상태를 확인해 주세요.", null); return
        }
        pending = result; scope = RecorderAccount.scope
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "application/zip"; addCategory(Intent.CATEGORY_OPENABLE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, REQUEST)
        } catch (_: Exception) { pending = null; result.error("IMPORT_PICK_FAILED", "파일 선택을 열지 못했어요.", null) }
    }
    fun onResult(request: Int, code: Int, data: Intent?) {
        if (request != REQUEST) return
        val reply = pending ?: return
        if (code != Activity.RESULT_OK || data?.data == null) {
            pending = null; reply.success(null); return
        }
        val uri = data.data!!
        if (uri.scheme != "content") { pending = null; reply.error("IMPORT_PICK_FAILED", "문서 파일을 선택해 주세요.", null); return }
        Thread {
            val directory = File(activity.cacheDir, "import-input-${UUID.randomUUID()}")
            val file = File(directory, "source.zip")
            val timer = java.util.Timer("song-record-import-timeout", true)
            timer.schedule(object : java.util.TimerTask() {
                override fun run() { try { input?.close() } catch (_: Exception) {} }
            }, 300000L)
            try {
                check(directory.mkdir())
                val limit = StatFs(activity.cacheDir.path).availableBytes - 16L * 1024 * 1024
                check(limit > 0)
                val deadline = android.os.SystemClock.elapsedRealtime() + 300000
                var copied = 0L
                activity.contentResolver.openInputStream(uri).use { input ->
                    checkNotNull(input)
                    this.input = input
                    file.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            check(!closed && scope == RecorderAccount.scope && android.os.SystemClock.elapsedRealtime() < deadline)
                            val n = input.read(buffer)
                            if (n < 0) break
                            copied += n; check(copied <= limit)
                            output.write(buffer, 0, n)
                        }
                    }
                }
                check(copied > 0 && !closed && scope == RecorderAccount.scope)
                activity.runOnUiThread { pending = null; reply.success(file.canonicalPath) }
            } catch (_: Exception) {
                file.delete(); directory.delete()
                activity.runOnUiThread { pending = null; reply.error("IMPORT_READ_FAILED", "파일 읽기·여유 공간·현재 계정을 확인해 주세요.", null) }
            } finally { timer.cancel(); input = null }
        }.start()
    }
    fun close() { closed = true; try { input?.close() } catch (_: Exception) {} }
    companion object { private const val REQUEST = 23001 }
}
