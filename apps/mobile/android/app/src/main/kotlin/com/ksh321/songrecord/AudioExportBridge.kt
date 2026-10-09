package com.ksh321.songrecord

import android.app.Activity
import android.content.Intent
import com.ksh321.songrecord.recorder.RecorderAccount
import com.ksh321.songrecord.recorder.RecorderPaths
import com.ksh321.songrecord.recorder.RecorderService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Only a newly created SAF document receives a bounded, verified current-account copy. */
internal class AudioExportBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private var scope: String? = null
    private var size = 0L
    private var checksum = ""
    private var writing = false
    private var closed = false
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "export") { result.notImplemented(); return }
        try {
            check(!closed && pending == null && !RecorderAccount.exporting && !RecorderService.isCapturing())
            val user = requireNotNull(call.argument<String>("userId"))
            val id = requireNotNull(call.argument<String>("recordingId"))
            val env = requireNotNull(call.argument<String>("environment"))
            require(UUID.fromString(user).toString() == user && UUID.fromString(id).toString() == id)
            check(RecorderAccount.scope == "$env/$user")
            val expected = RecorderPaths.child(activity.filesDir, "song_record/$env/accounts/$user/audio/$id.m4a")
            val path = requireNotNull(call.argument<String>("path"))
            check(RecorderPaths.contains(activity.filesDir, expected.parentFile!!, path) && File(path).canonicalFile == expected)
            val count = requireNotNull(call.argument<Number>("size")).toLong()
            val hash = requireNotNull(call.argument<String>("checksum"))
            require(count in 1L..6291456L && hash.matches(Regex("[a-f0-9]{64}")))
            check(expected.isFile && expected.length() == count)
            val filename = requireNotNull(call.argument<String>("filename"))
            require(filename.endsWith(".m4a") && filename.length <= 180 && filename.none { it.code < 32 || it.code == 127 || it in "/\\:*?\"<>|" })
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE); type = "audio/mp4"; putExtra(Intent.EXTRA_TITLE, filename)
            }
            pending = result; source = expected; scope = RecorderAccount.scope; size = count; checksum = hash
            RecorderAccount.exporting = true
            try { activity.startActivityForResult(intent, REQUEST) }
            catch (_: Exception) { finish(false, true) }
        } catch (_: Exception) { result.error("EXPORT_UNAVAILABLE", "내보낼 파일과 계정 상태를 확인해 주세요.", null) }
    }
    fun onResult(request: Int, code: Int, data: Intent?) {
        if (request != REQUEST || pending == null) return
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { finish(false); return }
        if (uri.scheme != "content") { finish(false, true); return }
        writing = true
        Thread {
            var failed = true
            try {
                check(!closed && RecorderAccount.scope == scope)
                val file = checkNotNull(source)
                check(file.canonicalFile == file && file.isFile && file.length() == size)
                // Buffer the whole bounded source before writing: never mix a changed file into the export.
                val bytes = file.inputStream().use { input ->
                    val buffer = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(65536)
                    while (true) { val n = input.read(chunk); if (n < 0) break; check(buffer.size() + n <= size); buffer.write(chunk, 0, n) }
                    buffer.toByteArray()
                }
                check(bytes.size.toLong() == size)
                val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                check(hash == checksum && !closed && RecorderAccount.scope == scope)
                // Reject populated/unknown-size destinations even if a provider offers overwrite.
                activity.contentResolver.openFileDescriptor(uri, "rw").use { descriptor ->
                    val fd = checkNotNull(descriptor)
                    check(fd.statSize == 0L)
                    android.os.ParcelFileDescriptor.AutoCloseOutputStream(fd).use { it.write(bytes); it.flush() }
                }
                val copied = activity.contentResolver.openInputStream(uri).use { input ->
                    val digest = MessageDigest.getInstance("SHA-256")
                    val stream = checkNotNull(input); val chunk = ByteArray(65536); var total = 0L
                    while (true) { val n = stream.read(chunk); if (n < 0) break; total += n; check(total <= size); digest.update(chunk, 0, n) }
                    check(total == size); digest.digest().joinToString("") { "%02x".format(it) }
                }
                check(copied == checksum)
                failed = false
            } catch (_: Exception) {
                // Do not delete a user/provider URI. Explain that a failed copy may remain.
            } finally { activity.runOnUiThread { writing = false; finish(!failed, failed) } }
        }.start()
    }
    private fun finish(saved: Boolean, failed: Boolean = false) {
        val callback = pending ?: return; pending = null; source = null; scope = null
        RecorderAccount.exporting = false
        if (failed) callback?.error("EXPORT_FAILED", "파일 저장을 완료하지 못했어요. 저장 위치에 미완성 사본이 있을 수 있습니다.", null)
        else callback?.success(saved)
    }
    fun close() { closed = true; if (!writing) finish(false) }
    companion object { private const val REQUEST = 24146 }
}
