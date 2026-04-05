# iOS Fixes Required

## Current Xcode Warnings (as of v1.0.2-stable)

### 1. Dependency Warnings

#### audio_service (0.18.17)
- Warning: `initWithImage:` is deprecated in iOS 10.0
- **Fix Plan**: 
  - [ ] Check for newer version of audio_service package
  - [ ] If no fix available, may need to fork and update the iOS implementation
  - [ ] Consider submitting PR to package maintainer

#### flutter_inappwebview_ios (1.1.2)
- Multiple deprecation warnings:
  - [ ] `init(url:entersReaderIfAvailable:)` deprecated in iOS 11.0
  - [ ] `statusBarStyle` setter deprecated in iOS 9.0
  - [ ] `clearCache` methods deprecated
  - [ ] `onFindResultReceived` deprecated
- **Fix Plan**:
  - [ ] Update to latest version of flutter_inappwebview_ios
  - [ ] If warnings persist, consider alternative packages or submit fixes upstream

### 2. App Icon Issues
- Warning: "The app icon set 'AppIcon' has 6 unassigned children"
- **Fix Plan**:
  - [ ] Review Assets.xcassets in Xcode
  - [ ] Remove unused icon sizes
  - [ ] Ensure all required icon sizes are properly assigned
  - [ ] Generate missing icon sizes if needed

### 3. Deployment Target Warning
- Current setting: iOS 9.0
- Supported range: iOS 12.0 to 18.2.99
- **Fix Plan**:
  - [ ] Update minimum iOS version in:
    - [ ] Podfile
    - [ ] project.pbxproj
    - [ ] Update Flutter platform configuration
  - [ ] Test app on minimum supported iOS version (12.0)

### 4. Privacy Info Warning
- Warning about processing `PrivacyInfo.xcprivacy`
- **Fix Plan**:
  - [ ] Review flutter_native_splash implementation
  - [ ] Update privacy manifest if needed
  - [ ] Consider updating flutter_native_splash package

## Priority Order
1. Deployment Target Update (High Priority)
2. App Icon Fixes (Medium Priority)
3. Package Updates (Lower Priority)
   - These are mostly deprecation warnings, not critical errors

## Notes
- All these warnings don't affect core functionality
- App is currently working well in TestFlight
- These fixes are for maintenance and future-proofing

## Testing Plan
1. Create a separate branch for iOS fixes
2. Test each fix individually
3. Verify no regression in core functionality:
   - Audio playback
   - Background audio
   - Metadata display
   - App drawer functionality
4. Test on multiple iOS versions (12.0+)
5. Test on both iPhone and iPad
