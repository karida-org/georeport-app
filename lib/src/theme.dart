// Georeport brand theme — generated from the brand guidelines.
// Fonts: bundle IBM Plex Sans + IBM Plex Sans JP (OFL) as app fonts.
import 'package:flutter/material.dart';

abstract final class GeoreportColors {
  static const green = Color(0xFF2F6E2B); // primary
  static const greenDeep = Color(0xFF264F36); // emphasis / app icon field
  static const greenLight = Color(0xFF6FBF67); // dark-mode primary / accents
  static const greenSoft = Color(0xFFE3F0E2); // tint fills, selected states
  static const ink = Color(0xFF1D2B23); // text
  static const inkMuted = Color(0xFF52645A); // secondary text
  static const border = Color(0xFFDDE5DE);
  static const bg = Color(0xFFF4F7F4); // scaffold
  static const darkBg = Color(0xFF101613);
  static const darkSurface = Color(0xFF182219);
  static const darkBorder = Color(0xFF2A3830);
  static const darkText = Color(0xFFE6EDE7);
  static const darkTextMuted = Color(0xFF9FB0A4);
}

const _fontFallback = ['IBMPlexSansJP'];

final georeportLightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: GeoreportColors.green,
    primary: GeoreportColors.green,
    secondary: GeoreportColors.greenDeep,
    surface: Colors.white,
    outline: GeoreportColors.border,
  ),
  scaffoldBackgroundColor: GeoreportColors.bg,
  fontFamily: 'IBMPlexSans',
  fontFamilyFallback: _fontFallback,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: GeoreportColors.ink,
    elevation: 0,
    centerTitle: false,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: GeoreportColors.green,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: GeoreportColors.ink,
      side: const BorderSide(color: GeoreportColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  chipTheme: const ChipThemeData(
    selectedColor: GeoreportColors.greenSoft,
    labelStyle: TextStyle(color: GeoreportColors.ink),
  ),
  dividerColor: GeoreportColors.border,
);

final georeportDarkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: GeoreportColors.green,
    brightness: Brightness.dark,
    primary: GeoreportColors.greenLight,
    surface: GeoreportColors.darkSurface,
    outline: GeoreportColors.darkBorder,
  ),
  scaffoldBackgroundColor: GeoreportColors.darkBg,
  fontFamily: 'IBMPlexSans',
  fontFamilyFallback: _fontFallback,
  appBarTheme: const AppBarTheme(
    backgroundColor: GeoreportColors.darkSurface,
    foregroundColor: GeoreportColors.darkText,
    elevation: 0,
    centerTitle: false,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: GeoreportColors.greenLight,
      foregroundColor: GeoreportColors.darkBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),
  dividerColor: GeoreportColors.darkBorder,
);
