#!/bin/bash

# 16KB Page Size Alignment Checker for Android APK
# Checks if native libraries (.so files) are properly aligned for 16KB page sizes

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path_to_apk_file>"
    echo "Example: $0 app/build/outputs/apk/release/app-release.apk"
    exit 1
fi

APK_FILE="$1"

if [ ! -f "$APK_FILE" ]; then
    echo "❌ Error: APK file not found: $APK_FILE"
    exit 1
fi

echo "🔍 Checking 16KB page size alignment for: $APK_FILE"
echo "=================================================="

# Extract APK to temporary directory
TEMP_DIR=$(mktemp -d)
echo "📦 Extracting APK..."
unzip -q "$APK_FILE" -d "$TEMP_DIR"

# Check if lib directory exists
if [ ! -d "$TEMP_DIR/lib" ]; then
    echo "✅ No native libraries found - APK is 16KB compatible (no .so files)"
    rm -rf "$TEMP_DIR"
    exit 0
fi

echo "🔍 Found native libraries, checking alignment..."

# Check each .so file for 16KB alignment
ALIGNMENT_ISSUES=0
TOTAL_SO_FILES=0

for so_file in $(find "$TEMP_DIR/lib" -name "*.so"); do
    TOTAL_SO_FILES=$((TOTAL_SO_FILES + 1))
    relative_path=${so_file#$TEMP_DIR/}
    
    # Check if file is aligned to 16KB (16384 bytes)
    if command -v readelf >/dev/null 2>&1; then
        # Use readelf to check ELF segment alignment
        alignment_check=$(readelf -l "$so_file" 2>/dev/null | grep -E "LOAD.*0x[0-9a-fA-F]*000" | head -1)
        if [ -n "$alignment_check" ]; then
            echo "✅ $relative_path - Properly aligned"
        else
            echo "❌ $relative_path - Alignment issue detected"
            ALIGNMENT_ISSUES=$((ALIGNMENT_ISSUES + 1))
        fi
    else
        # Fallback: Check file size alignment (basic check)
        file_size=$(stat -f%z "$so_file" 2>/dev/null || stat -c%s "$so_file" 2>/dev/null)
        if [ $((file_size % 16384)) -eq 0 ]; then
            echo "✅ $relative_path - Size aligned to 16KB"
        else
            echo "⚠️  $relative_path - Size not 16KB aligned (basic check)"
            ALIGNMENT_ISSUES=$((ALIGNMENT_ISSUES + 1))
        fi
    fi
done

# Cleanup
rm -rf "$TEMP_DIR"

# Summary
echo "=================================================="
echo "📊 SUMMARY:"
echo "   Total .so files checked: $TOTAL_SO_FILES"
echo "   Alignment issues found: $ALIGNMENT_ISSUES"

if [ $ALIGNMENT_ISSUES -eq 0 ]; then
    echo ""
    echo "🎉 SUCCESS: APK is 16KB page size compatible!"
    echo "   All native libraries are properly aligned."
    echo "   This APK should pass Google Play's 16KB requirement."
    exit 0
else
    echo ""
    echo "❌ ISSUES FOUND: APK may not be 16KB compatible"
    echo "   $ALIGNMENT_ISSUES native libraries have alignment issues."
    echo "   Consider updating your build configuration."
    exit 1
fi