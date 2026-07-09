import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How far down (logical px) the user must scroll before the back-to-top
/// button appears.
const double kBackToTopThreshold = 400;

/// Whether the back-to-top button should show for a given scroll [offset].
bool showBackToTop(double offset, {double threshold = kBackToTopThreshold}) =>
    offset > threshold;

/// Overlays a small "back to top" arrow (issue #25) on a scrollable built by
/// [builder]. Owns the [ScrollController]; the button fades in once the user
/// has scrolled past [kBackToTopThreshold] and scrolls smoothly back to the
/// top when tapped.
class BackToTop extends StatefulWidget {
  const BackToTop({super.key, required this.builder});

  /// Builds the scrollable; it must attach [ScrollController] to its scroll
  /// view for the button to track the offset.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<BackToTop> createState() => _BackToTopState();
}

class _BackToTopState extends State<BackToTop> {
  final ScrollController _controller = ScrollController();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final visible = _controller.hasClients && showBackToTop(_controller.offset);
    if (visible != _visible) setState(() => _visible = visible);
  }

  void _scrollToTop() {
    _controller.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.builder(context, _controller),
        Positioned(
          right: 16,
          bottom: 16,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_visible,
              child: FloatingActionButton.small(
                heroTag: null, // several instances can share one route tree
                backgroundColor: AppTheme.surfaceAlt,
                foregroundColor: AppTheme.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppTheme.border),
                ),
                tooltip: 'Back to top',
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
