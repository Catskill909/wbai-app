package app.pacifica.wbai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import io.flutter.Log

/**
 * CRITICAL FIX: Native Android MediaSession for Samsung devices
 * 
 * Samsung devices (especially J7) require specific MediaSessionCompat setup
 * that Flutter's audio_service doesn't provide properly.
 * 
 * This bypasses Flutter's audio_service and creates a proper native
 * Android MediaSession that Samsung lockscreen recognizes.
 */
class SamsungMediaSessionManager(private val context: Context) {
    
    companion object {
        private const val TAG = "SamsungMediaSession"
        private const val NOTIFICATION_ID = 12345
        private const val CHANNEL_ID = "wbai_samsung_media_channel"
        private const val MEDIA_SESSION_TAG = "WBAIMediaSession"
    }
    
    private var mediaSession: MediaSessionCompat? = null
    private var notificationManager: NotificationManager? = null
    private var isPlaying = false
    private var currentTitle = "WBAI 99.5 FM"
    private var currentArtist = "Pacifica Radio"
    
    init {
        Log.d(TAG, "🔍 SAMSUNG DEBUG: SamsungMediaSessionManager.init() called")
        Log.d(TAG, "🔍 SAMSUNG DEBUG: Context = $context")
        
        try {
            Log.d(TAG, "🔍 SAMSUNG DEBUG: Setting up notification channel...")
            setupNotificationChannel()
            Log.d(TAG, "🔍 SAMSUNG DEBUG: Notification channel setup complete")
            
            Log.d(TAG, "🔍 SAMSUNG DEBUG: Setting up MediaSession...")
            setupMediaSession()
            Log.d(TAG, "🔍 SAMSUNG DEBUG: MediaSession setup complete")
            
            Log.d(TAG, "🔍 SAMSUNG DEBUG: SamsungMediaSessionManager initialization SUCCESS")
        } catch (e: Exception) {
            Log.e(TAG, "🔍 SAMSUNG DEBUG: CRITICAL ERROR in init(): ${e.message}")
            Log.e(TAG, "🔍 SAMSUNG DEBUG: Stack trace: ${e.stackTrace}")
        }
    }
    
    private fun setupNotificationChannel() {
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "WBAI Media Controls",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Media playback controls for WBAI Radio"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager?.createNotificationChannel(channel)
        }
        
