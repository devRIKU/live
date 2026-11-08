import 'package:flutter/material.dart';

/// Lively design tokens — port of `design-system/tokens.css`.
/// Single source of truth for every value. Never hard-code colors elsewhere.
class Lively {
  Lively._();

  // ── Layer 1 · Primitives ────────────────────────────────────────────────
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral25 = Color(0xFFFBFAF8);
  static const neutral50 = Color(0xFFF5F4F2);
  static const neutral100 = Color(0xFFECEAE7);
  static const neutral200 = Color(0xFFDEDBD6);
  static const neutral300 = Color(0xFFC4C0B9);
  static const neutral400 = Color(0xFF9C978F);
  static const neutral500 = Color(0xFF77726B);
  static const neutral600 = Color(0xFF565149);
  static const neutral700 = Color(0xFF3A3630);
  static const neutral800 = Color(0xFF262320);
  static const neutral900 = Color(0xFF171614);
  static const neutral950 = Color(0xFF0D0C0B);

  static const indigo300 = Color(0xFFA8B3F2);
  static const indigo400 = Color(0xFF8189E6);
  static const indigo500 = Color(0xFF6A88E2);
  static const indigo600 = Color(0xFF556ADC);
  static const indigo700 = Color(0xFF4250D5);
  static const indigo800 = Color(0xFF393CC1);
  static const indigo900 = Color(0xFF2B2D8F);

  static const periwinkle200 = Color(0xFFF4F7FF);
  static const periwinkle300 = Color(0xFFDDE7FF);
  static const periwinkle400 = Color(0xFFBED2FF);

  static const orange300 = Color(0xFFF2D1B7);
  static const orange400 = Color(0xFFE29357);
  static const orange500 = Color(0xFFD5650F);
  static const orange600 = Color(0xFFB4530B);
  static const orange700 = Color(0xFF8C3F08);

  static const gold300 = Color(0xFFF9E7BB);
  static const gold400 = Color(0xFFEAAF1C);
  static const gold500 = Color(0xFFC99612);

  static const flame500 = Color(0xFFFF6B00);
  static const butter100 = Color(0xFFFFFAEB);
  static const butter200 = Color(0xFFFFF0C2);

  static const appleBlue = Color(0xFF007AFF);
  static const appleGreen = Color(0xFF34C759);
  static const appleRed = Color(0xFFFF3B30);
  static const appleOrange = Color(0xFFFF9500);
  static const appleGray = Color(0xFF8E8E93);

  // ── Spacing · 4px base ──────────────────────────────────────────────────
  static const s0 = 0.0, s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0;
  static const s5 = 20.0, s6 = 24.0, s8 = 32.0, s10 = 40.0, s12 = 48.0, s16 = 64.0;

  // ── Radii ───────────────────────────────────────────────────────────────
  static const rXs = 4.0, rSm = 6.0, rMd = 8.0, rLg = 12.0, rXl = 16.0, r2xl = 20.0;
  static const rCapsule = 999.0;

  // ── Borders ─────────────────────────────────────────────────────────────
  static const bHairline = 0.5, bThin = 1.0, bThick = 2.0;

  // ── Type scale (HIG roles, px) ──────────────────────────────────────────
  static const tDisplay = 30.0, tTitle = 22.0, tHeadline = 17.0, tBody = 16.0;
  static const tCallout = 15.0, tSubhead = 14.0, tFootnote = 13.0;
  static const tCaption = 12.0, tMicro = 11.0;

  static const lhDisplay = 1.2, lhTitle = 1.27, lhHeadline = 1.29;
  static const lhBody = 1.375, lhCallout = 1.33, lhSubhead = 1.36;
  static const lhFootnote = 1.31, lhCaption = 1.33, lhMicro = 1.27;

  // ── Motion ──────────────────────────────────────────────────────────────
  static const dInstant = Duration(milliseconds: 90);
  static const dFast = Duration(milliseconds: 140);
  static const dBase = Duration(milliseconds: 180);
  static const dSlow = Duration(milliseconds: 260);
  static const dSlower = Duration(milliseconds: 380);
  static const dEntrance = Duration(milliseconds: 520);

