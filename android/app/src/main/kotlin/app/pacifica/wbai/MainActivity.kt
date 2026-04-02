package app.pacifica.wbai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    
    companion object {
        private const val CHANNEL = "app.pacifica.wbai/samsung_media_session"
    }

    private fun ensureAudioChannelNoBadge() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channelId = "com.wbaifm.radio.audio" // must match AudioService.init config
                val existing = nm.getNotificationChannel(channelId)
                if (existing != null) {
                    existing.setShowBadge(false)
                    nm.createNotificationChannel(existing) // update channel
                } else {
                    val ch = NotificationChannel(
                        channelId,
                        "WBAI Radio",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "WBAI Radio Audio Playback"
                        setShowBadge(false)
                        lockscreenVisibility = NotificationManager.IMPORTANCE_LOW
                    }
                    nm.createNotificationChannel(ch)
                }
                android.util.Log.d("SAMSUNG_DEBUG", "AudioService channel badge disabled")
            } catch (e: Exception) {
                android.util.Log.e("SAMSUNG_DEBUG", "Failed to adjust channel badge: ${e.message}")
            }
        }
    }
    
    private var mediaSessionManager: SamsungMediaSessionManager? = null
    private var methodChannel: MethodChannel? = null
    private var mediaActionReceiver: BroadcastReceiver? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Create method channel for Samsung MediaSession communication
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Initialize Samsung MediaSession manager
        mediaSessionManager = SamsungMediaSessionManager(this)
        
        // Set up method channel handler
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMetadata" -> {
                    val title = call.argument<String>("title") ?: "WBAI 99.5 FM"
                    val artist = call.argument<String>("artist") ?: "Pacifica Radio"
                    mediaSessionManager?.updateMetadata(title, artist)
                    result.success(null)
                }
                "updatePlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    mediaSessionManager?.updatePlaybackState(isPlaying)
                    result.success(null)
                }
                "showNotification" -> {
                    mediaSessionManager?.showNotification()
                    result.success(null)
                }
                "hideNotification" -> {
                    mediaSessionManager?.hideNotification()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Set up broadcast receiver for media actions
        setupMediaActionReceiver()

        // Ensure AudioService channel does NOT show app icon badge
        ensureAudioChannelNoBadge()
    }
    
    private fun setupMediaActionReceiver() {
        mediaActionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.getStringExtra("action")
                when (action) {
                    "play" -> {
                        // Send play command to Flutter
                        methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "play"))
                    }
                    "pause" -> {
                        // Send pause command to Flutter
                        methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "pause"))
                    }
                    "stop" -> {
                        // Send stop command to Flutter
                        methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "stop"))
                    }
                }
            }
        }
        
        // Register the receiver
        val filter = IntentFilter("wbai_media_action")
        registerReceiver(mediaActionReceiver, filter)
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // CRITICAL DEBUG: Samsung MediaSession Status
        android.util.Log.d("SAMSUNG_DEBUG", "🔍 MainActivity.onCreate() called")
        android.util.Log.d("SAMSUNG_DEBUG", "🔍 mediaSessionManager = $mediaSessionManager")
        
        if (mediaSessionManager != null) {
            android.util.Log.d("SAMSUNG_DEBUG", "🔍 MediaSessionManager exists - READY (not showing notification yet)")
            android.util.Log.d("SAMSUNG_DEBUG", "🔍 STANDARD BEHAVIOR: Notification will show only when user presses PLAY")
        } else {
            android.util.Log.e("SAMSUNG_DEBUG", "🔍 CRITICAL: MediaSessionManager is NULL!")
        }
        
        android.util.Log.d("SAMSUNG_DEBUG", "🔍 MainActivity.onCreate() complete")
    }
    
    override fun onDestroy() {
        // Notify Flutter/Dart that the app is closing so it can stop & clear the player
        try {
            methodChannel?.invokeMethod("onAppClosing", null)
        } catch (e: Exception) {
            android.util.Log.e("SAMSUNG_DEBUG", "Failed to notify Dart on app close: ${e.message}")
        }

        // Clean up resources
        mediaSessionManager?.release()
        mediaActionReceiver?.let { unregisterReceiver(it) }

        super.onDestroy()
    }

    override fun onStop() {
        super.onStop()
        // If the Activity is finishing (e.g., user swiped it away), signal Dart to clear player
        if (isFinishing) {
            try {
                methodChannel?.invokeMethod("onAppClosing", null)
                android.util.Log.d("SAMSUNG_DEBUG", "onStop(): Activity finishing -> onAppClosing sent")
            } catch (e: Exception) {
                android.util.Log.e("SAMSUNG_DEBUG", "onStop notify failed: ${e.message}")
            }
        }
    }
}
