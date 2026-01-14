import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AdminUserManagementScreen extends ConsumerStatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  ConsumerState<AdminUserManagementScreen> createState() => _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends ConsumerState<AdminUserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  Set<int> _selectedUserIds = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterRole = 'all';
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getUsers();
    if (result['success']) {
      setState(() {
        _users = List<Map<String, dynamic>>.from(result['data'] ?? []);
        _isLoading = false;
        _selectedUserIds.clear();
        _selectAll = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Failed to load users'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((user) {
      final matchesSearch = user['full_name']?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false ||
          user['email']?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
      final matchesRole = _filterRole == 'all' || user['role'] == _filterRole;
      return matchesSearch && matchesRole;
    }).toList();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectAll) {
        _selectedUserIds.clear();
      } else {
        _selectedUserIds = _filteredUsers.map((user) => user['id'] as int).toSet();
      }
      _selectAll = !_selectAll;
    });
  }

  void _toggleUserSelection(int userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
      _selectAll = _selectedUserIds.length == _filteredUsers.length;
    });
  }

  Future<void> _bulkDeleteUsers() async {
    if (_selectedUserIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Multiple Users'),
        content: Text('Are you sure you want to delete ${_selectedUserIds.length} user(s)? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await ApiService.bulkDeleteUsers(_selectedUserIds.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['success'] ? result['message'] ?? 'Users deleted successfully' : result['error'] ?? 'Failed to delete users'),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
          ),
        );
        if (result['success']) {
          _loadUsers();
        }
      }
    }
  }

  Future<void> _exportToCSV() async {
    try {
      // Request storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission required'), backgroundColor: Colors.red),
            );
          }
          return;
        }
      }

      // Download CSV
      final result = await ApiService.exportUsersToCSV();
      
      if (result['success'] && result['data'] != null) {
        final csvContent = result['data'] as String;
        
        // Save to Downloads folder
        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${directory.path}/teachers_export_$timestamp.csv');
        await file.writeAsString(csvContent);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('CSV exported to: ${file.path}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Failed to export CSV'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddEditUserDialog(
        onSave: () {
          _loadUsers();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => _AddEditUserDialog(
        user: user,
        onSave: () {
          _loadUsers();
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _deleteUser(String userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete $userName? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await ApiService.deleteUser(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['success'] ? 'User deleted successfully' : result['error'] ?? 'Failed to delete user'),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
          ),
        );
        if (result['success']) _loadUsers();
      }
    }
  }

  Future<void> _toggleUserStatus(String userId, String currentStatus) async {
    final newStatus = currentStatus == 'active' ? 'inactive' : 'active';
    final result = await ApiService.updateUserStatus(userId, newStatus);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['success'] ? 'User status updated' : result['error'] ?? 'Failed to update status'),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
      if (result['success']) _loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          if (_selectedUserIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _bulkDeleteUsers,
              tooltip: 'Delete Selected (${_selectedUserIds.length})',
            ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToCSV,
            tooltip: 'Export to CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                 BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        ),
                        onChanged: (value) => setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                        value: _filterRole,
                        icon: const Icon(Icons.filter_list, size: 20),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'admin', child: Text('Admins')),
                          DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
                        ],
                        onChanged: (value) => setState(() => _filterRole = value!),
                      ),
                      ),
                    ),
                  ],
                ),
                if (_filteredUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _selectAll,
                            onChanged: (value) => _toggleSelectAll(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Select All (${_filteredUsers.length})', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (_selectedUserIds.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              '${_selectedUserIds.length} Selected',
                              style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // User List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUsers,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('No users found', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredUsers.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final userId = user['id'] as int;
                          final isSelected = _selectedUserIds.contains(userId);
                          
                          return _UserCard(
                            user: user,
                            isSelected: isSelected,
                            onToggleSelection: () => _toggleUserSelection(userId),
                            onEdit: () => _showEditUserDialog(user),
                            onDelete: () => _deleteUser(user['id'].toString(), user['full_name'] ?? ''),
                            onToggleStatus: () => _toggleUserStatus(user['id'].toString(), user['status'] ?? 'active'),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add User'),
        elevation: 4,
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleStatus;

  const _UserCard({
    required this.user,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = user['status'] == 'active';
    final role = (user['role'] ?? 'teacher').toString().toUpperCase();
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onLongPress: onToggleSelection,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.2) : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isSelected 
              ? Border.all(color: theme.colorScheme.primary) 
              : Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
          boxShadow: isSelected ? [] : [
             BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              Container(
                 width: 48,
                 height: 48,
                 decoration: BoxDecoration(
                    color: isActive ? theme.colorScheme.primary.withOpacity(0.1) : Colors.grey[200],
                    shape: BoxShape.circle,
                 ),
                 child: Center(
                    child: Text(
                      (user['full_name'] ?? 'U')[0].toUpperCase(),
                       style: TextStyle(
                          color: isActive ? theme.colorScheme.primary : Colors.grey, 
                          fontWeight: FontWeight.bold,
                          fontSize: 20
                       ),
                    ),
                 ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['full_name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                       user['email'] ?? 'No Email',
                       style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    if ((user['organization_name'] ?? user['organization_id']) != null)
                      Text(
                        'Org: ${user['organization_name'] ?? user['organization_id']}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    const SizedBox(height: 6),
                    Row(
                       children: [
                          _buildBadge(role, role == 'ADMIN' ? Colors.purple : Colors.blue),
                          const SizedBox(width: 8),
                          _buildBadge(isActive ? 'ACTIVE' : 'INACTIVE', isActive ? Colors.green : Colors.red),
                       ],
                    )
                  ],
                ),
              ),
              // Actions
              if (isSelected)
                 Checkbox(value: true, onChanged: (v) => onToggleSelection())
              else
                 PopupMenuButton(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    itemBuilder: (context) => <PopupMenuEntry>[
                       PopupMenuItem(
                          onTap: onEdit,
                          child: const Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')]),
                       ),
                       PopupMenuItem(
                          onTap: onToggleStatus,
                          child: Row(children: [Icon(isActive ? Icons.block : Icons.check_circle, size: 18), const SizedBox(width: 8), Text(isActive ? 'Deactivate' : 'Activate')]),
                       ),
                       const PopupMenuDivider(),
                       PopupMenuItem(
                          onTap: onDelete,
                          child: const Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))]),
                       ),
                    ],
                 )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
     return Container(
       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
       decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
       ),
       child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
     );
  }
}

