import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';
import '../../providers/app_providers.dart';

class AdminOrganizationManagementScreen extends ConsumerStatefulWidget {
  const AdminOrganizationManagementScreen({super.key});

  @override
  ConsumerState<AdminOrganizationManagementScreen> createState() => _AdminOrganizationManagementScreenState();
}

class _AdminOrganizationManagementScreenState extends ConsumerState<AdminOrganizationManagementScreen> {
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final role = (ref.read(authProvider).user?['role'] ?? 'teacher').toString();
    if (role == 'admin' || role == 'super_admin') {
      _loadOrganizations();
    }
  }

  Future<void> _loadOrganizations() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getOrganizations();
    if (result['success']) {
      setState(() {
        _organizations = List<Map<String, dynamic>>.from(result['data'] ?? []);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Failed to load organizations'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrganizations {
    if (_searchQuery.trim().isEmpty) return _organizations;
    final query = _searchQuery.toLowerCase();
    return _organizations.where((org) {
      final name = (org['name'] ?? '').toString().toLowerCase();
      final code = (org['code'] ?? '').toString().toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();
  }

  void _showCreateOrganizationDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateOrganizationDialog(
        onSave: () {
          _loadOrganizations();
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _deleteOrganization(Map<String, dynamic> org) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Organization'),
        content: Text('Delete ${org['name']}? This will not delete users automatically.'),
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
      final result = await ApiService.deleteOrganization(org['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['success'] ? 'Organization deleted' : result['error'] ?? 'Delete failed'),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
          ),
        );
        if (result['success']) _loadOrganizations();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final role = (ref.watch(authProvider).user?['role'] ?? 'teacher').toString();
    final isAdmin = role == 'admin' || role == 'super_admin';

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Organizations'),
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
        title: const Text('Organizations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrganizations,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 4)),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search organizations...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrganizations.isEmpty
                    ? Center(
                        child: Text('No organizations found', style: TextStyle(color: Colors.grey[500])),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredOrganizations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final org = _filteredOrganizations[index];
                          final status = (org['status'] ?? 'active').toString();
                          final isActive = status == 'active';

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.apartment, color: isActive ? Colors.green : Colors.grey),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(org['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text('Code: ${org['code'] ?? '-'}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                      const SizedBox(height: 6),
                                      _buildBadge(isActive ? 'ACTIVE' : 'INACTIVE', isActive ? Colors.green : Colors.red),
                                    ],
                                  ),
                                ),
                                PopupMenuButton(
                                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                                  itemBuilder: (context) => <PopupMenuEntry>[
                                    PopupMenuItem(
                                      onTap: () => _deleteOrganization(org),
                                      child: const Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateOrganizationDialog,
        icon: const Icon(Icons.add),
        label: const Text('Create Organization'),
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

class _CreateOrganizationDialog extends StatefulWidget {
  final VoidCallback onSave;

  const _CreateOrganizationDialog({required this.onSave});

  @override
  State<_CreateOrganizationDialog> createState() => _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<_CreateOrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminIdController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String _status = 'active';

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminIdController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final orgData = {
      'name': _nameController.text.trim(),
      'code': _codeController.text.trim(),
      'status': _status,
      'admin_full_name': _adminNameController.text.trim(),
      'admin_email': _adminEmailController.text.trim(),
      'admin_teacher_id': _adminIdController.text.trim(),
      'admin_password': _adminPasswordController.text,
    };

    final result = await ApiService.createOrganization(orgData);
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['success'] ? 'Organization created' : result['error'] ?? 'Create failed'),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
      if (result['success']) widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create Organization', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Organization Name',
                    prefixIcon: Icon(Icons.apartment),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Organization name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Organization Code',
                    hintText: 'ORG001',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Organization code is required' : null,
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
                  onChanged: (value) => setState(() => _status = value ?? 'active'),
                ),
                const SizedBox(height: 20),
                Text('Admin Account', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminNameController,
                  decoration: const InputDecoration(
                    labelText: 'Admin Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Admin name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _adminEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Admin Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value?.isEmpty ?? true) return 'Admin email is required';
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
                      return 'Invalid email format';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _adminIdController,
                  decoration: const InputDecoration(
                    labelText: 'Admin ID',
                    hintText: 'ADM001',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Admin ID is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _adminPasswordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Admin Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) return 'Admin password is required';
                    if (value != null && value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
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
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Create'),
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
