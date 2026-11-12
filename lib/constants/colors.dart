import 'package:flutter/material.dart';

/// Toko5758 Design System - Neo-Brutalist Bauhaus (from refrensi_design/bauhaus/DESIGN.md)
/// Form follows function. Raw, high contrast, geometric.
class AppColors {
  // === BRUTALIST TOKENS ===
  static const Color primary = Color(0xFF1a1a1a);        // Near-black (text, primary elements, borders)
  static const Color background = Color(0xFFf5f0e8);     // Warm cream / aged paper
  static const Color surface = Color(0xFFf5f0e8);        // Same as background for flat blocks
  static const Color white = Color(0xFFFFFFFF);          // Pure white for contrast blocks

  // Accents (use one per section for energy)
  static const Color accentYellow = Color(0xFFffcc00);   // High-energy CTAs, highlights
  static const Color danger = Color(0xFFe63b2e);         // Destructive, alerts, stok kritis (red)
  static const Color accentBlue = Color(0xFF0055ff);     // Links, interactive elements
  static const Color warning = Color(0xFFf59e0b);        // Keep for stok hampir habis (amber)
  static const Color success = Color(0xFF10b981);        // Lunas / sukses (green, used sparingly)

  // Text (high contrast on cream)
  static const Color textMain = Color(0xFF1a1a1a);       // Near black
  static const Color textSecondary = Color(0xFF4b4b4b);  // Dark gray for secondary

  // Legacy aliases for minimal breakage in existing code (map to brutal tokens)
  static const Color primaryDark = Color(0xFF000000);
  static const Color primaryLight = Color(0xFFffcc00);   // Use yellow as "light" accent

  // Spacing grid (4px base) - unchanged
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;

  // Neo-Brutalist: prefer 0. Legacy alias kept so existing code doesn't break immediately.
  static const double radius = 0.0;
  static const double radius8 = 0.0; // brutalist - no rounded

  // Brutalist "shadow": solid offset block (4-6px down-right, no blur)
  static const BoxShadow brutalOffsetShadow = BoxShadow(
    color: Color(0xFF1a1a1a), // solid black
    offset: Offset(4, 4),
    blurRadius: 0,
    spreadRadius: 0,
  );

  // Legacy / compatibility shadow (used in many const lists). Brutal version.
  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0xFF1a1a1a),
    offset: Offset(3, 3),
    blurRadius: 0,
  );

  // Thick black border (use on cards, buttons, inputs)
  static const BorderSide brutalBorder = BorderSide(
    color: Color(0xFF1a1a1a),
    width: 2.5,
  );
}
