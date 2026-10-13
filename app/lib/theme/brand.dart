import 'package:flutter/material.dart';

/// Colors of the app: white background and the blue from the logo
/// (same look as the October prototype). No other brand colors.
class Brand {
  static const blue = Color(0xFF0A84E0); // blue from the logo
  static const light = Color(0xFFEAF4FD); // light fill for selected items
  static const soft = Color(0xFFCFE6FA); // thin dividers inside cards
  static const ink = Color(0xFF15202B); // main text
  static const muted = Color(0xFF64707C); // secondary text
  static const red = Color(0xFFD03A3A); // error messages, missing fields, declined / cancelled
  static const redLight = Color(0xFFFDEDED); // light fill behind error messages and missing fields
  static const white = Colors.white;
}

const _r10 = BorderRadius.all(Radius.circular(10));

OutlineInputBorder _border(double width) =>
    OutlineInputBorder(borderRadius: _r10, borderSide: BorderSide(color: Brand.blue, width: width));

OutlineInputBorder _errBorder(double width) =>
    OutlineInputBorder(borderRadius: _r10, borderSide: BorderSide(color: Brand.red, width: width));

/// The Material theme used by every screen.
ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.blue,
      primary: Brand.blue,
      surface: Colors.white,
      error: Brand.red,
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.ink),
      shape: Border(bottom: BorderSide(color: Brand.soft)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Brand.soft,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: const RoundedRectangleBorder(borderRadius: _r10),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.blue,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Brand.blue, width: 1.3),
        shape: const RoundedRectangleBorder(borderRadius: _r10),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Brand.blue)),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: const TextStyle(color: Brand.muted),
      border: _border(1.2),
      enabledBorder: _border(1.2),
      focusedBorder: _border(2),
      errorBorder: _errBorder(1.4),
      focusedErrorBorder: _errBorder(2),
      errorStyle: const TextStyle(color: Brand.red, fontWeight: FontWeight.w600),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: Brand.blue, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blue : Colors.white),
      checkColor: WidgetStateProperty.all(Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.light,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Brand.blue : Brand.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.blue : Brand.muted)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.blue,
      contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(color: Brand.soft, space: 1, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.blue, linearTrackColor: Brand.light),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Brand.blue),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.blue : Colors.white),
      trackOutlineColor: WidgetStateProperty.all(Brand.blue),
    ),
  );
}
