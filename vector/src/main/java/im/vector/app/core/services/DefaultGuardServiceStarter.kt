/*
 * Copyright 2024 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
 * Please see LICENSE files in the repository root for full details.
 */

package im.vector.app.core.services

import android.content.Context
import android.os.Build
import im.vector.app.core.di.ActiveSessionHolder
import im.vector.app.features.settings.BackgroundSyncMode
import timber.log.Timber
import javax.inject.Inject

class DefaultGuardServiceStarter @Inject constructor(
    private val context: Context,
    private val activeSessionHolder: ActiveSessionHolder
) : GuardServiceStarter {

    override fun start() {
        Timber.d("## Sync: DefaultGuardServiceStarter.start()")
        val session = activeSessionHolder.getSafeActiveSession() ?: run {
            Timber.w("## Sync: No active session, cannot start sync service")
            return
        }
        val intent = VectorSyncAndroidService.newPeriodicIntent(
            context = context,
            sessionId = session.sessionId,
            syncTimeoutSeconds = BackgroundSyncMode.DEFAULT_SYNC_TIMEOUT_SECONDS,
            syncDelaySeconds = 0,
            isNetworkBack = false
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Timber.d("## Sync: Sync foreground service started")
        } catch (e: Exception) {
            Timber.e(e, "## Sync: Failed to start foreground sync service")
        }
    }

    override fun stop() {
        Timber.d("## Sync: DefaultGuardServiceStarter.stop()")
        val intent = VectorSyncAndroidService.stopIntent(context)
        try {
            context.startService(intent)
            Timber.d("## Sync: Sync foreground service stopped")
        } catch (e: Exception) {
            Timber.e(e, "## Sync: Failed to stop sync service")
        }
    }
}
