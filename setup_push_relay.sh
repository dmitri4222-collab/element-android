#!/bin/bash

#==============================================================================
# Setup Push Relay Branch
# Создаёт ветку, копирует изменённые файлы, делает коммиты
#==============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- ПЕРЕМЕННЫЕ ---
REPO_DIR="${1:-$(pwd)}"
BRANCH="feature/built-in-push-relay"

# Проверяем что мы в репозитории
if [ ! -f "$REPO_DIR/settings.gradle" ]; then
    print_error "Не найден settings.gradle. Укажите путь к репозиторию:"
    print_error "  ./setup_push_relay.sh /path/to/element-android"
    exit 1
fi

cd "$REPO_DIR"
print_info "Репозиторий: $REPO_DIR"

# Проверяем git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Не git репозиторий"
    exit 1
fi

#==============================================================================
# 1. СОЗДАНИЕ ВЕТКИ
#==============================================================================

print_info "Переключаемся на develop..."
git checkout develop
git pull origin develop 2>/dev/null || print_warn "Не удалось подтянуть develop, продолжаем"

# Удалить ветку если уже существует
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    print_warn "Ветка $BRANCH уже существует, удаляем..."
    git branch -D "$BRANCH"
fi

print_info "Создаём ветку $BRANCH..."
git checkout -b "$BRANCH"

#==============================================================================
# 2. ПУТИ К ФАЙЛАМ
#==============================================================================

PUSHERS_MANAGER="vector/src/main/java/im/vector/app/core/pushers/PushersManager.kt"
UNIFIED_PUSH_HELPER="vector/src/main/java/im/vector/app/core/pushers/UnifiedPushHelper.kt"
PUSH_RELAY_SERVICE="vector/src/main/java/im/vector/app/core/pushers/PushRelayService.kt"
PUSH_RELAY_BOOT_RECEIVER="vector/src/main/java/im/vector/app/core/pushers/PushRelayBootReceiver.kt"
CONFIG="vector-config/src/main/java/im/vector/app/config/Config.kt"
VECTOR_APPLICATION="vector-app/src/main/java/im/vector/app/VectorApplication.kt"
HOME_ACTIVITY="vector/src/main/java/im/vector/app/features/home/HomeActivity.kt"
MANIFEST_FDROID="vector/src/fdroid/AndroidManifest.xml"
MANIFEST_MAIN="vector/src/main/AndroidManifest.xml"

#==============================================================================
# 3. КОММИТ 1 — PushersManager.kt
#==============================================================================

print_info "Коммит 1/7: PushersManager.kt"

cat > "$PUSHERS_MANAGER" << 'KOTLIN'
/*
 * Copyright 2019-2024 New Vector Ltd.
 *
 * SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
 * Please see LICENSE files in the repository root for full details.
 */

package im.vector.app.core.pushers

import im.vector.app.core.device.GetDeviceInfoUseCase
import im.vector.app.core.di.ActiveSessionHolder
import im.vector.app.core.resources.AppNameProvider
import im.vector.app.core.resources.LocaleProvider
import im.vector.app.core.resources.StringProvider
import im.vector.app.features.mdm.MdmData
import im.vector.app.features.mdm.MdmService
import org.matrix.android.sdk.api.session.pushers.HttpPusher
import org.matrix.android.sdk.api.session.pushers.Pusher
import java.net.URL
import java.util.UUID
import javax.inject.Inject
import kotlin.math.abs

internal const val DEFAULT_PUSHER_FILE_TAG = "mobile"

