# Version Management with Cider

## Current Version Info
Your app version in pubspec.yaml is currently: `1.0.0+1`
- `1.0.0` is the semantic version (major.minor.patch)
- `1` is the build number

## Common Cider Commands

### Installation
```bash
dart pub global activate cider
```

### Version Bumping Commands

1. **Bump Build Number Only**
```bash
cider bump build
```
Effect: 1.0.0+1 → 1.0.0+2

2. **Bump Patch Version**
```bash
cider bump patch
```
Effect: 1.0.0+2 → 1.0.1+2

3. **Bump Minor Version**
```bash
cider bump minor
```
Effect: 1.0.1+2 → 1.1.0+2

4. **Bump Major Version**
```bash
cider bump major
```
Effect: 1.1.0+2 → 2.0.0+2

### Release Commands

1. **Create Release Version**
```bash
cider release
```
Effect: Updates version and git tags

2. **Create Beta Version**
```bash
cider release --pre beta
```
Effect: 1.0.0 → 1.0.0-beta.1

### Version Files Updated
Cider automatically updates versions in:
- pubspec.yaml
- ios/Runner/Info.plist (CFBundleVersion and CFBundleShortVersionString)
- android/app/build.gradle (versionCode and versionName)

### Examples for Your Workflow

1. **New Feature Release**
```bash
# Bump minor version for new feature
cider bump minor
# Then bump build number
cider bump build
```

2. **Bug Fix Release**
```bash
# Bump patch version for bug fix
cider bump patch
# Then bump build number
cider bump build
```

3. **Beta Release**
```bash
# Create beta version
cider release --pre beta
# Bump build for each beta
cider bump build
```

### CI/CD Integration Example
```yaml
# In your CI pipeline
steps:
  - name: Bump version
    run: |
      dart pub global activate cider
      cider bump build
      # For release builds
      cider release
```

## Best Practices

1. **Version Bumping**
- Major (1.0.0 → 2.0.0): Breaking changes
- Minor (1.0.0 → 1.1.0): New features
- Patch (1.0.0 → 1.0.1): Bug fixes
- Build (+1 → +2): New builds

2. **When to Bump**
- Build number: Every new build for testing
- Patch: Bug fixes and minor improvements
- Minor: New features
- Major: Breaking changes

3. **Git Integration**
- Commit after version changes
- Tag releases with version number
- Use release notes for major changes

## Quick Reference

```bash
# Check current version
cider version

# Bump build number
cider bump build

# Release new version
cider bump minor && cider bump build

# Create beta release
cider release --pre beta

# Verify version files
cider verify
```

## Benefits of Using Cider

1. **Consistency**
- Ensures iOS and Android versions stay in sync
- Maintains consistent versioning across all files
- Prevents manual version mismatch errors

2. **Automation**
- Easy integration with CI/CD pipelines
- Automated version bumping for builds
- Simplified release management

3. **Flexibility**
- Supports semantic versioning
- Handles pre-release versions
- Works with custom version formats

Would you like to proceed with installing and setting up cider in your project?