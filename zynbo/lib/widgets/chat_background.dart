import 'package:flutter/material.dart';

import '../theme/zynbo_colors.dart';

/// Tiled doodle background used inside [ChatScreen].
/// Renders the Zynbo branded pattern over the dark scaffold with low opacity
/// so messages stay readable.
class ChatBackground extends StatelessWidget {
  final Widget child;
  final double opacity;

  const ChatBackground({
    super.key,
    required this.child,
    this.opacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: ZynboColors.bg),
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: Image.asset(
              'assets/images/chat_bg.png',
              repeat: ImageRepeat.repeat,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        // Very subtle vertical gradient to focus the eye on the message column.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZynboColors.bg.withOpacity(0.55),
                  Colors.transparent,
                  ZynboColors.bg.withOpacity(0.6),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
