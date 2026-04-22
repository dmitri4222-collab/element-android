/*
 * Copyright 2022-2024 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
 * Please see LICENSE files in the repository root for full details.
 */
package im.vector.app.features.debug.di

import android.content.Context
import android.content.Intent
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import im.vector.app.core.debug.DebugNavigator
import im.vector.app.core.debug.DebugReceiver
import im.vector.app.core.debug.LeakDetector
import im.vector.app.features.debug.DebugMenuActivity
import im.vector.app.receivers.VectorDebugReceiver
import javax.inject.Inject

@InstallIn(SingletonComponent::class)
@Module
abstract class DebugModule {

    companion object {
        @Provides
        fun providesDebugNavigator() = object : DebugNavigator {
            override fun openDebugMenu(context: Context) {
                context.startActivity(Intent(context, DebugMenuActivity::class.java))
            }
        }

        @Provides
        fun providesLeakDetector(): LeakDetector = object : LeakDetector {
            override fun enable(enable: Boolean) = Unit
        }
    }

    @Binds
    abstract fun bindsDebugReceiver(receiver: VectorDebugReceiver): DebugReceiver
}
