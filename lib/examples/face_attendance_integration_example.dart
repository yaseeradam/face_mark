import 'package:flutter/material.dart';
import '../screens/register_student_screen_new.dart';
import '../screens/scan_attendance_screen.dart';

/// Example integration of new face attendance screens
///
/// This file shows how to integrate the new screens into your existing app.
/// You can use this as a reference for your dashboard or navigation system.

class FaceAttendanceIntegrationExample extends StatelessWidget {
  const FaceAttendanceIntegrationExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance System')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            const Text(
              'Face Attendance System',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by AI Face Recognition',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),

            const SizedBox(height: 32),

            // Register Student Card
            _buildFeatureCard(
              context,
              icon: Icons.person_add,
              title: 'Register Student',
              description: 'Scan face 3 times and fill student details',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterStudentScreenNew(),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Mark Attendance Card
            _buildFeatureCard(
              context,
              icon: Icons.face_retouching_natural,
              title: 'Mark Attendance',
              description: 'Scan student face to mark attendance',
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ScanAttendanceScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Info Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('1. Register students with face scans'),
                  _buildInfoRow('2. Face is converted to secure embeddings'),
                  _buildInfoRow('3. Use scan to identify and mark attendance'),
                  _buildInfoRow('4. System uses AI for accurate recognition'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.amber[900]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alternative: Add to existing Dashboard
///
/// If you have an existing dashboard screen, you can add these options:
///
/// Example for GridView dashboard:
///
/// GridView.count(
///   crossAxisCount: 2,
///   children: [
///     DashboardCard(
///       icon: Icons.person_add,
///       title: 'Register',
///       onTap: () => Navigator.push(
///         context,
///         MaterialPageRoute(builder: (context) => const RegisterStudentScreenNew()),
///       ),
///     ),
///     DashboardCard(
///       icon: Icons.face,
///       title: 'Scan',
///       onTap: () => Navigator.push(
///         context,
///         MaterialPageRoute(builder: (context) => const ScanAttendanceScreen()),
///       ),
///     ),
///   ],
/// )
///
/// Example for Drawer menu:
///
/// ListTile(
///   leading: const Icon(Icons.person_add),
///   title: const Text('Register Student'),
///   onTap: () {
///     Navigator.pop(context); // Close drawer
///     Navigator.push(
///       context,
///       MaterialPageRoute(builder: (context) => const RegisterStudentScreenNew()),
///     );
///   },
/// ),
/// ListTile(
///   leading: const Icon(Icons.face),
///   title: const Text('Mark Attendance'),
///   onTap: () {
///     Navigator.pop(context);
///     Navigator.push(
///       context,
///       MaterialPageRoute(builder: (context) => const ScanAttendanceScreen()),
///     );
///   },
/// ),