class PushersManager @Inject constructor(
        private val unifiedPushHelper: UnifiedPushHelper,
        private val activeSessionHolder: ActiveSessionHolder,
        private val localeProvider: LocaleProvider,
        private val stringProvider: StringProvider,
        private val appNameProvider: AppNameProvider,
        private val getDeviceInfoUseCase: GetDeviceInfoUseCase,
        private val mdmService: MdmService,
) {
    suspend fun testPush() {
        val currentSession = activeSessionHolder.getActiveSession()

        currentSession.pushersService().testPush(
                unifiedPushHelper.getPushGateway() ?: return,
                stringProvider.getString(im.vector.app.config.R.string.pusher_app_id),
                unifiedPushHelper.getEndpointOrToken().orEmpty(),
                TEST_EVENT_ID
        )
    }

    suspend fun enqueueRegisterPusherWithFcmKey(pushKey: String): UUID {
        return enqueueRegisterPusher(
                pushKey = pushKey,
                gateway = mdmService.getData(MdmData.DefaultPushGatewayUrl, stringProvider.getString(im.vector.app.config.R.string.pusher_http_url))
        )
    }

    /**
     * Регистрирует pusher для встроенного push relay.
     * Gateway URL строится динамически из homeserver URL пользователя:
     * https://matrix.company.org → https://matrix.company.org/push
     */
    suspend fun enqueueRegisterPusherWithRelayKey(pushKey: String, homeServerUrl: String): UUID {
        val parsed = URL(homeServerUrl)
        val gateway = "${parsed.protocol}://${parsed.host}/push"
        return enqueueRegisterPusher(pushKey = pushKey, gateway = gateway)
    }

    suspend fun enqueueRegisterPusher(
            pushKey: String,
            gateway: String
    ): UUID {
        val currentSession = activeSessionHolder.getActiveSession()
        val pusher = createHttpPusher(pushKey, gateway)
        return currentSession.pushersService().enqueueAddHttpPusher(pusher)
    }

    private suspend fun createHttpPusher(
            pushKey: String,
            gateway: String
    ) = HttpPusher(
            pushkey = pushKey,
            appId = stringProvider.getString(im.vector.app.config.R.string.pusher_app_id),
            profileTag = DEFAULT_PUSHER_FILE_TAG + "_" + abs(activeSessionHolder.getActiveSession().myUserId.hashCode()),
            lang = localeProvider.current().language,
            appDisplayName = appNameProvider.getAppName(),
            deviceDisplayName = getDeviceInfoUseCase.execute().displayName().orEmpty(),
            url = gateway,
            enabled = true,
            deviceId = activeSessionHolder.getActiveSession().sessionParams.deviceId,
            append = false,
            withEventIdOnly = true,
    )

    suspend fun registerEmailForPush(email: String) {
        val currentSession = activeSessionHolder.getActiveSession()
        val appName = appNameProvider.getAppName()
        currentSession.pushersService().addEmailPusher(
                email = email,
                lang = localeProvider.current().language,
                emailBranding = appName,
                appDisplayName = appName,
                deviceDisplayName = currentSession.sessionParams.deviceId
        )
    }

    fun getPusherForCurrentSession(): Pusher? {
        val session = activeSessionHolder.getSafeActiveSession() ?: return null
        val deviceId = session.sessionParams.deviceId
        return session.pushersService().getPushers().firstOrNull { it.deviceId == deviceId }
    }

    suspend fun unregisterEmailPusher(email: String) {
        val currentSession = activeSessionHolder.getSafeActiveSession() ?: return
        currentSession.pushersService().removeEmailPusher(email)
    }

    suspend fun unregisterPusher(pushKey: String) {
        val currentSession = activeSessionHolder.getSafeActiveSession() ?: return
        currentSession.pushersService().removeHttpPusher(pushKey, stringProvider.getString(im.vector.app.config.R.string.pusher_app_id))
    }

    companion object {
        const val TEST_EVENT_ID = "\$THIS_IS_A_FAKE_EVENT_ID"
    }
}
KOTLIN

git add "$PUSHERS_MANAGER"
git commit -m "feat: add enqueueRegisterPusherWithRelayKey to PushersManager

Gateway URL строится динамически из homeserver URL пользователя.
https://matrix.company.org -> https://matrix.company.org/push
Поддерживает несколько изолированных серверов."

