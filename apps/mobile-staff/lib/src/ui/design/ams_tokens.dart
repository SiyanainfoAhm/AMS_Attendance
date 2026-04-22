import "package:flutter/material.dart";

class AmsTokens {
  static const brand = Color(0xFF4F46E5); // Indigo-600
  static const brand2 = Color(0xFF0EA5E9); // Sky-500 (accent)
  static const bg = Color(0xFFF6F7FB);
  static const surface = Colors.white;
  static const text = Color(0xFF0F172A); // Slate-900
  static const muted = Color(0xFF64748B); // Slate-500
  static const border = Color(0xFFE2E8F0); // Slate-200
  static const success = Color(0xFF16A34A); // Green-600
  static const warning = Color(0xFFF59E0B); // Amber-500
  static const danger = Color(0xFFDC2626); // Red-600

  static const r12 = BorderRadius.all(Radius.circular(12));
  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r20 = BorderRadius.all(Radius.circular(20));

  static List<BoxShadow> shadowSm = const [
    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
  ];

  static List<BoxShadow> shadowMd = const [
    BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 8)),
  ];
}

