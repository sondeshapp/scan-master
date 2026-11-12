package com.example.scan_master

import android.view.OrientationEventListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var orientationListener: OrientationEventListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "scan_master/device_tilt",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            private var lastHorizontal: Boolean? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                orientationListener?.disable()
                orientationListener = object : OrientationEventListener(this@MainActivity) {
                    override fun onOrientationChanged(orientation: Int) {
                        if (orientation == ORIENTATION_UNKNOWN || events == null) return
                        val isHorizontal =
                            (orientation in 60..120) || (orientation in 240..300)
                        val isVertical =
                            (orientation >= 330 || orientation <= 30) || (orientation in 150..210)
                        if (!isHorizontal && !isVertical) return
                        if (lastHorizontal != isHorizontal) {
                            lastHorizontal = isHorizontal
                            events.success(isHorizontal)
                        }
                    }
                }.also {
                    if (it.canDetectOrientation()) {
                        it.enable()
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                orientationListener?.disable()
                orientationListener = null
                lastHorizontal = null
            }
        })
    }

    override fun onDestroy() {
        orientationListener?.disable()
        orientationListener = null
        super.onDestroy()
    }
}
