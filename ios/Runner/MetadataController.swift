import Foundation
import MediaPlayer
import AVFoundation
import UIKit

class MetadataController {
    // Forensic: Timer to log current lockscreen metadata every second
    private var forensicLogTimer: Timer?
    
    // CRITICAL FIX: Timer to periodically reapply metadata to override just_audio_background
    private var metadataGuardTimer: Timer?
    
    // Enhanced recovery tracking
    private var recoveryAttemptCount: Int = 0
    private var lastRecoveryTime: Date?
    
    // Call this once at app startup to start forensic logging
    func startForensicMetadataLogging() {
        // DISABLED: This timer was causing artwork to be removed from lockscreen
        // by reapplying metadata without artwork every second
        print("[METADATA_CONTROLLER] DISABLED - AppDelegate handles all metadata now")
        forensicLogTimer?.invalidate()
        forensicLogTimer = nil
        // DO NOT START TIMER - it conflicts with AppDelegate
    }

    // Call this to stop forensic logging
    func stopForensicMetadataLogging() {
        forensicLogTimer?.invalidate()
        forensicLogTimer = nil
    }
    
    // CRITICAL FIX: Start a timer to periodically reapply metadata
    func startMetadataGuard() {
        // DISABLED: This was causing conflicts with AppDelegate
        print("[METADATA_CONTROLLER] startMetadataGuard() DISABLED - AppDelegate handles metadata")
        metadataGuardTimer?.invalidate()
        metadataGuardTimer = nil
    }
    
    // CRITICAL FIX: Reapply the last known metadata
    private func reapplyLastMetadata() {
        // DISABLED: This was overriding AppDelegate's metadata and removing artwork
        print("[METADATA_CONTROLLER] reapplyLastMetadata() DISABLED - AppDelegate handles metadata")
        return
    }

    static let shared = MetadataController()
    private var methodChannel: FlutterMethodChannel?
    private var lastTitle: String?
    private var lastArtist: String?
    private var lastArtworkUrl: String?
    private var lastIsPlaying: Bool = true
    private var lastForceUpdate: Bool = false
    
    // Debounce timer for lockscreen metadata updates
    private var debounceTimer: Timer?
    private var pendingMetadata: (title: String, artist: String, artworkUrl: String?, isPlaying: Bool, forceUpdate: Bool)?
    
    // Background task to keep app alive during updates
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    private init() {}
    
    func setMethodChannel(_ channel: FlutterMethodChannel) {
        self.methodChannel = channel
        // Ensure audio session is configured at startup
        configureAudioSession()
        // Start verification task to ensure lockscreen is working
        startForensicMetadataLogging()
        // CRITICAL FIX: Start metadata guard to override just_audio_background
        startMetadataGuard()
        
        // Add forensic logging for play, pause, and toggle remote command events
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { event in
            print("[REMOTE] Play command received at \(Date())")
            return .success
        }
        commandCenter.pauseCommand.addTarget { event in
            print("[REMOTE] Pause command received at \(Date())")
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { event in
            print("[REMOTE] Toggle command received at \(Date())")
            return .success
        }
    }
    
    /// Robustly configure AVAudioSession with detailed error logging and return success status
    @discardableResult
    func configureAudioSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        var success = true
        
        do {
            print("[AUDIO] Attempting to set AVAudioSession category to .playback")
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            print("[AUDIO] Category set successfully")
        } catch {
            print("[AUDIO][ERROR] Failed to set category: \(error)")
            success = false
        }
        
        do {
            print("[AUDIO] Attempting to activate AVAudioSession")
            try session.setActive(true)
            print("[AUDIO] AVAudioSession activated successfully")
        } catch {
            print("[AUDIO][ERROR] Failed to activate AVAudioSession: \(error)")
            success = false
            
            // Implement special recovery for error -50 (session busy)
            if let error = error as NSError?, error.code == -50 {
                print("[AUDIO][RECOVERY] Error -50 detected (session busy). Attempting recovery after delay...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        try session.setActive(true)
                        print("[AUDIO][RECOVERY] Successfully activated audio session after retry")
                    } catch {
                        print("[AUDIO][ERROR] Recovery attempt also failed: \(error)")
                    }
                }
            }
        }
        
