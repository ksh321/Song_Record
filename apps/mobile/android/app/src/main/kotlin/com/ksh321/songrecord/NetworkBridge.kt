package com.ksh321.songrecord

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Connectivity is a scheduling hint, never evidence of authentication. */
class NetworkBridge(context: Context) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    private fun publish() {
        main.post {
            val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
            sink?.success(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        sink = events
        val observer = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publish()
            override fun onLost(network: Network) = publish()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
        }
        callback = observer
        manager.registerDefaultNetworkCallback(observer)
        publish()
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { manager.unregisterNetworkCallback(it) }
        callback = null
        sink = null
    }
}
