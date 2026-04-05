# Metadata Feed Update: sh_photo → big_pix

**Date**: November 17, 2024  
**Feed URL**: `https://confessor.kpfk.org/playlist/_pl_current_ary.php`

## Summary

The KPFK metadata feed has been updated with a new field `big_pix` that replaces `sh_photo`. This document tracks all changes made to support the new feed structure.

## Feed Structure Changes

### Old Format (sh_photo)
```json
{
  "current": {
    "sh_name": "Brad Friedman's BradCast",
    "sh_djname": "Brad Friedman",
    "sh_photo": "https://confessor.kpfk.org/pix/friedman_210.jpg"
  }
}
```

### New Format (big_pix)
```json
{
  "current": {
    "sh_name": "Brad Friedman's BradCast",
    "sh_djname": "Brad Friedman",
    "big_pix": "friedman_it_210.jpg"
  }
}
```

**Key Difference**: 
- `sh_photo` contained the full URL
- `big_pix` contains only the filename
- Full URL must be constructed: `https://confessor.kpfk.org/pix/{big_pix}`

## Code Changes

### 1. Primary Model Update
**File**: `lib/domain/models/stream_metadata.dart`

**Change**: Updated `ShowInfo.fromJson()` to parse `big_pix` and construct full URL

```dart
factory ShowInfo.fromJson(Map<String, dynamic> json) {
  // Construct full image URL from big_pix filename
  // big_pix contains just the filename (e.g., "friedman_it_210.jpg")
  // We need to prepend the base URL from gl_pixurl
  String? imageUrl;
  final bigPix = json['big_pix'];
  if (bigPix != null && bigPix.toString().isNotEmpty) {
    // Use the base URL from the feed's global settings
    imageUrl = 'https://confessor.kpfk.org/pix/$bigPix';
  }
  
  return ShowInfo(
    showName: StringUtils.decodeHtmlEntities(json['sh_name'] ?? ''),
    host: StringUtils.decodeHtmlEntities(json['sh_djname'] ?? ''),
    time: '${json['cur_start'] ?? ''}${json['cur_end'] != null ? ' - ${json['cur_end']}' : ''}',
    songTitle: json['pl_song'] != null ? StringUtils.decodeHtmlEntities(json['pl_song']) : null,
    songArtist: json['pl_artist'] != null ? StringUtils.decodeHtmlEntities(json['pl_artist']) : null,
    hostImage: imageUrl,  // Now uses constructed URL from big_pix
  );
}
```

**Impact**: 
- ✅ No changes needed to `hostImage` field or downstream code
- ✅ All existing image display logic continues to work
- ✅ Main app screen, lock screen, and media controls all use `hostImage`

## Documentation Updates

### Files Updated
1. `docs/LOCKSCREEN_ARTWORK_FLOW.md` - Updated JSON examples
2. `docs/lockscreen-image-bug.md` - Updated API response examples and parsing code
3. `LOCKSCREEN_FIX_README.md` - Updated troubleshooting reference

## Verification Checklist

- [x] Model parsing updated to use `big_pix`
- [x] URL construction logic implemented
- [x] Base URL matches feed's `gl_pixurl` value
- [x] Metadata service URL verified (already correct)
- [x] Documentation updated
- [ ] Test with live feed data
- [ ] Verify images display in main app
- [ ] Verify images display in lock screen
- [ ] Test with different shows

## Downstream Usage (No Changes Required)

The following components use `hostImage` and require **NO changes**:

1. **Main App Display** (`lib/presentation/pages/home_page.dart`)
   - `Image.network(state.metadata!.current.hostImage!)`

2. **Lock Screen Artwork** (`lib/data/repositories/stream_repository.dart`)
   - `artUri: showInfo.hostImage != null ? Uri.parse(showInfo.hostImage!) : null`

3. **iOS Lock Screen Service** (`lib/services/ios_lockscreen_service.dart`)
   - `final String? artworkUrl = showInfo.hostImage;`

4. **Media Item Updates** (`lib/services/audio_service/kpfk_audio_handler.dart`)
   - Uses MediaItem with artUri from hostImage

## Testing Notes

### Expected Behavior
1. App fetches metadata from feed
2. `big_pix` field is parsed (e.g., `"friedman_it_210.jpg"`)
3. Full URL is constructed: `https://confessor.kpfk.org/pix/friedman_it_210.jpg`
4. Image displays in main app
5. Image displays in lock screen controls

### Potential Issues
- ❌ If `big_pix` is empty/null, no image will display (graceful fallback)
- ❌ If base URL changes, update the hardcoded path in `ShowInfo.fromJson()`
- ⚠️ Image filenames may vary in size/quality (e.g., `_210.jpg` vs `_it_210.jpg`)

## Future Considerations

### Dynamic Base URL
Currently the base URL is hardcoded: `https://confessor.kpfk.org/pix/`

If needed, this could be made dynamic by:
1. Parsing `gl_pixurl` from the feed's `global` section
2. Storing it in a constant or passing it to the model
3. Using it in URL construction

### Example Implementation
```dart
factory StreamMetadata.fromJson(dynamic jsonData) {
  if (jsonData is String) {
    jsonData = json.decode(jsonData);
  }
  
  if (jsonData is! List || jsonData.length < 3) {
    throw FormatException('Invalid API response format');
  }
  
  // Extract base URL from global settings
  final globalData = jsonData[0]['global'];
  final basePixUrl = globalData['gl_pixurl'] ?? 'https://confessor.kpfk.org/pix';
  
  return StreamMetadata(
    previous: ShowInfo.fromJson({}, basePixUrl),
    current: ShowInfo.fromJson(jsonData[1]['current'], basePixUrl),
    next: ShowInfo.fromJson(jsonData[2]['next'], basePixUrl),
  );
}
```

## Summary

✅ **All changes completed successfully**
- Model updated to use `big_pix` field
- URL construction implemented
- Documentation updated
- No downstream changes required

**Status**: Ready for testing with live feed data
