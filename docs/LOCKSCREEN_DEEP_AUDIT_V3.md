# 🔴 LOCKSCREEN ARTWORK BUG - DEEP FORENSIC AUDIT V3

## 🚨 CRITICAL DISCOVERY: IMAGE FLASHING ON/OFF

**USER REPORT**: "I saw the image flash on and off in the lockscreen"

**THIS IS THE SMOKING GUN** - It proves:
1. ✅ Artwork IS being downloaded successfully
2. ✅ Artwork IS being set on lockscreen
3. ❌ Something is **IMMEDIATELY OVERRIDING** it and removing it
4. ❌ Multiple systems are **FIGHTING** for control

---

## 🔍 COMPLETE SYSTEM AUDIT

### System 1: AppDelegate.swift (Our Fix)
**Location**: `/ios/Runner/AppDelegate.swift`
**Method**: `applyPendingMetadataUpdate()` (line 146-185)

**What it does**:
```swift
// Line 149: Sets lockscreen IMMEDIATELY
MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

// Line 159-172: Downloads artwork asynchronously
downloadArtworkWithTimeout(...) { image in
    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
    updatedInfo[MPMediaItemPropertyArtwork] = artwork
    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo  // ← Sets artwork
}
```

**Status**: ✅ Working - Sets artwork successfully

---

### System 2: MetadataController.swift (POTENTIAL CULPRIT)
**Location**: `/ios/Runner/MetadataController.swift`
**Method**: `performMetadataUpdate()` (line 215-319)

**CRITICAL FINDING**: Has a **FORENSIC TIMER** that runs **EVERY SECOND**!

**Line 18-40**: Forensic logging timer
```swift
forensicLogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    
    // CRITICAL: Checks if metadata was overridden
    if (currentTitle != lastTitle || currentArtist != lastArtist) {
        print("[FORENSIC][OVERRIDE] Detected metadata override!")
        self.reapplyLastMetadata()  // ← RE-APPLIES METADATA
    }
}
```

**Line 57-71**: Reapply metadata function
```swift
private func reapplyLastMetadata() {
    self.updateMetadata(
        title: lastTitle,
        artist: lastArtist,
        artworkUrl: self.lastArtworkUrl,
        isPlaying: self.lastIsPlaying,
        forceUpdate: true
    )
}
```

**Line 289-313**: Downloads artwork and sets metadata
```swift
URLSession.shared.dataTask(with: url) { data, response, error in
    if let data = data, let image = UIImage(data: data) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        var freshInfo = updatedNowPlayingInfo
        freshInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = freshInfo  // ← SETS METADATA
    }
}.resume()
```

**Line 318**: Sets metadata WITHOUT artwork if no URL
```swift
MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo  // ← NO ARTWORK
```

**STATUS**: ⚠️ **SUSPICIOUS** - But is it being used?

---

### System 3: KPFKAudioHandler (Flutter Audio Service)
**Location**: `/lib/services/audio_service/kpfk_audio_handler.dart`
**Method**: `updateMediaItem()` (line 659-688)

**What it does**:
```dart
Future<void> updateMediaItem(MediaItem mediaItem) async {
  LoggerService.info('🔍 METADATA BATTLE: updateMediaItem() called');
  
  // iOS: Ignore to keep Swift as single source of truth
  if (Platform.isIOS) {
    LoggerService.info('🎵 IGNORING MediaItem update - using Swift implementation only');
    return;  // ← DOES NOTHING ON iOS
  }
}
```

**STATUS**: ✅ Correctly ignoring iOS updates

---

### System 4: StreamRepository (Flutter)
**Location**: `/lib/data/repositories/stream_repository.dart`
**Method**: `_updateMediaMetadata()` (line 338-434)

**What it does**:
```dart
// Line 409: Calls audio handler
_audioHandler.updateMediaItem(mediaItem);

// Line 422-427: ALSO calls native iOS service
if (Platform.isIOS) {
  _nativeMetadataService.updateLockscreenMetadata(
    title: title,
    artist: artist,
    artworkUrl: showInfo.hostImage,  // ← PASSES ARTWORK URL
    isPlaying: isPlaying,
  );
}
```

**STATUS**: ✅ Correctly calling native service

---

### System 5: NativeMetadataService (Flutter → iOS Bridge)
**Location**: `/lib/services/metadata_service_native.dart`
**Method**: `updateLockscreenMetadata()` (line 182-282)

**What it does**:
```dart
final Map<String, dynamic> metadata = {
  'title': title,
  'artist': artist,
  'isPlaying': isPlaying,
  'artworkUrl': artworkUrl,  // ← INCLUDES ARTWORK URL
};

await _channel.invokeMethod('updateMetadata', metadata);  // ← CALLS iOS
```

**STATUS**: ✅ Correctly passing artwork URL to iOS

---

## 🔴 ROOT CAUSE ANALYSIS

### The Flash Sequence (What's Happening):

```
Time 0ms:    User presses play
Time 50ms:   AppDelegate sets lockscreen with text (no artwork)
Time 100ms:  Artwork download starts
Time 500ms:  Artwork download completes
Time 550ms:  AppDelegate sets lockscreen WITH ARTWORK ✅ (USER SEES THIS)
Time 551ms:  ??? SOMETHING OVERRIDES IT ???
Time 552ms:  Lockscreen shows NO ARTWORK ❌ (USER SEES THIS)
```

### Possible Culprits:

