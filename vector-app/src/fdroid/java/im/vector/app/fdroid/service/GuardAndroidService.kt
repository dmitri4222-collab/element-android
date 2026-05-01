package im.vector.app.fdroid.service

import android.app.ActivityManager
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import dagger.hilt.android.AndroidEntryPoint
import im.vector.app.core.di.ActiveSessionHolder
import im.vector.app.core.services.VectorAndroidService
import im.vector.app.core.services.VectorSyncAndroidService
import im.vector.app.fdroid.BackgroundSyncStarter
import im.vector.app.features.notifications.NotificationUtils
import im.vector.lib.strings.CommonStrings
import timber.log.Timber
import javax.inject.Inject

@AndroidEntryPoint
class GuardAndroidService : VectorAndroidService() {

    @Inject lateinit var notificationUtils: NotificationUtils
    @Inject lateinit var activeSessionHolder: ActiveSessionHolder
    @Inject lateinit var backgroundSyncStarter: BackgroundSyncStarter

    private val handler = Handler(Looper.getMainLooper())
    private var lastSyncServiceStartTime = 0L

    private val syncCheckRunnable = object : Runnable {
        override fun run() {
            checkAndRestartSyncService()
            handler.postDelayed(this, SYNC_CHECK_INTERVAL_MS)
        }
    }

    companion object {
        private const val SYNC_CHECK_INTERVAL_MS = 50_000L
        private const val MIN_RESTART_INTERVAL_MS = 60_000L
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = notificationUtils.buildForegroundServiceNotification(
            CommonStrings.notification_listening_for_notifications, false
        )
        startForeground(NotificationUtils.NOTIFICATION_ID_FOREGROUND_SERVICE, notification)
        handler.removeCallbacks(syncCheckRunnable)
        handler.postDelayed(syncCheckRunnable, SYNC_CHECK_INTERVAL_MS)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(syncCheckRunnable)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        backgroundSyncStarter.start(activeSessionHolder)
        super.onTaskRemoved(rootIntent)
    }

    private fun checkAndRestartSyncService() {
        @Suppress("DEPRECATION")
        val isRunning = getSystemService<ActivityManager>()
            ?.getRunningServices(100)
            ?.any { it.service.className == VectorSyncAndroidService::class.java.name }
            ?: false

        if (!isRunning) {
            val now = System.currentTimeMillis()
            if (now - lastSyncServiceStartTime < MIN_RESTART_INTERVAL_MS) {
                Timber.w("## Guard: Too soon to restart VectorSyncAndroidService, skipping")
                return
            }
            lastSyncServiceStartTime = now
            Timber.w("## Guard: VectorSyncAndroidService dead, restarting")
            activeSessionHolder.getSafeActiveSession()?.sessionId?.let { sessionId ->
                val intent = VectorSyncAndroidService.newPeriodicIntent(
                    context = this,
                    sessionId = sessionId,
                    syncTimeoutSeconds = 6,
                    syncDelaySeconds = 0,
                    isNetworkBack = false
                )
                ContextCompat.startForegroundService(this, intent)
            }
        }
    }
}
