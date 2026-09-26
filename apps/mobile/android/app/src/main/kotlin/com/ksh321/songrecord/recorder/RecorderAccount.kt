package com.ksh321.songrecord.recorder

import android.content.Context
import java.io.File
import java.util.UUID

/** Supplied only after Flutter verifies the server session. Never infer legacy ownership. */
internal object RecorderAccount {
    @Volatile var scope: String? = null
        private set
    @Volatile var exporting = false
    fun select(context: Context, user: String?, environment: String?) {
        check(!exporting) { "백업을 마친 뒤 다시 시도해 주세요." }
        val next = if (user == null) null else {
            require(UUID.fromString(user).toString() == user && user != "00000000-0000-0000-0000-000000000000")
            require(environment in setOf("dev", "staging", "prod"))
            "$environment/$user"
        }
        if (next == scope) return
        check(!RecorderService.isCapturing()) { "녹음을 완료한 뒤 다시 시도해 주세요." }
        scope = next
        RecorderService.resetAccountState(context)
    }
    fun requireScope(): String = checkNotNull(scope) { "로그인이 필요해요." }
    fun directory(context: Context): File {
        return RecorderPaths.child(context.filesDir, "recordings/accounts/${requireScope()}")
    }
    fun contains(context: Context, path: String): Boolean {
        if (scope == null) return false
        return RecorderPaths.contains(context.filesDir, directory(context), path)
    }
    fun journalName(): String = "recorder_recovery_journal_v1_" + requireScope().replace('/', '_')
}
