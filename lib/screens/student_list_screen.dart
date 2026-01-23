import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'student_details_screen.dart';
import 'register_student_screen_new.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import '../utils/ui_helpers.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  final int? classId;
  final String? className;

  const StudentListScreen({super.key, this.classId, this.className});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'all';

  // Optional attendance-by-date view
  bool _showAttendance = false;
  DateTime _selectedDate = DateTime.now();
  final Set<int> _presentStudentIds = <int>{};
  bool _isAttendanceLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final result = await ApiService.getStudents(classId: widget.classId);
    debugPrint('📚 Students API Result: ${result['success']}');
    if (!mounted) return;
    
    if (result['success']) {
      final students = List<Map<String, dynamic>>.from(result['data'] ?? []);
      // Log first student to see structure
      if (students.isNotEmpty) {
        debugPrint('📚 First student data: ${students.first}');
      }
      setState(() {
        _students = students;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      UIHelpers.showError(context, result['error'] ?? 'Failed to load students');
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    return _students.where((student) {
      // Support both 'name' and 'full_name' fields
      final name = (student['full_name'] ?? student['name'] ?? '').toString().toLowerCase();
      final studentId = student['student_id']?.toString().toLowerCase() ?? '';
      final matchesSearch = name.contains(_searchQuery.toLowerCase()) || 
                           studentId.contains(_searchQuery.toLowerCase());
      
      // Check for face registration using 'face_enrolled' boolean field
      final hasFace = student['face_enrolled'] == true;
      
      if (_filterStatus == 'all') return matchesSearch;
      if (_filterStatus == 'registered') return matchesSearch && hasFace;
      if (_filterStatus == 'pending') return matchesSearch && !hasFace;
      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user ?? {};
    final role = (user['role'] ?? 'teacher').toString();
    final isAdmin = role == 'admin' || role == 'super_admin';

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                pinned: true,
                snap: false,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.className != null ? "Students • ${widget.className}" : "Students", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("${_students.length} students registered", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
                  ],
                ),
                actions: [
                  IconButton.filledTonal(
                    onPressed: _loadStudents,
                    icon: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    style: IconButton.styleFrom(backgroundColor: theme.cardColor),
                  ),
                  const SizedBox(width: 16),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: "Search by name or ID...",
                        filled: true,
                        fillColor: theme.cardColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildChip(context, "All Students", _filterStatus == 'all', () => setState(() => _filterStatus = 'all')),
                      const SizedBox(width: 8),
                      _buildChip(context, "Registered", _filterStatus == 'registered', () => setState(() => _filterStatus = 'registered')),
                      const SizedBox(width: 8),
                      _buildChip(context, "Pending Face", _filterStatus == 'pending', () => setState(() => _filterStatus = 'pending')),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_filteredStudents.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('No students found', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (isAdmin)
                          TextButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterStudentScreenNew())),
                            icon: const Icon(Icons.add),
                            label: const Text('Add First Student'),
                          ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == _filteredStudents.length) {
                        return const SizedBox(height: 100);
                      }
                      final student = _filteredStudents[index];
                      // Check face_enrolled boolean instead of face_encoding
                      final hasFace = student['face_enrolled'] == true;
                      // Support both name and full_name fields
                      final studentName = student['full_name'] ?? student['name'] ?? 'Unknown';
                      return _buildStudentCard(
                        context,
                        studentName,
                        "ID: ${student['student_id']} • ${student['class_name'] ?? 'No Class'}",
                        hasFace ? "Registered" : "Pending",
                        hasFace ? Colors.green : Colors.orange,
                        student['photo_path'],
                        student,
                      );
                    },
                    childCount: _filteredStudents.length + 1,
                  ),
                ),
            ],
          ),
          
          if (isAdmin)
            Positioned(
              bottom: 90,
              right: 16,
              child: FloatingActionButton(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterStudentScreenNew()));
                  _loadStudents();
                },
                backgroundColor: theme.colorScheme.primary,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, bool isSelected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : theme.colorScheme.onSurface)),
        backgroundColor: isSelected ? theme.colorScheme.primary : theme.cardColor,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    );
  }

  Widget _buildStudentCard(BuildContext context, String name, String subtitle, String status, Color statusColor, String? imageUrl, Map<String, dynamic> student) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRegistered = statusColor == Colors.green;
    final photoUrl = ApiService.uploadsUrl(imageUrl);
    
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentDetailsScreen(student: student)));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[100]!),
        ),
        child: Row(
          children: [
            // Avatar - show photo if available, otherwise colored initials/checkmark
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRegistered ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                border: Border.all(
                  color: isRegistered ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: photoUrl == null
                    ? Center(
                        child: isRegistered
                            ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
                            : Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                      )
                    : Image.network(
                        photoUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: isRegistered
                                ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
                                : Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
