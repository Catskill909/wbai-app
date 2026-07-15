# Metadata Feed Update: KPFK → WBAI

**Date**: July 15, 2026
**Feed URL**: `https://confessor2.wbai.org/playlist/_pl_current_ary.php`

## Summary

The app was still pointed at KPFK's Confessor now-playing feed (a leftover from
cloning the KPFK app). It now points at WBAI's own Confessor instance, which
uses the same JSON structure but with WBAI-specific field quirks.

## Feed Structure Differences (WBAI vs KPFK)

- `sh_photo` is a full image URL on WBAI's feed (KPFK sends the bare filename
  in `big_pix` instead). Parsing now prefers `sh_photo` and falls back to
  `big_pix` if present.
- The global fallback station image is under `gl_stapix` on WBAI (KPFK has no
  `gl_stapix_big`, WBAI's feed doesn't send it either) — parsing now falls
  back from `gl_stapix_big` to `gl_stapix`.
- `sh_djname` (host) is frequently empty on WBAI's feed for music/automated
  shows (e.g. "Ecologic"). The UI falls back to the station name in that case
  — this is a data gap on WBAI's side, not a parsing bug.
- Fixed a pre-existing bug found during this change: the "next show" time was
  always blank because the feed uses `nxt_start`/`nxt_end` for the next
  show entry, not `cur_start`/`cur_end`.

## Code Changes

**Files**:
- `lib/services/metadata_service.dart` — API URL updated to
  `confessor2.wbai.org`.
- `lib/domain/models/stream_metadata.dart` — `ShowInfo.fromJson()` prefers
  `sh_photo`, falls back to `big_pix`; `StreamMetadata.fromJson()` falls back
  from `gl_stapix_big` to `gl_stapix`; time parsing now reads `nxt_start`/
  `nxt_end` for the next show.

## Verification

Confirmed live against `https://confessor2.wbai.org/playlist/_pl_current_ary.php`:

```
current: Ecologic | time: 10:00 AM - 11:00 AM
next: Living for the City | host: Michael G. Haskins | time: 11:00 AM - 12:00 PM
station fallback image: https://confessor2.wbai.org/pix/WBAI.png
```

- [x] Model parsing updated for WBAI's feed shape
- [x] Metadata service URL updated
- [x] Verified with live feed data
- [x] `flutter analyze` clean
