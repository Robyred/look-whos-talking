import 'package:flutter/material.dart';

/// Brand palette — see `DESIGN_PLAN_v1.md` §2.
const kBackground = Color(0xFF0F1117);
const kSurface = Color(0xFF161B27);
const kSurfaceVariant = Color(0xFF1E2535);
const kPrimaryCoral = Color(0xFFFF6B6B);
const kSecondaryTeal = Color(0xFF4ECDC4);
const kTertiaryAmber = Color(0xFFFFB347);
const kViolet = Color(0xFF9B7FE8);
const kOnSurface = Color(0xFFF0F2F8);
const kMuted = Color(0xFF8892A4);
const kOutline = Color(0xFF2A3347);

/// Dark-first theme: dark background, coral primary, teal/amber/violet accents.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: kPrimaryCoral,
    onPrimary: kBackground,
    secondary: kSecondaryTeal,
    onSecondary: kBackground,
    tertiary: kTertiaryAmber,
    onTertiary: kBackground,
    error: kPrimaryCoral,
    onError: kBackground,
    surface: kSurface,
    onSurface: kOnSurface,
    surfaceContainerHighest: kSurfaceVariant,
    onSurfaceVariant: kMuted,
    outline: kOutline,
  );

  const rounded12 = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackground,
      foregroundColor: kOnSurface,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: kMuted),
      actionsIconTheme: IconThemeData(color: kMuted),
      titleTextStyle: TextStyle(
        color: kOnSurface,
        fontSize: 20,
        fontWeight: FontWeight.w400,
      ),
    ),
    cardTheme: const CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPrimaryCoral,
        foregroundColor: kBackground,
        minimumSize: const Size.fromHeight(52),
        shape: rounded12,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimaryCoral,
        side: const BorderSide(color: kPrimaryCoral),
        minimumSize: const Size.fromHeight(52),
        shape: rounded12,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPrimaryCoral),
    ),
    dividerTheme: const DividerThemeData(color: kOutline, thickness: 1),
    tabBarTheme: const TabBarThemeData(
      labelColor: kOnSurface,
      unselectedLabelColor: kMuted,
      indicatorColor: kPrimaryCoral,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: kSurfaceVariant,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      hintStyle: TextStyle(color: kMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide(color: kOutline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide(color: kOutline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide(color: kPrimaryCoral),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? kSecondaryTeal
            : kMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? kSecondaryTeal.withValues(alpha: 0.35)
            : kOutline,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: kMuted,
      textColor: kOnSurface,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kPrimaryCoral,
    ),
  );
}

/// Uppercase, letter-spaced, muted section heading (plan §3).
const TextStyle kSectionHeading = TextStyle(
  color: kMuted,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.2,
);

/// Muted metadata text (dates, durations, counts).
const TextStyle kMetadataText = TextStyle(color: kMuted, fontSize: 13);
