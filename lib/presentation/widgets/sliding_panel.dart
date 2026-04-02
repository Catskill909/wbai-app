import 'package:flutter/material.dart';
import '../theme/font_constants.dart';

class SlidingPanel extends StatefulWidget {
  final Widget child;
  final String title;
  final double minHeight;
  final double maxHeight;

  const SlidingPanel({
    super.key,
    required this.child,
    required this.title,
    this.minHeight = 60.0,
    this.maxHeight = 500.0,
  });

  @override
  State<SlidingPanel> createState() => _SlidingPanelState();
}

class _SlidingPanelState extends State<SlidingPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _heightFactor = _controller.drive(Tween(begin: 0.0, end: 1.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePanel() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Panel Header
        GestureDetector(
          onTap: _togglePanel,
          child: Container(
            height: widget.minHeight,
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                IconButton(
                  icon: AnimatedIcon(
                    icon: AnimatedIcons.menu_close,
                    progress: _controller,
                  ),
                  onPressed: _togglePanel,
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTextStyles.sectionTitle.copyWith(
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Panel Content
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ClipRect(
              child: Align(
                heightFactor: _heightFactor.value,
                child: Container(
                  height: widget.maxHeight - widget.minHeight,
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: DefaultTextStyle(
                    style: AppTextStyles.bodyMedium,
                    child: child!,
                  ),
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ],
    );
  }
}
