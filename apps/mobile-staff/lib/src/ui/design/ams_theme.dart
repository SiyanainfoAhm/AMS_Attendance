import "package:flutter/material.dart";

import "ams_tokens.dart";

class AmsTheme {
  static ThemeData light() {
    final cs = ColorScheme.fromSeed(
      seedColor: AmsTokens.brand,
      primary: AmsTokens.brand,
      secondary: AmsTokens.brand2,
      surface: AmsTokens.surface,
      brightness: Brightness.light,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: AmsTokens.bg,
      visualDensity: VisualDensity.standard,
    );

    final t = base.textTheme;
    final textTheme = t.copyWith(
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AmsTokens.text, height: 1.2),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AmsTokens.text),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AmsTokens.text),
      bodyLarge: t.bodyLarge?.copyWith(color: AmsTokens.text),
      bodyMedium: t.bodyMedium?.copyWith(color: AmsTokens.text),
      bodySmall: t.bodySmall?.copyWith(color: AmsTokens.muted),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: AmsTokens.r16,
      borderSide: const BorderSide(color: AmsTokens.border),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AmsTokens.text,
      ),
      cardTheme: const CardThemeData(
        color: AmsTokens.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AmsTokens.r20),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: cs.primary, width: 1.2)),
        errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AmsTokens.danger)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AmsTokens.danger, width: 1.2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