#==============================================================================
# 4. КОММИТ 2 — UnifiedPushHelper.kt
#==============================================================================

print_info "Коммит 2/7: UnifiedPushHelper.kt"

# Патчим метод storeCustomOrDefaultGateway — заменяем хардкод на динамический URL
python3 << 'PYEOF'
import re

filepath = "vector/src/main/java/im/vector/app/core/pushers/UnifiedPushHelper.kt"

with open(filepath, "r") as f:
    content = f.read()

old = '''    suspend fun storeCustomOrDefaultGateway(
            endpoint: String,
            onDoneRunnable: Runnable? = null
    ) {
        // if we use the embedded distributor,
        // register app_id type upfcm on sygnal
        // the pushkey if FCM key
        if (UnifiedPush.getDistributor(context) == context.packageName) {
            unifiedPushStore.storePushGateway(
                    gateway = mdmService.getData(
                            mdmData = MdmData.DefaultPushGatewayUrl,
                            defaultValue = stringProvider.getString(im.vector.app.config.R.string.pusher_http_url),
                    )
            )
            onDoneRunnable?.run()
            return
        }'''

new = '''    suspend fun storeCustomOrDefaultGateway(
            endpoint: String,
            onDoneRunnable: Runnable? = null
    ) {
        // Встроенный дистрибьютор — используем push relay на том же сервере что и homeserver
        if (UnifiedPush.getDistributor(context) == context.packageName) {
            val homeServerUrl = try {
                matrix.authenticationService()
                        .getLastAuthenticatedSession()
                        ?.sessionParams
                        ?.homeServerUrl
            } catch (e: Exception) {
                Timber.e(e, "Failed to get homeserver URL for push gateway")
                null
            }

            val gateway = if (homeServerUrl != null) {
                val parsed = java.net.URL(homeServerUrl)
                "${parsed.protocol}://${parsed.host}/push"
            } else {
                // fallback на значение из MDM/strings
                mdmService.getData(
                        mdmData = MdmData.DefaultPushGatewayUrl,
                        defaultValue = stringProvider.getString(im.vector.app.config.R.string.pusher_http_url),
                )
            }

            unifiedPushStore.storePushGateway(gateway)
            onDoneRunnable?.run()
            return
        }'''

if old in content:
    content = content.replace(old, new)
    with open(filepath, "w") as f:
        f.write(content)
    print("OK: UnifiedPushHelper patched")
else:
    print("WARN: pattern not found in UnifiedPushHelper, check manually")
PYEOF

git add "$UNIFIED_PUSH_HELPER"
git commit -m "feat: dynamic push gateway URL in UnifiedPushHelper

Вместо хардкода gateway URL берём homeserver URL текущей сессии
и строим gateway как https://{homeserver_host}/push.
Поддерживает несколько изолированных Matrix серверов."

#==============================================================================
# 5. КОММИТ 3 — Config.kt
#==============================================================================

print_info "Коммит 3/7: Config.kt"

python3 << 'PYEOF'
filepath = "vector-config/src/main/java/im/vector/app/config/Config.kt"

with open(filepath, "r") as f:
    content = f.read()

# 1. Отключить внешние дистрибьюторы
content = content.replace(
    "const val ALLOW_EXTERNAL_UNIFIED_PUSH_DISTRIBUTORS = true",
    "const val ALLOW_EXTERNAL_UNIFIED_PUSH_DISTRIBUTORS = false"
)

# 2. Отключить sunset баннер "перейди на Element X"
old_sunset = '''    val sunsetConfig: SunsetConfig = SunsetConfig.Enabled(
            learnMoreLink = "https://element.io/app-for-productivity",
            replacementApplicationName = "Element X",
            replacementApplicationId = "io.element.android.x",
    )'''
new_sunset = "    val sunsetConfig: SunsetConfig = SunsetConfig.Disabled"
content = content.replace(old_sunset, new_sunset)

