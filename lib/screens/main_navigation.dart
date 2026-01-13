import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import 'scan_attendance_screen.dart';
import 'student_list_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../providers/app_providers.dart';

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
          color: isDark ? const Color(0xFF1E2936) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(context, ref, 0, Icons.home_rounded, Icons.home_outlined, 'Home'),
                _buildNavItem(context, ref, 1, Icons.qr_code_scanner_rounded, Icons.qr_code_scanner_outlined, 'Scan'),
                _buildNavItem(context, ref, 2, Icons.people_rounded, Icons.people_outlined, 'Students'),
                _buildNavItem(context, ref, 3, Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Reports'),
                _buildNavItem(context, ref, 4, Icons.settings_rounded, Icons.settings_outlined, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildNavItem(BuildContext context, WidgetRef ref, int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final currentIndex = ref.watch(navigationProvider);
    final isSelected = currentIndex == index;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => ref.read(navigationProvider.notifier).state = index,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? primaryColor : Colors.grey,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
