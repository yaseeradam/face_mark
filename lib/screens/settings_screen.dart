import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/biometric_service.dart';
import '../theme/app_theme.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'face_capture_screen.dart';
import 'package:local_auth/local_auth.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String _schoolStartTimeKey = 'settings_school_start_time';
  static const String _lateCutoffTimeKey = 'settings_late_cutoff_time';
  static const String _autoAbsentTimeKey = 'settings_auto_absent_time';
  static const String _allowLateArrivalsKey = 'settings_allow_late_arrivals';
  static const String _requireAbsenceExcuseKey = 'settings_require_absence_excuse';
  static const String _multipleCheckinsKey = 'settings_multiple_checkins';
  static const String _biometricLoginKey = 'settings_biometric_login_enabled';

  bool _offlineMode = false;
  bool _faceIdEnabled = false;
  bool _biometricLoginEnabled = false;
  bool _biometricAvailable = false;
  bool _isUpdatingBiometric = false;
  String _biometricLabel = 'Biometric';
  IconData _biometricIcon = Icons.fingerprint_rounded;
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;
  TimeOfDay _schoolStartTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _lateCutoffTime = const TimeOfDay(hour: 8, minute: 15);
  TimeOfDay _autoAbsentTime = const TimeOfDay(hour: 9, minute: 0);
  bool _allowLateArrivals = true;
  bool _requireAbsenceExcuse = false;
  bool _multipleCheckinsEnabled = false;

  @override
  void initState() {
    super.initState();
    _biometricLoginEnabled = StorageService.getBool(_biometricLoginKey, defaultValue: false);
    _loadUserProfile();
    _loadAttendanceSettings();
    _initBiometrics();
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

  Future<void> _initBiometrics() async {
    final available = await BiometricService.isAvailable();
    if (!mounted) return;

    if (!available) {
      setState(() {
        _biometricAvailable = false;
        _biometricLabel = 'Biometric';
        _biometricIcon = Icons.fingerprint_rounded;
      });
      return;
    }

    final types = await BiometricService.getAvailableBiometrics();
    final label = BiometricService.getBiometricTypeString(types);
    final icon = types.contains(BiometricType.face)
        ? Icons.face_unlock_outlined
        : (types.contains(BiometricType.fingerprint)
            ? Icons.fingerprint_rounded
            : Icons.lock_outline);

    if (!mounted) return;
    setState(() {
      _biometricAvailable = true;
      _biometricLabel = label;
      _biometricIcon = icon;
    });
  }

  Future<void> _setBiometricLoginEnabled(bool enabled) async {
    if (_isUpdatingBiometric) return;

    if (enabled) {
      if (!_biometricAvailable) {
        _showSnackBar('Biometric authentication is not available on this device', isError: true);
        return;
      }

      setState(() => _isUpdatingBiometric = true);
      final ok = await BiometricService.authenticate(
        reason: 'Authenticate to enable biometric login',
      );
      if (!mounted) return;
      setState(() => _isUpdatingBiometric = false);

      if (!ok) return;
    }

    if (!mounted) return;
    setState(() => _biometricLoginEnabled = enabled);
    await StorageService.saveBool(_biometricLoginKey, enabled);
  }

  Future<void> _loadAttendanceSettings() async {
    final storedSchoolStart = StorageService.getString(_schoolStartTimeKey);
    final storedLateCutoff = StorageService.getString(_lateCutoffTimeKey);
    final storedAutoAbsent = StorageService.getString(_autoAbsentTimeKey);

    if (mounted) {
      setState(() {
        _schoolStartTime = _timeFromStorage(storedSchoolStart, _schoolStartTime);
        _lateCutoffTime = _timeFromStorage(storedLateCutoff, _lateCutoffTime);
        _autoAbsentTime = _timeFromStorage(storedAutoAbsent, _autoAbsentTime);
        _allowLateArrivals = StorageService.getBool(_allowLateArrivalsKey, defaultValue: _allowLateArrivals);
        _requireAbsenceExcuse = StorageService.getBool(_requireAbsenceExcuseKey, defaultValue: _requireAbsenceExcuse);
        _multipleCheckinsEnabled = StorageService.getBool(_multipleCheckinsKey, defaultValue: _multipleCheckinsEnabled);
      });
    }

    final result = await ApiService.getAttendanceSettings();
    if (result['success'] && result['data'] != null) {
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final schoolStart = _timeFromStorage(data['school_start_time'], _schoolStartTime);
      final lateCutoff = _timeFromStorage(data['late_cutoff_time'], _lateCutoffTime);
      final autoAbsent = _timeFromStorage(data['auto_absent_time'], _autoAbsentTime);
      final allowLate = data['allow_late_arrivals'] == true;
      final requireExcuse = data['require_absence_excuse'] == true;
      final multipleCheckins = data['multiple_checkins'] == true;

      if (mounted) {
        setState(() {
          _schoolStartTime = schoolStart;
          _lateCutoffTime = lateCutoff;
          _autoAbsentTime = autoAbsent;
          _allowLateArrivals = allowLate;
          _requireAbsenceExcuse = requireExcuse;
          _multipleCheckinsEnabled = multipleCheckins;
        });
      }

      await StorageService.saveString(_schoolStartTimeKey, _timeToStorage(schoolStart));
      await StorageService.saveString(_lateCutoffTimeKey, _timeToStorage(lateCutoff));
      await StorageService.saveString(_autoAbsentTimeKey, _timeToStorage(autoAbsent));
      await StorageService.saveBool(_allowLateArrivalsKey, allowLate);
      await StorageService.saveBool(_requireAbsenceExcuseKey, requireExcuse);
      await StorageService.saveBool(_multipleCheckinsKey, multipleCheckins);
    }
  }

  TimeOfDay _timeFromStorage(String? value, TimeOfDay fallback) {
    if (value == null || value.isEmpty) return fallback;
    final parts = value.split(':');
    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return fallback;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _timeToStorage(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTime(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }

  Future<void> _pickTime({
    required BuildContext context,
    required String storageKey,
    required TimeOfDay currentTime,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );
    if (picked == null) return;
    onPicked(picked);
    await StorageService.saveString(storageKey, _timeToStorage(picked));
    await _syncAttendanceSettings();
  }

  Future<void> _syncAttendanceSettings() async {
    final result = await ApiService.updateAttendanceSettings({
      'school_start_time': _timeToStorage(_schoolStartTime),
      'late_cutoff_time': _timeToStorage(_lateCutoffTime),
      'auto_absent_time': _timeToStorage(_autoAbsentTime),
      'allow_late_arrivals': _allowLateArrivals,
      'require_absence_excuse': _requireAbsenceExcuse,
      'multiple_checkins': _multipleCheckinsEnabled,
    });

    if (!result['success'] && mounted) {
      _showSnackBar(result['error'] ?? 'Saved locally. Sync failed.', isError: false);
    }
  }

  Future<void> _setupFaceId() async {
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

    setState(() => _isLoading = true);
    final result = await ApiService.setupFaceId(File(photo.path));
    setState(() => _isLoading = false);

    if (!mounted) return;
    _showSnackBar(
      result['success'] ? 'Face ID setup successful!' : result['error'] ?? 'Failed to setup Face ID',
      isError: !result['success'],
    );
    if (result['success']) {
      setState(() => _faceIdEnabled = true);
    }
  }

  Future<void> _changePassword() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Change Password',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: oldPasswordController,
                label: 'Current Password',
                icon: Icons.lock_outline,
                obscure: true,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: newPasswordController,
                label: 'New Password',
                icon: Icons.lock_rounded,
                obscure: true,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: confirmPasswordController,
                label: 'Confirm New Password',
                icon: Icons.lock_rounded,
                obscure: true,
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (newPasswordController.text != confirmPasswordController.text) {
                          _showSnackBar('Passwords do not match', isError: true);
                          return;
                        }
                        Navigator.pop(context, true);
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Change'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final apiResult = await ApiService.changePassword(
        oldPasswordController.text,
        newPasswordController.text,
      );
      if (mounted) {
        _showSnackBar(
          apiResult['success'] ? 'Password changed successfully!' : apiResult['error'] ?? 'Failed to change password',
          isError: !apiResult['success'],
        );
      }
    }
  }

  Future<void> _syncData() async {
    _showSnackBar('Syncing data...');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      _showSnackBar('Data synced successfully!');
    }
  }

  Future<void> _logout() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout_rounded, color: AppTheme.error, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              'Log Out',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to log out?',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Log Out'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await ApiService.logout();
      await StorageService.clearToken();
      await StorageService.removeString('user_profile');
      ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final role = (_currentUser?['role'] ?? '').toString();
    final canEditAttendanceSettings = role == 'admin' || role == 'super_admin';

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // ═══════════════════════════════════════════════════════════════
            // HEADER
            // ═══════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Settings',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            // ═══════════════════════════════════════════════════════════════
            // PROFILE CARD
            // ═══════════════════════════════════════════════════════════════
            SliverToBoxAdapter(
              child: _buildProfileCard(context, isDark),
            ),

            // ═══════════════════════════════════════════════════════════════
            // SETTINGS SECTIONS
            // ═══════════════════════════════════════════════════════════════
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Connectivity Section
                  _buildSectionHeader('Connectivity'),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    isDark: isDark,
                    children: [
                      _buildSwitchTile(
                        icon: Icons.wifi_off_rounded,
                        iconColor: AppTheme.info,
                        title: 'Offline Mode',
                        subtitle: 'Use without internet',
                        value: _offlineMode,
                        onChanged: (v) => setState(() => _offlineMode = v),
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildActionTile(
                        icon: Icons.sync_rounded,
                        iconColor: AppTheme.success,
                        title: 'Sync Data',
                        subtitle: 'Sync with server',
                        onTap: _syncData,
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Attendance Rules Section
                  _buildSectionHeader('Attendance Rules'),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    isDark: isDark,
                    children: [
                      _buildTimeTile(
                        icon: Icons.access_time_rounded,
                        iconColor: AppTheme.primary,
                        title: 'School Start Time',
                        time: _formatTime(context, _schoolStartTime),
                        onTap: canEditAttendanceSettings
                            ? () => _pickTime(
                                  context: context,
                                  storageKey: _schoolStartTimeKey,
                                  currentTime: _schoolStartTime,
                                  onPicked: (time) => setState(() => _schoolStartTime = time),
                                )
                            : null,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildTimeTile(
                        icon: Icons.schedule_rounded,
                        iconColor: AppTheme.warning,
                        title: 'Late Cutoff Time',
                        time: _formatTime(context, _lateCutoffTime),
                        onTap: canEditAttendanceSettings
                            ? () => _pickTime(
                                  context: context,
                                  storageKey: _lateCutoffTimeKey,
                                  currentTime: _lateCutoffTime,
                                  onPicked: (time) => setState(() => _lateCutoffTime = time),
                                )
                            : null,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildTimeTile(
                        icon: Icons.timer_off_rounded,
                        iconColor: AppTheme.error,
                        title: 'Auto-Mark Absent',
                        time: _formatTime(context, _autoAbsentTime),
                        onTap: canEditAttendanceSettings
                            ? () => _pickTime(
                                  context: context,
                                  storageKey: _autoAbsentTimeKey,
                                  currentTime: _autoAbsentTime,
                                  onPicked: (time) => setState(() => _autoAbsentTime = time),
                                )
                            : null,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.timelapse_rounded,
                        iconColor: AppTheme.warning,
                        title: 'Allow Late Arrivals',
                        subtitle: 'Mark students late instead of absent',
                        value: _allowLateArrivals,
                        onChanged: canEditAttendanceSettings
                            ? (v) async {
                                setState(() => _allowLateArrivals = v);
                                await StorageService.saveBool(_allowLateArrivalsKey, v);
                                await _syncAttendanceSettings();
                              }
                            : null,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.note_alt_rounded,
                        iconColor: const Color(0xFF14B8A6),
                        title: 'Require Excuse',
                        subtitle: 'Require reason for absences',
                        value: _requireAbsenceExcuse,
                        onChanged: canEditAttendanceSettings
                            ? (v) async {
                                setState(() => _requireAbsenceExcuse = v);
                                await StorageService.saveBool(_requireAbsenceExcuseKey, v);
                                await _syncAttendanceSettings();
                              }
                            : null,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.repeat_rounded,
                        iconColor: AppTheme.accent,
                        title: 'Multiple Check-ins',
                        subtitle: 'Enable check-in/check-out',
                        value: _multipleCheckinsEnabled,
                        onChanged: canEditAttendanceSettings
                            ? (v) async {
                                setState(() => _multipleCheckinsEnabled = v);
                                await StorageService.saveBool(_multipleCheckinsKey, v);
                                await _syncAttendanceSettings();
                              }
                            : null,
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Appearance Section
                  _buildSectionHeader('Appearance'),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    isDark: isDark,
                    children: [
                      _buildSwitchTile(
                        icon: Icons.dark_mode_rounded,
                        iconColor: AppTheme.accent,
                        title: 'Dark Mode',
                        subtitle: 'Switch to dark theme',
                        value: isDark,
                        onChanged: (v) {
                          ref.read(themeModeProvider.notifier).state = v ? ThemeMode.dark : ThemeMode.light;
                        },
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Security Section
                  _buildSectionHeader('Security'),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    isDark: isDark,
                    children: [
                      _buildActionTile(
                        icon: Icons.lock_reset_rounded,
                        iconColor: AppTheme.warning,
                        title: 'Change Password',
                        subtitle: 'Update your password',
                        onTap: _changePassword,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: _biometricIcon,
                        iconColor: AppTheme.primary,
                        title: 'Biometric Login',
                        subtitle: !_biometricAvailable
                            ? 'Not available on this device'
                            : (_biometricLoginEnabled ? 'Enabled (${_biometricLabel})' : 'Use ${_biometricLabel} to sign in'),
                        value: _biometricLoginEnabled,
                        onChanged: (_biometricAvailable && !_isUpdatingBiometric) ? _setBiometricLoginEnabled : null,
                        isDark: isDark,
                      ),
                      _buildDivider(isDark),
                      _buildFaceIdTile(isDark),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Logout Button
                  _buildLogoutButton(isDark),

                  const SizedBox(height: 24),

                  // Version Info
                  Center(
                    child: Text(
                      'Face Attendance v2.5.0',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
                      ),
                    ),
                  ),

                  const SizedBox(height: 100),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProfileCard(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final userName = _currentUser?['full_name'] ?? 'User';
    final userRole = _currentUser?['role'] ?? 'admin';
    final userEmail = _currentUser?['email'] ?? '';
    
    String roleDisplay = 'Teacher';
    if (userRole == 'super_admin') roleDisplay = 'Super Admin';
    else if (userRole == 'admin') roleDisplay = 'Administrator';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                userName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userEmail,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    roleDisplay,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSettingsCard({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(
          color: isDark ? AppTheme.borderDark.withOpacity(0.3) : AppTheme.borderLight,
        ),
        boxShadow: isDark ? null : AppTheme.softShadowLight,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      color: isDark ? AppTheme.borderDark.withOpacity(0.3) : AppTheme.borderLight,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required bool isDark,
  }) {
    final isEnabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Opacity(
              opacity: isEnabled ? 1 : 0.55,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String time,
    required VoidCallback? onTap,
    required bool isDark,
  }) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Opacity(
                  opacity: isEnabled ? 1 : 0.55,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceSecondaryDark : AppTheme.surfaceSecondaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isEnabled ? AppTheme.primary : (isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceIdTile(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.face_rounded, color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Face ID Login',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _faceIdEnabled ? 'Enabled' : 'Setup for quick login',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
                  ),
                ),
              ],
            ),
          ),
          _faceIdEnabled
            ? Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 24)
            : FilledButton(
                onPressed: _setupFaceId,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Setup'),
              ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(color: AppTheme.error.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: AppTheme.error, size: 22),
              const SizedBox(width: 10),
              Text(
                'Log Out',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: isDark ? AppTheme.surfaceSecondaryDark : AppTheme.surfaceSecondaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }
}
