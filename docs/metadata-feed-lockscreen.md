# iOS Lockscreen Metadata Image Bug - Deep Analysis & Fix

## Problem Statement
The metadata image (show artwork) displays correctly in the main app screen but does NOT show immediately in the iOS lockscreen player controls or notification tray when the app first starts. The image eventually appears, but there's a delay that creates a poor user experience.

## Root Cause Analysis

### 1. **Artwork Loading Race Condition**
The primary issue is a **race condition** between metadata updates and artwork downloads:

```
App Start → Metadata Fetch → Update Lockscreen → Download Artwork (async)
                                      ↓
                            Lockscreen shows text FIRST
                                      ↓
                            Artwork downloads LATER
```

**Key Problem**: The lockscreen is updated with text metadata BEFORE the artwork image has been downloaded.

### 2. **Current Flow Analysis**

#### **Step 1: App Initialization**
```
AppDelegate.swift (line 44-45):
- setupDefaultMetadata() is DISABLED (good - was clearing artwork)
- But NO initial artwork is set
```

#### **Step 2: Metadata Service Starts**
```dart
// metadata_service.dart (line 28-30)
MetadataService() {
  _fetchMetadata(); // Initial fetch
}
```

#### **Step 3: Metadata Arrives**
```dart
// stream_repository.dart (line 139-146)
_metadataSubscription = _metadataService.metadataStream.listen(
  (metadata) {
    _currentMetadata = metadata;
    _metadataController.add(metadata);
    _updateMediaMetadata(metadata); // ← TRIGGERS LOCKSCREEN UPDATE
  }
);
```

#### **Step 4: Lockscreen Update (THE PROBLEM)**
```dart
// stream_repository.dart (line 422-427)
_nativeMetadataService.updateLockscreenMetadata(
  title: title,
  artist: artist,
  artworkUrl: showInfo.hostImage, // ← URL passed, not image
  isPlaying: isPlaying,
);
```

#### **Step 5: Native iOS Processing**
```swift
// AppDelegate.swift (line 108-187)
private func applyPendingMetadataUpdate() {
  // 1. Set metadata with text IMMEDIATELY (line 154)
  MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  
  // 2. Download artwork ASYNCHRONOUSLY (line 157-177)
  if let artworkUrl = currentArtworkUrl, artworkUrl != self.lastArtworkUrl {
    self.downloadArtworkWithRetry(url: url, artworkUrl: artworkUrl) { image in
      // This happens LATER, after lockscreen already displayed
    }
  }
}
```

### 3. **The Critical Gap**

**Line 154** in `AppDelegate.swift`:
```swift
MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
```
This sets the lockscreen metadata **WITHOUT artwork** because the artwork hasn't been downloaded yet.

**Lines 162-177**: The artwork download happens asynchronously and updates the lockscreen LATER when complete.

**Result**: User sees blank artwork initially, then it pops in later.

## Solution Strategy

### **Option A: Delay Lockscreen Update Until Artwork Ready** ⭐ RECOMMENDED
Wait for artwork to download before setting the lockscreen metadata.

**Pros:**
- Clean user experience - artwork appears immediately
- No visual "pop-in" effect
- Matches user expectations

**Cons:**
- Slight delay before lockscreen shows anything
- Need timeout fallback if artwork fails to load

### **Option B: Pre-cache Artwork**
Download and cache artwork before updating lockscreen.

**Pros:**
- Instant display on subsequent updates
- Reduces network calls

**Cons:**
- More complex cache management
- Still has delay on first show

### **Option C: Show Placeholder Image**
Display a default KPFK logo while artwork downloads.

**Pros:**
- Immediate visual feedback
- Professional appearance

**Cons:**
- Requires bundled asset
- Still shows a "change" when real artwork loads

## Recommended Fix: Option A with Timeout

### Implementation Plan

#### **1. Modify AppDelegate.swift - Delay Metadata Update**

**Current behavior:**
```swift
// Set metadata immediately
MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

// Download artwork later
if let artworkUrl = currentArtworkUrl {
  downloadArtworkWithRetry(url: url) { image in
    // Update again with artwork
  }
}
```

**New behavior:**
```swift
// If artwork URL exists, wait for download
if let artworkUrl = currentArtworkUrl, artworkUrl != self.lastArtworkUrl {
  // Download FIRST
  downloadArtworkWithRetry(url: url, timeout: 3.0) { image in
    if let image = image {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
    }
    // Set metadata AFTER artwork ready (or timeout)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }
} else {
  // No artwork or same artwork - update immediately
  MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
}
```

#### **2. Add Timeout to Artwork Download**

