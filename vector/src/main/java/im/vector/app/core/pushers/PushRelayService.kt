/*
 * Copyright 2024 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only
 */

package im.vector.app.core.pushers

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import timber.log.Timber
import java.io.IOException
import java.util.concurrent.TimeUnit

class PushRelayService : Service() {

    private val client = OkHttpClient.Builder()
            .readTimeout(0, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()

    private var currentCall: Call? = null
    private var isStopped = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        connectSSE()
        return START_STICKY
    }

    private fun connectSSE() {
        if (isStopped) return

        val token = getSharedPreferences(PUSH_PREFS, Context.MODE_PRIVATE)
                .getString(DEVICE_TOKEN_KEY, null)

        if (token == null) {
            Timber.w("PushRelayService: no device token, retrying later")
            scheduleReconnect()
            return
        }

        // Homeserver URL сохранён при логине
        val homeServerUrl = getSharedPreferences(PUSH_PREFS, Context.MODE_PRIVATE)
                .getString(HOMESERVER_URL_KEY, null)

        if (homeServerUrl == null) {
            Timber.w("PushRelayService: no homeserver URL, retrying later")
            scheduleReconnect()
            return
        }

        val parsed = runCatching { java.net.URL(homeServerUrl) }.getOrNull() ?: run {
            Timber.e("PushRelayService: invalid homeserver URL: $homeServerUrl")
            scheduleReconnect()
            return
        }

        val sseUrl = "${parsed.protocol}://${parsed.host}/sse/$token"
        Timber.d("PushRelayService: connecting to $sseUrl")

        val request = Request.Builder()
                .url(sseUrl)
                .addHeader("Accept", "text/event-stream")
                .addHeader("Cache-Control", "no-cache")
                .build()

        currentCall = client.newCall(request)
        currentCall?.enqueue(object : Callback {
            override fun onResponse(call: Call, response: Response) {
                if (response.code != 200) {
                    Timber.w("PushRelayService: unexpected response code ${response.code}")
                    response.close()
                    scheduleReconnect()
                    return
                }

                try {
                    response.body?.source()?.let { source ->
                        while (!source.exhausted() && !isStopped) {
                            val line = source.readUtf8Line() ?: break
                            when {
                                line.startsWith("data:") -> {
                                    val data = line.removePrefix("data:").trim()
                                    if (data.isNotEmpty() && data != "ping") {
                                        onPushReceived(data)
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (!isStopped) {
                        Timber.e(e, "PushRelayService: SSE stream error")
                    }
                } finally {
                    response.close()
                    if (!isStopped) {
                        scheduleReconnect()
                    }
                }
            }

            override fun onFailure(call: Call, e: IOException) {
                if (!call.isCanceled() && !isStopped) {
                    Timber.e(e, "PushRelayService: connection failed")
                    scheduleReconnect()
                }
            }
        })
    }

   private fun onPushReceived(data: String) {
    Timber.d("PushRelayService: push received")
    val intent = Intent("org.unifiedpush.android.connector.MESSAGE").apply {
        `package` = packageName
        putExtra("message", data.toByteArray())
        putExtra("instance", "default")
    }
    sendBroadcast(intent)
}

    private fun scheduleReconnect() {
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isStopped) connectSSE()
        }, RECONNECT_DELAY_MS)
    }
    
    override fun onDestroy() {
        isStopped = true
        currentCall?.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Push Service",
                    NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Получение push уведомлений"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            getSystemService(NotificationManager::class.java)
                    .createNotificationChannel(channel)
        }
    }

    private fun buildNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Digital Matrix")
            .setContentText("Подключено")
            .setSmallIcon(im.vector.app.R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .setOngoing(true)
            .build()

    companion object {
        const val PUSH_PREFS = "push_prefs"
        const val DEVICE_TOKEN_KEY = "device_token"
        const val HOMESERVER_URL_KEY = "homeserver_url"
        const val ACTION_PUSH_MESSAGE = "im.vector.app.PUSH_MESSAGE"
        const val EXTRA_PUSH_DATA = "push_data"

        private const val NOTIFICATION_ID = 6789
        private const val CHANNEL_ID = "push_relay_service"
        private const val RECONNECT_DELAY_MS = 5_000L
    }
}
