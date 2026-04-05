# Home Screen Layout Audit — `home_page.dart`

## Goal
Guarantee all content (image, show info, play/pause button) is always visible with no overflow on every supported device, from iPhone SE to iPad Pro.

---

## Device Matrix

| Device | Logical W×H | Body H (approx) | Notes |
|---|---|---|---|
| iPhone SE 3rd | 375×667 | ~603 | No home indicator |
| iPhone 14 | 390×844 | ~716 | Home indicator 34pt |
| iPhone 14 Pro Max | 430×932 | ~800 | Dynamic island |
| iPad 9th gen | 768×1024 | ~928 | Tablet branch |
| iPad Pro 12.9" | 1024×1366 | ~1270 | Large tablet branch |

---

## Issues Found

### 1. `fixedBelow` is fragile (critical)
`fixedBelow` is a hard-coded estimate of the vertical space consumed by the text section + play button. Currently 310px (normal phone), 260px (small phone), 340px (tablet).

**Why it breaks:** Both the show title and the "Next / Song" text allow up to 2 lines. Worst-case heights:

| Element | Small phone | Normal phone | Tablet |
|---|---|---|---|
| `SizedBox` above text | 16 | 20 | 20 |
| Show title 2 lines @ 20/28/36px | ~44 | ~62 | ~80 |
| `SizedBox(4)` | 4 | 4 | 4 |
| Time row (1 line) | ~18 | ~22 | ~28 |
| `SizedBox(8/10)` | 8 | 10 | 10 |
| Next/Song 2 lines @ 12/14/18px | ~28 | ~34 | ~44 |
| **Text subtotal** | ~118 | ~152 | ~186 |
| Play button (margin×2 + button) | 24+90+24=138 | 32+120+32=184 | 32+150+32=214 |
| **Total below image** | ~256 | ~336 | ~400 |
| Current `fixedBelow` | 260 | 310 | 340 |
| **Worst-case deficit** | ~0 | **~26px** | **~60px** |

The normal-phone and tablet branches can overflow when both text fields wrap to 2 lines. My quick fix (280→310) closes the gap for 1-line titles but still overflows with 2-line titles.

**Root problem:** any static number will be wrong for some content. The image should shrink organically when text takes more space.

---

### 2. `bottomPad = 100` over-reserves space
The bottom icon row (Donate, Alarm at `bottom: 16`, height 56 → top edge 72px above SafeArea floor; News at `bottom: 0`, height 44 with 8px SafeArea minimum → top edge ~52px) requires only **~80px** of clearance. The current 100px leaves ~20px of dead space between the play button and the icon row.

---

### 3. Play button vertical margin is generous on small screens
`margin: EdgeInsets.symmetric(vertical: 32)` = 64px wasted on normal phones; `24` on small phones = 48px. On a 667px tall iPhone SE these margins are a significant portion of available height. Should tighten to 20/28.

---

### 4. Text `maxLines` / ellipsis — already correct ✓
All three text widgets (show name, time, next/song) already have `maxLines: 2, overflow: TextOverflow.ellipsis`. No change needed here.

---

### 5. Image `margin top` double-counts `imgTop`
The image container has `margin: EdgeInsets.only(top: isSmall ? 12 : 20)` which is the same value as `imgTop` used in the available-height formula. Both are then applied, shrinking the image by more than intended on some devices.

---

## Proposed Fix — Flex-based Layout

Replace the pre-computed `fixedBelow`/`availImg`/`imageSize` math with Flutter's native flex system. The image lives in a `Flexible` widget; it absorbs all remaining vertical space after fixed-height elements claim their share. The image can never push anything below it out of view.

### Layout tree (after fix)

```
Padding(bottom: bottomPad)           // bottomPad: small=80, phone=80, tab=100
└── Column(mainAxisSize: max)
    ├── SizedBox(height: imgTop)      // top spacing (12/20)
    ├── Flexible(fit: loose)          // image — shrinks to fit remaining height
    │   └── Center
    │       └── LayoutBuilder
    │           └── SizedBox(side, side)   // side = min(maxH, sw*pct)
    │               └── imageContainer
    ├── SizedBox(height: 16/20)       // gap below image
    ├── textSection                    // natural height, maxLines:2 on all
    └── playButtonContainer            // tightened margin: 20/28
```

Key properties:
- `Flexible(fit: FlexFit.loose)` → child gets **up to** remaining height; never more.
- `LayoutBuilder` inside Flexible measures the actual remaining height and squares it against the desired width percentage to pick the image side.
- All elements below the image are fixed-height → they always render.
- `bottomPad` keeps content clear of the icon row with minimal dead space.

### Updated constants

| Constant | Small phone | Normal phone | Tablet |
|---|---|---|---|
| `bottomPad` | 80 | 80 | 100 |
| `imgTop` | 12 | 20 | 20 |
| `widthPct` | 0.80 | 0.85 | 0.70 |
| Play margin (vert) | 20 | 28 | 32 |
| Play button size | 90 | 120 | 150 |

---

## Files to Change

| File | Change |
|---|---|
| `lib/presentation/pages/home_page.dart` | Replace `fixedBelow`/`availImg`/`imageSize` block with `Flexible` + inner `LayoutBuilder`; tighten `bottomPad` and play button margin; remove duplicate `margin: top` from image container |

No font, theme, or other file changes required.

---

## Verification Plan

After the fix, test on:
- [ ] iPhone SE (smallest supported: 375×667, no safe area bottom)
- [ ] iPhone 14 (standard: 390×844)
- [ ] iPhone 14 Pro Max (largest phone: 430×932)
- [ ] iPad 9th gen simulator (tablet branch)
- [ ] Long show name that wraps to 2 lines (e.g., "Democracy Now! with Amy Goodman")
- [ ] Song info that wraps to 2 lines
- [ ] Error card visible (should not push play button off screen — Column does not scroll)

---

## What We Are NOT Changing

- `maxLines: 2` / `overflow: TextOverflow.ellipsis` on all text (already correct)
- Text styles / font sizes in `font_constants.dart`
- Bottom icon button sizes, positions, or styling
- AppBar, drawer, or any other screen
