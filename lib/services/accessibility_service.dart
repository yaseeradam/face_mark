import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class AccessibilityService {
  static void announceMessage(String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  static Widget makeAccessible({
    required Widget child,
    required String label,
    String? hint,
    String? value,
    bool excludeSemantics = false,
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      excludeSemantics: excludeSemantics,
      onTap: onTap,
      child: child,
    );
  }

  static Widget accessibleButton({
    required Widget child,
    required String label,
    required VoidCallback onPressed,
    String? hint,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: true,
      enabled: true,
      onTap: onPressed,
      child: child,
    );
  }

  static Widget accessibleTextField({
    required Widget child,
    required String label,
    String? hint,
    String? value,
    bool isPassword = false,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      value: value,
      textField: true,
      obscured: isPassword,
      child: child,
    );
  }

  static Widget accessibleImage({
    required Widget child,
    required String description,
  }) {
    return Semantics(
      label: description,
      image: true,
      child: child,
    );
  }

  static Widget accessibleCard({
    required Widget child,
    required String label,
    String? hint,
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: onTap != null,
      onTap: onTap,
      child: child,
    );
  }

  static Widget accessibleList({
    required Widget child,
    required String label,
    int? itemCount,
  }) {
    return Semantics(
      label: '$label${itemCount != null ? ' with $itemCount items' : ''}',
      child: child,
    );
  }

  static Widget accessibleProgress({
    required Widget child,
    required String label,
    double? value,
  }) {
    return Semantics(
      label: label,
      value: value != null ? '${(value * 100).round()}%' : null,
      child: child,
    );
  }
}

class HighContrastTheme {
  static ThemeData getHighContrastTheme(bool isDark) {
    final baseTheme = isDark ? ThemeData.dark() : ThemeData.light();
    
    return baseTheme.copyWith(
      colorScheme: isDark
          ? const ColorScheme.dark(
              primary: Colors.yellow,
              onPrimary: Colors.black,
              secondary: Colors.cyan,
              onSecondary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
              background: Colors.black,
              onBackground: Colors.white,
              error: Colors.red,
              onError: Colors.white,
            )
          : const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              secondary: Colors.blue,
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              background: Colors.white,
              onBackground: Colors.black,
              error: Colors.red,
              onError: Colors.white,
            ),
      textTheme: baseTheme.textTheme.copyWith(
        bodyLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(88, 48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}