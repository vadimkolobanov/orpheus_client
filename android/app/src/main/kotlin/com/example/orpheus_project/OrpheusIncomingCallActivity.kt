package com.example.orpheus_project

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Полноэкранный incoming UI (как Telegram) для self-managed Telecom calls.
 *
 * Для self-managed Android НЕ обязан показывать системный InCall UI — приложение должно показать своё.
 * Важно: self-managed calls НЕ воспроизводят системный рингтон автоматически — мы делаем это сами.
 */
class OrpheusIncomingCallActivity : Activity() {
    companion object {
        const val EXTRA_CONNECTION_KEY = "connection_key"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val ACTION_CLOSE = "com.example.orpheus_project.ACTION_CLOSE_INCOMING_CALL"
        const val EXTRA_CLOSE_KEY = "close_key"
        private const val TAG = "OrpheusIncomingCall"
    }

    private var connectionKey: String? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var isRinging = false

    private val closeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val key = intent.getStringExtra(EXTRA_CLOSE_KEY)
            if (key != null && key == connectionKey) {
                finishCompat()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_incoming_call)

        connectionKey = intent.getStringExtra(EXTRA_CONNECTION_KEY)
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Входящий звонок"

        Log.i(TAG, "onCreate: connectionKey=$connectionKey, caller=$callerName")

        // Best-effort show on lockscreen + turn screen on.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        // Keep screen on while showing incoming call
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        findViewById<TextView>(R.id.incomingCallerName).text = callerName

        findViewById<Button>(R.id.btnAnswer).setOnClickListener {
            Log.i(TAG, "Answer clicked")
            stopRinging()
            val key = connectionKey ?: return@setOnClickListener
            OrpheusConnectionRegistry.get(key)?.onAnswer()
            finishCompat()
        }

        findViewById<Button>(R.id.btnReject).setOnClickListener {
            Log.i(TAG, "Reject clicked")
            stopRinging()
            val key = connectionKey ?: return@setOnClickListener
            OrpheusConnectionRegistry.get(key)?.onReject()
            finishCompat()
        }

        // Запускаем рингтон и вибрацию
        startRinging()
    }

    private fun startRinging() {
        if (isRinging) return
        isRinging = true

        Log.i(TAG, "Starting ringtone and vibration")

        // 1. Vibration
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            vibrator?.let { vib ->
                // Паттерн вибрации как у телефонного звонка: 0ms delay, 500ms on, 500ms off, repeat
                val pattern = longArrayOf(0, 500, 500, 500, 500)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(pattern, 0)
                }
                Log.i(TAG, "Vibration started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start vibration", e)
        }

        // 2. Ringtone
        try {
            // Пробуем использовать системный рингтон для звонков
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            if (ringtoneUri != null) {
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(this@OrpheusIncomingCallActivity, ringtoneUri)
                    
                    // Используем STREAM_RING для громкости звонка
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        setAudioStreamType(AudioManager.STREAM_RING)
                    }
                    
                    isLooping = true
                    prepare()
                    start()
                }
                Log.i(TAG, "Ringtone started: $ringtoneUri")
            } else {
                Log.w(TAG, "No ringtone URI available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start ringtone", e)
            mediaPlayer?.release()
            mediaPlayer = null
        }
    }

    private fun stopRinging() {
        if (!isRinging) return
        isRinging = false

        Log.i(TAG, "Stopping ringtone and vibration")

        try {
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping vibration", e)
        }

        try {
            mediaPlayer?.let { player ->
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            }
            mediaPlayer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping ringtone", e)
        }
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(ACTION_CLOSE)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(closeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(closeReceiver, filter)
        }
    }

    override fun onStop() {
        super.onStop()
        try {
            unregisterReceiver(closeReceiver)
        } catch (_: Exception) {
        }
    }

    override fun onResume() {
        super.onResume()
        // Если connection уже нет — закрываемся (например, удалённый hang-up).
        val key = connectionKey
        if (key != null && OrpheusConnectionRegistry.get(key) == null) {
            Log.i(TAG, "onResume: connection gone, finishing")
            stopRinging()
            finishCompat()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRinging()
        Log.i(TAG, "onDestroy")
    }

    private fun finishCompat() {
        stopRinging()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
    }
}


