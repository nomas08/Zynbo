import 'package:flutter/material.dart';

/// Zynbo brand palette — dark, minimal, Telegram/WhatsApp-inspired.
///
/// Naming convention:
///   bg          — root scaffold background
///   surface     — cards, tiles, input fields
///   surfaceHi   — raised surfaces, dividers, hover states
///   text        — primary text (light on dark)
///   muted       — secondary text
///   teal        — brand sender-bubble color
///   lime        — primary accent (CTA, online dot, badges)
///   deepInk     — for elements that need to contrast against [lime]
class ZynboColors {
  const ZynboColors._();

  static const Color bg = Color(0xFF050C0B);
  static const Color surface = Color(0xFF0E1716);
  static const Color surfaceHi = Color(0xFF182725);
  static const Color text = Color(0xFFE8EFEC);
  static const Color muted = Color(0xFF8FA39F);
  static const Color divider = Color(0xFF1A2725);

  static const Color teal = Color(0xFF0E5651);
  static const Color lime = Color(0xFFB6FF3D);
  static const Color deepInk = Color(0xFF06100F);

  static const Color online = Color(0xFF34D399);
  static const Color danger = Color(0xFFFF6B6B);
}