        Log.d(TAG, "🤖 SAMSUNG: Notification channel created")
    }
    
    private fun setupMediaSession() {
        try {
            // CRITICAL: Create MediaSessionCompat with proper setup for Samsung
            mediaSession = MediaSessionCompat(context, MEDIA_SESSION_TAG).apply {
                
                // CRITICAL: Set flags that Samsung requires
                setFlags(
                    MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
                )
                
                // CRITICAL: Set callback for media button handling
                setCallback(object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        Log.d(TAG, "🔍 SAMSUNG DEBUG: MediaSession onPlay() called from lockscreen!")
                        Log.d(TAG, "🤖 SAMSUNG: MediaSession onPlay called")
                        // Send to Flutter via broadcast
                        sendToFlutter("play")
                    }
                    
                    override fun onPause() {
                        Log.d(TAG, "🔍 SAMSUNG DEBUG: MediaSession onPause() called from lockscreen!")
                        Log.d(TAG, "🤖 SAMSUNG: MediaSession onPause called")
                        // Send to Flutter via broadcast
                        sendToFlutter("pause")
                    }
                    
                    override fun onStop() {
                        Log.d(TAG, "🔍 SAMSUNG DEBUG: MediaSession onStop() called from lockscreen!")
                        Log.d(TAG, "🤖 SAMSUNG: MediaSession onStop called")
                        // Send to Flutter via broadcast
                        sendToFlutter("stop")
                    }
                })
                
                // CRITICAL: Set initial metadata that Samsung requires
                setMetadata(
                    MediaMetadataCompat.Builder()
                        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
                        .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
                        .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Live Radio")
                        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, -1) // Live stream
                        .build()
                )
                
                // CRITICAL: Activate the session - Samsung REQUIRES this
                isActive = true
            }
            
            Log.d(TAG, "🤖 SAMSUNG: MediaSession created and activated")
            
        } catch (e: Exception) {
            Log.e(TAG, "🤖 SAMSUNG: Failed to setup MediaSession: ${e.message}")
        }
    }
    
    private fun sendToFlutter(action: String) {
        Log.d(TAG, "🔍 SAMSUNG DEBUG: sendToFlutter() called with action: $action")
        try {
            // Send broadcast intent that MainActivity will receive
            val intent = Intent("wbai_media_action").apply {
                putExtra("action", action)
            }
            context.sendBroadcast(intent)
            Log.d(TAG, "🔍 SAMSUNG DEBUG: Broadcast sent successfully for action: $action")
            Log.d(TAG, "🤖 SAMSUNG: Sending $action to Flutter")
        } catch (e: Exception) {
            Log.e(TAG, "🔍 SAMSUNG DEBUG: CRITICAL ERROR sending broadcast: ${e.message}")
        }
    }
    
    /**
     * Update the media session with new metadata
     * Call this when song/show changes
     */
    fun updateMetadata(title: String, artist: String) {
        currentTitle = title
        currentArtist = artist
        
        mediaSession?.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Live Radio")
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, -1)
                .build()
        )
        
        Log.d(TAG, "🤖 SAMSUNG: Updated metadata - Title: $title, Artist: $artist")
        updateNotification()
    }
    
    /**
     * Update playback state
     * Call this when play/pause state changes
     */
    fun updatePlaybackState(playing: Boolean) {
        isPlaying = playing
        
        val state = if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        
        mediaSession?.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_STOP
                )
                .build()
        )
        
        Log.d(TAG, "🤖 SAMSUNG: Updated playback state - Playing: $playing")
        updateNotification()
    }
    
    private fun updateNotification() {
        try {
            val playPauseIcon = if (isPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            }
            
            val playPauseAction = if (isPlaying) "pause" else "play"
            
            // Create notification with MediaStyle - CRITICAL for Samsung
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification) // Use our custom light red icon
                .setContentTitle(currentTitle)
                .setContentText(currentArtist)
                .setSubText("WBAI 99.5 FM")
                .setTicker(currentTitle) // Enable scrolling text for long titles
                .setOnlyAlertOnce(true)
                .setNumber(0) // Prevent numeric badge providers from showing counts
                
                // CRITICAL: Set visibility to PUBLIC for Samsung lockscreen
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                
                // CRITICAL: Use MediaStyle with session token
                .setStyle(
                    MediaStyle()
                        .setMediaSession(mediaSession?.sessionToken)
                        .setShowActionsInCompactView(0) // Show play/pause in compact view
                )
                
                // Add media controls
                .addAction(
                    playPauseIcon,
                    playPauseAction,
                    createPendingIntent(playPauseAction)
                )
                
                // CRITICAL: Set as ongoing when playing
                .setOngoing(isPlaying)
                
                // High priority for lockscreen visibility
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Explicitly disable app icon badge for this media notification
                builder.setBadgeIconType(NotificationCompat.BADGE_ICON_NONE)
            }

            val notification = builder.build()
            
            notificationManager?.notify(NOTIFICATION_ID, notification)
            Log.d(TAG, "🤖 SAMSUNG: Notification updated - Playing: $isPlaying")

            // Force-clear Samsung launcher badge count for this app
            clearAppBadge()
            
        } catch (e: Exception) {
            Log.e(TAG, "🤖 SAMSUNG: Failed to update notification: ${e.message}")
        }
    }
    
    private fun createPendingIntent(action: String): PendingIntent {
        val intent = Intent("wbai_media_action").apply {
            putExtra("action", action)
        }
        
        return PendingIntent.getBroadcast(
            context,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
    
    /**
     * Show the media notification
     * Call this when starting playback
     */
    fun showNotification() {
        Log.d(TAG, "🔍 SAMSUNG DEBUG: showNotification() called")
        Log.d(TAG, "🔍 SAMSUNG DEBUG: mediaSession = $mediaSession")
        Log.d(TAG, "🔍 SAMSUNG DEBUG: notificationManager = $notificationManager")
        Log.d(TAG, "🔍 SAMSUNG DEBUG: currentTitle = '$currentTitle'")
        Log.d(TAG, "🔍 SAMSUNG DEBUG: currentArtist = '$currentArtist'")
        Log.d(TAG, "🔍 SAMSUNG DEBUG: isPlaying = $isPlaying")
        
        try {
            updateNotification()
            Log.d(TAG, "🔍 SAMSUNG DEBUG: updateNotification() completed successfully")
            Log.d(TAG, "🤖 SAMSUNG: Media notification shown")
        } catch (e: Exception) {
            Log.e(TAG, "🔍 SAMSUNG DEBUG: CRITICAL ERROR in showNotification(): ${e.message}")
            Log.e(TAG, "🔍 SAMSUNG DEBUG: Stack trace: ${e.stackTrace}")
        }
    }
    
    /**
     * Hide the media notification
     * Call this when stopping playback
     */
    fun hideNotification() {
        notificationManager?.cancel(NOTIFICATION_ID)
        Log.d(TAG, "🤖 SAMSUNG: Media notification hidden")
        // Also ensure badge is cleared
        clearAppBadge()
    }
    
    /**
     * Clean up resources
     */
    fun release() {
        mediaSession?.apply {
            isActive = false
            release()
        }
        hideNotification()
        Log.d(TAG, "🤖 SAMSUNG: MediaSession released")
    }

    /**
     * Clear Samsung launcher badge count for this app.
     * Older Samsung launchers show badge counts for any active notifications; force it to 0.
     */
    private fun clearAppBadge() {
        try {
            val intent = Intent("android.intent.action.BADGE_COUNT_UPDATE").apply {
                putExtra("badge_count", 0)
                putExtra("badge_count_package_name", context.packageName)
                putExtra("badge_count_class_name", "app.pacifica.wbai.MainActivity")
            }
            context.sendBroadcast(intent)
            Log.d(TAG, "🤖 SAMSUNG: Badge count cleared via broadcast")
        } catch (e: Exception) {
            Log.e(TAG, "🤖 SAMSUNG: Failed to clear badge: ${e.message}")
        }
    }
}
