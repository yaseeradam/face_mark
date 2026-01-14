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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isLoading = true;
  Timer? _refreshTimer;
  
  // Auto-refresh interval (30 seconds)
  static const Duration _refreshInterval = Duration(seconds: 30);
  
  // Real data from API
  int _totalStudents = 0;
  int _totalClasses = 0;
  int _presentToday = 0;
  int _totalTeachers = 0;
  double _attendanceRate = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
      // Handle errors silently, show 0 values
    }

    if (mounted) {
      setState(() => _isLoading = false);
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

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                  Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2), width: 2),
                          color: theme.colorScheme.primary.withOpacity(0.1),
                        ),
                        child: Icon(Icons.person, color: theme.colorScheme.primary),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Welcome back,", style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(userName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _loadDashboardData,
                    icon: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                      foregroundColor: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // Scrollable Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadDashboardData,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    // Stats Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text("Overview", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          _buildStatCard(
                            context,
                            icon: Icons.face,
                            iconBg: Colors.white,
                            iconColor: theme.colorScheme.primary,
                            label: "Present Today",
                            value: _isLoading ? "..." : "${_attendanceRate.toStringAsFixed(0)}%",
                            trend: _presentToday > 0 ? "+$_presentToday" : null,
                            bg: theme.colorScheme.primary,
                            textColor: Colors.white,
                          ),
                          const SizedBox(width: 16),
                          _buildStatCard(
                            context,
                            icon: Icons.groups,
                            iconBg: Colors.blue[50] ?? Colors.blue.shade50,
                            iconColor: theme.colorScheme.primary,
                            label: "Total Students",
                            value: _isLoading ? "..." : "$_totalStudents",
                            bg: theme.cardColor,
                            textColor: theme.colorScheme.onSurface,
                            isOutlined: true,
                          ),
                          const SizedBox(width: 16),
                           _buildStatCard(
                            context,
                            icon: Icons.class_,
                            iconBg: Colors.purple[50] ?? Colors.purple.shade50,
                            iconColor: Colors.purple,
                            label: "Classes",
                            value: _isLoading ? "..." : "$_totalClasses",
                            bg: theme.cardColor,
                            textColor: theme.colorScheme.onSurface,
                            isOutlined: true,
                          ),
                          const SizedBox(width: 16),
                           _buildStatCard(
                            context,
                            icon: Icons.school,
                            iconBg: Colors.orange[50] ?? Colors.orange.shade50,
                            iconColor: Colors.orange,
                            label: "Teachers",
                            value: _isLoading ? "..." : "$_totalTeachers",
                            bg: theme.cardColor,
                            textColor: theme.colorScheme.onSurface,
                            isOutlined: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Quick Actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Quick Actions", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        _buildActionCard(context, "Register New", Icons.person_add, Colors.blue, 
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterStudentScreenNew()))),
                        _buildActionCard(context, "Scan Face", Icons.center_focus_strong, Colors.green,
                          () => ref.read(navigationProvider.notifier).state = 1),
                        _buildActionCard(context, "Classes", Icons.class_, Colors.purple,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassManagementScreen()))),
                        _buildActionCard(context, "Teachers", Icons.school, Colors.orange,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherManagementScreen()))),
                        _buildActionCard(context, "User Management", Icons.manage_accounts, Colors.indigo,
                          () => Navigator.pushNamed(context, '/admin-user-management')),
                        if (isSuperAdmin)
                          _buildActionCard(context, "Organizations", Icons.apartment, Colors.brown,
                            () => Navigator.pushNamed(context, '/admin-org-management')),
                        _buildActionCard(context, "Reports", Icons.bar_chart, Colors.teal,
                          () => ref.read(navigationProvider.notifier).state = 3),
                        _buildActionCard(context, "Settings", Icons.settings, Colors.grey,
                          () => ref.read(navigationProvider.notifier).state = 4),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Quick Info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text("Quick Info", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoItem(context, "Total Students", "$_totalStudents registered", Icons.people, Colors.blue),
                    _buildInfoItem(context, "Total Classes", "$_totalClasses active classes", Icons.class_, Colors.purple),
                    _buildInfoItem(context, "Total Teachers", "$_totalTeachers teachers", Icons.school, Colors.orange),
                  ], // Close ListView children
                ), // Close ListView
              ), // Close RefreshIndicator
            ), // Close Expanded
          ], // Close Column children
        ), // Close Column and SafeArea child
      ); // Close SafeArea and return statement
  }

  Widget _buildStatCard(BuildContext context, {required IconData icon, required String label, required String value, String? trend, required Color bg, required Color textColor, required Color iconBg, required Color iconColor, bool isOutlined = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: isOutlined ? Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!) : null,
        boxShadow: !isOutlined ? [
          BoxShadow(
            color: bg.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isOutlined ? iconBg.withOpacity(isDark ? 0.1 : 1) : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isOutlined ? iconColor : Colors.white),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(trend, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, String label, IconData icon, MaterialColor color, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }


}
