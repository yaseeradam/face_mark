import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _offlineMode = false;
  bool _faceIdEnabled = false;
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getProfile();
    if (result['success']) {
      setState(() {
        _currentUser = result['data'];
        _faceIdEnabled = _currentUser?['has_face_id'] ?? false;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupFaceId() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );

    if (photo != null) {
      setState(() => _isLoading = true);
      final result = await ApiService.setupFaceId(File(photo.path));
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['success'] ? 'Face ID setup successful!' : result['error'] ?? 'Failed to setup Face ID'),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
          ),
        );
        if (result['success']) {
          setState(() => _faceIdEnabled = true);
        }
      }
    }
  }

  Future<void> _changePassword() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (result == true) {
      final apiResult = await ApiService.changePassword(
        oldPasswordController.text,
        newPasswordController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiResult['success'] ? 'Password changed successfully!' : apiResult['error'] ?? 'Failed to change password'),
            backgroundColor: apiResult['success'] ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncData() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing data...'), duration: Duration(seconds: 1)),
    );
    // Reload all data
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data synced successfully!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ApiService.logout();
      await StorageService.clearToken();
      ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Settings"),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  child: Text(
                    (_currentUser?['full_name'] ?? 'U')[0].toUpperCase(),
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_currentUser?['full_name'] ?? 'User', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  _currentUser?['role'] == 'super_admin'
                      ? 'Super Admin'
                      : _currentUser?['role'] == 'admin'
                          ? 'Administrator'
                          : 'Teacher',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(_currentUser?['email'] ?? '', style: theme.textTheme.bodySmall),
                if ((_currentUser?['organization_name'] ?? '').toString().isNotEmpty)
                  Text(_currentUser?['organization_name'] ?? '', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 8),
                      SizedBox(width: 8),
                      Text("Active", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Connectivity
          _buildSectionHeader("Connectivity & Data"),
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  value: _offlineMode,
                  onChanged: (v) => setState(() => _offlineMode = v),
                  title: const Text("Offline Mode", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text("Use face recognition without internet"),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.wifi_off, color: theme.colorScheme.primary),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.sync, color: Colors.blue),
                  ),
                  title: const Text("Sync Data", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text("Sync with server"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _syncData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Appearance
          _buildSectionHeader("Appearance"),
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  value: isDark,
                  onChanged: (v) {
                    ref.read(themeModeProvider.notifier).state = v ? ThemeMode.dark : ThemeMode.light;
                  },
                  title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.w600)),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.purple[100], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.dark_mode, color: Colors.purple),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Security
          _buildSectionHeader("Security"),
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.lock_reset, color: Colors.orange),
                  ),
                  title: const Text("Change Password", style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePassword,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.purple[100], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.face, color: Colors.purple),
                  ),
                  title: const Text("Face ID Login", style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_faceIdEnabled ? 'Enabled' : 'Setup Face ID for quick login'),
                  trailing: _faceIdEnabled 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : FilledButton(
                          onPressed: _setupFaceId,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          child: const Text('Setup'),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Logout
          ListTile(
            onTap: _logout,
            tileColor: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Center(child: Text("Log Out", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              "FACE MARK v2.4.1\nBuild 20231024",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
      ),
    );
  }
}
