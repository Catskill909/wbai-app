# Plan B: Native iOS Audio Implementation

## Overview

After extensive efforts to solve the iOS lockscreen metadata and controls issues using just_audio and platform channel approaches, this document outlines an alternative solution: a hybrid approach that leverages native iOS audio capabilities while maintaining the existing Flutter UI.

## Key Approach

The core concept is to **completely replace the audio playback system on iOS with a native implementation**, while keeping the existing Flutter UI, view models, and metadata systems. This creates a clean separation of concerns:

1. **Flutter Layer**: Handles UI, metadata fetching, and commands to the native layer
2. **Native iOS Layer**: Handles all audio playback, session management, and lockscreen controls/metadata

## Architecture

```
┌────────────── Flutter ──────────────┐     ┌────────────── Native iOS ──────────────┐
│                                      │     │                                         │
│  ┌─────────────┐    ┌─────────────┐  │     │  ┌────────────┐    ┌────────────────┐  │
│  │ Flutter UI  │    │  Metadata   │  │     │  │            │    │ MPNowPlaying   │  │
│  │ & View      │◄───┤  Service    │  │     │  │            │    │ InfoCenter     │  │
│  │ Models      │    │  (existing) │  │     │  │  AVPlayer  │───►│ (lockscreen    │  │
│  └──────┬──────┘    └──────┬──────┘  │     │  │  Manager   │    │ metadata)      │  │
│         │                  │         │     │  │            │    │                │  │
│         ▼                  ▼         │     │  │            │    └────────────────┘  │
│  ┌─────────────────────────────────┐ │     │  │            │    ┌────────────────┐  │
│  │                                 │ │     │  │            │    │ MPRemoteCommand │  │
│  │  Native Audio Platform Channel  │◄┼─────┼──┤            │◄───┤ Center         │  │
│  │                                 │ │     │  │            │    │ (lockscreen    │  │
│  └─────────────────────────────────┘ │     │  │            │    │ controls)      │  │
│                                      │     │  └────────────┘    └────────────────┘  │
└──────────────────────────────────────┘     └─────────────────────────────────────────┘
```

## Implementation Plan

### 1. Create Native iOS Audio Manager

```swift
// NativeAudioManager.swift
import AVFoundation
import MediaPlayer

class NativeAudioManager: NSObject {
    static let shared = NativeAudioManager()
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var methodChannel: FlutterMethodChannel?
    private var isPlaying = false
    
    // Metadata storage
    private var currentTitle: String = "WPFW Radio"
    private var currentArtist: String = "WPFW 89.3 FM"
    private var currentArtworkUrl: String?
    
    func initialize(with channel: FlutterMethodChannel) {
        self.methodChannel = channel
        setupAudioSession()
        setupRemoteCommands()
    }
    
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[NATIVE] Failed to set up audio session: \(error)")
        }
    }
    
    func setupPlayer(withUrl url: String) {
        guard let streamUrl = URL(string: url) else { return }
        playerItem = AVPlayerItem(url: streamUrl)
        player = AVPlayer(playerItem: playerItem)
        
        // Add observers for playback state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        player?.addObserver(
            self,
            forKeyPath: "status",
            options: [.new, .old],
            context: nil
        )
    }
    
    func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        notifyFlutterOfPlaybackChange()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        notifyFlutterOfPlaybackChange()
    }
    
    func updateMetadata(title: String, artist: String, artworkUrl: String?) {
        currentTitle = title
        currentArtist = artist
        currentArtworkUrl = artworkUrl
        updateNowPlayingInfo()
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        
        // Set metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentArtist
        
        // Add playback info
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // Add timestamp to force update
        nowPlayingInfo["_timestamp"] = Date().timeIntervalSince1970
        
        // Set the info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Load artwork asynchronously if available
        if let artworkUrl = currentArtworkUrl, let url = URL(string: artworkUrl) {
            loadArtwork(from: url) { [weak self] image in
                guard let self = self, let image = image else { return }
                
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
    
    private func loadArtwork(from url: URL, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Disable all commands first
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.play()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }
        
        // Toggle command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.pause()
            } else {
                self.play()
            }
            return .success
        }
    }
    
    private func notifyFlutterOfPlaybackChange() {
        methodChannel?.invokeMethod(
            "playbackStateChanged",
            arguments: ["isPlaying": isPlaying]
        )
    }
    
    @objc private func playerItemDidPlayToEndTime() {
        // For streaming, this usually means an error or end of stream
        methodChannel?.invokeMethod("streamEnded", arguments: nil)
    }
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "status", let player = object as? AVPlayer {
            switch player.status {
            case .readyToPlay:
                methodChannel?.invokeMethod("playerReady", arguments: nil)
            case .failed:
                methodChannel?.invokeMethod(
                    "playerError",
                    arguments: ["error": player.error?.localizedDescription ?? "Unknown error"]
                )
            default:
                break
            }
        }
    }
}
```