// Keep the existing _AddEditUserDialog class unchanged
class _AddEditUserDialog extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback onSave;

  const _AddEditUserDialog({this.user, required this.onSave});

  @override
  State<_AddEditUserDialog> createState() => _AddEditUserDialogState();
}

class _AddEditUserDialogState extends State<_AddEditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _userIdController;
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  String _role = 'teacher';
  String _status = 'active';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _userIdController = TextEditingController(text: widget.user?['user_id'] ?? '');
    _fullNameController = TextEditingController(text: widget.user?['full_name'] ?? '');
    _emailController = TextEditingController(text: widget.user?['email'] ?? '');
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _role = widget.user?['role'] ?? 'teacher';
    _status = widget.user?['status'] ?? 'active';
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final userData = {
      'teacher_id': _userIdController.text,
      'full_name': _fullNameController.text,
      'email': _emailController.text,
      'role': _role,
      'status': _status,
    };

    if (_passwordController.text.isNotEmpty) {
      userData['password'] = _passwordController.text;
    }

    final String endpoint = '/teachers/';
    final result = widget.user == null
        ? await ApiService.createUser(userData)
        : await ApiService.updateUser(widget.user!['id'].toString(), userData);

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['success']
              ? widget.user == null
                  ? 'User created successfully'
                  : 'User updated successfully'
              : result['error'] ?? 'Operation failed'),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
      if (result['success']) widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.user != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEdit ? 'Edit User' : 'Add New User',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _userIdController,
                  decoration: const InputDecoration(
                    labelText: 'User ID',
                    hintText: 'e.g., TCH001',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'User ID is required' : null,
                  enabled: !isEdit,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'John Doe',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Full name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'john@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value?.isEmpty ?? true) return 'Email is required';
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
                      return 'Invalid email format';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: isEdit ? 'New Password (leave blank to keep current)' : 'Password',
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (!isEdit && (value?.isEmpty ?? true)) return 'Password is required';
                    if (value != null && value.isNotEmpty && value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (_passwordController.text.isNotEmpty && value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) => setState(() => _role = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    prefixIcon: Icon(Icons.toggle_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (value) => setState(() => _status = value!),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isEdit ? 'Update User' : 'Create User'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
