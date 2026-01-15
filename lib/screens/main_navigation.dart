import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import 'scan_attendance_screen.dart';
import 'student_list_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/navigation_utils.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  int? _pressedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user ?? {};
    final role = (user['role'] ?? 'teacher').toString();
    final navKeys = NavigationUtils.keysForRole(role);
    final screens = navKeys.map((key) => _screenForKey(key)).toList();
    final currentIndex = ref.watch(navigationProvider);
    final safeIndex = currentIndex.clamp(0, screens.length - 1);
    if (safeIndex != currentIndex) {
      Future.microtask(() => ref.read(navigationProvider.notifier).state = safeIndex);
    }
    final hasStudents = navKeys.contains('students');

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 32,
              offset: const Offset(0, -8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: hasStudents
                  ? [
                      _buildNavItem(
                        context,
                        NavigationUtils.indexForKey(role, 'home'),
                        _activeIconForKey('home'),
                        _inactiveIconForKey('home'),
                        _labelForKey('home'),
                        isDark,
                      ),
                      _buildNavItem(
                        context,
                        NavigationUtils.indexForKey(role, 'students'),
                        _activeIconForKey('students'),
                        _inactiveIconForKey('students'),
                        _labelForKey('students'),
                        isDark,
                      ),
                      _buildCenterButton(context, isDark, NavigationUtils.indexForKey(role, 'scan')),
                      _buildNavItem(
                        context,
                        NavigationUtils.indexForKey(role, 'reports'),
                        _activeIconForKey('reports'),
                        _inactiveIconForKey('reports'),
                        _labelForKey('reports'),
                        isDark,
                      ),
                      _buildNavItem(
                        context,
                        NavigationUtils.indexForKey(role, 'settings'),
                        _activeIconForKey('settings'),
                        _inactiveIconForKey('settings'),
                        _labelForKey('settings'),
                        isDark,
                      ),
                    ]
                  : navKeys
                      .map((key) => _buildNavItem(
                            context,
                            NavigationUtils.indexForKey(role, key),
                            _activeIconForKey(key),
                            _inactiveIconForKey(key),
                            _labelForKey(key),
                            isDark,
                          ))
                      .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    bool isDark,
  ) {
    final currentIndex = ref.watch(navigationProvider);
    final isSelected = currentIndex == index;
    final isPressed = _pressedIndex == index;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    
    // Map index for the skip of center button
    final actualIndex = index;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressedIndex = index),
      onTapUp: (_) => setState(() => _pressedIndex = null),
      onTapCancel: () => setState(() => _pressedIndex = null),
      onTap: () => ref.read(navigationProvider.notifier).state = actualIndex,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected 
              ? primaryColor.withOpacity(0.1) 
              : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  color: isSelected 
                    ? primaryColor 
                    : (isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight),
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  color: isSelected 
                    ? primaryColor 
                    : (isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 11,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Center elevated button for Scan (most common action)
  Widget _buildCenterButton(BuildContext context, bool isDark, int index) {
    final theme = Theme.of(context);
    final currentIndex = ref.watch(navigationProvider);
    final isSelected = currentIndex == index;
    final isPressed = _pressedIndex == index;
    
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressedIndex = index),
      onTapUp: (_) => setState(() => _pressedIndex = null),
      onTapCancel: () => setState(() => _pressedIndex = null),
      onTap: () => ref.read(navigationProvider.notifier).state = index,
      child: AnimatedScale(
        scale: isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          transform: Matrix4.translationValues(0, isSelected ? -4 : 0, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(isSelected ? 0.4 : 0.25),
                blurRadius: isSelected ? 16 : 12,
                offset: Offset(0, isSelected ? 8 : 6),
                spreadRadius: isSelected ? 0 : -2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.face_retouching_natural : Icons.face_retouching_natural_outlined,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 4),
              const Text(
                'Scan',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelForKey(String key) {
    switch (key) {
      case 'home':
        return 'Home';
      case 'scan':
        return 'Scan';
      case 'students':
        return 'Students';
      case 'reports':
        return 'Reports';
      case 'settings':
        return 'Settings';
      default:
        return key;
    }
  }

  IconData _activeIconForKey(String key) {
    switch (key) {
      case 'home':
        return Icons.home_rounded;
      case 'scan':
        return Icons.face_retouching_natural;
      case 'students':
        return Icons.groups_rounded;
      case 'reports':
        return Icons.analytics_rounded;
      case 'settings':
        return Icons.settings_rounded;
      default:
        return Icons.circle;
    }
  }

  IconData _inactiveIconForKey(String key) {
    switch (key) {
      case 'home':
        return Icons.home_outlined;
      case 'scan':
        return Icons.face_retouching_natural_outlined;
      case 'students':
        return Icons.groups_outlined;
      case 'reports':
        return Icons.analytics_outlined;
      case 'settings':
        return Icons.settings_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Widget _screenForKey(String key) {
    switch (key) {
      case 'home':
        return const DashboardScreen();
      case 'scan':
        return const ScanAttendanceScreen();
      case 'students':
        return const StudentListScreen();
      case 'reports':
        return const ReportsScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }
}