### 2. AppDelegate Integration

```swift
// AppDelegate.swift
import UIKit
import Flutter
import AVFoundation
import MediaPlayer

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private var nativeAudioChannel: FlutterMethodChannel?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        
        // Set up native audio channel
        nativeAudioChannel = FlutterMethodChannel(
            name: "com.wpfwfm.radio/native_audio",
            binaryMessenger: controller.binaryMessenger
        )
        
        // Initialize the native audio manager
        NativeAudioManager.shared.initialize(with: nativeAudioChannel!)
        
        // Handle method calls from Flutter
        setupMethodCallHandler()
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func setupMethodCallHandler() {
        nativeAudioChannel?.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            
            print("[NATIVE] Received method call: \(call.method)")
            
            switch call.method {
            case "setupPlayer":
                if let args = call.arguments as? [String: Any], 
                   let url = args["url"] as? String {
                    NativeAudioManager.shared.setupPlayer(withUrl: url)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing URL", details: nil))
                }
                
            case "play":
                NativeAudioManager.shared.play()
                result(true)
                
            case "pause":
                NativeAudioManager.shared.pause()
                result(true)
                
            case "updateMetadata":
                if let args = call.arguments as? [String: Any],
                   let title = args["title"] as? String,
                   let artist = args["artist"] as? String {
                    let artworkUrl = args["artworkUrl"] as? String
                    NativeAudioManager.shared.updateMetadata(
                        title: title,
                        artist: artist,
                        artworkUrl: artworkUrl
                    )
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Invalid metadata", details: nil))
                }
                
            case "testConnection":
                result("connected")
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
```

### 3. Flutter Native Audio Service

```dart
// native_audio_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import '../logger/logger_service.dart';

class NativeAudioService {
  static const MethodChannel _channel = MethodChannel('com.wpfwfm.radio/native_audio');
  static StreamController<bool> _playbackStateController = StreamController<bool>.broadcast();
  
  // Public stream for UI to listen to
  static Stream<bool> get playbackStateStream => _playbackStateController.stream;
  
  // Current playback state
  static bool _isPlaying = false;
  static bool get isPlaying => _isPlaying;
  
  // Initialize the service
  static Future<void> initialize() async {
    LoggerService.info('🎵 NATIVE: Initializing native audio service');
    
    // Set up method call handler for events from native
    _channel.setMethodCallHandler(_handleMethodCall);
    
    // Test connection to native
    try {
      final result = await _channel.invokeMethod('testConnection');
      LoggerService.info('🎵 NATIVE: Connection test result: $result');
    } catch (e) {
      LoggerService.error('🎵 NATIVE: Failed to connect to native audio service: $e');
    }
  }
  
  // Set up the player with stream URL
  static Future<bool> setupPlayer(String url) async {
    try {
      LoggerService.info('🎵 NATIVE: Setting up player with URL: $url');
      final result = await _channel.invokeMethod('setupPlayer', {'url': url});
      return result == true;
    } catch (e) {
      LoggerService.error('🎵 NATIVE: Failed to set up player: $e');
      return false;
    }
  }
  
  // Play the stream
  static Future<bool> play() async {
    try {
      LoggerService.info('🎵 NATIVE: Playing stream');
      final result = await _channel.invokeMethod('play');
      return result == true;
    } catch (e) {
      LoggerService.error('🎵 NATIVE: Failed to play: $e');
      return false;
    }
  }
  
  // Pause the stream
  static Future<bool> pause() async {
    try {
      LoggerService.info('🎵 NATIVE: Pausing stream');
      final result = await _channel.invokeMethod('pause');
      return result == true;
    } catch (e) {
      LoggerService.error('🎵 NATIVE: Failed to pause: $e');
      return false;
    }
  }
  
  // Update metadata
  static Future<bool> updateMetadata({
    required String title,
    required String artist,
    String? artworkUrl,
  }) async {
    try {
      LoggerService.info('🎵 NATIVE: Updating metadata - Title: $title, Artist: $artist');
      final result = await _channel.invokeMethod('updateMetadata', {
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
      });
      return result == true;
    } catch (e) {
      LoggerService.error('🎵 NATIVE: Failed to update metadata: $e');
      return false;
    }
  }
  
  // Handle method calls from native
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    LoggerService.info('🎵 NATIVE: Received call from native: ${call.method}');
    
    switch (call.method) {
      case 'playbackStateChanged':
        final Map<dynamic, dynamic> args = call.arguments;
        _isPlaying = args['isPlaying'] ?? false;
        _playbackStateController.add(_isPlaying);
        LoggerService.info('🎵 NATIVE: Playback state changed to: $_isPlaying');
        break;
        
      case 'playerReady':
        LoggerService.info('🎵 NATIVE: Player is ready');
        break;
        
      case 'playerError':
        final Map<dynamic, dynamic> args = call.arguments;
        final error = args['error'] ?? 'Unknown error';
        LoggerService.error('🎵 NATIVE: Player error: $error');
        break;
        
      case 'streamEnded':
        LoggerService.info('🎵 NATIVE: Stream ended');
        _isPlaying = false;
        _playbackStateController.add(_isPlaying);
        break;
    }
  }
}
```

