# 🔍 CATCH THE OVERRIDE - Forensic Test

## 🎯 Objective

Find EXACTLY what is removing the artwork from the lockscreen.

## 🚨 What We Know

1. ✅ Artwork downloads successfully
2. ✅ Artwork is SET on lockscreen
3. ❌ Artwork DISAPPEARS immediately (you saw it flash)
4. ❌ Something is OVERRIDING our metadata

## 🔬 Forensic Logging Added

I've added comprehensive timestamp logging to catch the culprit:

### What the Logs Will Show:

```
[TIMESTAMP-1234567890.123] ⚡ Setting lockscreen metadata IMMEDIATELY (text-only first)
[TIMESTAMP-1234567890.123] Has artwork: false
[TIMESTAMP-1234567890.123] Title: Democracy Now!
[TIMESTAMP-1234567890.123] ✅ Lockscreen set with text

[VERIFY-100ms] Artwork present: false  ← Should be false

[METADATA] 🎨 New artwork URL detected: 'https://...'
[METADATA] ⏳ Starting async artwork download...
[METADATA] 🔄 Artwork download attempt 1/3

[TIMESTAMP-1234567890.623] 🎨 Adding artwork to lockscreen
[TIMESTAMP-1234567890.623] Artwork size: (300.0, 300.0)
[TIMESTAMP-1234567890.623] ✅ Artwork SET on lockscreen

[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: ???  ← KEY MOMENT
[VERIFY-500ms-AFTER-ARTWORK] Artwork still present: ???  ← KEY MOMENT
[VERIFY-1000ms-AFTER-ARTWORK] Artwork still present: ???  ← KEY MOMENT
```

### If Artwork is Removed, You'll See:

```
[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: false
[VERIFY-100ms-AFTER-ARTWORK] ❌❌❌ ARTWORK WAS REMOVED BY SOMETHING! ❌❌❌
[VERIFY-100ms-AFTER-ARTWORK] This is the bug! Something is overriding our metadata!
```

This tells us the artwork was removed **within 100ms** of being set.

## 🧪 Test Procedure

### Step 1: Rebuild App
```bash
cd /Users/paulhenshaw/Desktop/kpfk-app/kpfk_radio
flutter clean
flutter pub get
flutter run
```

### Step 2: Open Xcode Console
1. Open Xcode
2. Window → Devices and Simulators
3. Select your device
4. Click "Open Console" button
5. Filter for "TIMESTAMP" or "VERIFY"

### Step 3: Test Lockscreen
1. Press play in app
2. Wait 2 seconds
3. Lock device
4. Observe lockscreen

### Step 4: Capture Logs
**CRITICAL**: Copy ALL log output and send it to me.

Look for these specific patterns:

#### Pattern 1: Artwork Removed Immediately (0-100ms)
```
[TIMESTAMP-xxx] ✅ Artwork SET on lockscreen
[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: false
[VERIFY-100ms-AFTER-ARTWORK] ❌❌❌ ARTWORK WAS REMOVED
```

**Culprit**: Something is overriding within 100ms
**Likely**: Another system setting metadata immediately after us

#### Pattern 2: Artwork Removed After 100-500ms
```
[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: true
[VERIFY-500ms-AFTER-ARTWORK] Artwork still present: false
```

**Culprit**: Something is overriding between 100-500ms
**Likely**: Delayed async operation or timer

#### Pattern 3: Artwork Removed After 500ms-1s
```
[VERIFY-500ms-AFTER-ARTWORK] Artwork still present: true
[VERIFY-1000ms-AFTER-ARTWORK] Artwork still present: false
```

**Culprit**: Something is overriding around 1 second
**Likely**: MetadataController forensic timer (runs every 1 second)

#### Pattern 4: Artwork Persists
```
[VERIFY-100ms-AFTER-ARTWORK] Artwork still present: true
[VERIFY-500ms-AFTER-ARTWORK] Artwork still present: true
[VERIFY-1000ms-AFTER-ARTWORK] Artwork still present: true
```

**Result**: BUG IS FIXED! 🎉

## 🔍 What to Look For in Logs

### Red Flags:

1. **Multiple MPNowPlayingInfoCenter updates**
   - Look for multiple `[TIMESTAMP-xxx]` entries close together
   - Indicates multiple systems fighting

2. **MetadataController activity**
   - Look for `[FORENSIC]` or `[GUARD]` logs
   - Indicates MetadataController is active

3. **just_audio activity**
   - Look for just_audio plugin logs
   - Might be setting its own metadata

4. **Timing patterns**
   - If artwork removed at exactly 1 second → MetadataController timer
   - If artwork removed immediately → Competing system
   - If artwork removed randomly → Race condition

## 📋 Checklist

- [ ] App rebuilt with new logging
- [ ] Xcode console open and ready
- [ ] Played audio and locked device
- [ ] Captured complete log output
- [ ] Identified when artwork was removed
- [ ] Found suspicious log entries around that time

## 🎯 Expected Outcome

The logs will tell us EXACTLY:
1. When artwork is set (timestamp)
2. When artwork is removed (100ms/500ms/1s check)
3. What happened in between (other log entries)

This will identify the culprit system.

## 📞 Report Back

Send me:
1. **Complete Xcode console log** (all TIMESTAMP and VERIFY entries)
2. **Timing of artwork removal** (100ms? 500ms? 1s?)
3. **Any suspicious log entries** between artwork set and removal
4. **What you saw on lockscreen** (flash? blank? text only?)

---

## 🚀 Quick Commands

```bash
# Rebuild
cd /Users/paulhenshaw/Desktop/kpfk-app/kpfk_radio && flutter clean && flutter pub get && flutter run

# Filter logs in terminal (if not using Xcode)
# (Run this in a separate terminal while app is running)
idevicesyslog | grep -E "TIMESTAMP|VERIFY|METADATA|FORENSIC"
```

---

**Status**: 🔬 Forensic logging active
**Next**: Run test and capture logs
**Goal**: Identify the override source within 5 minutes