Add a timeout parameter to prevent indefinite waiting:

```swift
private func downloadArtworkWithRetry(
  url: URL, 
  artworkUrl: String, 
  maxRetries: Int = 2,
  timeout: TimeInterval = 3.0, // ← NEW
  completion: @escaping (UIImage?) -> Void
) {
  // Implement timeout logic
  let timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
    print("[METADATA] ⏱️ Artwork download timeout - proceeding without image")
    completion(nil)
  }
  
  // Existing download logic...
  // Cancel timer on success
}
```

#### **3. Preserve Cached Artwork**

The code already has caching logic (lines 143-151), but we need to ensure it's used correctly:

```swift
// Use cached artwork immediately if available
if let currentUrl = currentArtworkUrl, 
   currentUrl == self.lastArtworkUrl, 
   let cachedArtwork = self.cachedArtwork {
  nowPlayingInfo[MPMediaItemPropertyArtwork] = cachedArtwork
  MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  return // ← Early return, no download needed
}
```

## Detailed Code Changes

### File: `/ios/Runner/AppDelegate.swift`

#### Change 1: Modify `applyPendingMetadataUpdate()` method

**Location**: Lines 108-188

**Current Issue**: Sets metadata immediately, downloads artwork later

**Fix**: Wait for artwork download before setting metadata (with timeout)

#### Change 2: Add timeout to `downloadArtworkWithRetry()`

**Location**: Lines 191-262

**Current Issue**: No timeout - can wait indefinitely

**Fix**: Add timeout parameter and timer to ensure metadata updates even if download fails

#### Change 3: Optimize cached artwork path

**Location**: Lines 143-151

**Current Issue**: Cached artwork is set but then overwritten

**Fix**: Early return when using cached artwork to prevent unnecessary updates

### File: `/ios/Runner/MetadataController.swift`

Similar changes needed in the `MetadataController` class for consistency.

## Testing Plan

### Test Case 1: Fresh App Start
1. Kill app completely
2. Start app
3. Press play
4. **Expected**: Lockscreen shows artwork within 3 seconds
5. **Verify**: No blank artwork period

### Test Case 2: Show Change
1. App running with show A
2. Wait for show B to start
3. **Expected**: Lockscreen updates with new artwork
4. **Verify**: No flicker or blank period

### Test Case 3: Network Slow/Failure
1. Enable network throttling (slow 3G)
2. Start app and play
3. **Expected**: Lockscreen shows text within 3 seconds even if artwork fails
4. **Verify**: Graceful fallback

### Test Case 4: Cached Artwork
1. Play show A (artwork downloads)
2. Pause
3. Play again
4. **Expected**: Artwork appears instantly from cache
5. **Verify**: No re-download

## Metrics to Track

- **Time to First Artwork**: Should be < 3 seconds
- **Cache Hit Rate**: Should be > 80% for same show
- **Fallback Rate**: Track how often timeout triggers
- **User Experience**: No visible blank artwork period

## Alternative Considerations

### Why Not Pre-load on App Start?
- Don't know which show is playing until metadata fetched
- Wastes bandwidth if user doesn't play
- Better to optimize the critical path

### Why Not Use Placeholder?
- Adds visual complexity
- Still shows a "change" when real artwork loads
- Better to wait briefly for real artwork

### Why 3 Second Timeout?
- Balance between waiting for artwork and user experience
- Most images download in < 1 second on good connection
- 3 seconds is acceptable wait for lockscreen to appear
- Prevents indefinite waiting on poor connections

## Implementation Priority

1. **High Priority**: Add timeout to artwork download
2. **High Priority**: Wait for artwork before setting metadata
3. **Medium Priority**: Optimize cached artwork path
4. **Low Priority**: Add metrics/logging for monitoring

## Success Criteria

✅ Lockscreen shows artwork within 3 seconds of play button press
✅ No visible blank artwork period
✅ Graceful fallback if artwork fails to load
✅ Cached artwork displays instantly
✅ No performance regression

## Related Files

- `/ios/Runner/AppDelegate.swift` - Main metadata handling
- `/ios/Runner/MetadataController.swift` - Alternative metadata controller
- `/lib/services/metadata_service_native.dart` - Dart-side native service
- `/lib/data/repositories/stream_repository.dart` - Metadata flow orchestration
- `/lib/services/metadata_service.dart` - Metadata fetching

## Notes

- The app already has retry logic for artwork downloads (good!)
- Caching logic exists but needs optimization
- Two separate metadata channels exist (com.kpfkfm.radio/metadata and com.kpfkfm.radio/now_playing) - may need consolidation
- MetadataController.swift has similar logic - changes should be applied there too
