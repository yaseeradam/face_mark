import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_navigation.dart';
import '../screens/dashboard_screen.dart';
import '../screens/student_list_screen.dart';
import '../screens/register_student_screen_new.dart';
import '../screens/mark_attendance_screen_1.dart';
import '../screens/attendance_history_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/admin_profile_setup_screen.dart';
import '../screens/student_details_screen.dart';
import '../screens/class_management_screen.dart';
import '../screens/teacher_management_screen.dart';
import '../screens/attendance_report_screen.dart';
import '../screens/admin/admin_user_management_screen.dart';
import '../screens/admin/admin_organization_management_screen.dart';
import '../screens/scan_attendance_screen.dart';
import '../screens/forgot_password_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String studentList = '/students';
  static const String registerStudent = '/register-student';
  static const String markAttendance = '/mark-attendance';
  static const String attendanceHistory = '/attendance-history';
  static const String reports = '/reports';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String studentDetails = '/student-details';
  static const String classManagement = '/class-management';
  static const String teacherManagement = '/teacher-management';
  static const String attendanceReport = '/attendance-report';
  static const String adminUserManagement = '/admin-user-management';
  static const String adminOrgManagement = '/admin-org-management';
  static const String scanAttendance = '/scan-attendance';
  static const String forgotPassword = '/forgot-password';

  static Map<String, WidgetBuilder> get routes => {
    splash: (context) => const SplashScreen(),
    login: (context) => const LoginScreen(),
    dashboard: (context) => const MainNavigation(),
    studentList: (context) => const StudentListScreen(),
    registerStudent: (context) => const RegisterStudentScreenNew(),
    markAttendance: (context) => const MarkAttendanceScreen1(),
    attendanceHistory: (context) => const AttendanceHistoryScreen(),
    reports: (context) => const ReportsScreen(),
    settings: (context) => const SettingsScreen(),
    profile: (context) => const AdminProfileSetupScreen(),
    studentDetails: (context) => const StudentDetailsScreen(),
    classManagement: (context) => const ClassManagementScreen(),
    teacherManagement: (context) => const TeacherManagementScreen(),
    attendanceReport: (context) => const AttendanceReportScreen(),
    adminUserManagement: (context) => const AdminUserManagementScreen(),
    adminOrgManagement: (context) => const AdminOrganizationManagementScreen(),
    scanAttendance: (context) => const ScanAttendanceScreen(),
    forgotPassword: (context) => const ForgotPasswordScreen(),
  };
}
