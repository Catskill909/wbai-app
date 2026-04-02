import 'package:flutter/material.dart';
import '../theme/font_constants.dart';

/// Modal overlay that displays show information (name, host, description)
/// with a nice animation and close button
class ShowInfoModal extends StatefulWidget {
  final String showName;
  final String? host;
  final String? description;
  final VoidCallback onClose;

  const ShowInfoModal({
    super.key,
    required this.showName,
    this.host,
    this.description,
    required this.onClose,
  });

  @override
  State<ShowInfoModal> createState() => _ShowInfoModalState();
}

class _ShowInfoModalState extends State<ShowInfoModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleClose() {
    _controller.reverse().then((_) => widget.onClose());
  }

  bool _isSmallPhone(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide < 380;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent tap from closing when tapping modal
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: _isSmallPhone(context) ? 20 : 24,
                  ),
                  padding: EdgeInsets.all(_isSmallPhone(context) ? 20 : 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Content
                      Padding(
                        padding: EdgeInsets.only(
                          top: _isSmallPhone(context) ? 8 : 12,
                          right: _isSmallPhone(context) ? 32 : 40,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show Name
                              Text(
                                widget.showName,
                                style: AppTextStyles.showTitleForDevice(
                                  MediaQuery.of(context).size,
                                ),
                              ),
                              if (widget.host != null &&
                                  widget.host!.isNotEmpty) ...[
                                SizedBox(
                                    height: _isSmallPhone(context) ? 8 : 12),
                                Text(
                                  'Host: ${widget.host}',
                                  style: AppTextStyles.bodyLargeForDevice(
                                    MediaQuery.of(context).size,
                                  ).copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                              if (widget.description != null &&
                                  widget.description!.isNotEmpty) ...[
                                SizedBox(
                                    height: _isSmallPhone(context) ? 12 : 16),
                                Text(
                                  widget.description!,
                                  style: AppTextStyles.bodyMediumForDevice(
                                    MediaQuery.of(context).size,
                                  ).copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Close button
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: _isSmallPhone(context) ? 24 : 28,
                          ),
                          onPressed: _handleClose,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
