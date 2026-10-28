package com.ksh321.songrecord

import android.content.Context
import com.ksh321.songrecord.recorder.RecorderAccount
import com.ksh321.songrecord.recorder.RecorderPaths
import com.ksh321.songrecord.recorder.RecorderFileTools
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Small derived peaks stay inside the owner's existing removable account tree.
 * Audio bytes, identifiers from another account, and unverified cache contents
 * are never accepted as a playable source. */
internal object PlaybackWaveforms {
    private val worker=Executors.newSingleThreadExecutor()
    @Volatile private var warmGeneration=0
    private fun file(context: Context, owner: String, checksum: String): File {
        val parts=owner.split('/')
        require(parts.size==2 && parts[0] in setOf("dev","staging","prod"))
        require(UUID.fromString(parts[1]).toString()==parts[1])
        require(checksum.matches(Regex("[0-9a-f]{64}")))
        return RecorderPaths.child(context.filesDir,
            "song_record/${parts[0]}/accounts/${parts[1]}/waveforms/$checksum.wave")
    }
    fun obtain(context: Context, owner: String, checksum: String,
               cancelled: () -> Boolean, decode: () -> Map<String,Any?>): List<Double> {
        fun guard(){check(!cancelled() && RecorderAccount.scope==owner)}
        guard()
        val target=file(context,owner,checksum)
        val cached=runCatching {
            require(target.isFile && target.length()==488L)
            DataInputStream(target.inputStream().buffered()).use { input ->
                require(input.readInt()==0x53525731 && input.readInt()==120)
                List(120){input.readFloat().toDouble().also { require(it.isFinite() && it in 0.0..1.0) }}
            }
        }.getOrNull()
        if(cached!=null){guard();return cached}
        val values=requireNotNull(decode()["waveform"] as? List<*>)
        require(values.size==120)
        val peaks=values.map{(it as Number).toDouble().also{v->require(v.isFinite() && v in 0.0..1.0)}}
        guard()
        // Cache failure does not discard successfully prepared peaks.
        runCatching {
            target.parentFile!!.mkdirs()
            val temporary=file(context,owner,checksum).let{File(it.parentFile,it.name+".${UUID.randomUUID()}.tmp")}
            try {
                DataOutputStream(temporary.outputStream().buffered()).use { out ->
                    out.writeInt(0x53525731);out.writeInt(120);peaks.forEach{out.writeFloat(it.toFloat())}
                }
                guard()
                check(target.canonicalFile==target.absoluteFile)
                check(temporary.renameTo(target))
            } finally {temporary.delete()}
        }
        guard();return peaks
    }
    fun prepareFile(context: Context, owner: String, source: File, checksum: String) {
        val app=context.applicationContext
        worker.execute {runCatching {
            obtain(app,owner,checksum,{RecorderAccount.scope!=owner}) {
                ImportAudioInspector.inspect(source,true){RecorderAccount.scope!=owner}
            }
        }}
    }
    fun warmAccount(context: Context) {
        val epoch=++warmGeneration
        val owner=RecorderAccount.scope?:return
        val app=context.applicationContext
        worker.execute {runCatching {
            val (environment,user)=owner.split('/')
            val roots=listOf(
                RecorderPaths.child(app.filesDir,"song_record/$environment/accounts/$user/audio"),
                RecorderPaths.child(app.filesDir,"recordings/accounts/$owner"))
            for(root in roots) for(source in root.listFiles().orEmpty().sortedByDescending{it.lastModified()}) {
                if(epoch!=warmGeneration || RecorderAccount.scope!=owner)return@execute
                if(!source.name.matches(Regex("[0-9a-f-]{36}\\.m4a")) ||
                   source.canonicalFile!=source.absoluteFile || !source.isFile || source.length() !in 1L..6291456L)continue
                val checksum=RecorderFileTools.sha256(source)
                runCatching {obtain(app,owner,checksum,{epoch!=warmGeneration || RecorderAccount.scope!=owner}) {
                    ImportAudioInspector.inspect(source,true){epoch!=warmGeneration || RecorderAccount.scope!=owner}
                }}
            }
        }}
    }
}
