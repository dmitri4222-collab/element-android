/*
 * Copyright 2021-2024 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
 * Please see LICENSE files in the repository root for full details.
 */
package im.vector.app.fdroid.service

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import im.vector.app.core.services.GuardServiceStarter
import im.vector.app.core.services.VectorSyncAndroidService
import im.vector.app.features.settings.BackgroundSyncMode
import im.vector.app.features.settings.VectorPreferences
import org.matrix.android.sdk.api.Matrix
import timber.log.Timber
import javax.inject.Inject

class FDroidGuardServiceStarter @Inject constructor(
        private val preferences: VectorPreferences,
        private val appContext: Context,
        private val matrix: Matrix
) : GuardServiceStarter {

    override fun start() {
        try {
            Timber.i("## Sync: starting GuardService")
            // Start no-op foreground service to prevent process kill
            val guardIntent = Intent(appContext, GuardAndroidService::class.java)
            ContextCompat.startForegroundService(appContext, guardIntent)

            // Start sync service if background sync is enabled
            if (preferences.isBackgroundSyncEnabled()) {
                val session = matrix.authenticationService().getLastAuthenticatedSession() ?: return
                val syncIntent = VectorSyncAndroidService.newPeriodicIntent(
                    context = appContext,
                    sessionId = session.sessionId,
                    syncTimeoutSeconds = preferences.backgroundSyncTimeOut(),
                    syncDelaySeconds = preferences.backgroundSyncDelay(),
                    isNetworkBack = false
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appContext.startForegroundService(syncIntent)
                } else {
                    appContext.startService(syncIntent)
                }
            }
        } catch (ex: Throwable) {
            Timber.e(ex, "## Sync: ERROR starting services")
        }
    }

    override fun stop() {
        val guardIntent = Intent(appContext, GuardAndroidService::class.java)
        appContext.stopService(guardIntent)

        val syncIntent = VectorSyncAndroidService.stopIntent(appContext)
        appContext.startService(syncIntent)
    }
}
