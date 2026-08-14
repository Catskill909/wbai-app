import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/domain/models/stream_notice.dart';
import 'package:wbai_radio/presentation/widgets/stream_notice_modal.dart';

/// Renders both notice variants to PNGs so their appearance can be reviewed and
/// regressions caught without a device — this app has no iOS simulator runtime
/// installed, and the modal is otherwise only reachable during a real outage.
///
/// Refresh after an intentional design change:
///   flutter test --update-goldens test/stream_notice_modal_golden_test.dart
void main() {
  setUpAll(() async {
    // flutter_test ships no icon font, so Icons render as hollow boxes and the
    // golden misrepresents the badge. Load the real one from the SDK.
    final iconFont = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter'}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                iconFont.readAsBytesSync().buffer.asByteData())))
          .load();
    }

    // GoogleFonts asks for 'Oswald_700' etc. with 'Oswald' as the fallback.
    // Register the bundled files under both so the goldens show real
    // typography instead of the test framework's placeholder boxes.
    const variants = <String, String>{
      'Regular': 'regular',
      'Medium': '500',
      'SemiBold': '600',
      'Bold': '700',
    };
    for (final family in <String>['Oswald', 'Poppins']) {
      for (final entry in variants.entries) {
        final bytes = File('assets/fonts/$family-${entry.key}.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData();
        await (FontLoader('${family}_${entry.value}')
              ..addFont(Future.value(bytes)))
            .load();
        if (entry.key == 'Regular') {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
      }
    }
  });

  Widget harness(StreamNotice notice, {Brightness brightness = Brightness.dark}) {
    final dark = brightness == Brightness.dark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        // Stand-in for the home screen behind the scrim, so the golden shows
        // the modal in context rather than floating on nothing.
        backgroundColor: dark ? const Color(0xFF0F0404) : const Color(0xFFF5F2EF),
        body: Stack(
          children: [
            Center(
              child: Icon(Icons.radio,
                  size: 160,
                  color: dark ? Colors.white24 : Colors.black26),
            ),
            StreamNoticeModal(
              notice: notice,
              onDismiss: () {},
              onRetry: () {},
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('outage variant', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 13/14 Pro
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      const StreamNotice.outage(detail: 'Stream not found on server'),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StreamNoticeModal),
      matchesGoldenFile('goldens/stream_notice_outage.png'),
    );
  });

  testWidgets('connection variant', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(const StreamNotice.connection()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StreamNoticeModal),
      matchesGoldenFile('goldens/stream_notice_connection.png'),
    );
  });

  testWidgets('outage has no retry; connection has both actions',
      (tester) async {
    await tester.pumpWidget(harness(const StreamNotice.outage()));
    await tester.pumpAndSettle();
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);

    await tester.pumpWidget(harness(const StreamNotice.connection()));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    // Without this escape hatch the only way to close the notice is to fire
    // another play attempt.
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('dismiss and retry callbacks fire (guards AbsorbPointer regression)',
      (tester) async {
    var dismissed = 0;
    var retried = 0;
    Widget wired(StreamNotice notice) => MaterialApp(
          home: Scaffold(
            body: StreamNoticeModal(
              notice: notice,
              onDismiss: () => dismissed++,
              onRetry: () => retried++,
            ),
          ),
        );

    await tester.pumpWidget(wired(const StreamNotice.connection()));
    await tester.tap(find.text('Try again'));
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(retried, 1);
    expect(dismissed, 1);

    await tester.pumpWidget(wired(const StreamNotice.outage()));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(dismissed, 2);
  });

  // WBAI is theme-aware. Light mode gets its own goldens because the card and
  // ink colours flip there — the failure mode this guards against is dark ink
  // on a dark card (or the reverse) going unnoticed until a user reports it.
  testWidgets('outage variant — light theme', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(
      const StreamNotice.outage(detail: 'Stream not found on server'),
      brightness: Brightness.light,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StreamNoticeModal),
      matchesGoldenFile('goldens/stream_notice_outage_light.png'),
    );
  });

  testWidgets('connection variant — light theme', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(
      const StreamNotice.connection(),
      brightness: Brightness.light,
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StreamNoticeModal),
      matchesGoldenFile('goldens/stream_notice_connection_light.png'),
    );
  });
}
