package com.ksh321.songrecord

import android.app.Activity
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** One nonce per interactive request; does not reinitialize the Google Flutter singleton. */
class IdentityLinkBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "googleProof") { result.notImplemented(); return }
        if (pending != null) { result.error("BUSY", "Authentication in progress", null); return }
        val clientId = call.argument<String>("clientId")
        val nonce = call.argument<String>("nonce")
        if (clientId.isNullOrBlank() || nonce == null || !nonce.matches(Regex("[A-Za-z0-9_-]{43}"))) {
            result.error("INVALID", "Invalid authentication request", null); return
        }
        pending = result
        val signal = CancellationSignal()
        cancellation = signal
        try {
            val option = GetSignInWithGoogleOption.Builder(clientId).setNonce(nonce).build()
            val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
            CredentialManager.create(activity).getCredentialAsync(activity, request, signal,
                ContextCompat.getMainExecutor(activity),
                object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                    override fun onResult(response: GetCredentialResponse) {
                        val callback = pending ?: return
                        pending = null
                        cancellation = null
                        try {
                            val credential = response.credential
                            if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                                callback.error("FAILED", "Unexpected credential", null); return
                            }
                            callback.success(GoogleIdTokenCredential.createFrom(credential.data).idToken)
                        } catch (_: Exception) { callback.error("FAILED", "Authentication failed", null) }
                    }
                    override fun onError(e: GetCredentialException) {
                        val callback = pending ?: return
                        pending = null
                        cancellation = null
                        callback.error(if (e is GetCredentialCancellationException) "CANCELED" else "FAILED", "Authentication ended", null)
                    }
                })
        } catch (_: Exception) {
            pending = null
            cancellation = null
            result.error("FAILED", "Authentication failed", null)
        }
    }
    fun close() {
        val callback = pending
        pending = null
        cancellation?.cancel()
        cancellation = null
        callback?.error("CANCELED", "Activity closed", null)
    }
}
