# Implementation Notes and Required Changes

## Current Issues and Solutions

### 1. Player Controls
Current Issue:
- Small play and pause icons
- Icons not stacked/overlapping
- Unclear audio state

Solutions:
```dart
// Implementation in HomePage:
IconButton(
  icon: Icon(
    state.playbackState == StreamState.playing
      ? Icons.pause_circle_filled
      : Icons.play_circle_filled,
    size: 96.0,  // Much larger size
  ),
  onPressed: () => handlePlayPause(),
)
```

### 2. WebView Integration
Current Issue:
- Metadata not working
- Wrong URL implementation

Solutions:
```dart
// Update WebView configuration:
- Base URL: https://starkey.digital/wpfw
- Background: #0F0404
- Metadata endpoints:
  - info/index.html for display
  - info/proxy.php for data fetching
```

### 3. Metadata Service
Current Issue:
- Incorrect endpoint usage
- Missing error handling

Required Updates:
```dart
// JSON Structure from proxy.php:
{
  "current": {
    "sh_name": "Show Name",
    "pl_song": "Current Song",
    "pl_artist": "Artist Name"
  }
}

// Implementation needed in MetadataService:
- Add proper CORS handling
- Implement retry logic
- Add offline caching
```

## Implementation Phases

### Phase 1: UI Updates
1. Redesign player controls
   - Center-aligned large play/pause button
   - Clear state indication
   - Improved touch target size

2. WebView layout
   - Proper layering with controls
   - Consistent styling with app theme
   - Loading states

### Phase 2: Metadata Integration
1. Update endpoints
2. Implement proper parsing
3. Add error recovery

### Phase 3: Testing & Polish
1. Test all states
2. Verify metadata flow
3. Optimize performance

## Next Steps
1. Update HomePage layout
2. Implement new WebView configuration
3. Fix metadata service implementation

## Notes for Future Updates
- Consider adding offline mode
- Implement caching for metadata
- Add analytics tracking

## Updates 2025-04-14
1. HTML Entity Improvements
   - Improved handling of HTML entities in metadata
   - Added proper decoding for special characters
   - Enhanced text processing for stream information

2. Text Styling Updates
   - Refined text formatting across the app
   - Improved readability and consistency
   - Updated font styling implementation

3. Side Drawer Enhancements
   - Changed app title from "WPFW Radio" to "WPFW"
   - Updated layout and styling
   - Improved navigation structure
