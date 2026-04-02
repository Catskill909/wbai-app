import UIKit
import Flutter
import MediaPlayer
import AVFoundation

class SceneDelegate: FlutterSceneDelegate {

    private var metadataChannel: FlutterMethodChannel?

    // MARK: - State
    private var metadataDebounceTimer: Timer?
    private var lastTitle: String?
    private var lastArtist: String?
    private var lastIsPlaying: Bool?
    private var lastArtworkUrl: String?
    private var cachedArtwork: MPMediaItemArtwork?
    private var pendingMetadataUpdate: [String: Any]?
    private var isSettingArtwork: Bool = false

    // MARK: - Scene Lifecycle

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)

        guard let controller = window?.rootViewController as? FlutterViewController else { return }

        // Metadata channel (native metadata updates from Dart)
        metadataChannel = FlutterMethodChannel(
            name: "com.wbaifm.radio/metadata",
            binaryMessenger: controller.binaryMessenger)

        // Now-playing channel (IOSLockscreenService)
        let nowPlayingChannel = FlutterMethodChannel(
            name: "com.wbaifm.radio/now_playing",
            binaryMessenger: controller.binaryMessenger)

        metadataChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "updateMetadata":
                self?.handleUpdateMetadata(call: call, result: result)
            case "keepAudioSessionAlive":
                self?.configureAudioSession()
                result(true)
            case "channelTest":
                print("[METADATA] Channel test received from Flutter")
                result("Channel test successful")
            case "testMessage":
                result("Test received")
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        nowPlayingChannel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "updateNowPlaying":
                self?.handleUpdateNowPlaying(call: call, result: result)
            case "clearNowPlaying":
                self?.handleClearNowPlaying(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        setupRemoteCommandCenter()
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        print("[LIFECYCLE] Scene did become active")
        configureAudioSession()

        if let title = lastTitle, let artist = lastArtist, let isPlaying = lastIsPlaying {
            print("[LIFECYCLE] Refreshing metadata on become active: \(title) by \(artist)")
            var metadata: [String: Any] = [
                "title": title,
                "artist": artist,
                "isPlaying": isPlaying,
                "forceUpdate": true
            ]
            if let artworkUrl = lastArtworkUrl {
                metadata["artworkUrl"] = artworkUrl
            }
            pendingMetadataUpdate = metadata
            applyPendingMetadataUpdate()
        }
    }

    override func sceneWillEnterForeground(_ scene: UIScene) {
        print("[LIFECYCLE] Scene will enter foreground")
        configureAudioSession()
    }

    override func sceneDidEnterBackground(_ scene: UIScene) {
        print("[LIFECYCLE] Scene did enter background")
        // Audio continues in background — no session deactivation
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Only set category — do NOT activate here. Session is activated
            // by the Dart audio handler when the user presses play.
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
        } catch {
            print("[AUDIO] Session category error: \(error)")
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.metadataChannel?.invokeMethod("remotePlay", arguments: nil)
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.metadataChannel?.invokeMethod("remotePause", arguments: nil)
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.metadataChannel?.invokeMethod("remoteTogglePlayPause", arguments: nil)
            }
            return .success
        }

        print("[REMOTE] Commands setup complete")
    }

    // MARK: - Metadata Handlers

    private func handleUpdateMetadata(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let artist = args["artist"] as? String,
              let isPlaying = args["isPlaying"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        let placeholderTitles = ["Loading stream...", "Connecting...", "", "WBAI Radio", "WBAI Stream"]
        let placeholderArtists = ["Connecting...", "", "Live Stream"]
        if (placeholderTitles.contains(title) || placeholderArtists.contains(artist)) && isPlaying {
            print("[METADATA] Blocking placeholder during playback: \(title) by \(artist)")
            result(true)
            return
        }

        if title == lastTitle && artist == lastArtist && isPlaying == lastIsPlaying {
            result(true)
            return
        }

        lastTitle = title
        lastArtist = artist
        lastIsPlaying = isPlaying
        pendingMetadataUpdate = args

        metadataDebounceTimer?.invalidate()
        metadataDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.applyPendingMetadataUpdate()
        }

        print("[METADATA] Queued update: \(title) by \(artist), playing=\(isPlaying)")
        result(true)
    }

    private func handleUpdateNowPlaying(call: FlutterMethodCall, result: FlutterResult) {
        if isSettingArtwork {
            print("[NOW_PLAYING] Blocked — artwork is being set")
            result(false)
            return
        }

        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let artist = args["artist"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        let album = args["album"] as? String ?? "WBAI 99.5 FM"
        let artworkUrl = args["artworkUrl"] as? String
        let isPlaying = args["isPlaying"] as? Bool ?? true

        let placeholderTitles = ["Loading stream...", "Connecting...", "", "WBAI Radio", "WBAI Stream"]
        let placeholderArtists = ["Connecting...", "", "Live Stream"]
        if (placeholderTitles.contains(title) || placeholderArtists.contains(artist)) && isPlaying {
            result(true)
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
        ]

        if let artworkUrlString = artworkUrl,
           artworkUrlString == self.lastArtworkUrl,
           let cached = self.cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cached
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            result(true)
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        result(true)

        if let artworkUrlString = artworkUrl,
           !artworkUrlString.isEmpty,
           artworkUrlString != self.lastArtworkUrl,
           let url = URL(string: artworkUrlString) {
            downloadArtworkWithTimeout(url: url, artworkUrl: artworkUrlString, timeout: 3.0) { [weak self] image in
                guard let self = self, let image = image else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.cachedArtwork = artwork
                self.lastArtworkUrl = artworkUrlString
                self.isSettingArtwork = true
                var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                updatedInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.isSettingArtwork = false
                }
            }
        }
    }

    private func handleClearNowPlaying(result: FlutterResult) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        result(true)
    }

    // MARK: - Pending Metadata

    private func applyPendingMetadataUpdate() {
        DispatchQueue.main.async {
            if self.isSettingArtwork { return }
            guard let update = self.pendingMetadataUpdate,
                  let title = update["title"] as? String,
                  let artist = update["artist"] as? String,
                  let isPlaying = update["isPlaying"] as? Bool else { return }

            var nowPlayingInfo: [String: Any] = [
                MPMediaItemPropertyTitle: title,
                MPMediaItemPropertyArtist: artist,
                MPMediaItemPropertyAlbumTitle: "WBAI 99.5 FM",
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
                MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
            ]

            let currentArtworkUrl = update["artworkUrl"] as? String

            if let currentUrl = currentArtworkUrl,
               currentUrl == self.lastArtworkUrl,
               let cached = self.cachedArtwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = cached
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                return
            }

            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

            if let artworkUrl = currentArtworkUrl,
               artworkUrl != self.lastArtworkUrl,
               let url = URL(string: artworkUrl) {
                self.downloadArtworkWithTimeout(url: url, artworkUrl: artworkUrl, timeout: 3.0) { [weak self] image in
                    guard let self = self, let image = image else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.cachedArtwork = artwork
                    self.lastArtworkUrl = artworkUrl
                    self.isSettingArtwork = true
                    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                    updatedInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.isSettingArtwork = false
                    }
                }
            }
        }
    }

    // MARK: - Artwork Download

    private func downloadArtworkWithTimeout(url: URL, artworkUrl: String, timeout: TimeInterval, completion: @escaping (UIImage?) -> Void) {
        var completed = false
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            if !completed { completed = true; completion(nil) }
        }
        downloadArtworkWithRetry(url: url, maxRetries: 2) { image in
            timer.invalidate()
            if !completed { completed = true; completion(image) }
        }
    }

    private func downloadArtworkWithRetry(url: URL, maxRetries: Int, attempt: Int = 0, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let data = data, let image = UIImage(data: data) {
                    completion(image)
                    return
                }
                if attempt < maxRetries {
                    let delay = Double(attempt + 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.downloadArtworkWithRetry(url: url, maxRetries: maxRetries, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
}
