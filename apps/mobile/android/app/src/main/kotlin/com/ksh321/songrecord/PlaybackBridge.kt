package com.ksh321.songrecord

import android.app.Activity
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.ksh321.songrecord.recorder.RecorderAccount
import com.ksh321.songrecord.recorder.RecorderPaths
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/** Native player owns no metadata or deletion authority. Never prints source URLs/paths. */
internal class PlaybackBridge(private val activity: Activity) {
    private val handler=Handler(Looper.getMainLooper())
    private val io=Executors.newSingleThreadExecutor()
    var events: EventChannel.EventSink?=null
    private var player: MediaPlayer?=null
    private var pending: MethodChannel.Result?=null
    private var token=0
    private var scope: String?=null
    private var phase="idle"
    private var position=0
    private var duration=0
    private var generation=0
    private val tick=object: Runnable {
        override fun run() {
            if(player==null)return
            if(scope!=RecorderAccount.scope){stop();return}
            emit(phase)
            handler.postDelayed(this,500)
        }
    }
    fun handle(call: MethodCall,result: MethodChannel.Result) {
        try {
            when(call.method) {
                "load" -> load(call,result)
                "stop" -> {stop();result.success(null)}
                "play","pause","seek" -> {
                    check(call.argument<Int>("token")==token && scope==RecorderAccount.scope)
                    val current=checkNotNull(player)
                    check(phase in setOf("paused","playing","completed"))
                    when(call.method) {
                        "play" -> {current.start();emit("playing")}
                        "pause" -> {current.pause();emit("paused")}
                        "seek" -> current.seekTo((call.argument<Int>("position")?:0).coerceIn(0,duration))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {result.error("PLAYBACK_FAILED","재생 상태를 확인해 주세요.",null)}
    }
    private fun load(call: MethodCall,result: MethodChannel.Result) {
        stop(false)
        val owner=requireNotNull(call.argument<String>("userId"))
        val environment=requireNotNull(call.argument<String>("environment"))
        val id=requireNotNull(call.argument<String>("recordingId"))
        require(UUID.fromString(owner).toString()==owner && UUID.fromString(id).toString()==id)
        check(RecorderAccount.scope=="$environment/$owner")
        token=requireNotNull(call.argument<Int>("token"));scope=RecorderAccount.scope
        val currentGeneration=generation
        val kind=call.argument<String>("kind")
        val source=if(kind=="local") requireNotNull(call.argument<String>("path"))
                   else if(kind=="remote")requireNotNull(call.argument<String>("url"))
                   else throw IllegalArgumentException("Invalid source")
        val size=call.argument<Number>("size")?.toLong()
        val checksum=call.argument<String>("sha256")
        val localHttp=((activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE)!=0) && call.argument<Boolean>("allowLocalHttp")==true
        pending=result;phase="loading"
        io.execute {
            try {
                if(kind=="local") {
                    val expected=RecorderPaths.child(activity.filesDir,"song_record/$environment/accounts/$owner/audio/$id.m4a")
                    check(File(source).canonicalFile==expected && File(source).absoluteFile.canonicalFile==File(source).absoluteFile)
                    check(expected.isFile && size!=null && size in 1L..6291456L && expected.length()==size)
                    val digest=MessageDigest.getInstance("SHA-256")
                    var count=0L
                    expected.inputStream().use { input ->
                        val buffer=ByteArray(65536)
                        while(true){val n=input.read(buffer);if(n<0)break;count+=n;check(count<=6291456L);digest.update(buffer,0,n)}
                    }
                    val hash=digest.digest().joinToString(""){"%02x".format(it)}
                    check(count==size && hash==checksum)
                } else {
                    val uri=Uri.parse(source)
                    val local=localHttp && uri.scheme=="http" && uri.host in setOf("localhost","127.0.0.1","10.0.2.2")
                    check(local || (uri.scheme=="https" && uri.host?.endsWith(".r2.cloudflarestorage.com")==true))
                    check(uri.userInfo==null && uri.fragment==null)
                }
                activity.runOnUiThread {
                    if(currentGeneration!=generation)return@runOnUiThread
                    if(scope!=RecorderAccount.scope){fail();return@runOnUiThread}
                    try {
                        val next=MediaPlayer();player=next
                        next.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                        next.setOnPreparedListener {
                            if(player!==it)return@setOnPreparedListener
                            if(scope!=RecorderAccount.scope){fail();return@setOnPreparedListener}
                            duration=it.duration
                            if(duration<1){fail();return@setOnPreparedListener}
                            val callback=pending;pending=null;emit("paused");callback?.success(duration)
                            handler.post(tick)
                        }
                        next.setOnCompletionListener {if(player===it){position=duration;emit("completed")}}
                        next.setOnSeekCompleteListener {if(player===it)emit(phase)}
                        next.setOnErrorListener { failed,_,_ -> if(player===failed)fail();true }
                        next.setDataSource(source);next.prepareAsync()
                    }catch(_:Exception){fail()}
                }
            } catch(_:Exception) {activity.runOnUiThread {if(currentGeneration==generation)fail()}}
        }
        // Bounded preparation: a dead network request cannot leave the UI loading forever.
        handler.postDelayed({if(currentGeneration==generation && pending!=null)fail()},30000)
    }
    private fun emit(next: String) {
        phase=next
        if(next!="failed")try {position=player?.currentPosition?:position}catch(_:Exception){}
        events?.success(mapOf("token" to token,"phase" to phase,"position" to position,"duration" to duration))
    }
    private fun fail() {
        val callback=pending;pending=null
        handler.removeCallbacks(tick);player?.release();player=null
        emit("failed");callback?.error("PLAYBACK_FAILED","파일이나 연결 상태를 확인해 주세요.",null)
    }
    fun stop(notify: Boolean=true) {
        generation++;handler.removeCallbacks(tick)
        val callback=pending;pending=null
        player?.release();player=null
        if(notify && phase!="idle")emit("failed")
        phase="idle";position=0;duration=0;scope=null
        callback?.error("PLAYBACK_SUPERSEDED","재생 요청이 변경됐습니다.",null)
    }
    fun close(){stop();io.shutdownNow();events=null}
}
