package nl.mennovanhout.nspanel_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var proximityListener: SensorEventListener? = null
    private var lightListener: SensorEventListener? = null

    private var pool: SoundPool? = null
    private var tickId = 0
    private var tickReady = false

    private var cpuLock: PowerManager.WakeLock? = null

    private fun loadTick() {
        if (pool != null) return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val p = SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(attrs)
            .build()
        p.setOnLoadCompleteListener { _, _, status ->
            tickReady = status == 0
        }
        val key = io.flutter.FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset("assets/sounds/pop.wav")
        assets.openFd(key).use { fd ->
            tickId = p.load(fd, 1)
        }
        pool = p
    }

    private fun applyFullscreen() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        applyFullscreen()

        window.decorView.setOnSystemUiVisibilityChangeListener {
            applyFullscreen()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyFullscreen()
        }
    }

    private fun sensorStream(
        sensors: SensorManager,
        sensor: Sensor?,
        keep: (SensorEventListener?) -> Unit
    ) = object : EventChannel.StreamHandler {
        override fun onListen(
            arguments: Any?,
            events: EventChannel.EventSink
        ) {
            if (sensor == null) {
                events.error(
                    "no_sensor",
                    "This device has no such sensor",
                    null
                )
                return
            }

            val l = object : SensorEventListener {
                override fun onSensorChanged(e: SensorEvent) {
                    events.success(e.values[0].toDouble())
                }

                override fun onAccuracyChanged(
                    s: Sensor?,
                    a: Int
                ) {}
            }

            keep(l)
            sensors.registerListener(
                l,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
        }

        override fun onCancel(arguments: Any?) {
            keep(null)
        }
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        loadTick()

        val messenger = flutterEngine
            .dartExecutor
            .binaryMessenger

        val sensors =
            getSystemService(Context.SENSOR_SERVICE) as SensorManager

        val proximity =
            sensors.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        val light =
            sensors.getDefaultSensor(Sensor.TYPE_LIGHT)

        val audio =
            getSystemService(Context.AUDIO_SERVICE) as AudioManager

        EventChannel(
            messenger,
            "nl.mennovanhout.nspanel/proximity"
        ).setStreamHandler(
            sensorStream(sensors, proximity) { l ->
                proximityListener?.let {
                    sensors.unregisterListener(it)
                }
                proximityListener = l
            }
        )

        EventChannel(
            messenger,
            "nl.mennovanhout.nspanel/light"
        ).setStreamHandler(
            sensorStream(sensors, light) { l ->
                lightListener?.let {
                    sensors.unregisterListener(it)
                }
                lightListener = l
            }
        )

        MethodChannel(
            messenger,
            "nl.mennovanhout.nspanel/sensors"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "proximityMaxRange" ->
                    result.success(
                        proximity?.maximumRange?.toDouble()
                    )

                "wantsSetup" -> {
                    val wants =
                        intent?.getBooleanExtra("setup", false)
                            ?: false
                    intent?.removeExtra("setup")
                    result.success(wants)
                }

                "androidId" ->
                    result.success(
                        Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID
                        )
                    )

                "wifiRssi" -> {
                    val wifi =
                        applicationContext.getSystemService(
                            Context.WIFI_SERVICE
                        ) as WifiManager
                    result.success(
                        wifi.connectionInfo?.rssi
                    )
                }

                "getBrightness" ->
                    result.success(
                        Settings.System.getInt(
                            contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS,
                            -1
                        )
                    )

                "setBrightness" -> {
                    if (!Settings.System.canWrite(this)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val v =
                        (call.arguments as Int)
                            .coerceIn(0, 255)

                    Settings.System.putInt(
                        contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS_MODE,
                        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
                    )

                    Settings.System.putInt(
                        contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS,
                        v
                    )

                    val lp = window.attributes
                    lp.screenBrightness = v / 255f
                    window.attributes = lp

                    result.success(true)
                }

                "hasVibrator" -> {
                    val v =
                        getSystemService(
                            Context.VIBRATOR_SERVICE
                        ) as? Vibrator
                    result.success(
                        v?.hasVibrator() == true
                    )
                }

                "vibrate" -> {
                    val ms =
                        ((call.arguments as? Int) ?: 15)
                            .toLong()
                            .coerceIn(1, 200)

                    val v =
                        getSystemService(
                            Context.VIBRATOR_SERVICE
                        ) as? Vibrator

                    if (v == null || !v.hasVibrator()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= 26) {
                        v.vibrate(
                            VibrationEffect.createOneShot(
                                ms,
                                VibrationEffect.DEFAULT_AMPLITUDE
                            )
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        v.vibrate(ms)
                    }

                    result.success(true)
                }

                "tick" -> {
                    loadTick()

                    val vol =
                        ((call.arguments as? Double) ?: 0.5)
                            .toFloat()
                            .coerceIn(0f, 1f)

                    if (tickReady) {
                        pool?.play(
                            tickId,
                            vol,
                            vol,
                            1,
                            0,
                            1f
                        )
                    }

                    result.success(tickReady)
                }

                "isInteractive" -> {
                    val pm =
                        getSystemService(
                            Context.POWER_SERVICE
                        ) as PowerManager
                    result.success(pm.isInteractive)
                }

                "wakeScreen" -> {
                    val pm =
                        getSystemService(
                            Context.POWER_SERVICE
                        ) as PowerManager

                    @Suppress("DEPRECATION")
                    val wl = pm.newWakeLock(
                        PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                        "nspanel:wake"
                    )

                    wl.acquire(3000)
                    result.success(true)
                }

                "holdCpu" -> {
                    val on =
                        call.arguments as? Boolean ?: false

                    val pm =
                        getSystemService(
                            Context.POWER_SERVICE
                        ) as PowerManager

                    if (on) {
                        if (cpuLock == null) {
                            cpuLock = pm.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "nspanel:dark"
                            )
                            cpuLock?.acquire()
                        }
                    } else {
                        cpuLock?.let {
                            if (it.isHeld) {
                                it.release()
                            }
                        }
                        cpuLock = null
                    }

                    result.success(true)
                }

                "getVolume" -> {
                    val max =
                        audio.getStreamMaxVolume(
                            AudioManager.STREAM_MUSIC
                        )
                    val cur =
                        audio.getStreamVolume(
                            AudioManager.STREAM_MUSIC
                        )

                    result.success(
                        if (max > 0) cur * 100 / max else 0
                    )
                }

                "setVolume" -> {
                    val max =
                        audio.getStreamMaxVolume(
                            AudioManager.STREAM_MUSIC
                        )

                    val pct =
                        (call.arguments as Int)
                            .coerceIn(0, 100)

                    audio.setStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        Math.round(pct * max / 100f),
                        0
                    )

                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        pool?.release()
        pool = null

        cpuLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        cpuLock = null

        val sensors =
            getSystemService(Context.SENSOR_SERVICE) as SensorManager

        proximityListener?.let {
            sensors.unregisterListener(it)
        }

        lightListener?.let {
            sensors.unregisterListener(it)
        }

        super.onDestroy()
    }
}
