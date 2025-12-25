import 'package:flutter/material.dart';

/// UI Helper utilities for safe widget operations
class UIHelpers {
  /// Safely show a SnackBar only if the context is still mounted
  /// 
  /// Usage:
  /// ```dart
  /// await UIHelpers.showSnackBar(
  ///   context,
  ///   message: 'Operation successful',
  ///   isError: false,
  /// );
  /// ```
  static void showSnackBar(
    BuildContext context, {
    required String message,
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
  }

  /// Show success message
  static void showSuccess(BuildContext context, String message) {
    showSnackBar(context, message: message, isError: false);
  }

  /// Show error message
  static void showError(BuildContext context, String message) {
    showSnackBar(context, message: message, isError: true);
  }

  /// Show warning message
  static void showWarning(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show info message
  static void showInfo(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Safely show a dialog only if the context is mounted
  static Future<T?> showSafeDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    if (!context.mounted) {
      return Future.value(null);
    }
    
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
    );
  }

  /// Show a confirmation dialog
  static Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDangerous = false,
  }) async {
    if (!context.mounted) return false;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  /// Show loading dialog
  static void showLoadingDialog(BuildContext context, {String? message}) {
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message ?? 'Loading...')),
            ],
          ),
        ),
      ),
    );
  }

  /// Dismiss any showing dialog
  static void dismissDialog(BuildContext context) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }
}
