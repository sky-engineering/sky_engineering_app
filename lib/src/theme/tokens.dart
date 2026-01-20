import 'package:flutter/material.dart';

/// Shared brand colors and semantic tokens for the app theme.
class AppColors {
  AppColors._();

  static const Color brandPrimary = Color(0xFF00426A);
  static const Color brandPrimaryDark = Color(0xFF002D46);
  static const Color onSurface = Color(0xFFB2B4B3);
  static const Color accentYellow = Color(0xFFF1C400);
  static const Color accentYellowBright = Color(0xFFFFD84D);
  static const Color success = Color(0xFF51E29A);
  static const Color warning = Color(0xFFFFB547);
  static const Color danger = Color(0xFFFF6B6B);
}

/// Consistent spacing scale for paddings and gaps.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Common corner radii so cards, buttons, and chips align.
class AppRadii {
  AppRadii._();

  static const BorderRadius sm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius md = BorderRadius.all(Radius.circular(12));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(16));
}

/// Animation + interaction timing tokens to keep motion consistent.
class AppDurations {
  AppDurations._();

  static const Duration short = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration long = Duration(milliseconds: 320);
}

/// Elevation presets for cards/dialogs/FABs.
class AppElevations {
  AppElevations._();

  static const double card = 1;
  static const double raisedCard = 4;
  static const double floating = 8;
}
