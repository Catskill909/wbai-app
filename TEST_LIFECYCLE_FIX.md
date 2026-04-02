# 🧪 TEST: Lifecycle Artwork Fix

## ✅ WHAT WE FIXED

1. **Lifecycle handler now includes artwork URL** when refreshing metadata
2. **Added verification logging** for cached artwork display

## 🔍 WHAT TO LOOK FOR IN LOGS

### When You Lock/Unlock Phone (Lifecycle Refresh):

**EXPECTED LOGS:**
```
[LIFECYCLE] App did become active
[LIFECYCLE] Refreshing metadata on become active: Democracy Now! by Host: Amy Goodman
[LIFECYCLE] Including artwork URL: https://confessor.kpfk.org/pix/democracy_now_97.jpg  ← ✅ GOOD!
[TIMESTAMP-xxx] ⚡ Using CACHED artwork for lockscreen  ← ✅ NEW!
[TIMESTAMP-xxx] Title: Democracy Now!, Artist: Host: Amy Goodman
[TIMESTAMP-xxx] Cached artwork URL: https://confessor.kpfk.org/pix/democracy_now_97.jpg
[TIMESTAMP-xxx] ✅ Lockscreen set with CACHED artwork  ← ✅ NEW!
[VERIFY-CACHED-100ms] Artwork present: true  ← ✅ CRITICAL!
```

**BAD LOGS (If still broken):**
```
[VERIFY-CACHED-100ms] Artwork present: false  ← ❌ PROBLEM!
[VERIFY-CACHED-100ms] ❌ CACHED ARTWORK DISAPPEARED!
```

## 🧪 TEST PROCEDURE

1. **Start app and play audio**
   ```bash
   cd /Users/paulhenshaw/Desktop/kpfk-app/kpfk_radio
   flutter run
   ```

2. **Press play** - Wait for artwork to appear (first time download)
   - Look for: `[TIMESTAMP-xxx] ✅ Artwork SET on lockscreen`
   - Look for: `[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: true`

3. **Lock your device** (press power button)
   - Check lockscreen - artwork should be visible

4. **Unlock your device** (this triggers lifecycle refresh)
   - Look for: `[LIFECYCLE] Including artwork URL: ...`
   - Look for: `[TIMESTAMP-xxx] ✅ Lockscreen set with CACHED artwork`
   - Look for: `[VERIFY-CACHED-100ms] Artwork present: true`

5. **Lock device again**
   - Check lockscreen - artwork should STILL be visible

6. **Repeat lock/unlock 3-5 times**
   - Artwork should persist every time

## 📊 SUCCESS CRITERIA

✅ **PASS**: Artwork appears on lockscreen and STAYS after lock/unlock cycles
✅ **PASS**: Logs show `[VERIFY-CACHED-100ms] Artwork present: true`
✅ **PASS**: No `❌ CACHED ARTWORK DISAPPEARED!` messages

❌ **FAIL**: Artwork disappears after unlock
❌ **FAIL**: Logs show `[VERIFY-CACHED-100ms] Artwork present: false`
❌ **FAIL**: Lockscreen shows blank/gradient box

## 🔍 DEBUGGING

If artwork still disappears:

1. **Check for competing updates**:
   - Look for `[METADATA]` logs AFTER the lifecycle refresh
   - Look for `[LOCK] 🔒 Metadata updates LOCKED` messages

2. **Check for override sources**:
   - Look for `just_audio` or `audio_service` logs
   - Look for `updateNowPlaying` calls without artwork

3. **Check iOS system**:
   - iOS might be clearing artwork due to memory pressure
   - Try with a smaller test image

## 📝 WHAT CHANGED

### File: `ios/Runner/AppDelegate.swift`

**Lines 460-476** (Lifecycle handler):
```swift
// BEFORE (BROKEN):
let metadata: [String: Any] = [
    "title": title,
    "artist": artist,
    "isPlaying": isPlaying,
    "forceUpdate": true
    // ❌ MISSING: artworkUrl!
]

// AFTER (FIXED):
var metadata: [String: Any] = [
    "title": title,
    "artist": artist,
    "isPlaying": isPlaying,
    "forceUpdate": true
]
if let artworkUrl = lastArtworkUrl {
    metadata["artworkUrl"] = artworkUrl  // ✅ INCLUDED!
}
```

**Lines 145-168** (Cached artwork logging):
```swift
// Added timestamp logging and verification for cached artwork
print("[TIMESTAMP-\(timestamp)] ⚡ Using CACHED artwork for lockscreen")
print("[TIMESTAMP-\(timestamp)] ✅ Lockscreen set with CACHED artwork")
// Verify it stuck after 100ms
print("[VERIFY-CACHED-100ms] Artwork present: \(hasArtwork)")
```

## 🎯 ROOT CAUSE

The lifecycle handler was **refreshing metadata without the artwork URL** every time you unlocked the phone. This caused iOS to update the lockscreen with **text-only metadata**, clearing the artwork.

The fix ensures the artwork URL is **always included** in lifecycle refreshes, and the cached artwork is **reused** instead of re-downloaded.

---

**Test Date**: November 17, 2024
**Fix Version**: Lifecycle + Cached Artwork Logging
**Expected Result**: Artwork persists across lock/unlock cycles
