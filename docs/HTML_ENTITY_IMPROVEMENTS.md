# HTML Entity Handling Improvements

## Current Implementation

The current `StringUtils.decodeHtmlEntities()` method handles these HTML entities:

```dart
&amp;   -> &
&lt;    -> <
&gt;    -> >
&quot;  -> "
&#039;  -> '
&#39;   -> '
&apos;  -> '
```

## Missing Entities

### Typographic Quotes
These entities represent typographically correct quotation marks:

- `&rsquo;` → ' (right single quote)
- `&lsquo;` → ' (left single quote)
- `&rdquo;` → " (right double quote)
- `&ldquo;` → " (left double quote)

### Special Characters
These entities represent common typographic characters:

- `&mdash;` → — (em dash)
- `&ndash;` → – (en dash)
- `&hellip;` → … (ellipsis)

## Why These Were Missing

1. Initial implementation focused on basic HTML entities (&amp;, &lt;, &gt;)
2. Apostrophe entities (&#039;, &#39;, &apos;) were added as they're very common
3. Typographic quotes and special characters are more specific to formatted text content

## Implementation Plan

1. Add all missing entities to `StringUtils.decodeHtmlEntities()`
2. Maintain the existing replacement chain pattern
3. Add replacements in a logical order (quotes first, then special characters)
4. Test with various combinations of entities to ensure proper decoding

## Impact

This improvement will ensure better handling of formatted text from the API, particularly for:
- Show titles that use smart quotes
- Song titles with proper typography
- Host names and descriptions with special characters

## Testing Considerations

Test cases should include:
1. Mixed basic and typographic quotes
2. Multiple entities in the same string
3. Nested entities (e.g., &amp;rsquo;)
4. Empty strings and null values