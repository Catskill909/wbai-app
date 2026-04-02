# UI Redesign Specification

## Player Controls

### 1. Main Play/Stop Button
```dart
// Centered large button design
Container(
  alignment: Alignment.center,
  child: IconButton(
    iconSize: 96.0,
    icon: Icon(
      isPlaying ? Icons.pause_circle : Icons.play_circle,
      color: Colors.white,
    ),
    onPressed: handlePlayback,
  ),
)
```

### 2. Layout Structure
```
+-----------------+
|    WebView      |
|  (Station URL)  |
|                 |
+-----------------+
|                 |
|    ⏵/⏸         |
|  Large Button   |
|                 |
+-----------------+
|   Metadata      |
|    Display      |
+-----------------+
```

## Color Scheme
- Background: `#0F0404`
- Text: `#FFFFFF`
- Accents: White with various opacity levels

## WebView Integration
- Full width
- Dynamic height
- Background color matching app theme
- Smooth transitions

## Metadata Display
- Clear typography
- Show name prominently displayed
- Current track info when available
- Graceful fallback for missing data

## Error States
1. Loading State:
   - Subtle loading indicator
   - Placeholder content

2. Error State:
   - Clear error message
   - Retry button
   - Fallback content

## Animation
- Smooth transitions between play/pause
- Subtle loading animations
- Metadata fade in/out

## Accessibility
- Large touch targets (minimum 48x48dp)
- High contrast text
- Clear state indicators

## Platform Specific Adjustments
### iOS:
- Respect safe areas
- iOS-style loading indicators

### Android:
- Material Design touch ripples
- Android native feedback

## Next Steps
1. Implement large centered controls
2. Update WebView styling
3. Add smooth transitions
4. Test on both platforms