        return success
    }
    
    /// Debounced, main-threaded lockscreen metadata update with defensive placeholder guard
    func updateMetadata(title: String, artist: String, artworkUrl: String?, isPlaying: Bool, forceUpdate: Bool) {
        // CRITICAL FIX: Store last metadata for reapplication
        self.lastTitle = title
        self.lastArtist = artist
        self.lastArtworkUrl = artworkUrl
        self.lastIsPlaying = isPlaying
        
        // EXPERT GUARD: Block placeholder metadata from ever reaching lockscreen
        let lowerTitle = title.lowercased()
        let lowerArtist = artist.lowercased()
        if lowerTitle.contains("loading stream") || lowerArtist.contains("connecting") {
            print("[EXPERT BLOCK] Ignoring placeholder metadata: title='\(title)', artist='\(artist)'")
            return
        }
        // --- DEFENSIVE PLACEHOLDER GUARD ---
        let placeholderTitles: Set<String> = ["Loading stream...", "Connecting...", "", "WPFW Radio", "WPFW Stream"]
        let placeholderArtists: Set<String> = ["Connecting...", "", "Live Stream"]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if placeholderTitles.contains(trimmedTitle) || placeholderArtists.contains(trimmedArtist) {
            print("[BLOCKED] Placeholder metadata blocked from iOS lockscreen update: title=\"\(title)\", artist=\"\(artist)\"")
            return
        }
        // --- END PLACEHOLDER GUARD ---
        
        // Verify AVAudioSession before even attempting to update
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            print("[AUDIO][PREEMPTIVE] AVAudioSession issues detected before update, fixing proactively")
            configureAudioSession()
        }
        
        // Debounce rapid updates (batch within 250ms)
        pendingMetadata = (title, artist, artworkUrl, isPlaying, forceUpdate)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.performMetadataUpdate()
        }
    }

    /// Actually perform the lockscreen metadata update (runs on main thread)
    private func performMetadataUpdate() {
        // DISABLED: AppDelegate handles all metadata now
        print("[METADATA_CONTROLLER] performMetadataUpdate() DISABLED - AppDelegate handles all metadata")
        pendingMetadata = nil
    }

    
    func clearMetadata() {
        print("[FORENSIC] Clearing MPNowPlayingInfoCenter")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("[FORENSIC] MPNowPlayingInfoCenter cleared")
        print(" MPNowPlayingInfoCenter cleared")
    }
    
    /// New method to verify metadata actually appeared and retry if needed
    private func verifyMetadataUpdateSucceeded(expectedTitle: String, expectedArtist: String, retryCount: Int = 0) {
        // Don't retry too many times
        if retryCount >= 3 {
            print("[FORENSIC][VERIFY] Abandoning verification after 3 retry attempts")
            return
        }
        
        // Check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            let currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            let currentTitle = currentInfo[MPMediaItemPropertyTitle] as? String
            let currentArtist = currentInfo[MPMediaItemPropertyArtist] as? String
            let currentRate = currentInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0.0
            
            print("[FORENSIC][VERIFY] Expected: '\(expectedTitle)' by '\(expectedArtist)', rate=\(self.lastIsPlaying ? 1.0 : 0.0)")
            print("[FORENSIC][VERIFY] Current: '\(currentTitle ?? "nil")' by '\(currentArtist ?? "nil")' rate=\(currentRate)")
            
            // If metadata is missing or incorrect, retry with force
            if currentTitle != expectedTitle || currentArtist != expectedArtist || 
               (self.lastIsPlaying && currentRate == 0.0) || (!self.lastIsPlaying && currentRate > 0.0) {
                print("[FORENSIC][RECOVERY] Metadata verification failed - retrying update with force")
                
                // Force reconfiguration of audio session
                self.configureAudioSession()
                
                // Re-send metadata with force flag
                self.updateMetadata(title: expectedTitle, 
                                   artist: expectedArtist, 
                                   artworkUrl: self.lastArtworkUrl, 
                                   isPlaying: self.lastIsPlaying, 
                                   forceUpdate: true)
                
                // Schedule another verification
                self.verifyMetadataUpdateSucceeded(expectedTitle: expectedTitle, 
                                                expectedArtist: expectedArtist,
                                                retryCount: retryCount + 1)
            } else {
                print("[FORENSIC][VERIFY] Metadata verification successful!")
                self.recoveryAttemptCount = 0
            }
        }
    }
}
