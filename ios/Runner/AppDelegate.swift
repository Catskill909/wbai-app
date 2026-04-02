import UIKit
import Flutter
import MediaPlayer
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var metadataChannel: FlutterMethodChannel?

    private var metadataDebounceTimer: Timer?
    private var lastTitle: String?
    private var lastArtist: String?
    private var lastIsPlaying: Bool?
    private var lastArtworkUrl: String?
    private var cachedArtwork: MPMediaItemArtwork?
    private var pendingMetadataUpdate: [String: Any]?
    private var isSettingArtwork: Bool = false

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
        } catch {
            print("[AUDIO] Session category error: \(error)")
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureAudioSession()

        let controller = window?.rootViewController as! FlutterViewController

        metadataChannel = FlutterMethodChannel(name: "com.wbaifm.radio/metadata",
                                               binaryMessenger: controller.binaryMessenger)

        let nowPlayingChannel = FlutterMethodChannel(name: "com.wbaifm.radio/now_playing",
                                                    binaryMessenger: controller.binaryMessenger)

        metadataChannel?.setMethodCallHandler({ (call, result) in
            switch call.method {
            case "updateMetadata":
                self.handleUpdateMetadata(call: call, result: result)
            case "keepAudioSessionAlive":
                self.configureAudioSession()
                result(true)
            case "channelTest":
                result("Channel test successful")
            case "testMessage":
                result("Test received")
            default:
                result(FlutterMethodNotImplemented)
            }
        })

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

        setupRemoteCommandCenter()
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Remote Commands

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.metadataChannel?.invokeMethod("remotePlay", arguments: nil) }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.metadataChannel?.invokeMethod("remotePause", arguments: nil) }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.metadataChannel?.invokeMethod("remoteTogglePlayPause", arguments: nil) }
            return .success
        }
        print("[REMOTE] Commands setup complete")
    }

    // MARK: - App Lifecycle

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        if let title = lastTitle, let artist = lastArtist, let isPlaying = lastIsPlaying {
            var metadata: [String: Any] = ["title": title, "artist": artist, "isPlaying": isPlaying, "forceUpdate": true]
            if let artworkUrl = lastArtworkUrl { metadata["artworkUrl"] = artworkUrl }
            pendingMetadataUpdate = metadata
            applyPendingMetadataUpdate()
        }
    }

    override func applicationWillEnterForeground(_ application: UIApplication) {
        super.applicationWillEnterForeground(application)
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        super.applicationDidEnterBackground(application)
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
            result(true); return
        }
        if title == lastTitle && artist == lastArtist && isPlaying == lastIsPlaying {
            result(true); return
        }

        lastTitle = title; lastArtist = artist; lastIsPlaying = isPlaying
        pendingMetadataUpdate = args
        metadataDebounceTimer?.invalidate()
        metadataDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.applyPendingMetadataUpdate()
        }
        result(true)
    }

    private func handleUpdateNowPlaying(call: FlutterMethodCall, result: FlutterResult) {
        if isSettingArtwork { result(false); return }
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let artist = args["artist"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        let album = args["album"] as? String ?? "WBAI 99.5 FM"
        let artworkUrl = args["artworkUrl"] as? String
        let isPlaying = args["isPlaying"] as? Bool ?? true

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue
        ]

        if let artworkUrlString = artworkUrl, artworkUrlString == self.lastArtworkUrl, let cached = self.cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = cached
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            result(true); return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        result(true)

        if let artworkUrlString = artworkUrl, !artworkUrlString.isEmpty,
           artworkUrlString != self.lastArtworkUrl, let url = URL(string: artworkUrlString) {
            downloadArtworkWithTimeout(url: url, artworkUrl: artworkUrlString, timeout: 3.0) { [weak self] image in
                guard let self = self, let image = image else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.cachedArtwork = artwork; self.lastArtworkUrl = artworkUrlString
                self.isSettingArtwork = true
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                updated[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.isSettingArtwork = false }
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
            if let url = currentArtworkUrl, url == self.lastArtworkUrl, let cached = self.cachedArtwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = cached
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                return
            }

            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

            if let artworkUrl = currentArtworkUrl, artworkUrl != self.lastArtworkUrl,
               let url = URL(string: artworkUrl) {
                self.downloadArtworkWithTimeout(url: url, artworkUrl: artworkUrl, timeout: 3.0) { [weak self] image in
                    guard let self = self, let image = image else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.cachedArtwork = artwork; self.lastArtworkUrl = artworkUrl
                    self.isSettingArtwork = true
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? nowPlayingInfo
                    updated[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.isSettingArtwork = false }
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
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                timer.invalidate()
                if !completed {
                    completed = true
                    completion(data.flatMap { UIImage(data: $0) })
                }
            }
        }.resume()
    }
}
