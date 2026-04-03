/*
 * Copyright 2024 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only
 */

package im.vector.app.core.pushers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Стартует PushRelayService после перезагрузки устройства.
 */
class PushRelayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val token = context
                    .getSharedPreferences(PushRelayService.PUSH_PREFS, Context.MODE_PRIVATE)
                    .getString(PushRelayService.DEVICE_TOKEN_KEY, null)

            // Стартуем только если пользователь уже залогинен
            if (token != null) {
                context.startForegroundService(
                        Intent(context, PushRelayService::class.java)
                )
            }
        }
    }
}
