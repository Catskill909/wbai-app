import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `main.dart` sets `GoogleFonts.config.allowRuntimeFetching = false`, so every
/// font the app asks for MUST exist in `assets/fonts/`. When one doesn't,
/// google_fonts catches its own exception and only `debugPrint`s — the text
/// silently renders in a system fallback face, which is easy to miss in review
/// and impossible to fix after release.
///
/// This walks the real source, works out every (family, weight) pair the app
/// requests, and asserts the matching file is bundled.
void main() {
  // Mirrors google_fonts' _fontWeightToFilenameWeightParts.
  const Map<String, String> weightToFilenamePart = <String, String>{
    'w100': 'Thin',
    'w200': 'ExtraLight',
    'w300': 'Light',
    'w400': 'Regular',
    'normal': 'Regular',
    'w500': 'Medium',
    'w600': 'SemiBold',
    'w700': 'Bold',
    'bold': 'Bold',
    'w800': 'ExtraBold',
    'w900': 'Black',
  };

  /// Text of the balanced-paren argument list starting at [openParen].
  String argsOf(String source, int openParen) {
    var depth = 0;
    for (var i = openParen; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) return source.substring(openParen + 1, i);
      }
    }
    return '';
  }

  test('every GoogleFonts family/weight the app uses is bundled', () {
    final callPattern = RegExp(r'GoogleFonts\.([a-z][A-Za-z0-9]*)\(');
    final weightPattern = RegExp(r'fontWeight:\s*FontWeight\.([a-z0-9]+)');

    final required = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in callPattern.allMatches(source)) {
        final family = match.group(1)!;
        // 'oswald' -> 'Oswald'. Matches google_fonts' own family naming for
        // the single-word families this app uses.
        final familyName =
            family[0].toUpperCase() + family.substring(1);
        final args = argsOf(source, match.end - 1);
        final weight = weightPattern.firstMatch(args)?.group(1) ?? 'w400';
        final part = weightToFilenamePart[weight];
        expect(part, isNotNull,
            reason: 'Unrecognised FontWeight.$weight in ${entity.path}');
        required.add('$familyName-$part.ttf');
      }
    }

    expect(required, isNotEmpty,
        reason: 'Found no GoogleFonts usage — has the test stopped matching?');

    for (final filename in required) {
      expect(File('assets/fonts/$filename').existsSync(), isTrue,
          reason: 'assets/fonts/$filename is requested by the app but is not '
              'bundled. With allowRuntimeFetching=false it will silently fall '
              'back to a system font. Add the file, or stop using that weight.');
    }
  });

  test('OFL licences ship alongside the fonts', () {
    // main.dart reads these through LicenseRegistry at startup; a missing file
    // throws inside that stream.
    for (final family in <String>['Oswald', 'Poppins']) {
      expect(File('assets/fonts/OFL-$family.txt').existsSync(), isTrue,
          reason: 'Bundled OFL fonts must ship their licence.');
    }
  });

  test('no stray font files that nothing asks for', () {
    // Cheap guard against the 980KB of assets quietly growing.
    final bundled = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .length;
    expect(bundled, 8,
        reason: 'Expected Oswald + Poppins at 4 weights each. Update this '
            'count deliberately if the type system changes.');
  });
}
