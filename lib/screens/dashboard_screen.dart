import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'mark_attendance_screen_1.dart';
import 'register_student_screen_new.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'admin_profile_setup_screen.dart';
import 'attendance_history_screen.dart';
import 'student_list_screen.dart';
import 'class_management_screen.dart';
import 'teacher_management_screen.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> 
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Timer? _refreshTimer;
  late AnimationController _animationController;
  
  static const Duration _refreshInterval = Duration(seconds: 30);
  
  int _totalStudents = 0;
  int _totalClasses = 0;
  int _presentToday = 0;
  int _totalTeachers = 0;
  double _attendanceRate = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _loadDashboardData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (mounted) {
        _loadDashboardData();
      }
    });
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final statsResult = await ApiService.getDashboardStats();
      if (statsResult['success']) {
        final data = statsResult['data'] as Map<String, dynamic>? ?? {};
        _totalStudents = data['total_students'] ?? 0;
        _totalClasses = data['total_classes'] ?? 0;
        _totalTeachers = data['total_teachers'] ?? 0;
        _presentToday = data['present_today'] ?? 0;
        _attendanceRate = (data['attendance_rate'] ?? 0).toDouble();
      }
    } catch (e) {
      // Handle errors silently
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _animationController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user ?? {};
    final userName = (user['full_name'] ?? 'Admin').toString();
    final userRole = (user['role'] ?? 'admin').toString();
    final isSuperAdmin = userRole == 'super_admin';
    
    // Get greeting based on time of day
    final hour = DateTime.now().hour;
    String greeting = 'Good morning';
    String emoji = '☀️';
    if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
      emoji = '🌤️';
    } else if (hour >= 17) {
      greeting = 'Good evening';
      emoji = '🌙';
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ═══════════════════════════════════════════════════════════════
            // HEADER SECTION
            // ═══════════════════════════════════════════════════════════════
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  // Avatar with gradient border
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                    ),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? AppTheme.surfaceDark : Colors.white,
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        color: theme.colorScheme.primary,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "$greeting $emoji",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Refresh button with soft styling
                  _buildSoftIconButton(
                    icon: _isLoading ? null : Icons.refresh_rounded,
                    isLoading: _isLoading,
                    onTap: _loadDashboardData,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            // ═══════════════════════════════════════════════════════════════
            // SCROLLABLE CONTENT
            // ═══════════════════════════════════════════════════════════════
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadDashboardData,
                color: theme.colorScheme.primary,
                child: ListView(
                  padding: const EdgeInsets.only(top: 16, bottom: 100),
                  children: [
                    // ─────────────────────────────────────────────────────────
                    // TODAY'S OVERVIEW CARD (Featured)
                    // ─────────────────────────────────────────────────────────
                    _buildFeaturedCard(context, isDark),
                    
                    const SizedBox(height: 24),
                    
                    // ─────────────────────────────────────────────────────────
                    // STATS ROW
                    // ─────────────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              context,
                              icon: Icons.groups_rounded,
                              label: "Students",
                              value: _isLoading ? "..." : "$_totalStudents",
                              color: AppTheme.info,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              context,
                              icon: Icons.class_rounded,
                              label: "Classes",
                              value: _isLoading ? "..." : "$_totalClasses",
                              color: AppTheme.accent,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              context,
                              icon: Icons.school_rounded,
                              label: "Teachers",
                              value: _isLoading ? "..." : "$_totalTeachers",
                              color: AppTheme.warning,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ─────────────────────────────────────────────────────────
                    // QUICK ACTIONS SECTION
                    // ─────────────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        "Quick Actions",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Action Cards Grid
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.15,
                        children: [
                          _buildActionCard(
                            context,
                            icon: Icons.person_add_rounded,
                            label: "Register Student",
                            description: "Add new face",
                            color: AppTheme.info,
                            isDark: isDark,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterStudentScreenNew()),
                            ),
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.face_retouching_natural,
                            label: "Scan Face",
                            description: "Mark attendance",
                            color: AppTheme.success,
                            isDark: isDark,
                            onTap: () => ref.read(navigationProvider.notifier).state = 1,
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.class_rounded,
                            label: "Classes",
                            description: "Manage classes",
                            color: AppTheme.accent,
                            isDark: isDark,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ClassManagementScreen()),
                            ),
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.school_rounded,
                            label: "Teachers",
                            description: "Manage staff",
                            color: AppTheme.warning,
                            isDark: isDark,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TeacherManagementScreen()),
                            ),
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.manage_accounts_rounded,
                            label: "Users",
                            description: "User management",
                            color: const Color(0xFF6366F1),
                            isDark: isDark,
                            onTap: () => Navigator.pushNamed(context, '/admin-user-management'),
                          ),
                          if (isSuperAdmin)
                            _buildActionCard(
                              context,
                              icon: Icons.apartment_rounded,
                              label: "Organizations",
                              description: "Manage orgs",
                              color: const Color(0xFF78716C),
                              isDark: isDark,
                              onTap: () => Navigator.pushNamed(context, '/admin-org-management'),
                            ),
                          _buildActionCard(
                            context,
                            icon: Icons.analytics_rounded,
                            label: "Reports",
                            description: "View analytics",
                            color: const Color(0xFF14B8A6),
                            isDark: isDark,
                            onTap: () => ref.read(navigationProvider.notifier).state = 3,
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.settings_rounded,
                            label: "Settings",
                            description: "App settings",
                            color: AppTheme.textSecondaryLight,
                            isDark: isDark,
                            onTap: () => ref.read(navigationProvider.notifier).state = 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FEATURED CARD - Today's Overview with Gradient
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildFeaturedCard(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Attendance",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _isLoading ? "..." : "${_attendanceRate.toStringAsFixed(0)}%",
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 48,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_isLoading && _presentToday > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.white),
                              const SizedBox(width: 2),
                              Text(
                                "$_presentToday present",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                ),
                child: const Icon(
                  Icons.face_retouching_natural,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Progress bar
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _isLoading ? 0 : (_attendanceRate / 100).clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isLoading 
              ? "Loading..." 
              : "$_presentToday of $_totalStudents students present today",
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAT CARD - Compact stat display
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(
          color: isDark ? AppTheme.borderDark.withOpacity(0.3) : AppTheme.borderLight,
        ),
        boxShadow: isDark ? null : AppTheme.softShadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION CARD - Quick action button
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(
              color: isDark ? AppTheme.borderDark.withOpacity(0.3) : AppTheme.borderLight,
            ),
            boxShadow: isDark ? null : AppTheme.softShadowLight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const Spacer(),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOFT ICON BUTTON - Utility button with soft styling
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSoftIconButton({
    IconData? icon,
    bool isLoading = false,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark 
              ? AppTheme.surfaceSecondaryDark 
              : AppTheme.surfaceSecondaryLight,
            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          ),
          child: Center(
            child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
                  ),
                )
              : Icon(
                  icon,
                  size: 22,
                  color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
                ),
          ),
        ),
      ),
    );
  }
}
