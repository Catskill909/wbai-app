import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/testing/debug_stream_override.dart';
import '../../domain/models/stream_notice.dart';
import '../bloc/stream_bloc.dart';
import '../theme/font_constants.dart';

/// Rehearse every outage the app can hit — without taking the station off air.
///
/// Two levels of fidelity:
///  • **Redirect the stream** to a broken endpoint, then press play on the home
///    screen. This exercises the REAL pipeline (`.m3u` resolve → health probe →
///    classification → notice), so a pass here means the detection genuinely
///    works, not just that the modal can be drawn.
///  • **Show a notice directly**, for checking wording and layout on a real
///    screen without waiting for a probe.
///
/// Debug builds only — [SettingsPage] never links here in release, and
/// [DebugStreamOverride] refuses to hold an override outside [kDebugMode].
class DebugOutagePage extends StatefulWidget {
  const DebugOutagePage({super.key});

  @override
  State<DebugOutagePage> createState() => _DebugOutagePageState();
}

class _DebugOutagePageState extends State<DebugOutagePage> {
  @override
  Widget build(BuildContext context) {
    final active = DebugStreamOverride.activeLabel;

    return Scaffold(
      appBar: AppBar(title: Text('Outage Testing', style: AppTextStyles.drawerTitle)),
      body: ListView(
        children: [
          Container(
            width: double.infinity,
            color: active == null
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.orange.withValues(alpha: 0.2),
            padding: const EdgeInsets.all(16),
            child: Text(
              active == null
                  ? 'Pointing at the LIVE stream.'
                  : 'REDIRECTED → $active\n'
                      'The live stream is untouched; only this app is looking '
                      'elsewhere. Reset to Live when you are done.',
              style: AppTextStyles.bodyMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              '1 · REDIRECT THE STREAM, THEN PRESS PLAY',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Pick one, go back, and press play. The app runs its real '
              'detection against a dead endpoint. No listener is affected.',
            ),
          ),
          ...DebugOutagePreset.all.map((preset) {
            final selected = preset.url == DebugStreamOverride.url;
            return ListTile(
              leading: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(preset.label, style: AppTextStyles.bodyMedium),
              subtitle: Text('${preset.description}\nExpect: ${preset.expected}'),
              isThreeLine: true,
              onTap: () {
                setState(() {
                  if (preset.url == null) {
                    DebugStreamOverride.clear();
                  } else {
                    DebugStreamOverride.apply(preset);
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(preset.url == null
                        ? 'Back to the live stream.'
                        : 'Redirected. Go back and press play.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            );
          }),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              '2 · SHOW A NOTICE DIRECTLY',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Skips detection — for checking wording, layout and the buttons. '
              'The connection variant is otherwise hard to trigger on purpose, '
              'since it needs something like a captive-portal Wi-Fi.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_tethering_off_rounded),
            title: Text('Show OUTAGE notice', style: AppTextStyles.bodyMedium),
            subtitle: const Text('"We\'ll be right back" + Got it'),
            onTap: () {
              context.read<StreamBloc>().add(StreamNoticeRaised(
                    const StreamNotice.outage(
                        detail: 'Simulated: stream not found on server'),
                  ));
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_off_rounded),
            title: Text('Show CONNECTION notice', style: AppTextStyles.bodyMedium),
            subtitle: const Text('"Can\'t reach the stream" + Try again / Dismiss'),
            onTap: () {
              context
                  .read<StreamBloc>()
                  .add(StreamNoticeRaised(const StreamNotice.connection()));
              Navigator.of(context).pop();
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Also worth checking: with the live stream selected, play and '
              'pause a few times and let it run through a rebuffer. No modal '
              'should EVER appear. A false alarm is worse than silence.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
