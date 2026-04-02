import UIKit
import Flutter
import MediaPlayer
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    // Single metadata channel
    private var metadataChannel: FlutterMethodChannel?
    
    // Single AVAudioSession configuration
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[AUDIO] Session configured with enhanced options")
        } catch {
            print("[AUDIO] Session configuration error: \(error)")
        }
    }
    
    // Set default metadata
    private func setupDefaultMetadata() {
        let nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: "KPFK 90.7 FM",
            MPMediaItemPropertyArtist: "Pacifica Radio",
            MPMediaItemPropertyAlbumTitle: "KPFK",
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. Configure audio session
        configureAudioSession()
        
        // 2. DISABLED: Set default metadata (was overriding artwork)
        // setupDefaultMetadata() // DISABLED - This was clearing artwork with text-only metadata
        
        // 3. Set up Flutter controller
        let controller = window?.rootViewController as! FlutterViewController
        
        // 4. Set up metadata channel
        metadataChannel = FlutterMethodChannel(name: "com.kpfkfm.radio/metadata",
                                            binaryMessenger: controller.binaryMessenger)
        
        // 4b. Set up NOW PLAYING channel for IOSLockscreenService
        let nowPlayingChannel = FlutterMethodChannel(name: "com.kpfkfm.radio/now_playing",
                                                   binaryMessenger: controller.binaryMessenger)
        
        // 5. Set up method handler for metadata channel
        metadataChannel?.setMethodCallHandler({ (call, result) in
            switch call.method {
            case "updateMetadata":
                self.handleUpdateMetadata(call: call, result: result)
            case "keepAudioSessionAlive":
                // Reconfigure audio session to ensure it stays active
                self.configureAudioSession()
                result(true)
            case "channelTest":
                print("[METADATA] Channel test received from Flutter")
                result("Channel test successful")
            case "testMessage":
                result("Test received")
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        
        // 5b. Set up method handler for NOW PLAYING channel (IOSLockscreenService)
        nowPlayingChannel.setMethodCallHandler({ (call, result) in
            switch call.method {
            case "updateNowPlaying":
                self.handleUpdateNowPlaying(call: call, result: result)
            case "clearNowPlaying":
                self.handleClearNowPlaying(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        
        // 6. Set up remote commands
        setupRemoteCommandCenter()
        
        // 7. Register plugins
        GeneratedPluginRegistrant.register(with: self)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Debounce timer for metadata updates
    private var metadataDebounceTimer: Timer?
    private var lastTitle: String?
    private var lastArtist: String?
    private var lastIsPlaying: Bool?
    private var lastArtworkUrl: String?
    private var cachedArtwork: MPMediaItemArtwork?
    private var pendingMetadataUpdate: [String: Any]?
    private var isSettingArtwork: Bool = false  // Lock to prevent overrides
    
    /// Apply the pending metadata update on the main thread
    private func applyPendingMetadataUpdate() {
        // Must be called on main thread
        DispatchQueue.main.async {
            // CRITICAL: Don't update if we're in the middle of setting artwork
            if self.isSettingArtwork {
                print("[METADATA] ⚠️ BLOCKED update - artwork is being set")
                return
            }
            
            guard let update = self.pendingMetadataUpdate else { return }
            
            // Extract values
            guard let title = update["title"] as? String,
                  let artist = update["artist"] as? String,
                  let isPlaying = update["isPlaying"] as? Bool else {
                print("[METADATA] Invalid pending metadata update")
                return
            }
            
            // Ensure AVAudioSession is active
            self.configureAudioSession()
            
            // Create metadata dictionary with additional required properties
            var nowPlayingInfo: [String: Any] = [
                MPMediaItemPropertyTitle: title,
                MPMediaItemPropertyArtist: artist,
                MPMediaItemPropertyAlbumTitle: "KPFK 90.7 FM",
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
                MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
            ]
            
            let currentArtworkUrl = update["artworkUrl"] as? String
            
            // CRITICAL FIX: Use cached artwork immediately if available (same URL)
            if let currentUrl = currentArtworkUrl, currentUrl == self.lastArtworkUrl, let cachedArtwork = self.cachedArtwork {
                // Same artwork URL - use cached artwork and set metadata immediately
                let timestamp = Date().timeIntervalSince1970
                print("[TIMESTAMP-\(timestamp)] ⚡ Using CACHED artwork for lockscreen")
                print("[TIMESTAMP-\(timestamp)] Title: \(title), Artist: \(artist)")
                print("[TIMESTAMP-\(timestamp)] Cached artwork URL: \(currentUrl)")
                
                nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                
                print("[TIMESTAMP-\(timestamp)] ✅ Lockscreen set with CACHED artwork")
                print("[METADATA] ✅ Using cached artwork for same URL: \(currentUrl)")
                
                // Verify it stuck after 100ms
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
                    let hasArtwork = current?[MPMediaItemPropertyArtwork] != nil
                    print("[VERIFY-CACHED-100ms] Artwork present: \(hasArtwork)")
                    if !hasArtwork {
                        print("[VERIFY-CACHED-100ms] ❌ CACHED ARTWORK DISAPPEARED!")
                    }
                }
                
                return // Early return - no download needed
            }
            
            // CRITICAL FIX: Set lockscreen IMMEDIATELY with text, then add artwork asynchronously
            // This ensures lockscreen appears instantly without waiting for image download
            let timestamp1 = Date().timeIntervalSince1970
            print("[TIMESTAMP-\(timestamp1)] ⚡ Setting lockscreen metadata IMMEDIATELY (text-only first)")
            print("[TIMESTAMP-\(timestamp1)] Has artwork: false")
            print("[TIMESTAMP-\(timestamp1)] Title: \(title)")
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            print("[TIMESTAMP-\(timestamp1)] ✅ Lockscreen set with text")
            
            // Verify it stuck after 100ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
                let hasArtwork = current?[MPMediaItemPropertyArtwork] != nil
                print("[VERIFY-100ms] Artwork present: \(hasArtwork)")
                if hasArtwork {
                    print("[VERIFY-100ms] ⚠️ UNEXPECTED: Artwork appeared from somewhere!")
                }
            }
            
            // Now download and add artwork asynchronously if we have a new URL
            if let artworkUrl = currentArtworkUrl, artworkUrl != self.lastArtworkUrl {
                print("[METADATA] 🎨 New artwork URL detected: '\(artworkUrl)'")
                if let url = URL(string: artworkUrl) {
                    print("[METADATA] ⏳ Starting async artwork download...")
                    
                    // Download artwork with timeout (3 seconds max)
                    self.downloadArtworkWithTimeout(url: url, artworkUrl: artworkUrl, timeout: 3.0) { [weak self] image in
                        guard let self = self else { return }
                        
                        // Add artwork to metadata if download succeeded
                        if let image = image {
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            self.cachedArtwork = artwork
                            self.lastArtworkUrl = artworkUrl
                            
                            // Update lockscreen with artwork
                            let timestamp2 = Date().timeIntervalSince1970
                            print("[TIMESTAMP-\(timestamp2)] 🎨 Adding artwork to lockscreen")
                            print("[TIMESTAMP-\(timestamp2)] Artwork size: \(image.size)")
                            
                            // CRITICAL: Lock to prevent ANY other updates for 2 seconds
                            self.isSettingArtwork = true
                            print("[LOCK] 🔒 Metadata updates LOCKED for 2 seconds")
                            
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                            print("[TIMESTAMP-\(timestamp2)] ✅ Artwork SET on lockscreen")
                            
                            // Keep lock for 2 seconds to prevent overrides
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.isSettingArtwork = false
                                print("[LOCK] 🔓 Metadata updates UNLOCKED")
                            }
                            
                            // CRITICAL: Verify artwork persists
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
                                let hasArtwork = current?[MPMediaItemPropertyArtwork] != nil
                                print("[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: \(hasArtwork)")
                                if !hasArtwork {
                                    print("[VERIFY-100ms-AFTER-ARTWORK] ❌❌❌ ARTWORK WAS REMOVED BY SOMETHING! ❌❌❌")
                                    print("[VERIFY-100ms-AFTER-ARTWORK] This is the bug! Something is overriding our metadata!")
                                }
                            }
                            
                            // Check again after 500ms
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
                                let hasArtwork = current?[MPMediaItemPropertyArtwork] != nil
                                print("[VERIFY-500ms-AFTER-ARTWORK] Artwork still present: \(hasArtwork)")
                                if !hasArtwork {
                                    print("[VERIFY-500ms-AFTER-ARTWORK] ❌ ARTWORK REMOVED BETWEEN 100-500ms")
                                }
                            }
                            
                            // Check again after 1 second
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
                                let hasArtwork = current?[MPMediaItemPropertyArtwork] != nil
                                print("[VERIFY-1000ms-AFTER-ARTWORK] Artwork still present: \(hasArtwork)")
                                if !hasArtwork {
                                    print("[VERIFY-1000ms-AFTER-ARTWORK] ❌ ARTWORK REMOVED BETWEEN 500ms-1s (MetadataController timer?)")
                                }
                            }
                        } else {
                            print("[METADATA] ⚠️ Artwork download failed or timed out - lockscreen remains text-only")
                        }
                    }
                } else {
                    print("[METADATA] ❌ Invalid URL for artwork: '\(artworkUrl)'")
                }
            } else if currentArtworkUrl == nil {
                // Clear cached artwork if no URL provided
                self.cachedArtwork = nil
                self.lastArtworkUrl = nil
                print("[METADATA] ℹ️ No artwork URL provided - lockscreen is text-only")
            }
        }
    }
    
    /// Downloads artwork with timeout to prevent indefinite waiting
    /// This ensures lockscreen updates within a reasonable time even if download fails
    private func downloadArtworkWithTimeout(url: URL, artworkUrl: String, timeout: TimeInterval = 3.0, completion: @escaping (UIImage?) -> Void) {
        var hasCompleted = false
        
        // Set up timeout timer
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            if !hasCompleted {
                hasCompleted = true
                print("[METADATA] ⏱️ Artwork download timeout (\(timeout)s) - proceeding without image")
                completion(nil)
            }
        }
        
        // Start download with retry
        downloadArtworkWithRetry(url: url, artworkUrl: artworkUrl, maxRetries: 2) { image in
            // Cancel timeout if download completes first
            timeoutTimer.invalidate()
            
            if !hasCompleted {
                hasCompleted = true
                completion(image)
            }
        }
    }
    
    /// Downloads artwork with retry mechanism for improved reliability
    private func downloadArtworkWithRetry(url: URL, artworkUrl: String, maxRetries: Int = 2, completion: @escaping (UIImage?) -> Void) {
        func attemptDownload(attempt: Int) {
            print("[METADATA] 🔄 Artwork download attempt \(attempt + 1)/\(maxRetries + 1) for: \(artworkUrl)")
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                DispatchQueue.main.async {
                    // Log response details for diagnostics
                    if let httpResponse = response as? HTTPURLResponse {
                        print("[METADATA] 📡 HTTP Status: \(httpResponse.statusCode)")
                    }
                    
                    if let error = error {
                        print("[METADATA] ❌ Attempt \(attempt + 1) failed: \(error.localizedDescription)")
                        
                        // Retry if we haven't exceeded max attempts
                        if attempt < maxRetries {
                            let delay = Double(attempt + 1) // Progressive delay: 1s, 2s, 3s...
                            print("[METADATA] ⏳ Retrying in \(delay)s...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                attemptDownload(attempt: attempt + 1)
                            }
                        } else {
                            print("[METADATA] ❌ All retry attempts failed for: \(artworkUrl)")
                            completion(nil)
                        }
                        return
                    }
                    
                    guard let data = data else {
                        print("[METADATA] ❌ No data received on attempt \(attempt + 1)")
                        
                        // Retry if we haven't exceeded max attempts
                        if attempt < maxRetries {
                            let delay = Double(attempt + 1)
                            print("[METADATA] ⏳ Retrying in \(delay)s...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                attemptDownload(attempt: attempt + 1)
                            }
                        } else {
                            print("[METADATA] ❌ No data received after all retry attempts")
                            completion(nil)
                        }
                        return
                    }
                    
                    guard let image = UIImage(data: data) else {
                        print("[METADATA] ❌ Failed to create UIImage from \(data.count) bytes on attempt \(attempt + 1)")
                        
                        // Retry if we haven't exceeded max attempts
                        if attempt < maxRetries {
                            let delay = Double(attempt + 1)
                            print("[METADATA] ⏳ Retrying in \(delay)s...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                attemptDownload(attempt: attempt + 1)
                            }
                        } else {
                            print("[METADATA] ❌ Failed to create image after all retry attempts")
                            completion(nil)
                        }
                        return
                    }
                    
                    // Success!
                    print("[METADATA] ✅ Artwork download successful on attempt \(attempt + 1)")
                    completion(image)
                }
            }.resume()
        }
        
        // Start the first attempt
        attemptDownload(attempt: 0)
    }
    
    private func handleUpdateMetadata(call: FlutterMethodCall, result: FlutterResult) {
        // Extract metadata from arguments
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let artist = args["artist"] as? String,
              let isPlaying = args["isPlaying"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", 
                                message: "Invalid arguments", 
                                details: nil))
            return
        }
        
        // ENHANCED PLACEHOLDER GUARD
        // Skip placeholder metadata during playback
        let placeholderTitles = ["Loading stream...", "Connecting...", "", "KPFK Radio", "KPFK Stream"]
        let placeholderArtists = ["Connecting...", "", "Live Stream"]
        let isPlaceholder = placeholderTitles.contains(title) || placeholderArtists.contains(artist)
        
        if isPlaceholder && isPlaying {
            print("[METADATA] Blocking placeholder during playback: \(title) by \(artist)")
            result(true) // Still return success
            return
        }
        
        // Skip if nothing has changed
        if title == lastTitle && artist == lastArtist && isPlaying == lastIsPlaying {
            print("[METADATA] Skipping identical update: \(title) by \(artist), playing=\(isPlaying)")
            result(true)
            return
        }
        
        // Store current values
        lastTitle = title
        lastArtist = artist
        lastIsPlaying = isPlaying
        
        // Store the entire arguments as the pending update
        pendingMetadataUpdate = args
        
        // Cancel any pending update
        metadataDebounceTimer?.invalidate()
        
        // Schedule a debounced update (250ms delay)
        metadataDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.applyPendingMetadataUpdate()
        }
        
        // Log that we've queued the update
        print("[METADATA] Queued update for debouncing: \(title) by \(artist), playing=\(isPlaying)")
        
        result(true)
    }
    
    private func setupRemoteCommandCenter() {
        // Get command center
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Remove any existing handlers
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        
        // Add play handler
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.configureAudioSession()
            DispatchQueue.main.async {
                self?.metadataChannel?.invokeMethod("remotePlay", arguments: nil)
            }
            return .success
        }
        
        // Add pause handler
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.configureAudioSession()
            DispatchQueue.main.async {
                self?.metadataChannel?.invokeMethod("remotePause", arguments: nil)
            }
            return .success
        }
        
        // Add toggle handler
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.configureAudioSession()
            DispatchQueue.main.async {
                self?.metadataChannel?.invokeMethod("remoteTogglePlayPause", arguments: nil)
            }
            return .success
        }
        
        print("[REMOTE] Commands setup complete")
    }
    
    // MARK: - App Lifecycle Support
    
    // We're not using UIScene lifecycle methods as they require iOS 13+
    // Instead, we'll use the traditional app delegate methods
    
    // MARK: - App Lifecycle Methods
    
    // Called when app becomes active (either first launch or returning from background)
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        print("[LIFECYCLE] App did become active")
        // Ensure audio session is active when app becomes active
        configureAudioSession()
        
        // Refresh metadata if we have any - INCLUDE ARTWORK URL!
        if let title = lastTitle, let artist = lastArtist, let isPlaying = lastIsPlaying {
            print("[LIFECYCLE] Refreshing metadata on become active: \(title) by \(artist)")
            var metadata: [String: Any] = [
                "title": title,
                "artist": artist,
                "isPlaying": isPlaying,
                "forceUpdate": true
            ]
            // CRITICAL FIX: Include artwork URL if we have it!
            if let artworkUrl = lastArtworkUrl {
                metadata["artworkUrl"] = artworkUrl
                print("[LIFECYCLE] Including artwork URL: \(artworkUrl)")
            }
            pendingMetadataUpdate = metadata
            applyPendingMetadataUpdate()
        }
    }
    
    // Called when app enters foreground
    override func applicationWillEnterForeground(_ application: UIApplication) {
        super.applicationWillEnterForeground(application)
        print("[LIFECYCLE] App will enter foreground")
        // Ensure audio session is active when app comes to foreground
        configureAudioSession()
    }
    
    // Called when app enters background
    override func applicationDidEnterBackground(_ application: UIApplication) {
        super.applicationDidEnterBackground(application)
        print("[LIFECYCLE] App did enter background")
        // No need to deactivate audio session as we want background audio
    }
    
    // Called when app is about to terminate
    override func applicationWillTerminate(_ application: UIApplication) {
        super.applicationWillTerminate(application)
        print("[LIFECYCLE] App will terminate")
        // Clean up any resources if needed
    }
    
    // MARK: - NOW PLAYING Channel Handlers (IOSLockscreenService)
    
    /// Handle updateNowPlaying method from IOSLockscreenService
    private func handleUpdateNowPlaying(call: FlutterMethodCall, result: FlutterResult) {
        // CRITICAL: Don't update if we're in the middle of setting artwork
        if isSettingArtwork {
            print("[NOW_PLAYING] ⚠️ BLOCKED update - artwork is being set")
            result(false)
            return
        }
        
        // Extract metadata from arguments
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let artist = args["artist"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", 
                                message: "Invalid arguments for updateNowPlaying", 
                                details: nil))
            return
        }
        
        // Extract optional parameters
        let album = args["album"] as? String ?? "KPFK 90.7 FM"
        let artworkUrl = args["artworkUrl"] as? String
        let isPlaying = args["isPlaying"] as? Bool ?? true
        let duration = args["duration"] as? Int
        let position = args["position"] as? Int
        
        print("[NOW_PLAYING] Received updateNowPlaying: title='\(title)', artist='\(artist)', artworkUrl='\(artworkUrl ?? "nil")'")
        
        // ENHANCED PLACEHOLDER GUARD
        let placeholderTitles = ["Loading stream...", "Connecting...", "", "KPFK Radio", "KPFK Stream"]
        let placeholderArtists = ["Connecting...", "", "Live Stream"]
        let isPlaceholder = placeholderTitles.contains(title) || placeholderArtists.contains(artist)
        
        if isPlaceholder && isPlaying {
            print("[NOW_PLAYING] Blocking placeholder during playback: \(title) by \(artist)")
            result(true) // Still return success
            return
        }
        
        // Ensure AVAudioSession is active
        configureAudioSession()
        
        // Create metadata dictionary with required properties
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position != nil ? Double(position!) / 1000.0 : 0,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
        ]
        
        // Add duration if provided
        if let duration = duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(duration) / 1000.0
        }
        
        // CRITICAL FIX: Use cached artwork immediately if available (same URL)
        if let artworkUrlString = artworkUrl, artworkUrlString == self.lastArtworkUrl, let cachedArtwork = self.cachedArtwork {
            // Same artwork URL - use cached artwork and set metadata immediately
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            print("[NOW_PLAYING] ✅ Using cached artwork for same URL: \(artworkUrlString)")
            result(true)
            return // Early return - no download needed
        }
        
        // CRITICAL FIX: Set lockscreen IMMEDIATELY with text, then add artwork asynchronously
        print("[NOW_PLAYING] ⚡ Setting lockscreen metadata IMMEDIATELY (text-only first)")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        print("[NOW_PLAYING] ✅ Lockscreen set with text - artwork will be added asynchronously if available")
        result(true)
        
        // Now download and add artwork asynchronously if we have a new URL
        if let artworkUrlString = artworkUrl, !artworkUrlString.isEmpty, artworkUrlString != self.lastArtworkUrl, let url = URL(string: artworkUrlString) {
            print("[NOW_PLAYING] 🎨 New artwork URL detected: '\(artworkUrlString)'")
            print("[NOW_PLAYING] ⏳ Starting async artwork download...")
            
            // Download artwork with timeout (3 seconds max)
            self.downloadArtworkWithTimeout(url: url, artworkUrl: artworkUrlString, timeout: 3.0) { [weak self] image in
                guard let self = self else { return }
                
                // Add artwork to metadata if download succeeded
                if let image = image {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.cachedArtwork = artwork
                    self.lastArtworkUrl = artworkUrlString
                    
                    // Update lockscreen with artwork
                    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                    updatedInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    print("[NOW_PLAYING] ✅ Artwork downloaded and added to lockscreen, size: \(image.size)")
                } else {
                    print("[NOW_PLAYING] ⚠️ Artwork download failed or timed out - lockscreen remains text-only")
                }
            }
        } else if artworkUrl == nil || artworkUrl?.isEmpty == true {
            // Clear cached artwork if no URL provided
            self.cachedArtwork = nil
            self.lastArtworkUrl = nil
            print("[NOW_PLAYING] ℹ️ No artwork URL provided - lockscreen is text-only")
        }
    }
    
    /// Handle clearNowPlaying method from IOSLockscreenService
    private func handleClearNowPlaying(result: FlutterResult) {
        print("[NOW_PLAYING] Clearing lockscreen metadata")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        result(true)
    }
}
