# Custom Font Implementation Plan (Google Fonts)

## Overview
This document outlines the implementation plan for custom fonts in the WPFW Radio app using Google Fonts. We will be using:
- **Oswald**: For main headings and drawer titles
- **Poppins**: For body text and secondary information

## Implementation Approach

We'll leverage the existing `google_fonts` package to implement our font strategy, which provides several benefits:
- Automatic font weight and style handling
- Optimized font loading
- No need to manage font files locally
- Always up-to-date font versions

## Configuration Steps

### 1. Font Constants
Location: `lib/presentation/theme/font_constants.dart`

```dart
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';

class TextStyles {
  // Oswald styles for headlines
  static TextStyle drawerTitle = GoogleFonts.oswald(
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );
  
  static TextStyle showTitle = GoogleFonts.oswald(
    fontSize: 28,
    fontWeight: FontWeight.bold,
  );

  // Poppins styles for body text
  static TextStyle showTime = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  
  static TextStyle bodyText = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );
}
```

### 2. Theme Configuration
Updates to `lib/presentation/theme/app_theme.dart`:

```dart
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      textTheme: TextTheme(
        // Oswald for headlines
        headlineLarge: GoogleFonts.oswald(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headlineSmall: GoogleFonts.oswald(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        // Poppins for body text
        bodyLarge: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: Colors.white,
        ),
        bodyMedium: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: Colors.white,
        ),
      ),
    );
  }
}
```

## Implementation Areas

### 1. Navigation Drawer
- Use Oswald for all section titles
- Use Poppins for menu items and secondary text

### 2. Main View
- Use Oswald for:
  - Show titles
  - Section headers
- Use Poppins for:
  - Show times
  - Show descriptions
  - Metadata information
  - Button text
  - Secondary information

### 3. Settings Page
- Use Poppins for all text elements
- Maintain consistent sizing with main view

## Advantages of Google Fonts Approach

1. **Simplified Setup**
   - No need to manage font files
   - No pubspec.yaml font declarations needed
   - No platform-specific configurations required

2. **Performance**
   - Fonts are automatically cached
   - Progressive font loading
   - Reduced app bundle size

3. **Maintenance**
   - Easy to update font weights and styles
   - No need to manage font file versions
   - Consistent across platforms

## Testing & Verification

### Font Display Testing
- Verify font rendering on:
  - iOS devices
  - Android devices
  - Different screen sizes
  - Various text scale factors
- Test offline behavior (fonts should cache properly)

### Performance Testing
- Check initial font loading time
- Verify font caching
- Test app behavior when offline
- Monitor network usage for font downloading

## Best Practices

1. **Font Usage**
   - Always use the TextStyles constants for consistency
   - Keep font weights consistent across similar elements
   - Maintain hierarchy with font sizes

2. **Performance**
   - Use const constructors where possible
   - Consider preloading fonts for critical UI elements
   - Monitor font download size impact

3. **Accessibility**
   - Ensure fonts scale properly with system text size
   - Maintain sufficient contrast ratios
   - Test with different text scale factors