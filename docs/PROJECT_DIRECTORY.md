# Project Directory Structure

## Working Directory
The main working directory for the app is:
```
/Users/paulhenshaw/Desktop/wpfw-app/wpfw_radio
```

## Key Directories
```
wpfw_radio/
├── android/                    # Android project files
│   └── app/
│       └── src/
│           └── main/
│               ├── kotlin/     # Kotlin source files
│               └── AndroidManifest.xml
├── ios/                       # iOS project files
│   └── Runner/
│       └── Info.plist
├── lib/                       # Flutter source code
│   ├── core/
│   ├── data/
│   ├── domain/
│   ├── presentation/
│   └── services/
├── docs/                      # Project documentation
└── pubspec.yaml              # Flutter project config
```

## Important Paths
- Android Package Path: `wpfw_radio/android/app/src/main/kotlin/app/pacifica/wpfw`
- iOS Info.plist: `wpfw_radio/ios/Runner/Info.plist`
- Android Manifest: `wpfw_radio/android/app/src/main/AndroidManifest.xml`

## Command Line Operations
Always ensure commands are executed from the root project directory:
```bash
cd /Users/paulhenshaw/Desktop/wpfw-app/wpfw_radio
```

## Note
All file paths in documentation and commands should be relative to the project root directory `wpfw_radio/`