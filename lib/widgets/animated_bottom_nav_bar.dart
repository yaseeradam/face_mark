import 'package:flutter/material.dart';

/// Animated Bottom Navigation Bar with smooth transitions
/// 
/// Features:
/// - Scale animation on selection
/// - Color transitions
/// - Glowing indicator dot
/// - Background color change
/// - Selection underline
class AnimatedBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavItem> items;

  const AnimatedBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(
          items.length,
          (index) => _buildNavItem(
            context,
            items[index].icon,
            items[index].label,
            index,
            theme,
            isDark,
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    int index,
    ThemeData theme,
    bool isDark,
  ) {
    final isSelected = currentIndex == index;
    final color = isSelected
        ? theme.colorScheme.primary
        : (isDark ? Colors.grey[500] : Colors.grey[400]);

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with scale animation
            TweenAnimationBuilder<double>(
              key: ValueKey<bool>(isSelected),
              tween: Tween<double>(
                begin: 1.0,
                end: isSelected ? 1.2 : 1.0,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Icon with background
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: EdgeInsets.all(isSelected ? 8 : 0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? theme.colorScheme.primary.withOpacity(0.15)
                              : Colors.transparent,
                        ),
                        child: Icon(icon, color: color, size: 26),
                      ),

                      // Glowing dot indicator
                      if (isSelected)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 4),

            // Label with animated style
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                color: color,
                fontSize: isSelected ? 11 : 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),

            // Selection indicator line
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: 3,
              width: isSelected ? 20 : 0,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom Navigation Item Model
class BottomNavItem {
  final IconData icon;
  final String label;
  final String route;

  const BottomNavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

/// Predefined navigation items for the app
class AppNavItems {
  static const items = [
    BottomNavItem(icon: Icons.home, label: 'Home', route: '/dashboard'),
    BottomNavItem(icon: Icons.people, label: 'Students', route: '/students'),
    BottomNavItem(icon: Icons.center_focus_strong, label: 'Scan', route: '/scan'),
    BottomNavItem(icon: Icons.history, label: 'History', route: '/history'),
    BottomNavItem(icon: Icons.account_circle, label: 'Profile', route: '/profile'),
  ];
}
