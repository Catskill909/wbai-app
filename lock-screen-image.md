# Lock Screen Image Metadata Analysis

## Problem Statement
The lock screen and notification audio controls display text metadata (title, artist) correctly, but the image metadata from the same API is not showing. The image works perfectly in the app's main view, indicating the API and image data are correct.

## Current Status
- ✅ **Text Metadata**: Shows correctly on lock screen and notification controls
- ❌ **Image Metadata**: Missing from lock screen and notification controls  
- ✅ **Image in App**: Displays correctly in main app view
- ✅ **API Data**: Both text and image are present in the same API response

## Key Insight
The image should follow the **exact same path** as the working text metadata, not be handled separately.

## Metadata Flow Analysis

### 1. API Data Source
**Location**: `lib/data/repositories/stream_repository.dart`
- API provides both text and image metadata in same response
- Text metadata: `showName`, `host`, etc.
- Image metadata: `hostImage` URL

### 2. Working Text Metadata Path
Based on logs from flutter run:

```
🎵 SHOW: "Capitalism, Race & Democracy", HOST: "National Program"
🎵 SENDING TO LOCKSCREEN: Title="Capitalism, Race & Democracy", Artist="Host: National Program"  
🔒 NATIVE: Updating iOS lockscreen metadata
🔒 NATIVE: Title="Capitalism, Race & Democracy", Artist="Host: National Program", IsPlaying=true
🔒 NATIVE: Lockscreen metadata updated successfully via invokeMethod
```

**Successful Flow**:
1. API → StreamRepository → MetadataService
2. MetadataService → NativeMetadataService 
3. NativeMetadataService → `com.wpfwfm.radio/metadata` channel
4. AppDelegate.swift → `handleUpdateMetadata` → MPNowPlayingInfoCenter

### 3. Current Image Metadata Issues

#### Issue 1: Multiple Competing Services
- `IOSLockscreenService` (uses `com.wpfwfm.radio/now_playing` channel)
- `NativeMetadataService` (uses `com.wpfwfm.radio/metadata` channel) ✅ **This is the working one**
- `LockscreenService` (uses `com.wpfwfm.radio/metadata` channel)

#### Issue 2: Image Not Following Working Path
The working text metadata uses `NativeMetadataService` → `com.wpfwfm.radio/metadata` channel.
The image needs to follow this **exact same path**.

## Code Structure Analysis

### Flutter Side (Working Text Path)

#### 1. StreamRepository
**File**: `lib/data/repositories/stream_repository.dart`
- Receives API data with both text and image
- Processes metadata and sends to lockscreen

#### 2. NativeMetadataService (The Working Service)
**File**: `lib/services/metadata_service_native.dart`
- Method: `updateLockscreenMetadata()`
- Channel: `com.wpfwfm.radio/metadata`
- **Status**: ✅ Successfully handles text metadata

#### 3. Current Image Handling Issue
Looking at `NativeMetadataService.updateLockscreenMetadata()`:

```dart
// Add artwork if available
if (artworkUrl != null && artworkUrl.isNotEmpty) {
  metadata['artworkUrl'] = artworkUrl;
}

// Send to native code
await _channel.invokeMethod('updateMetadata', metadata);
```

**The image URL is being sent to the native side!**

### iOS Native Side (Working Text Path)

#### 1. AppDelegate.swift
**Channel**: `com.wpfwfm.radio/metadata`
**Method**: `handleUpdateMetadata`

**Current Implementation**:
```swift
private func handleUpdateMetadata(call: FlutterMethodCall, result: FlutterResult) {
    // Extract metadata from arguments
    guard let args = call.arguments as? [String: Any],
          let title = args["title"] as? String,
          let artist = args["artist"] as? String,
          let isPlaying = args["isPlaying"] as? Bool else {
        // Error handling
        return
    }
    
    // ❌ MISSING: artworkUrl extraction and handling
    // The artworkUrl is being sent but not processed!
}
```

## Root Cause Identified ✅

**CRITICAL INSIGHT: It's a Refresh/Timing Issue!**

The user confirmed that **the image sometimes appears on the lock screen**, which means:

1. ✅ **The path is correct** - Image can reach the lock screen
2. ✅ **The iOS implementation works** - It can display images  
3. ✅ **The API and data are correct** - Same data works in main app
4. ❌ **It's a refresh/synchronization issue** - Image doesn't always update when metadata changes

**This is NOT a broken implementation - it's a timing/refresh problem!**

The lock screen image refresh is not properly synchronized with the main app metadata updates.

## The Real Problem

**Main App Refresh**: ✅ Always updates image when metadata changes
**Lock Screen Refresh**: ❌ Sometimes updates, sometimes doesn't

This suggests:
- Race condition between text and image updates
- Caching issues in iOS MPNowPlayingInfoCenter
- Timing issues with asynchronous image loading
- Metadata refresh not triggering image refresh consistently

## Solution Required

**Fix the existing working path** by modifying `handleUpdateMetadata` in `AppDelegate.swift` to:

1. Extract the `artworkUrl` parameter (just like title/artist)
2. Download the image asynchronously  
3. Set the artwork in MPNowPlayingInfoCenter (just like title/artist)

This ensures the image follows the **exact same successful path** as the text metadata.

## Files That Need Modification

### Primary Fix Required
- **`ios/Runner/AppDelegate.swift`** - `handleUpdateMetadata` method
  - Add artworkUrl extraction
  - Add asynchronous image loading
  - Add artwork to MPNowPlayingInfoCenter

### Files That Should NOT Be Modified
- ✅ `lib/services/metadata_service_native.dart` - Already sends artworkUrl correctly
- ✅ `lib/data/repositories/stream_repository.dart` - Already provides image data
- ✅ Text metadata handling - Already works perfectly

## Expected Result
After fixing `handleUpdateMetadata` in AppDelegate.swift:
- Text metadata continues working exactly as before
- Image metadata will appear on lock screen and notification controls
- Single, consistent metadata path for both text and image
