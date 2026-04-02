# App Configuration Notes

## Application ID
**Android:** `app.pacifica.kpfk`  
**iOS:** `com.pacifica.kpfk`

Note: Android and iOS use different bundle identifier formats by design.

### Android Configuration
Required changes in `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        applicationId "app.pacifica.kpfk"
        ...
    }
}
```

And in `android/app/src/main/AndroidManifest.xml`:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="app.pacifica.kpfk">
```

### iOS Configuration
Required changes in `ios/Runner.xcodeproj/project.pbxproj`:
```
PRODUCT_BUNDLE_IDENTIFIER = com.pacifica.kpfk;
```

And in `ios/Runner/Info.plist`:
```xml
<key>CFBundleIdentifier</key>
<string>com.pacifica.kpfk</string>
<key>CFBundleDisplayName</key>
<string>KPFK</string>
```

## Implementation Steps
1. Update Android configuration files
2. Update iOS configuration files
3. Test building on both platforms
4. Verify app signing settings

## Notes
- Ensure consistency across all platform-specific files
- Update any existing references to the bundle ID
- Consider adding app signing configurations