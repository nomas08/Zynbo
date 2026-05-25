import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/zynbo_colors.dart';

/// Pill badge showing the unread message count. Caps at "99+".
class UnreadBadge extends StatelessWidget {
  final int count;

  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: const BoxDecoration(
        color: ZynboColors.lime,
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: ZynboColors.deepInk,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