### 4. Platform-Specific Player Factory

```dart
// audio_player_factory.dart
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'audio_service_interface.dart';
import 'wpfw_audio_handler.dart';  // Existing implementation
import 'native_audio_service.dart';  // New iOS native implementation

class AudioPlayerFactory {
  static AudioServiceInterface createAudioService() {
    if (Platform.isIOS) {
      return IOSNativeAudioService();
    } else {
      // Use existing implementation for Android and other platforms
      return WPFWAudioHandler();
    }
  }
}

// Interface that both implementations must conform to
abstract class AudioServiceInterface {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> updateMetadata({required String title, required String artist, String? artworkUrl});
  Stream<bool> get playbackStateStream;
  bool get isPlaying;
}

// iOS implementation wrapper
class IOSNativeAudioService implements AudioServiceInterface {
  @override
  Future<void> initialize() async {
    await NativeAudioService.initialize();
    await NativeAudioService.setupPlayer('https://wpfwfm.org:8443/wpfw');
  }
  
  @override
  Future<void> play() async {
    await NativeAudioService.play();
  }
  
  @override
  Future<void> pause() async {
    await NativeAudioService.pause();
  }
  
  @override
  Future<void> updateMetadata({
    required String title,
    required String artist,
    String? artworkUrl,
  }) async {
    await NativeAudioService.updateMetadata(
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
    );
  }
  
  @override
  Stream<bool> get playbackStateStream => NativeAudioService.playbackStateStream;
  
  @override
  bool get isPlaying => NativeAudioService.isPlaying;
}
```

## Integration Steps

1. **Create the native files**:
   - Add `NativeAudioManager.swift` to the iOS project
   - Modify `AppDelegate.swift` to include the native audio channel setup

2. **Create the Flutter files**:
   - Create `native_audio_service.dart` for the iOS-specific implementation
   - Create `audio_player_factory.dart` for platform detection and service creation
   - Create `audio_service_interface.dart` to define the common interface

3. **Update UI to use the factory**:
   - Replace direct references to `WPFWAudioHandler` with the factory-created instance
   - Ensure metadata updates are passed to the appropriate implementation

## Benefits

1. **Clean Separation**: The Flutter UI remains unchanged, but the underlying audio implementation is platform-specific
2. **Native Lockscreen Integration**: No more fighting with just_audio_background on iOS
3. **Reliable Controls**: Native iOS media controls will work as expected
4. **Metadata Consistency**: Single source of truth for metadata on each platform
5. **Better User Experience**: Native implementation will follow platform conventions

## Limitations

1. **Maintenance Overhead**: Two separate audio implementations to maintain
2. **Platform-Specific Bugs**: Issues may arise on one platform but not the other
3. **Feature Parity**: Ensuring both implementations support the same features

## Conclusion

This native iOS audio approach offers a clean break from the integration issues we've been facing with just_audio and just_audio_background. By embracing platform-specific code for the critical audio and lockscreen components, we can provide a much more reliable user experience on iOS while maintaining our existing Flutter UI.

If continued attempts with the current approach fail to resolve the issues, this Plan B provides a clear path forward that should eliminate the core problems we've been struggling with.
