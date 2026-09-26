package com.ksh321.songrecord.recorder

import java.nio.file.Files

/** Standalone JVM regression check; no Android device is required. */
fun main() {
    val temp = Files.createTempDirectory("song-record-path-check").toFile()
    try {
        val actual = temp.resolve("actual/files").apply { mkdirs() }
        val alias = temp.resolve("alias")
        Files.createSymbolicLink(alias.toPath(), actual.toPath())
        check(alias.canonicalFile != alias.absoluteFile)
        val scope = "recordings/accounts/dev/account-a"
        val root = RecorderPaths.child(alias, scope).apply { mkdirs() }
        check(root == actual.resolve(scope))
        val audio = root.resolve("sample.m4a").apply { writeText("synthetic") }
        check(RecorderPaths.contains(alias, root, audio.path))
        check(RecorderPaths.contains(alias, root, alias.resolve("$scope/sample.m4a").path))
        val foreign = RecorderPaths.child(alias, "recordings/accounts/dev/account-b").apply { mkdirs() }
        val otherAudio = foreign.resolve("private.m4a").apply { writeText("synthetic") }
        check(!RecorderPaths.contains(alias, root, otherAudio.path))
        check(runCatching { RecorderPaths.child(alias, "../outside") }.isFailure)
        check(!RecorderPaths.contains(alias, root, root.resolve("../account-b/private.m4a").path))
        val link = root.resolve("linked.m4a")
        Files.createSymbolicLink(link.toPath(), otherAudio.toPath())
        check(!RecorderPaths.contains(alias, root, link.path))
        check(runCatching { RecorderPaths.child(alias, "$scope/linked.m4a") }.isFailure)
        val directoryLink = root.resolve(".pending")
        Files.createSymbolicLink(directoryLink.toPath(), foreign.toPath())
        check(runCatching { RecorderPaths.child(alias, "$scope/.pending") }.isFailure)
        // Remove links before walking the synthetic tree for cleanup.
        Files.delete(directoryLink.toPath())
        Files.delete(link.toPath())
        Files.delete(alias.toPath())
        println("PASS: Android root alias, canonical paths, account isolation, traversal, file/directory symlinks")
    } finally {
        temp.deleteRecursively()
    }
}
