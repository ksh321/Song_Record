package com.ksh321.songrecord

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.io.File

/** Read-only full decode of the bounded app-private staged file. */
internal object ImportAudioInspector {
    fun inspect(file: File, collectWaveform: Boolean = false,
                cancelled: () -> Boolean = { false }): Map<String, Any?> =
        inspectSource({ it.setDataSource(file.path) }, collectWaveform, cancelled)

    fun waveform(bytes: ByteArray, cancelled: () -> Boolean): Map<String, Any?> =
        inspectSource({ it.setDataSource(PlaybackMemorySource(bytes)) }, true, cancelled)

    private fun inspectSource(source: (MediaExtractor) -> Unit, collectWaveform: Boolean,
                              cancelled: () -> Boolean): Map<String, Any?> {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            source(extractor)
            require(extractor.trackCount == 1)
            val format = extractor.getTrackFormat(0)
            val mime = format.getString(MediaFormat.KEY_MIME)
            val profile = format.getInteger(MediaFormat.KEY_AAC_PROFILE)
            val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val duration = format.getLong(MediaFormat.KEY_DURATION) / 1000L
            require(mime == "audio/mp4a-latm" && profile == 2 && sampleRate == 48000 && channels == 1)
            require(duration in 1..361000L)
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT)
            extractor.selectTrack(0)
            val codec = MediaCodec.createDecoderByType(mime!!)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val deadline = SystemClock.elapsedRealtime() + 30000L
            val info = MediaCodec.BufferInfo()
            var inputEnd = false
            var outputEnd = false
            var decoded = 0L
            val peaks = DoubleArray(120)
            while (!outputEnd) {
                require(SystemClock.elapsedRealtime() < deadline && !cancelled())
                if (!inputEnd) {
                    val index = codec.dequeueInputBuffer(10000L)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index) ?: error("Missing input buffer")
                        buffer.clear()
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnd = true
                        } else {
                            codec.queueInputBuffer(index, 0, count, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 10000L)
                if (index >= 0) {
                    if (collectWaveform && info.size > 0) {
                        val pcm = requireNotNull(codec.getOutputBuffer(index)).duplicate()
                            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                        pcm.position(info.offset); pcm.limit(info.offset + info.size)
                        var sample = decoded / 2
                        val total = (duration * 48).coerceAtLeast(1)
                        while (pcm.remaining() >= 2) {
                            val bin = ((sample++ * peaks.size) / total).toInt().coerceIn(0, peaks.lastIndex)
                            peaks[bin] = maxOf(peaks[bin], kotlin.math.abs(pcm.short.toInt()) / 32768.0)
                        }
                    }
                    decoded += info.size
                    require(decoded <= 362L * 48000 * 2)
                    outputEnd = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                    codec.releaseOutputBuffer(index, false)
                } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val actual = codec.outputFormat
                    require(actual.getInteger(MediaFormat.KEY_SAMPLE_RATE) == 48000 && actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1)
                    require(!actual.containsKey(MediaFormat.KEY_PCM_ENCODING) ||
                        actual.getInteger(MediaFormat.KEY_PCM_ENCODING) == android.media.AudioFormat.ENCODING_PCM_16BIT)
                }
            }
            require(decoded > 0)
            val decodedDuration = decoded * 1000L / (48000L * 2)
            require(decodedDuration in 1..361000L && kotlin.math.abs(decodedDuration - duration) <= 250L)
            return mapOf("mime" to mime, "aac_profile" to profile, "sample_rate" to sampleRate,
                "channels" to channels, "duration_ms" to decodedDuration) +
                (if (collectWaveform) mapOf("waveform" to peaks.toList()) else emptyMap())
        } finally {
            try { decoder?.release() } finally { extractor.release() }
        }
    }
}
