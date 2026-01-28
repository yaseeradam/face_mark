import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import '../utils/ui_helpers.dart';
import 'student_list_screen.dart';
import 'class_attendance_screen.dart';

class ClassManagementScreen extends ConsumerStatefulWidget {
  const ClassManagementScreen({super.key});

  @override
  ConsumerState<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends ConsumerState<ClassManagementScreen> {
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _teachers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadTeachers();
  }

  Future<void> _loadClasses() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final result = await ApiService.getClasses();
    if (!mounted) return;
    
    if (result['success']) {
      setState(() {
        _classes = List<Map<String, dynamic>>.from(result['data'] ?? []);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      UIHelpers.showError(context, result['error'] ?? 'Failed to load classes');
    }
  }

  Future<void> _loadTeachers() async {
    final result = await ApiService.getTeachers();
    if (!mounted) return;
    if (result['success']) {
      setState(() {
        _teachers = List<Map<String, dynamic>>.from(result['data'] ?? []);
      });
    }
  }

  List<Map<String, dynamic>> get _filteredClasses {
    if (_searchQuery.isEmpty) return _classes;
    return _classes.where((cls) {
      final name = cls['class_name']?.toString().toLowerCase() ?? '';
      final code = cls['class_code']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) || code.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _createClass(String name, String code, int? teacherId) async {
    final payload = {
      'class_name': name,
      'class_code': code,
      if (teacherId != null) 'teacher_id': teacherId,
    };
    final result = await ApiService.createClass(payload);
    if (!mounted) return;
    
    if (result['success']) {
      UIHelpers.showSuccess(context, 'Class created successfully!');
      await _loadClasses();
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Failed to create class');
    }
  }

  Future<void> _deleteClass(int classId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Class'),
        content: const Text('Are you sure you want to delete this class?'),
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
      final result = await ApiService.deleteClass(classId);
      if (!mounted) return;
      
      if (result['success']) {
        UIHelpers.showSuccess(context, 'Class deleted');
        await _loadClasses();
      } else {
        UIHelpers.showError(context, result['error'] ?? 'Failed to delete');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user ?? {};
    final role = (user['role'] ?? 'teacher').toString();
    final isAdmin = role == 'admin' || role == 'super_admin';

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new),
            style: IconButton.styleFrom(
              backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            ),
          ),
          title: const Text("Class Management"),
        ),
        body: Center(
          child: Text(
            "Access restricted to administrators",
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new),
          style: IconButton.styleFrom(
            backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Class Management"),
            Text("${_classes.length} classes", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            onPressed: _loadClasses,
            icon: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            style: IconButton.styleFrom(backgroundColor: theme.cardColor),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: "Search classes...",
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          
          // Class List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClasses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.class_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No classes found', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _showCreateClassDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Create First Class'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadClasses,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredClasses.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _filteredClasses.length) return const SizedBox(height: 100);
                            final cls = _filteredClasses[index];
                            return _buildClassCard(context, cls);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateClassDialog(context),
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildClassCard(BuildContext context, Map<String, dynamic> cls) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = [Colors.blue, Colors.green, Colors.purple, Colors.orange, Colors.teal];
    final color = colors[cls['id'] % colors.length];
    final studentCount = cls['student_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.class_, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cls['class_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(cls['class_code'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit Class')),
                  const PopupMenuItem(value: 'students', child: Text('View Students')),
                  const PopupMenuItem(value: 'attendance', child: Text('View Attendance')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Class', style: TextStyle(color: Colors.red))),
                ],
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteClass(cls['id']);
                  } else if (value == 'students') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentListScreen(
                          classId: cls['id'],
                          className: cls['class_name'],
                        ),
                      ),
                    );
                  } else if (value == 'attendance') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClassAttendanceScreen(
                          classId: cls['id'],
                          className: cls['class_name'],
                        ),
                      ),
                    );
                  } else if (value == 'edit') {
                    _showEditClassDialog(context, cls);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatItem("Students", studentCount.toString(), Icons.people)),
              Expanded(child: _buildStatItem("Code", cls['class_code'] ?? '-', Icons.tag)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12), textAlign: TextAlign.center),
      ],
    );
  }

  void _showCreateClassDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    int? selectedTeacherId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Create New Class"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Class Name",
                  hintText: "e.g., Computer Science 101",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                decoration: InputDecoration(
                  labelText: "Class Code",
                  hintText: "e.g., CS101",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                value: selectedTeacherId,
                decoration: InputDecoration(
                  labelText: "Assign Teacher",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  ..._teachers.map((t) => DropdownMenuItem<int?>(
                        value: t['id'],
                        child: Text(t['full_name'] ?? t['name'] ?? 'Teacher'),
                      )),
                ],
                onChanged: (value) => setDialogState(() => selectedTeacherId = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FilledButton(
              onPressed: () {
                if (nameController.text.isNotEmpty && codeController.text.isNotEmpty) {
                  Navigator.pop(context);
                  _createClass(nameController.text, codeController.text, selectedTeacherId);
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditClassDialog(BuildContext context, Map<String, dynamic> cls) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nameController = TextEditingController(text: (cls['class_name'] ?? '').toString());
    final codeController = TextEditingController(text: (cls['class_code'] ?? '').toString());
    int? selectedTeacherId = cls['teacher_id'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Edit Class"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Class Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                decoration: InputDecoration(
                  labelText: "Class Code",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                value: selectedTeacherId,
                decoration: InputDecoration(
                  labelText: "Assign Teacher",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  ..._teachers.map((t) => DropdownMenuItem<int?>(
                        value: t['id'],
                        child: Text(t['full_name'] ?? t['name'] ?? 'Teacher'),
                      )),
                ],
                onChanged: (value) => setDialogState(() => selectedTeacherId = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isEmpty || codeController.text.isEmpty) return;
                Navigator.pop(context);

                final result = await ApiService.updateClass(
                  cls['id'],
                  {
                    'class_name': nameController.text,
                    'class_code': codeController.text,
                    'teacher_id': selectedTeacherId,
                  },
                );

                if (!mounted) return;
                if (result['success']) {
                  UIHelpers.showSuccess(context, 'Class updated');
                  _loadClasses();
                } else {
                  UIHelpers.showError(context, result['error'] ?? 'Failed to update class');
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}
