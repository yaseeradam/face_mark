import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import 'package:camera/camera.dart';
import 'dart:io';

class StudentDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  
  const StudentDetailsScreen({super.key, this.student = const {}});

  @override
  ConsumerState<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends ConsumerState<StudentDetailsScreen> {
  late Map<String, dynamic> _student;
  bool _isLoading = false;
  bool _isLoadingStats = false;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    if (_student.isNotEmpty) {
      _fetchStats();
    }
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoadingStats = true);
    try {
      // Fetch last 30 days by default
      final studentKey = (_student['student_id'] ?? _student['id']).toString();
      final result = await ApiService.getStudentReport(studentKey);
      
      if (mounted) {
        if (result['success'] == true && result['data'] != null) {
          setState(() {
            _stats = _resolveStatsData(result['data']);
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading stats: $e");
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _updateFace() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      if (!mounted) return;
      
      final XFile? result = await showDialog<XFile>(
        context: context,
        builder: (context) => _CameraScannerDialog(camera: frontCamera),
      );

      if (result != null) {
        setState(() => _isLoading = true);
        final response = await ApiService.registerFace(
          studentId: _student['id'],
          imageFile: File(result.path),
        );
        setState(() => _isLoading = false);

        if (mounted) {
          if (response['success']) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Face updated successfully'), backgroundColor: Colors.green));
            _student['face_enrolled'] = true;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: ${response['error']}'), backgroundColor: Colors.red));
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteStudent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student'),
        content: const Text('Are you sure you want to delete this student? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final result = await ApiService.deleteStudent(_student['id']);
      setState(() => _isLoading = false);

      if (mounted) {
        if (result['success']) {
          Navigator.pop(context); // Go back to list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Student deleted successfully'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Failed to delete student'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showEditStudentDialog() async {
    final nameController = TextEditingController(text: _student['full_name'] ?? '');
    final studentIdController = TextEditingController(text: _student['student_id'] ?? '');
    int? selectedClassId = _student['class_id'];
    List<Map<String, dynamic>> classes = [];

    final classesResult = await ApiService.getClasses();
    if (classesResult['success'] == true && classesResult['data'] != null) {
      classes = List<Map<String, dynamic>>.from(classesResult['data']);
    }

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Student'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: studentIdController,
                        decoration: const InputDecoration(
                          labelText: 'Student ID',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Student ID is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Full name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      if (classes.isNotEmpty)
                        DropdownButtonFormField<int>(
                          value: selectedClassId,
                          decoration: const InputDecoration(
                            labelText: 'Class',
                          ),
                          items: classes
                              .map(
                                (c) => DropdownMenuItem<int>(
                                  value: c['id'],
                                  child: Text(c['class_name'] ?? c['name'] ?? 'Class'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(() => selectedClassId = value),
                          validator: (value) => value == null ? 'Please select a class' : null,
                        )
                      else
                        Text(
                          'No classes available',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          final result = await ApiService.updateStudent(_student['id'], {
                            'student_id': studentIdController.text.trim(),
                            'full_name': nameController.text.trim(),
                            'class_id': selectedClassId,
                          });
                          setDialogState(() => isSaving = false);
                          if (!mounted) return;
                          if (result['success'] == true) {
                            final className = classes.firstWhere(
                              (c) => c['id'] == selectedClassId,
                              orElse: () => {},
                            )['class_name'];
                            setState(() {
                              _student['student_id'] = studentIdController.text.trim();
                              _student['full_name'] = nameController.text.trim();
                              _student['class_id'] = selectedClassId;
                              if (className != null) _student['class_name'] = className;
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Student updated successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result['error'] ?? 'Failed to update student'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user ?? {};
    final role = (user['role'] ?? 'teacher').toString();
    final isAdmin = role == 'admin' || role == 'super_admin';

    final String name = _student['full_name'] ?? 'Unknown Student';
    final String studentId = _student['student_id'] ?? 'N/A';
    final String className = _student['class_name'] ?? 'Class ${_student['class_id'] ?? '-'}';
    final bool hasFace = _student['face_enrolled'] == true;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new),
          style: IconButton.styleFrom(
            backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
        title: const Text("Student Profile"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _isLoadingStats ? null : _fetchStats,
            icon: _isLoadingStats
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // Profile Header
                  Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.colorScheme.primary, width: 3),
                              color: Colors.grey[200],
                            ),
                            child: ClipOval(
                              child: _student['photo_path'] != null && _student['photo_path'].toString().isNotEmpty
                                ? Image.network(
                                    "${ApiService.baseUrl}/uploads/${_student['photo_path']}",
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, o, s) => const Icon(Icons.person, size: 60, color: Colors.grey),
                                  )
                                : const Icon(Icons.person, size: 60, color: Colors.grey),
                            ),
                          ),
                          if (hasFace)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 3),
                                ),
                                child: const Icon(Icons.face, color: Colors.white, size: 16),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(name, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text("ID: $studentId • $className", style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Stats Row
                  if (_isLoadingStats)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          _buildStatItem(
                            context,
                            "${_formatAttendanceRate(_stats)}%",
                            "Attendance",
                            Colors.blue,
                          ),
                          _buildStatItem(
                            context,
                            "${_asInt(_stats['days_present'] ?? _stats['present_days'] ?? _stats['present'])}",
                            "Present",
                            Colors.green,
                          ),
                          _buildStatItem(
                            context,
                            "${_asInt(_stats['days_absent'] ?? _stats['absent_days'] ?? _stats['absent'])}",
                            "Absent",
                            Colors.red,
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 32),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Personal Details", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow(context, Icons.badge_outlined, "Student ID", studentId),
                              const Divider(height: 24),
                              _buildDetailRow(context, Icons.class_outlined, "Class", className),
                              const Divider(height: 24),
                              _buildDetailRow(context, Icons.face, "Face Enrolled", hasFace ? "Yes" : "No"),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Action Buttons
                        if (isAdmin) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _showEditStudentDialog,
                                  icon: const Icon(Icons.edit),
                                  label: const Text("Edit Profile"),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                    foregroundColor: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _updateFace,
                                  icon: const Icon(Icons.face_retouching_natural),
                                  label: const Text("Update Face"),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    backgroundColor: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _deleteStudent,
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              label: const Text("Delete Student", style: TextStyle(color: Colors.red)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Colors.red.withOpacity(0.1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: Colors.grey),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _resolveStatsData(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final inner = raw['summary'] ?? raw['stats'] ?? raw['report'] ?? raw['data'];
      if (inner is Map<String, dynamic>) return inner;
      final listSource = raw['records'] ?? raw['attendance'] ?? raw['entries'];
      if (listSource is List) return _resolveStatsData(listSource);
      return raw;
    }
    if (raw is List) {
      int present = 0;
      int absent = 0;
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final status = entry['status']?.toString().toLowerCase();
          final isPresent = entry['present'] == true || entry['is_present'] == true;
          if (status == 'present' || isPresent) {
            present++;
          } else if (status == 'absent') {
            absent++;
          }
        }
      }
      final total = present + absent;
      final rate = total > 0 ? (present / total) * 100 : 0.0;
      return {
        'days_present': present,
        'days_absent': absent,
        'attendance_rate': rate,
        'total_days': total,
      };
    }
    return {};
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll('%', '').trim();
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  String _formatAttendanceRate(Map<String, dynamic> stats) {
    final present = _asInt(stats['days_present'] ?? stats['present_days'] ?? stats['present']);
    final absent = _asInt(stats['days_absent'] ?? stats['absent_days'] ?? stats['absent']);
    int total = _asInt(stats['total_days'] ?? stats['total'] ?? stats['total_records'] ?? stats['total_attendance']);
    if (total == 0) total = present + absent;
    double rate = _asDouble(stats['attendance_rate']);
    if (rate == 0 && total > 0) {
      rate = (present / total) * 100;
    }
    if (rate > 0 && rate <= 1) {
      rate *= 100;
    }
    return rate.toStringAsFixed(0);
  }
}

class _CameraScannerDialog extends StatefulWidget {
  final CameraDescription camera;
  const _CameraScannerDialog({required this.camera});

  @override
  State<_CameraScannerDialog> createState() => _CameraScannerDialogState();
}

class _CameraScannerDialogState extends State<_CameraScannerDialog> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CameraPreview(_controller!),
          
          // Laser bar animation
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final y = MediaQuery.of(context).size.height * _animationController.value;
              return Positioned(
                top: y,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.cyan,
                    boxShadow: [BoxShadow(color: Colors.cyan.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
                  ),
                ),
              );
            },
          ),
          
          Positioned(
            bottom: 40,
            child: FloatingActionButton(
              onPressed: () async {
                final photo = await _controller!.takePicture();
                if (mounted) Navigator.pop(context, photo);
              },
              backgroundColor: Colors.white,
              child: const Icon(Icons.camera_alt, color: Colors.black),
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
