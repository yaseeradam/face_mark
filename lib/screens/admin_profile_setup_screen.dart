import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:camera/camera.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import 'face_capture_screen.dart';

class AdminProfileSetupScreen extends ConsumerStatefulWidget {
  const AdminProfileSetupScreen({super.key});

  @override
  ConsumerState<AdminProfileSetupScreen> createState() => _AdminProfileSetupScreenState();
}

class _AdminProfileSetupScreenState extends ConsumerState<AdminProfileSetupScreen> {
  Map<String, dynamic> _profile = {};
  bool _isLoading = true;
  bool _isSettingUpFaceId = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final result = await ApiService.getProfile();
    if (result['success']) {
      if (mounted) {
        setState(() {
          _profile = result['data'] ?? {};
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              decoration: const InputDecoration(labelText: 'Current Password'),
              obscureText: true,
            ),
            TextField(
              controller: newController,
              decoration: const InputDecoration(labelText: 'New Password'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              final result = await ApiService.changePassword(
                currentController.text, 
                newController.text
              );
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['success'] ? 'Password changed successfully' : result['error'] ?? 'Failed'),
                    backgroundColor: result['success'] ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _setupFaceId() async {
    if (_isSettingUpFaceId) return;

    final XFile? photo = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceCaptureScreen(
          title: 'Set Up Face ID',
          subtitle: 'Align your face in the frame and smile',
          resolution: ResolutionPreset.medium,
        ),
      ),
    );
    if (photo == null) return;

    if (!mounted) return;
    setState(() => _isSettingUpFaceId = true);
    final result = await ApiService.setupFaceId(File(photo.path));
    if (!mounted) return;
    setState(() => _isSettingUpFaceId = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['success'] ? 'Face ID setup successful!' : (result['error'] ?? 'Failed to setup Face ID')),
        backgroundColor: result['success'] ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _logout() async {
    await ApiService.logout();
    ref.read(authProvider.notifier).logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String name = _profile['full_name'] ?? 'Admin User';
    final String email = _profile['email'] ?? 'admin@school.com';
    final String role = (_profile['role'] ?? 'Administrator').toString().toUpperCase();

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
         leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text("Profile & Setup"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // Header
          Container(
            color: theme.cardColor,
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.scaffoldBackgroundColor, width: 4),
                        color: theme.colorScheme.primaryContainer,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'A',
                          style: TextStyle(
                            fontSize: 40, 
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: theme.cardColor, width: 2)),
                        child: const Icon(Icons.edit, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(role, style: theme.textTheme.bodyMedium),
                Text(email, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, "Security & Access"),
                // Face ID Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.face, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text("Face ID Access", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Secure your account with biometric login for faster, safer access.",
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _isSettingUpFaceId ? null : _setupFaceId,
                              icon: const Icon(Icons.add_circle_outline, size: 16),
                              label: Text(_isSettingUpFaceId ? "Setting up..." : "Set up Face ID"),
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                _buildListItem(context, "Change Password", "Update your security credentials", Icons.lock, onTap: _changePassword),
                _buildListItem(context, "Two-Factor Auth", "Enabled via Authenticator App", Icons.shield),
                
                const SizedBox(height: 24),
                _buildHeader(context, "General"),
                _buildListItem(context, "Personal Information", null, Icons.person),
                _buildListItem(context, "Organization Details", null, Icons.domain),
                
                // Notifications Switch
                 Container(
                   margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.notifications, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Push Notifications", style: TextStyle(fontWeight: FontWeight.w600)),
                            Text("Alerts for attendance logs", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Switch(value: true, onChanged: (v) {}, activeThumbColor: theme.colorScheme.primary),
                    ],
                  ),
                 ),

                const SizedBox(height: 24),
                _buildHeader(context, "System"),
                _buildListItem(context, "Device Management", "Manage linked face scanners", Icons.settings_system_daydream),
                
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text("Log Out", style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.red.withOpacity(0.3)),
                    backgroundColor: Colors.red.withOpacity(0.05),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                 Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text("Version 1.0.4 (Build 220)", style: theme.textTheme.bodySmall),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildListItem(BuildContext context, String title, String? subtitle, IconData icon, {VoidCallback? onTap}) {
     final theme = Theme.of(context);
     final isDark = theme.brightness == Brightness.dark;
     
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
        tileColor: theme.cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: isDark ? Colors.grey[700] : Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: isDark ? Colors.grey[300] : Colors.grey[600]),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap ?? () {},
      ),
    );
  }
}
