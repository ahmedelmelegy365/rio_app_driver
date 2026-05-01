// lib/core/constants/app_colors.dart

import 'package:flutter/material.dart';

class AppColors {
  // ── Brand ──────────────────────────────────────────────────
  static const Color blue      = Color(0xFF05407A);
  static const Color blueDeep  = Color(0xFF032B52);
  static const Color blueMid   = Color(0xFF0A5BA8);
  static const Color green     = Color(0xFF22A650);
  static const Color orange    = Color(0xFFFF8C2A);
  static const Color red       = Color(0xFFEF4444);

  // ── Background ─────────────────────────────────────────────
  static const Color base      = Color(0xFFF0F4F8);
  static const Color baseDim   = Color(0xFFE2E8F0);
  static const Color card      = Color(0xFFFFFFFF);

  // ── Text ───────────────────────────────────────────────────
  static const Color textMain  = Color(0xFF1A2332);
  static const Color textSub   = Color(0xFF64748B);

  // ── Helpers ────────────────────────────────────────────────
  static const Color white10   = Color(0x1AFFFFFF);
  static const Color white20   = Color(0x33FFFFFF);

  // ── Gradients ──────────────────────────────────────────────
  static const LinearGradient appBarGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF05407A), Color(0xFF074E94)],
  );

  static const LinearGradient greenLineGradient = LinearGradient(
    colors: [Color(0xFF22A650), Color(0xFF1A8A40)],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF032B52), Color(0xFF05407A)],
  );
}