import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'mark_attendance_screen_1.dart';
import 'register_student_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'admin_profile_setup_screen.dart';
import 'attendance_history_screen.dart';
import 'student_list_screen.dart';
import 'class_management_screen.dart';
import 'teacher_management_screen.dart';
import '../services/api_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;
  bool _isLoading = true;
  
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
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    
    try {
      // Debug: Check if authenticated
      print('🔐 Is Authenticated: ${ApiService.isAuthenticated}');
      
      // Fetch students
      final studentsResult = await ApiService.getStudents();
      print('📊 Students Result: ${studentsResult['success']} - ${studentsResult['error'] ?? "OK"}');
      if (studentsResult['success']) {
        final students = studentsResult['data'] as List? ?? [];
        _totalStudents = students.length;
      } else {
        print('❌ Students Error: ${studentsResult['error']}');
      }
      
      // Fetch classes
      final classesResult = await ApiService.getClasses();
      print('📊 Classes Result: ${classesResult['success']} - ${classesResult['error'] ?? "OK"}');
      if (classesResult['success']) {
        final classes = classesResult['data'] as List? ?? [];
        _totalClasses = classes.length;
      } else {
        print('❌ Classes Error: ${classesResult['error']}');
      }
      
      // Fetch teachers
      final teachersResult = await ApiService.getTeachers();
      if (teachersResult['success']) {
        final teachers = teachersResult['data'] as List? ?? [];
        _totalTeachers = teachers.length;
      }
      
      // Fetch today's attendance
      final attendanceResult = await ApiService.getTodayAttendance();
      if (attendanceResult['success']) {
        final attendance = attendanceResult['data'] as List? ?? [];
        _presentToday = attendance.length;
        
        // Calculate attendance rate
        if (_totalStudents > 0) {
          _attendanceRate = (_presentToday / _totalStudents) * 100;
        }
      }
    } catch (e) {
      // Handle errors silently, show 0 values
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onNavTap(int index) {
    // Don't navigate if already on that screen
    if (_currentIndex == index) return;
    
    setState(() {
      _currentIndex = index;
    });
    
    // Navigation logic with proper routing
    switch (index) {
        case 0:
            // Already on Home
            break;
        case 1:
            Navigator.pushReplacement(
              context, 
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const StudentListScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
            break;
        case 2:
            Navigator.pushReplacement(
              context, 
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const MarkAttendanceScreen1(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
            break;
        case 3:
            Navigator.pushReplacement(
              context, 
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const AttendanceHistoryScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
            break;
        case 4:
            Navigator.pushReplacement(
              context, 
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const AdminProfileSetupScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
            break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
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
                        Text("Admin", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterStudentScreen()))),
                        _buildActionCard(context, "Scan Face", Icons.center_focus_strong, Colors.green,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarkAttendanceScreen1()))),
                        _buildActionCard(context, "Classes", Icons.class_, Colors.purple,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassManagementScreen()))),
                        _buildActionCard(context, "Teachers", Icons.school, Colors.orange,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherManagementScreen()))),
                        _buildActionCard(context, "User Management", Icons.manage_accounts, Colors.indigo,
                          () => Navigator.pushNamed(context, '/admin-user-management')),
                        _buildActionCard(context, "Reports", Icons.bar_chart, Colors.teal,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()))),
                        _buildActionCard(context, "System", Icons.settings, Colors.grey,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
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
            children: [
                _buildNavItem(context, Icons.home, "Home", 0, onTap: () => _onNavTap(0)),
                _buildNavItem(context, Icons.people, "Students", 1, onTap: () => _onNavTap(1)),
                _buildNavItem(context, Icons.center_focus_strong, "Scan", 2, onTap: () => _onNavTap(2)),
                _buildNavItem(context, Icons.history, "History", 3, onTap: () => _onNavTap(3)),
                _buildNavItem(context, Icons.account_circle, "Profile", 4, onTap: () => _onNavTap(4)),
            ],
        ),
      ),
    );
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

  Widget _buildNavItem(BuildContext context, IconData icon, String label, int index, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final isSelected = _currentIndex == index;
    final color = isSelected ? theme.colorScheme.primary : (theme.brightness == Brightness.dark ? Colors.grey[500] : Colors.grey[400]);

    return InkWell(
      onTap: () {
        if (onTap != null) {
          onTap();
        } else {
          setState(() {
            _currentIndex = index;
          });
        }
      },
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
                      // Icon
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: EdgeInsets.all(isSelected ? 8 : 0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected 
                              ? theme.colorScheme.primary.withOpacity(0.15)
                              : Colors.transparent,
                        ),
                        child: Icon(
                          icon, 
                          color: color, 
                          size: 26,
                        ),
                      ),
                      
                      // Notification Badge (optional - can be used for updates)
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
                                        color: theme.colorScheme.primary.withOpacity(0.5),
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
            
            // Label with fade and slide animation
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                color: color,
                fontSize: isSelected ? 11 : 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),
            
            // Selection Indicator
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
