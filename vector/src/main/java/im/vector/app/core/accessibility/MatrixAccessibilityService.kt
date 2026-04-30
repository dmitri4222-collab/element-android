package im.vector.app.core.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import timber.log.Timber

class MatrixAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        Timber.i("## Accessibility: service connected, process is alive")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // не обрабатываем события — нам нужно только существовать
    }

    override fun onInterrupt() {
        Timber.i("## Accessibility: service interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Timber.i("## Accessibility: service unbound")
        return super.onUnbind(intent)
    }
}
