# Social Media Icons Implementation Plan

## Overview
Add social media icons to the bottom of the app drawer that will open respective URLs in the device's browser when tapped. The email icon will open the device's default email client.

## Technical Requirements

### Dependencies
- Already available in project:
  - `url_launcher: ^6.2.5` (for handling URLs and email)
  - `flutter_svg: ^2.0.9` (for potential custom icons)
  - Material Icons (built into Flutter)

### Implementation Steps

1. **Update StreamConstants**
   ```dart
   // Add new constants
   static const String facebookUrl = 'https://www.facebook.com/wpfwdc';
   static const String twitterUrl = 'https://twitter.com/wpfw';
   static const String instagramUrl = 'https://www.instagram.com/wpfwdc';
   static const String youtubeUrl = 'https://www.youtube.com/wpfw';
   static const String emailAddress = 'contact@wpfwdc.org';
   ```

2. **Create Social Media Section**
   - Add new section after Settings section in AppDrawer
   - Create a responsive row layout for icons
   - Implement proper spacing and padding

3. **Icon Implementation**
   ```dart
   Widget _buildSocialIcons() {
     return Padding(
       padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.spaceAround,
         children: [
           IconButton(...), // Facebook
           IconButton(...), // Instagram
           IconButton(...), // YouTube
           IconButton(...), // Twitter
           IconButton(...), // Email
         ],
       ),
     );
   }
   ```

4. **URL Handling**
   - Social media links: Use existing `_launchUrl` method
   - Email: Implement using mailto scheme
   ```dart
   Future<void> _launchEmail() async {
     final Uri emailLaunchUri = Uri(
       scheme: 'mailto',
       path: StreamConstants.emailAddress,
     );
     await launchUrl(emailLaunchUri);
   }
   ```

5. **UI/UX Considerations**
   - Icon size: 24x24 dp
   - Equal spacing between icons
   - Touch target size: minimum 48x48 dp
   - Add tooltips for accessibility
   - Consider hover/tap effects for better user feedback

## Visual Layout

```
+------------------------+
|      Drawer Header     |
+------------------------+
|      Navigation        |
|        ...            |
+------------------------+
|      Content          |
|        ...            |
+------------------------+
|      Support          |
|        ...            |
+------------------------+
|      Settings         |
|        ...            |
+------------------------+
|     [f] [i] [y] [t] [e]   |
+------------------------+
```

## Next Steps
1. Switch to Code mode
2. Update StreamConstants with new URLs
3. Implement social media section in AppDrawer
4. Test URL launching on both iOS and Android
5. Add error handling for failed URL launches