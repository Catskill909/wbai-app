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
    final theme = Theme.of(context);
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
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
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
                      Row(
                        children: [
                          Text('Sleep Timer',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              )),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _TimerRing(
                          remaining: remaining, total: total, accent: accent),
                      const SizedBox(height: 16),
                      _PresetRow(
                        onSelect: (m) =>
                            context.read<SleepTimerCubit>().setMinutes(m),
                        currentMinutes: total.inMinutes,
                        disabled: isRunning || isPaused,
                        accent: accent,
                      ),
                      const SizedBox(height: 8),
                      _MinutesSlider(
                        value: total.inMinutes.toDouble(),
                        onChanged: (v) => context
                            .read<SleepTimerCubit>()
                            .setMinutes(v.round()),
                        disabled: isRunning || isPaused,
                        accent: accent,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: isRunning
                                ? FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        context.read<SleepTimerCubit>().pause(),
                                    child: const Text('Pause'),
                                  )
                                : isPaused
                                    ? FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => context
                                            .read<SleepTimerCubit>()
                                            .resume(),
                                        child: const Text('Resume'),
                                      )
                                    : FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => context
                                            .read<SleepTimerCubit>()
                                            .start(),
                                        child: const Text('Start'),
                                      ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: isBeforeStart
                                ? OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    child: const Text('Close'),
                                  )
                                : OutlinedButton(
                                    onPressed: () {
                                      context
                                          .read<SleepTimerCubit>()
                                          .cancelTimer();
                                      Navigator.of(context).maybePop();
                                    },
                                    child: const Text('Cancel'),
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
    final options = const [15, 30, 60];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in options)
          ChoiceChip(
            label: Text('$m min'),
            selected: currentMinutes == m,
            onSelected: disabled ? null : (_) => onSelect(m),
            selectedColor: accent.withValues(alpha: 0.25),
            labelStyle: TextStyle(
              color: currentMinutes == m ? Colors.white : null,
              fontWeight: currentMinutes == m ? FontWeight.w600 : null,
            ),
            shape: StadiumBorder(
              side: BorderSide(
                color: currentMinutes == m ? accent : Colors.white24,
              ),
            ),
          ),
      ],
    );
  }
}

class _MinutesSlider extends StatelessWidget {
  final double value; // minutes
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
            const Icon(Icons.access_time, size: 18),
            const SizedBox(width: 8),
            Text('${value.round()} minutes'),
          ],
        ),
        Slider(
          value: value.clamp(5, 120),
          onChanged: disabled ? null : onChanged,
          min: 5,
          max: 120,
          divisions: 23,
          activeColor: accent,
          thumbColor: accent,
          inactiveColor: Colors.white12,
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

    return Column(
      children: [
        SizedBox(
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
                  strokeWidth: 8,
                  color: accent,
                  backgroundColor: Colors.white12,
                ),
              ),
              Text('$h:${two(m)}:${two(s)}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [], fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}