# 3. Отключить аналитику
old_debug = '''    val DEBUG_ANALYTICS_CONFIG = Analytics.Enabled(
            postHogHost = "https://posthog.element.dev",
            postHogApiKey = "phc_VtA1L35nw3aeAtHIx1ayrGdzGkss7k1xINeXcoIQzXN",
            policyLink = "https://element.io/cookie-policy",
            sentryDSN = "https://f6acc9cfc2024641b28c87ad95e73e66@sentry.tools.element.io/49",
            sentryEnvironment = "DEBUG"
    )'''
content = content.replace(old_debug, "    val DEBUG_ANALYTICS_CONFIG = Analytics.Disabled")

old_release = '''    val RELEASE_ANALYTICS_CONFIG = Analytics.Enabled(
            postHogHost = "https://posthog.element.io",
            postHogApiKey = "phc_Jzsm6DTm6V2705zeU5dcNvQDlonOR68XvX2sh1sEOHO",
            policyLink = "https://element.io/cookie-policy",
            sentryDSN = "https://f6acc9cfc2024641b28c87ad95e73e66@sentry.tools.element.io/49",
            sentryEnvironment = "RELEASE"
    )'''
content = content.replace(old_release, "    val RELEASE_ANALYTICS_CONFIG = Analytics.Disabled")

with open(filepath, "w") as f:
    f.write(content)
print("OK: Config.kt patched")
PYEOF

git add "$CONFIG"
git commit -m "feat: configure app for corporate deployment

- Отключить внешние UnifiedPush дистрибьюторы
- Отключить баннер перехода на Element X
- Отключить аналитику PostHog и Sentry"

#==============================================================================
# 6. КОММИТ 4 — PushRelayService.kt (новый файл)
#==============================================================================

print_info "Коммит 4/7: PushRelayService.kt"

