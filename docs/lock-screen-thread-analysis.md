# Lock Screen Image Thread Analysis - Complete Audit

## Problem Statement
**CRITICAL BUG**: Lock screen image appears but then **goes away and comes back**. This indicates something is actively overriding/clearing the image after it's successfully set.

## Key Insight
- ✅ Image loads and displays initially
- ❌ Image gets cleared/overridden by some process
- ✅ Image sometimes reappears later
- **This is NOT a loading issue - it's an OVERRIDE issue**

## All Threads & Services That Touch Lock Screen Metadata

### 1. Flutter Services (Dart Side)

#### A. NativeMetadataService
**File**: `lib/services/metadata_service_native.dart`
**Channel**: `com.wpfwfm.radio/metadata`
**Method**: `updateLockscreenMetadata()`
**Frequency**: Called from StreamRepository
**Potential Issue**: ✅ Sends artworkUrl correctly

#### B. IOSLockscreenService  
**File**: `lib/services/ios_lockscreen_service.dart`
**Channel**: `com.wpfwfm.radio/now_playing` 
**Method**: `updateWithMetadata()`
**Potential Issue**: ⚠️ **COMPETING SERVICE** - Could be overriding

#### C. LockscreenService
**File**: `lib/services/metadata/lockscreen_service.dart`
**Channel**: `com.wpfwfm.radio/metadata`
**Method**: `updateMetadata()`
**Potential Issue**: ⚠️ **NO ARTWORK SUPPORT** - Could be clearing images

#### D. WPFWAudioHandler
**File**: `lib/services/audio_service/wpfw_audio_handler.dart`
**Purpose**: Audio service integration
**Potential Issue**: ⚠️ **JUST_AUDIO_BACKGROUND OVERRIDE** - Known to interfere

### 2. iOS Native Services (Swift Side)

#### A. AppDelegate.swift
**Channels**: 
- `com.wpfwfm.radio/metadata` (handleUpdateMetadata)
- `com.wpfwfm.radio/now_playing` (handleUpdateNowPlaying)
**Potential Issue**: ⚠️ **DUAL CHANNELS** - Race conditions

#### B. MetadataController.swift
**Purpose**: Sophisticated metadata handling with forensic logging
**Status**: ❌ **NOT CONNECTED** - Unused code with good artwork handling

### 3. All Refresh/Update Triggers

#### A. Periodic Metadata Fetches
**File**: `lib/data/repositories/stream_repository.dart`
**Frequency**: Every few seconds
**Calls**: `_nativeMetadataService.updateLockscreenMetadata()`

#### B. Playback State Changes
**File**: `lib/services/audio_service/wpfw_audio_handler.dart`
**Triggers**: Play/Pause/Stop events
**Potential Issue**: ⚠️ **FREQUENT UPDATES** without artwork

#### C. BLoC State Updates
**Files**: Various BLoC files
**Triggers**: UI state changes
**Potential Issue**: ⚠️ **CASCADE UPDATES**

#### D. Audio Session Changes
**File**: iOS `AppDelegate.swift`
**Triggers**: App lifecycle events
**Method**: `configureAudioSession()`

## Suspected Override Sources

### 1. **JUST_AUDIO_BACKGROUND Plugin**
**Evidence**: Comments in `wpfw_audio_handler.dart` mention preventing just_audio_background from controlling lockscreen
```dart
// This prevents just_audio_background from controlling the lockscreen metadata
// Our Swift implementation will handle the lockscreen metadata
```
**Risk**: ⚠️ **HIGH** - Plugin might be overriding artwork with text-only metadata

### 2. **Multiple Competing Services**
**Evidence**: 3 different lockscreen services exist
- NativeMetadataService (with artwork)
- IOSLockscreenService (with artwork)  
- LockscreenService (NO artwork)
**Risk**: ⚠️ **HIGH** - Services might be overriding each other

### 3. **Rapid Refresh Cycles**
**Evidence**: Frequent metadata updates from StreamRepository
**Risk**: ⚠️ **MEDIUM** - Fast updates might clear artwork before it loads

### 4. **Audio Handler State Updates**
**Evidence**: Playback state changes trigger metadata updates
**Risk**: ⚠️ **MEDIUM** - State changes might send text-only updates

## Investigation Required

### Phase 1: Identify the Override Source
1. **Audit all MPNowPlayingInfoCenter.default().nowPlayingInfo assignments**
2. **Find which service is clearing the artwork**
3. **Check for just_audio_background interference**

### Phase 2: Service Consolidation  
1. **Eliminate competing services**
2. **Use single source of truth for lockscreen updates**
3. **Ensure artwork is preserved in all update paths**

### Phase 3: Override Prevention
1. **Block services that don't support artwork**
2. **Implement artwork preservation logic**
3. **Add defensive checks against clearing**

## Files to Audit for MPNowPlayingInfoCenter Usage

### Flutter Files
- `lib/services/metadata_service_native.dart`
- `lib/services/ios_lockscreen_service.dart`
- `lib/services/metadata/lockscreen_service.dart`
- `lib/services/audio_service/wpfw_audio_handler.dart`
- `lib/data/repositories/stream_repository.dart`

### iOS Files  
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/MetadataController.swift`

### Plugin Files (Potential)
- Any just_audio_background related code
- Any audio_service related code

## Next Steps
1. **Search entire codebase for all MPNowPlayingInfoCenter assignments**
2. **Identify which service is clearing the artwork**
3. **Implement single source of truth with artwork preservation**
4. **Block competing services from overriding**

## 🎯 **ROOT CAUSE IDENTIFIED - COMPETING SERVICES OVERRIDE**

### **FOUND THE CULPRITS!**

**Multiple services are writing to `MPNowPlayingInfoCenter.default().nowPlayingInfo` and overriding each other:**

#### **AppDelegate.swift - MULTIPLE Assignments:**
1. **Line 34**: `setupDefaultMetadata()` - Sets default metadata **WITHOUT artwork**
2. **Line 144**: `applyPendingMetadataUpdate()` - Sets metadata **WITHOUT artwork initially**  
3. **Line 181**: `applyPendingMetadataUpdate()` - Sets metadata **WITH artwork later (async)**
4. **Line 393**: `handleUpdateNowPlaying()` - Sets metadata **WITHOUT artwork initially**
5. **Line 406**: `handleUpdateNowPlaying()` - Sets metadata **WITH artwork later (async)**
6. **Line 423**: `handleClearNowPlaying()` - **CLEARS all metadata**

#### **MetadataController.swift - Additional Assignments:**
7. **Line 298**: Sets metadata with artwork
8. **Line 318**: Sets metadata without artwork  
9. **Line 336**: **CLEARS all metadata**

### **The Override Pattern:**
1. ✅ Service A sets metadata **WITH artwork** 
2. ❌ Service B immediately sets metadata **WITHOUT artwork** → **IMAGE DISAPPEARS**
3. ✅ Service A's async artwork loads and sets metadata **WITH artwork** → **IMAGE REAPPEARS**
4. ❌ Service C sets metadata **WITHOUT artwork** → **IMAGE DISAPPEARS AGAIN**

**This explains the "appears but goes away and comes back" behavior!**

## Critical Questions ✅ **ANSWERED**
1. **Which service is making the text-only updates that clear artwork?** → **MULTIPLE: Both channels + default setup**
2. **Is just_audio_background plugin overriding our artwork?** → **SECONDARY: Main issue is competing native services**
3. **Are there hidden timer-based updates clearing metadata?** → **YES: setupDefaultMetadata() and multiple refresh cycles**
4. **Is the audio handler sending updates without artwork?** → **YES: Multiple handlers sending text-only updates**