  static const easeOut = Cubic(0.23, 1, 0.32, 1);
  static const easeOutQuart = Cubic(0.25, 1, 0.5, 1);
  static const easeOutQuint = Cubic(0.22, 1, 0.36, 1);
  static const easeOutExpo = Cubic(0.16, 0.3, 1, 1);
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);
  static const easeSpring = Cubic(0.22, 1.08, 0.36, 1);

  static const staggerStep = Duration(milliseconds: 60);
  static const staggerCap = Duration(milliseconds: 320);

  // ── Component metrics ───────────────────────────────────────────────────
  static const sidebarWidth = 244.0;
  static const columnWidth = 720.0;
  static const threadGap = 26.0;
  static const composerRadius = 28.0;
  static const composerPad = 8.0;
  static const composerMinHeight = 56.0;
  static const composerChipRadius = 20.0;
  static const popoverRadius = 20.0;
  static const bubbleRadius = 18.0;
  static const btnRadius = 10.0;
  static const btnHeight = 32.0;
  static const sendSize = 34.0;

  // ── Flow spectrum (flow states ONLY, never a surface fill) ──────────────
  static const flowSpectrum = <Color>[
    indigo800, indigo500, periwinkle400, gold400, orange500,
  ];

  static const flowVertical = <Color>[periwinkle400, indigo800, orange500];

  // ── Dark theme aliases (neutral-0 in light → semantic roles) ────────────
  static Color canvas(Brightness b) => b == Brightness.dark ? neutral950 : neutral0;
  static Color surface(Brightness b) => b == Brightness.dark ? const Color(0xFF000000) : neutral0;
  static Color surfaceRaised(Brightness b) => b == Brightness.dark ? const Color(0xFF1C1C1E) : neutral0;
  static Color surfaceSunken(Brightness b) => b == Brightness.dark ? const Color(0xFF101012) : neutral25;
  static Color surfaceMuted(Brightness b) => b == Brightness.dark ? const Color(0xFF2C2C2E) : neutral100;

  static Color textPrimary(Brightness b) => b == Brightness.dark ? const Color(0xFFFFFFFF) : neutral900;
  static Color textSecondary(Brightness b) =>
      b == Brightness.dark ? const Color(0xBDEBEBF5) : const Color(0x9E3C3C43);
  static Color textTertiary(Brightness b) =>
      b == Brightness.dark ? const Color(0x5CEBEBF5) : const Color(0x613C3C43);

  static Color separator(Brightness b) =>
      b == Brightness.dark ? const Color(0x99545458) : const Color(0x3D3C3C43);
  static Color separatorStrong(Brightness b) =>
      b == Brightness.dark ? const Color(0xD9545458) : const Color(0x5C3C3C43);
  static Color gridLine(Brightness b) =>
      b == Brightness.dark ? const Color(0x09FFFFFF) : const Color(0x0E171614);

  static Color fill(Brightness b, int level) {
    const lightFills = [0x1A767680, 0x29767680, 0x3D767680, 0x5C767680];
    const darkFills = [0x33767680, 0x4D767680, 0x6B767680, 0x8F767680];
    final hex = (b == Brightness.dark ? darkFills : lightFills)[level.clamp(0, 3)];
    return Color(hex);
  }

  static Color accent(Brightness b) => b == Brightness.dark ? const Color(0xFF0A84FF) : appleBlue;
  static Color accentHover(Brightness b) => b == Brightness.dark ? const Color(0xFF3D9BFF) : const Color(0xFF0069DF);
  static Color accentMuted(Brightness b) =>
      b == Brightness.dark ? const Color(0x330A84FF) : const Color(0x24007AFF);
  static Color accentText(Brightness b) => b == Brightness.dark ? const Color(0xFF64A8FF) : const Color(0xFF0071E3);

  static Color scrim(Brightness b) => Color(b == Brightness.dark ? 0x8C000000 : 0x4D000000);
}

/// Reads the current `Brightness` for token lookups.
extension LivelyBrightness on BuildContext {
  Brightness get livelyBrightness => Theme.of(this).brightness;
}