cat > "$PUSH_RELAY_SERVICE" << 'KOTLIN'
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
        val intent = Intent(this, VectorMessagingReceiver::class.java).apply {
            action = ACTION_PUSH_MESSAGE
            putExtra(EXTRA_PUSH_DATA, data)
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
KOTLIN

git add "$PUSH_RELAY_SERVICE"
git commit -m "feat: add PushRelayService for built-in SSE push

Foreground service который держит SSE соединение с push relay
на сервере homeserver. Автоматически переподключается при разрыве.
Доставляет push в VectorMessagingReceiver."

#==============================================================================
# 7. КОММИТ 5 — PushRelayBootReceiver.kt (новый файл)
#==============================================================================

print_info "Коммит 5/7: PushRelayBootReceiver.kt"

cat > "$PUSH_RELAY_BOOT_RECEIVER" << 'KOTLIN'
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
KOTLIN

git add "$PUSH_RELAY_BOOT_RECEIVER"
git commit -m "feat: add PushRelayBootReceiver for autostart after reboot

Стартует PushRelayService после перезагрузки только если
пользователь уже залогинен (device token существует)."

#==============================================================================
# 8. КОММИТ 6 — AndroidManifest.xml
#==============================================================================

print_info "Коммит 6/7: AndroidManifest.xml"

# Определяем какой манифест существует
if [ -f "$MANIFEST_FDROID" ]; then
    MANIFEST="$MANIFEST_FDROID"
elif [ -f "$MANIFEST_MAIN" ]; then
    MANIFEST="$MANIFEST_MAIN"
else
    # Ищем манифест
    MANIFEST=$(find vector -name "AndroidManifest.xml" | head -1)
fi

print_info "Манифест: $MANIFEST"

python3 << PYEOF
import re

filepath = "$MANIFEST"

with open(filepath, "r") as f:
    content = f.read()

# Добавляем permissions перед <application
permissions = """
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
"""

# Добавляем service и receiver перед </application>
components = """
        <!-- Push Relay Service -->
        <service
            android:name=".core.pushers.PushRelayService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />

        <receiver
            android:name=".core.pushers.PushRelayBootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
"""

# Вставляем permissions если ещё нет
if "RECEIVE_BOOT_COMPLETED" not in content:
    content = content.replace(
        "    <application",
        permissions + "    <application",
        1
    )
    print("OK: permissions added")
else:
    print("INFO: permissions already present")

# Вставляем компоненты если ещё нет
if "PushRelayService" not in content:
    content = content.replace(
        "    </application>",
        components + "    </application>",
        1
    )
    print("OK: service and receiver added")
else:
    print("INFO: PushRelayService already present")

with open(filepath, "w") as f:
    f.write(content)
PYEOF

git add "$MANIFEST"
git commit -m "feat: add PushRelayService declarations to AndroidManifest

- RECEIVE_BOOT_COMPLETED permission
- FOREGROUND_SERVICE + FOREGROUND_SERVICE_DATA_SYNC permissions
- REQUEST_IGNORE_BATTERY_OPTIMIZATIONS permission
- PushRelayService с foregroundServiceType=dataSync
- PushRelayBootReceiver для автостарта"

#==============================================================================
# 9. КОММИТ 7 — VectorApplication.kt + HomeActivity.kt
#==============================================================================

print_info "Коммит 7/7: VectorApplication.kt + HomeActivity.kt"

# VectorApplication — добавить генерацию токена
python3 << 'PYEOF'
filepath = "vector-app/src/main/java/im/vector/app/VectorApplication.kt"

with open(filepath, "r") as f:
    content = f.read()

# Добавить импорт UUID если нет
if "import java.util.UUID" not in content:
    content = content.replace(
        "import java.util.Locale",
        "import java.util.Locale\nimport java.util.UUID"
    )

# Добавить генерацию токена перед initMemoryLeakAnalysis()
patch = """
        // Генерация device token для push relay при первом запуске
        val pushPrefs = getSharedPreferences("push_prefs", Context.MODE_PRIVATE)
        if (pushPrefs.getString("device_token", null) == null) {
            pushPrefs.edit()
                    .putString("device_token", UUID.randomUUID().toString())
                    .apply()
        }

        """

old = "        initMemoryLeakAnalysis()"
new = patch + "        initMemoryLeakAnalysis()"

if old in content and "push_prefs" not in content:
    content = content.replace(old, new)
    with open(filepath, "w") as f:
        f.write(content)
    print("OK: VectorApplication.kt patched")
else:
    print("INFO: VectorApplication.kt already patched or pattern not found")
PYEOF

# HomeActivity — добавить запрос батареи и старт сервиса
python3 << 'PYEOF'
filepath = "vector/src/main/java/im/vector/app/features/home/HomeActivity.kt"

with open(filepath, "r") as f:
    content = f.read()

# Добавить импорты
imports_to_add = [
    ("import android.net.Uri", "import android.os.Bundle"),
    ("import android.os.PowerManager", "import android.os.Bundle"),
    ("import android.provider.Settings", "import android.os.Bundle"),
    ("import im.vector.app.core.pushers.PushRelayService", "import im.vector.app.SpaceStateHandler"),
]

for new_import, before in imports_to_add:
    if new_import not in content:
        content = content.replace(before, new_import + "\n" + before)

# Добавить метод requestBatteryOptimizationExclusion перед companion object
battery_method = """
    private fun requestBatteryOptimizationExclusion() {
        val pm = getSystemService(PowerManager::class.java)
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            runCatching {
                startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                )
            }
        }
    }

    """

if "requestBatteryOptimizationExclusion" not in content:
    content = content.replace(
        "    companion object {",
        battery_method + "    companion object {"
    )

# Добавить вызовы в конец onCreate перед закрывающей скобкой
# Ищем последний вызов в onCreate
start_service_patch = """
        // Запрос исключения батареи при первом логине
        val homeArgs = intent.getParcelableExtraCompat<HomeActivityArgs>(Mavericks.KEY_ARG)
        if (homeArgs?.authenticationDescription != null) {
            requestBatteryOptimizationExclusion()
        }

        // Старт встроенного push relay service
        startForegroundService(Intent(this, PushRelayService::class.java))
"""

old_view_started = "        homeActivityViewModel.handle(HomeActivityViewActions.ViewStarted)"
new_view_started = old_view_started + "\n" + start_service_patch

if "PushRelayService" not in content:
    content = content.replace(old_view_started, new_view_started)

with open(filepath, "w") as f:
    f.write(content)
print("OK: HomeActivity.kt patched")
PYEOF

git add "$VECTOR_APPLICATION" "$HOME_ACTIVITY"
git commit -m "feat: init push relay on app start

VectorApplication: генерация UUID device token при первом запуске
HomeActivity: запрос исключения батареи при новом логине,
старт PushRelayService foreground service"

#==============================================================================
# 9.5. КОММИТ 8 — OnboardingViewModel.kt
#==============================================================================

print_info "Коммит 8/8: OnboardingViewModel.kt"

ONBOARDING_VM="vector/src/main/java/im/vector/app/features/onboarding/OnboardingViewModel.kt"

python3 << 'PYEOF'
filepath = "vector/src/main/java/im/vector/app/features/onboarding/OnboardingViewModel.kt"

with open(filepath, "r") as f:
    content = f.read()

# Вставляем сохранение homeserver_url после activeSessionHolder.setActiveSession(session)
old = "        activeSessionHolder.setActiveSession(session)\n\n        authenticationService.reset()"
new = """        activeSessionHolder.setActiveSession(session)

        // Сохраняем homeserver URL для PushRelayService
        // Используется для построения SSE endpoint: https://{host}/sse/{token}
        applicationContext
                .getSharedPreferences("push_prefs", android.content.Context.MODE_PRIVATE)
                .edit()
                .putString("homeserver_url", session.sessionParams.homeServerUrl)
                .apply()

        authenticationService.reset()"""

if old in content and "homeserver_url" not in content:
    content = content.replace(old, new)
    with open(filepath, "w") as f:
        f.write(content)
    print("OK: OnboardingViewModel.kt patched")
elif "homeserver_url" in content:
    print("INFO: OnboardingViewModel.kt already patched")
else:
    print("WARN: pattern not found in OnboardingViewModel.kt, check manually")
PYEOF

git add "$ONBOARDING_VM"
git commit -m "feat: save homeserver URL to push_prefs after login

После успешного логина сохраняем homeserver URL в SharedPreferences.
PushRelayService использует его для построения SSE endpoint:
https://{homeserver_host}/sse/{device_token}

Поддерживает несколько изолированных серверов — каждый пользователь
подключается к relay своего сервера."

#==============================================================================
# 10. PUSH В REMOTE
#==============================================================================

print_info "Пушим ветку в remote..."
git push -u origin "$BRANCH" 2>/dev/null || print_warn "Не удалось запушить, сделайте вручную: git push -u origin $BRANCH"

#==============================================================================
# ИТОГ
#==============================================================================

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Push Relay ветка создана успешно! ✓                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
print_info "Ветка: $BRANCH"
echo ""
echo "Коммиты:"
git log --oneline origin/develop..HEAD
echo ""
echo "Для отката:"
echo "  git checkout develop"
echo ""
echo "Для сборки APK:"
echo "  ./gradlew assembleFdroidDebug"
echo ""
echo "Что сделано:"
echo "  ✓ PushersManager      — динамический gateway URL"
echo "  ✓ UnifiedPushHelper   — убран хардкод"
echo "  ✓ Config              — отключены внешние дистрибьюторы и аналитика"
echo "  ✓ PushRelayService    — SSE foreground service"
echo "  ✓ BootReceiver        — автостарт после перезагрузки"
echo "  ✓ AndroidManifest     — permissions и declarations"
echo "  ✓ VectorApplication   — генерация device token"
echo "  ✓ HomeActivity        — запрос батареи, старт сервиса"
echo "  ✓ OnboardingViewModel — сохранение homeserver URL после логина"
echo ""
