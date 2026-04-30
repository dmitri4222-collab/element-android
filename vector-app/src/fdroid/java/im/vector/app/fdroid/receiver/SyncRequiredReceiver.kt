package im.vector.app.fdroid.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import im.vector.app.core.extensions.singletonEntryPoint
import timber.log.Timber

class SyncRequiredReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "im.vector.app.ACTION_REQUIRE_SYNC") return
        Timber.d("## SyncRequiredReceiver: received, calling requireBackgroundSync")
        val session = context.singletonEntryPoint()
            .activeSessionHolder()
            .getSafeActiveSession() ?: return
        session.syncService().requireBackgroundSync()
    }
}