#### Hypothesis 1: MetadataController is Active ⭐⭐⭐⭐⭐
**Evidence**:
- MetadataController has a timer that runs every second
- It calls `reapplyLastMetadata()` which sets `MPNowPlayingInfoCenter`
- It downloads artwork asynchronously
- **BUT**: Is it being initialized?

**Test**: Check if MetadataController is being used

#### Hypothesis 2: just_audio Plugin Override ⭐⭐⭐⭐
**Evidence**:
- `just_audio` plugin is installed
- It might be setting its own metadata
- Could be overriding our metadata

**Test**: Check just_audio source code for MPNowPlayingInfoCenter usage

#### Hypothesis 3: audio_service Plugin Override ⭐⭐⭐
**Evidence**:
- `audio_service` plugin manages lockscreen
- Might be setting default metadata
- Could be clearing artwork

**Test**: Check audio_service source code

#### Hypothesis 4: Multiple Async Downloads Competing ⭐⭐
**Evidence**:
- AppDelegate downloads artwork
- MetadataController (if active) downloads artwork
- Both set MPNowPlayingInfoCenter
- Race condition possible

**Test**: Add timestamps to all MPNowPlayingInfoCenter updates

#### Hypothesis 5: iOS System Caching Issue ⭐
**Evidence**:
- iOS might be caching old metadata
- System might be reverting to cached state

**Test**: Force clear iOS metadata cache

---

## 🧪 DIAGNOSTIC TESTS

### Test 1: Check if MetadataController is Active
**Add to AppDelegate.swift** (in `didFinishLaunchingWithOptions`):
```swift
print("[DEBUG] ========================================")
print("[DEBUG] MetadataController.shared exists: \(MetadataController.self)")
print("[DEBUG] ========================================")
```

**Expected**: Should show if MetadataController is being used

### Test 2: Add Timestamps to All MPNowPlayingInfoCenter Updates
**Add to every MPNowPlayingInfoCenter.default().nowPlayingInfo = line**:
```swift
let timestamp = Date().timeIntervalSince1970
print("[TIMESTAMP] Setting MPNowPlayingInfoCenter at \(timestamp)")
print("[TIMESTAMP] Has artwork: \(nowPlayingInfo[MPMediaItemPropertyArtwork] != nil)")
print("[TIMESTAMP] Title: \(nowPlayingInfo[MPMediaItemPropertyTitle] as? String ?? "nil")")
```

**Expected**: Will show exact timing of all updates

### Test 3: Monitor for Overrides
**Add to AppDelegate after setting metadata**:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
    let hasArtwork = current?[MPMediaItemPropertyArtwork] != nil
    print("[VERIFY] 100ms later - Artwork still present: \(hasArtwork)")
    if !hasArtwork {
        print("[VERIFY] ❌ ARTWORK WAS REMOVED BY SOMETHING!")
    }
}
```

**Expected**: Will catch if something removes artwork immediately

### Test 4: Disable MetadataController
**Comment out in AppDelegate.swift** (if it exists):
```swift
// MetadataController.shared.setMethodChannel(...)
// MetadataController.shared.startForensicMetadataLogging()
```

**Expected**: If MetadataController is the culprit, artwork will persist

---

## 🎯 RECOMMENDED FIX STRATEGY

### Option A: Disable MetadataController Completely
If MetadataController is active and fighting with AppDelegate:
```swift
// In AppDelegate.swift, comment out all MetadataController references
// Use ONLY AppDelegate for metadata management
```

### Option B: Synchronize Both Systems
If both systems are needed:
```swift
// Make MetadataController use AppDelegate's cached artwork
// Prevent duplicate downloads
// Ensure they don't override each other
```

### Option C: Add Artwork Persistence Check
After setting artwork, verify it persists:
```swift
func setMetadataWithVerification(_ info: [String: Any]) {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    
    // Verify it stuck
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
        if current?[MPMediaItemPropertyArtwork] == nil && info[MPMediaItemPropertyArtwork] != nil {
            // Artwork was removed! Set it again
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
```

### Option D: Lock MPNowPlayingInfoCenter Updates
Prevent multiple systems from updating simultaneously:
```swift
private var isUpdatingMetadata = false

func setMetadata(_ info: [String: Any]) {
    guard !isUpdatingMetadata else {
        print("[LOCK] Metadata update in progress, queuing...")
        return
    }
    
    isUpdatingMetadata = true
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.isUpdatingMetadata = false
    }
}
```

---

## 🔬 NEXT STEPS

### Immediate Actions (5 minutes):
1. Add timestamp logging to ALL MPNowPlayingInfoCenter updates
2. Run app and capture complete log
3. Identify EXACT sequence of updates
4. Find what's removing artwork

### Investigation (15 minutes):
1. Check if MetadataController is being initialized
2. Search for ALL MPNowPlayingInfoCenter references
3. Check just_audio and audio_service plugin source
4. Identify the override source

### Fix Implementation (30 minutes):
1. Disable competing system (MetadataController or plugin)
2. OR synchronize systems to prevent conflicts
3. Add verification/persistence checks
4. Test thoroughly

---

## 📊 EVIDENCE CHECKLIST

- [x] Image shows in main app (URL valid)
- [x] Image flashes on lockscreen (download works)
- [x] Image disappears immediately (override happening)
- [ ] Timestamp logs captured
- [ ] Override source identified
- [ ] Fix implemented
- [ ] Fix tested and verified

---

**Status**: 🔴 **ROOT CAUSE NOT YET IDENTIFIED - NEED TIMESTAMP LOGS**
**Priority**: **CRITICAL** - Multiple systems fighting for control
**Next Step**: Add comprehensive timestamp logging to identify override source
