  - Ensure metadata updates are only sent to native when there is a real change (title, artist, artwork, playback state).
  - Add deduplication/throttling logic in `NativeMetadataService`.
- **Swift:**
  - Double-check that redundant updates are ignored on the native side.
  - Ensure artwork downloads are throttled and only triggered when the URL changes.

---
