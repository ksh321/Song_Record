package com.ksh321.songrecord.recorder

import java.io.File

/** Android may provide a filesDir alias. Resolve that trusted root once, then
 * reject traversal and symlinks in every app-managed descendant. */
internal object RecorderPaths {
    fun child(filesDir: File, relative: String): File {
        require(relative.isNotEmpty() && !File(relative).isAbsolute)
        require(relative.split('/').none { it.isEmpty() || it == "." || it == ".." })
        val base = filesDir.canonicalFile
        val child = File(base, relative).absoluteFile
        check(child.canonicalFile == child) { "Unsafe account storage path" }
        return child
    }

    fun contains(filesDir: File, root: File, path: String): Boolean {
        val supplied = File(path).absoluteFile
        val aliasPrefix = filesDir.absolutePath + File.separator
        val mapped = if (supplied.path.startsWith(aliasPrefix)) {
            File(filesDir.canonicalFile, supplied.path.removePrefix(aliasPrefix))
        } else supplied
        return mapped.canonicalFile == mapped &&
            mapped.path.startsWith(root.path + File.separator)
    }
}
