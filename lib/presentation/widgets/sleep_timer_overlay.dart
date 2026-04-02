import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/di/service_locator.dart' as di;
import '../bloc/sleep_timer_cubit.dart';
import '../theme/app_theme.dart';

class SleepTimerOverlay extends StatelessWidget {
  const SleepTimerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: di.getIt<SleepTimerCubit>(),
      child: const _SleepTimerView(),
    );
  }
}

class _SleepTimerView extends StatefulWidget {
  const _SleepTimerView();

  @override
  State<_SleepTimerView> createState() => _SleepTimerViewState();
}

class _SleepTimerViewState extends State<_SleepTimerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onComplete() async {
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sleep timer completed. Audio stopped.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = WBAIColors.blue;
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: ScaleTransition(
          scale:
              CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: BlocConsumer<SleepTimerCubit, SleepTimerState>(
                listener: (context, state) {
                  if (state is SleepTimerCompleted) {
                    _onComplete();
                  }
                },
                builder: (context, state) {
                  final cubit = context.read<SleepTimerCubit>();
                  final total = cubit.total;
                  final remaining = cubit.remaining;

                  final isRunning = state is SleepTimerRunning;
                  final isPaused = state is SleepTimerPaused;
                  final isBeforeStart = state is SleepTimerInactive ||
                      state is SleepTimerScheduled;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.bedtime_outlined,
                              color: accent, size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'Sleep Timer',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close,
                                color: Colors.grey.shade500, size: 20),
                            onPressed: () => Navigator.of(context).maybePop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Timer ring
                      _TimerRing(
                          remaining: remaining, total: total, accent: accent),
                      const SizedBox(height: 24),
                      // Preset buttons
                      _PresetRow(
                        onSelect: (m) =>
                            context.read<SleepTimerCubit>().setMinutes(m),
                        currentMinutes: total.inMinutes,
                        disabled: isRunning || isPaused,
                        accent: accent,
                      ),
                      const SizedBox(height: 16),
                      // Slider
                      _MinutesSlider(
                        value: total.inMinutes.toDouble(),
                        onChanged: (v) => context
                            .read<SleepTimerCubit>()
                            .setMinutes(v.round()),
                        disabled: isRunning || isPaused,
                        accent: accent,
                      ),
                      const SizedBox(height: 20),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: isRunning
                                  ? ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accent,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () => context
                                          .read<SleepTimerCubit>()
                                          .pause(),
                                      child: const Text('Pause',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    )
                                  : isPaused
                                      ? ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accent,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: () => context
                                              .read<SleepTimerCubit>()
                                              .resume(),
                                          child: const Text('Resume',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                        )
                                      : ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accent,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: () => context
                                              .read<SleepTimerCubit>()
                                              .start(),
                                          child: const Text('Start',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                        ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: isBeforeStart
                                  ? OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.black87,
                                        side: BorderSide(
                                            color: Colors.grey.shade300),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      child: const Text('Close',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    )
                                  : OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade400,
                                        side: BorderSide(
                                            color: Colors.red.shade200),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () {
                                        context
                                            .read<SleepTimerCubit>()
                                            .cancelTimer();
                                        Navigator.of(context).maybePop();
                                      },
                                      child: const Text('Cancel',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final void Function(int minutes) onSelect;
  final int currentMinutes;
  final bool disabled;
  final Color accent;
  const _PresetRow({
    required this.onSelect,
    required this.currentMinutes,
    required this.disabled,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    const options = [15, 30, 60];
    return Row(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: disabled ? null : () => onSelect(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                decoration: BoxDecoration(
                  color: currentMinutes == options[i]
                      ? accent
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: currentMinutes == options[i]
                        ? accent
                        : Colors.grey.shade300,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${options[i]} min',
                  style: TextStyle(
                    color: currentMinutes == options[i]
                        ? Colors.white
                        : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          if (i < options.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _MinutesSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final bool disabled;
  final Color accent;
  const _MinutesSlider({
    required this.value,
    required this.onChanged,
    required this.disabled,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.access_time_outlined,
                size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              '${value.round()} minutes',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: accent,
            inactiveTrackColor: Colors.grey.shade200,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.15),
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: value.clamp(5, 120),
            onChanged: disabled ? null : onChanged,
            min: 5,
            max: 120,
            divisions: 23,
          ),
        ),
      ],
    );
  }
}

class _TimerRing extends StatelessWidget {
  final Duration remaining;
  final Duration total;
  final Color accent;
  const _TimerRing(
      {required this.remaining, required this.total, required this.accent});

  @override
  Widget build(BuildContext context) {
    final totalSeconds = total.inSeconds == 0 ? 1 : total.inSeconds;
    final progress = 1 - (remaining.inSeconds / totalSeconds);

    String two(int n) => n.toString().padLeft(2, '0');
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final s = remaining.inSeconds % 60;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: CircularProgressIndicator(
              value: progress.isNaN ? 0 : progress,
              strokeWidth: 10,
              color: accent,
              backgroundColor: Colors.grey.shade200,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$h:${two(m)}:${two(s)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'remaining',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
