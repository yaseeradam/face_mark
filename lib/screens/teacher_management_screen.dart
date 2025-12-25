import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class TeacherManagementScreen extends ConsumerStatefulWidget {
  const TeacherManagementScreen({super.key});

  @override
  ConsumerState<TeacherManagementScreen> createState() => _TeacherManagementScreenState();
}

class _TeacherManagementScreenState extends ConsumerState<TeacherManagementScreen> {
  List<Map<String, dynamic>> _teachers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final result = await ApiService.getTeachers();
    if (!mounted) return; // Check again after async operation
    
    if (result['success']) {
      setState(() {
        _teachers = List<Map<String, dynamic>>.from(result['data'] ?? []);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      UIHelpers.showError(context, result['error'] ?? 'Failed to load teachers');
    }
  }

  List<Map<String, dynamic>> get _filteredTeachers {
    if (_searchQuery.isEmpty) return _teachers;
    return _teachers.where((teacher) {
      final name = teacher['full_name']?.toString().toLowerCase() ?? '';
      final email = teacher['email']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _deleteTeacher(int teacherId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Teacher'),
        content: const Text('Are you sure you want to delete this teacher?'),
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
      final result = await ApiService.deleteUser(teacherId.toString());
      if (!mounted) return;
      
      if (result['success']) {
        UIHelpers.showSuccess(context, 'Teacher deleted');
        await _loadTeachers();
      } else {
        UIHelpers.showError(context, result['error'] ?? 'Failed to delete');
      }
    }
  }

  Future<void> _toggleStatus(int teacherId, String currentStatus) async {
    final newStatus = currentStatus == 'active' ? 'inactive' : 'active';
    final result = await ApiService.updateUserStatus(teacherId.toString(), newStatus);
    if (!mounted) return;
    
    if (result['success']) {
      UIHelpers.showSuccess(context, 'Status updated');
      await _loadTeachers();
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Failed to update');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            const Text("Teacher Management"),
            Text("${_teachers.length} teachers", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            onPressed: _loadTeachers,
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
                hintText: "Search teachers...",
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          
          // Teacher List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTeachers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.school_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No teachers found', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _showCreateTeacherDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add First Teacher'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTeachers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredTeachers.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _filteredTeachers.length) return const SizedBox(height: 100);
                            return _buildTeacherCard(context, _filteredTeachers[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateTeacherDialog(context),
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildTeacherCard(BuildContext context, Map<String, dynamic> teacher) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isActive = teacher['status'] == 'active';
    final isAdmin = teacher['role'] == 'admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Text(
                  (teacher['full_name'] ?? 'T')[0].toUpperCase(),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green : Colors.grey,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(teacher['full_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAdmin ? Colors.purple.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAdmin ? 'ADMIN' : 'TEACHER',
                        style: TextStyle(color: isAdmin ? Colors.purple : Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(teacher['email'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(teacher['teacher_id'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle',
                child: Text(isActive ? 'Deactivate' : 'Activate'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (value) {
              if (value == 'toggle') _toggleStatus(teacher['id'], teacher['status'] ?? 'active');
              if (value == 'delete') _deleteTeacher(teacher['id']);
            },
          ),
        ],
      ),
    );
  }

  void _showCreateTeacherDialog(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final idController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'teacher';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Add New Teacher"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idController,
                  decoration: InputDecoration(
                    labelText: "Teacher ID",
                    hintText: "e.g., T001",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: "Full Name",
                    hintText: "e.g., Dr. John Smith",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: "Email",
                    hintText: "john.smith@school.com",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: "Password",
                    hintText: "••••••••",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: InputDecoration(
                    labelText: "Role",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A2633) : Colors.white,
                  ),
                  items: const [
                    DropdownMenuItem(value: "teacher", child: Text("Teacher")),
                    DropdownMenuItem(value: "admin", child: Text("Admin")),
                  ],
                  onChanged: (value) => setDialogState(() => role = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty && emailController.text.isNotEmpty && passwordController.text.isNotEmpty) {
                  // Pop dialog first
                  Navigator.pop(context);
                  
                  // Create user with proper error handling
                  final result = await ApiService.createUser({
                    'teacher_id': idController.text,
                    'full_name': nameController.text,
                    'email': emailController.text,
                    'password': passwordController.text,
                    'role': role,
                    'status': 'active',
                  });
                  
                  // Only show snackbar if widget is still mounted
                  if (mounted) {
                    if (result['success']) {
                      UIHelpers.showSuccess(context, 'Teacher added!');
                      await _loadTeachers();
                    } else {
                      UIHelpers.showError(context, result['error'] ?? 'Failed to add teacher');
                    }
                  }
                }
              },
              child: const Text("Add Teacher"),
            ),
          ],
        ),
      ),
    );
  }
}