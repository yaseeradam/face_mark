import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import 'scan_attendance_screen.dart';
import 'student_list_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class MainNavigation extends ConsumerWidget {
  const MainNavigation({super.key});

  final List<Widget> _screens = const [
    DashboardScreen(),
    ScanAttendanceScreen(),
    StudentListScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentIndex = ref.watch(navigationProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
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
              children: [
                _buildNavItem(
                  context, ref, 0,
                  Icons.home_rounded,
                  Icons.home_outlined,
                  'Home',
                  isDark,
                ),
                _buildNavItem(
                  context, ref, 1,
                  Icons.face_retouching_natural,
                  Icons.face_retouching_natural_outlined,
                  'Scan',
                  isDark,
                ),
                // Center FAB-style button for Scan
                _buildCenterButton(context, ref, isDark),
                _buildNavItem(
                  context, ref, 3,
                  Icons.analytics_rounded,
                  Icons.analytics_outlined,
                  'Reports',
                  isDark,
                ),
                _buildNavItem(
                  context, ref, 4,
                  Icons.settings_rounded,
                  Icons.settings_outlined,
                  'Settings',
                  isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    WidgetRef ref,
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    bool isDark,
  ) {
    final currentIndex = ref.watch(navigationProvider);
    final isSelected = currentIndex == index;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    
    // Map index for the skip of center button
    final actualIndex = index;

    return GestureDetector(
      onTap: () => ref.read(navigationProvider.notifier).state = actualIndex,
      behavior: HitTestBehavior.opaque,
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
    );
  }

  // Center elevated button for Students (most common action)
  Widget _buildCenterButton(BuildContext context, WidgetRef ref, bool isDark) {
    final theme = Theme.of(context);
    final currentIndex = ref.watch(navigationProvider);
    final isSelected = currentIndex == 2;
    
    return GestureDetector(
      onTap: () => ref.read(navigationProvider.notifier).state = 2,
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
              isSelected ? Icons.groups_rounded : Icons.groups_outlined,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            const Text(
              'Students',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
