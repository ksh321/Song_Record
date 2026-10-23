package com.ksh321.songrecord

import android.media.MediaDataSource

/** A separate cursor-free view per decoder/player over the same verified bytes. */
internal class PlaybackMemorySource(private val bytes: ByteArray) : MediaDataSource() {
    override fun getSize(): Long = bytes.size.toLong()
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        require(position >= 0 && offset >= 0 && size >= 0 && offset <= buffer.size - size)
        if (size == 0) return 0
        if (position >= bytes.size) return -1
        val count = minOf(size.toLong(), bytes.size.toLong() - position).toInt()
        bytes.copyInto(buffer, offset, position.toInt(), position.toInt() + count)
        return count
    }
    override fun close() {} // No shared cursor or file; caller releases its reference.
}
