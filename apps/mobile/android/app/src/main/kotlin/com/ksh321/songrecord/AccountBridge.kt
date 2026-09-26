package com.ksh321.songrecord

import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import com.ksh321.songrecord.recorder.RecorderAccount
import com.ksh321.songrecord.recorder.RecorderPaths
import com.ksh321.songrecord.recorder.RecorderService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Local recovery export only. P21/P22 define the portable backup/import contract. */
internal class AccountBridge(private val activity: Activity, private val stopPlayback: () -> Unit) {
    private var pending: MethodChannel.Result? = null
    private var payload: String? = null
    private var owner: String? = null
    private var writing = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "setAccount" -> {
                    RecorderAccount.select(activity, call.argument("userId"), call.argument("environment"))
                    stopPlayback()
                    result.success(null)
                }
                "prepareLogout" -> {
                    check(!RecorderService.isCapturing()) { "녹음을 완료한 뒤 로그아웃해 주세요." }
                    check(!RecorderAccount.exporting) { "백업을 마친 뒤 로그아웃해 주세요." }
                    result.success(null)
                }
                "exportRecovery" -> {
                    check(pending == null && !RecorderAccount.exporting)
                    check(!RecorderService.isCapturing()) { "녹음을 완료한 뒤 백업해 주세요." }
                    val scope = RecorderAccount.requireScope()
                    val data = requireNotNull(call.argument<String>("data"))
                    val json = JSONObject(data)
                    check(scope == "${json.getString("environment")}/${json.getString("source_user_id")}")
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        putExtra(Intent.EXTRA_TITLE, "SongRecord-recovery-${System.currentTimeMillis()}.zip")
                    }
                    pending = result; payload = data; owner = scope
                    RecorderAccount.exporting = true
                    try { activity.startActivityForResult(intent, REQUEST) }
                    catch (_: Exception) {
                        val callback = pending; finish(null)
                        callback?.error("BACKUP_FAILED", "파일 저장 화면을 열지 못했어요.", null)
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("ACCOUNT_ACTION_FAILED", "녹음이나 백업을 완료하고 다시 시도해 주세요. 계정 상태도 확인해 주세요.", null)
        }
    }

    fun onResult(request: Int, code: Int, data: Intent?) {
        if (request != REQUEST || pending == null) return
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { finish(false); return }
        val snapshot = payload ?: run { finish(false); return }
        val scope = owner ?: run { finish(false); return }
        writing = true
        Thread {
            try {
                check(RecorderAccount.scope == scope && !RecorderService.isCapturing())
                val entries = JSONArray()
                val output = activity.contentResolver.openOutputStream(uri, "w") ?: error("No output")
                ZipOutputStream(output.buffered()).use { zip ->
                    fun addBytes(name: String, bytes: ByteArray) {
                        zip.putNextEntry(ZipEntry(name)); zip.write(bytes); zip.closeEntry()
                    }
                    addBytes("data.json", snapshot.toByteArray(Charsets.UTF_8))
                    val (environment, user) = scope.split('/')
                    val roots = listOf(
                        "native" to RecorderAccount.directory(activity),
                        "local/audio" to RecorderPaths.child(activity.filesDir, "song_record/$environment/accounts/$user/audio"),
                        "local/pending" to RecorderPaths.child(activity.filesDir, "song_record/$environment/accounts/$user/pending"),
                    )
                    for ((prefix, root) in roots) {
                        if (!root.exists()) continue
                        check(root.canonicalFile == root.absoluteFile)
                        for (file in root.walkTopDown().onEnter { directory ->
                            check(directory.canonicalFile == directory.absoluteFile); true
                        }) {
                            check(file.canonicalFile == file.absoluteFile)
                            if (!file.isFile) continue
                            check(file.canonicalPath.startsWith(root.canonicalPath + File.separator))
                            val relative = file.relativeTo(root).invariantSeparatorsPath
                            val name = "$prefix/$relative"
                            val digest = MessageDigest.getInstance("SHA-256")
                            var total = 0L
                            zip.putNextEntry(ZipEntry(name))
                            file.inputStream().use { input ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read < 0) break
                                    zip.write(buffer, 0, read); digest.update(buffer, 0, read); total += read
                                }
                            }
                            zip.closeEntry()
                            entries.put(JSONObject().put("path", name).put("bytes", total)
                                .put("sha256", digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) })
                                .put("kind", if (name.contains("pending")) "unfinished" else "local_file"))
                        }
                    }
                    // Only this account's journal; remove absolute device paths.
                    val journal = JSONObject()
                    for ((key, value) in activity.getSharedPreferences(RecorderAccount.journalName(), 0).all) {
                        if (key != "pending_path" && key != "final_path" && key != "error_message") journal.put(key, value)
                    }
                    addBytes("recorder-journal.json", journal.toString().toByteArray(Charsets.UTF_8))
                    val manifest = JSONObject().put("format", "song-record-local-recovery").put("version", 1)
                        .put("source_user_id", user).put("environment", environment)
                        .put("export_id", UUID.randomUUID().toString()).put("files", entries)
                        .put("scope", "Local data only. No server files, legacy unowned recordings or import archives. Not P21 portable backup.")
                    addBytes("manifest.json", manifest.toString(2).toByteArray(Charsets.UTF_8))
                }
                activity.runOnUiThread { finish(true) }
            } catch (_: Exception) {
                try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) { }
                activity.runOnUiThread {
                    val callback = pending
                    finish(null)
                    callback?.error("BACKUP_FAILED", "복구 파일을 저장하지 못했어요. 원본은 유지돼요. 저장 위치에 불완전한 파일이 남았는지 확인해 주세요.", null)
                }
            }
        }.start()
    }
    private fun finish(success: Boolean?) {
        val callback = pending
        pending = null; payload = null; owner = null; writing = false
        RecorderAccount.exporting = false
        if (success != null) callback?.success(success)
    }
    fun close() {
        pending?.error("BACKUP_CANCELLED", "화면이 종료됐어요. 저장 결과를 확인해 주세요.", null)
        pending = null
        if (!writing) finish(null)
    }
    companion object { private const val REQUEST = 2108 }
}
