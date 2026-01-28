import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_service.dart';
import '../services/validation_service.dart';
import '../providers/app_providers.dart';
import '../widgets/common_widgets.dart';
import '../utils/ui_helpers.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/biometric_service.dart';
import 'face_capture_screen.dart';
import 'dart:io';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> 
    with SingleTickerProviderStateMixin {
  static const String _biometricLoginKey = 'settings_biometric_login_enabled';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _biometricLoginEnabled = false;
  bool _biometricAvailable = false;
  String _biometricLabel = 'Biometric';
  IconData _biometricIcon = Icons.fingerprint_rounded;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _biometricLoginEnabled = StorageService.getBool(_biometricLoginKey, defaultValue: false);
    if (_biometricLoginEnabled) {
      _initBiometrics();
    }
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    
    _animationController.forward();
  }

  Future<void> _initBiometrics() async {
    final available = await BiometricService.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _biometricAvailable = false;
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final emailError = ValidationService.validateIdentifier(_emailController.text);
    final passwordError = ValidationService.validatePassword(_passwordController.text);
    
    if (emailError != null || passwordError != null) {
      UIHelpers.showError(context, emailError ?? passwordError!);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final result = await ApiService.login(_emailController.text, _passwordController.text);
    
    if (!mounted) return;
    setState(() => _isLoading = false);
    
    if (result['success']) {
      final user = Map<String, dynamic>.from(result['data']['teacher'] ?? {});
      await StorageService.saveString('user_profile', jsonEncode(user));
      ref.read(authProvider.notifier).login(result['data']['access_token'], user);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Login failed');
    }
  }

  Future<void> _handleFaceLogin() async {
    if (_isLoading) return;

    final XFile? photo = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceCaptureScreen(
          title: 'Scan Face',
          subtitle: 'Align your face in the frame and smile',
          resolution: ResolutionPreset.low,
        ),
      ),
    );
    if (photo == null) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    final result = await ApiService.faceLogin(File(photo.path));

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      final data = Map<String, dynamic>.from(result['data'] ?? {});
      final user = Map<String, dynamic>.from(data['teacher'] ?? {});
      final token = data['access_token'];
      if (token != null) {
        ApiService.setToken(token);
        await StorageService.saveToken(token);
        await StorageService.saveString('user_profile', jsonEncode(user));
        ref.read(authProvider.notifier).login(token, user);
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      } else {
        UIHelpers.showError(context, 'Face login failed');
      }
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Face login failed');
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (_isLoading) return;

    if (!_biometricLoginEnabled) {
      UIHelpers.showError(context, 'Biometric login is disabled. Enable it in Settings.');
      return;
    }

    if (!_biometricAvailable) {
      UIHelpers.showError(context, 'Biometric authentication is not available on this device');
      return;
    }

    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) {
      UIHelpers.showError(context, 'No saved session found. Please sign in once with email/password.');
      return;
    }

    final ok = await BiometricService.authenticate(
      reason: 'Authenticate to sign in to FACE MARK',
    );
    if (!ok) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    ApiService.setToken(token);

    final profileResult = await ApiService.getProfile();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (profileResult['success'] == true && profileResult['data'] != null) {
      final user = Map<String, dynamic>.from(profileResult['data']);
      await StorageService.saveString('user_profile', jsonEncode(user));
      ref.read(authProvider.notifier).login(token, user);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
      return;
    }

    await ApiService.logout();
    ref.read(authProvider.notifier).logout();
    UIHelpers.showError(context, 'Session expired. Please sign in again.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ═══════════════════════════════════════════════════════════════════
          // BACKGROUND GRADIENT DECORATION
          // ═══════════════════════════════════════════════════════════════════
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                    ? [
                        AppTheme.primary.withOpacity(0.15),
                        AppTheme.backgroundDark,
                        AppTheme.accent.withOpacity(0.1),
                      ]
                    : [
                        AppTheme.primary.withOpacity(0.08),
                        AppTheme.backgroundLight,
                        AppTheme.accent.withOpacity(0.06),
                      ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          
          // Decorative circles
          Positioned(
            top: -size.height * 0.15,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.6,
              height: size.width * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withOpacity(isDark ? 0.15 : 0.1),
                    AppTheme.primary.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.height * 0.1,
            left: -size.width * 0.15,
            child: Container(
              width: size.width * 0.5,
              height: size.width * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accent.withOpacity(isDark ? 0.15 : 0.08),
                    AppTheme.accent.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // MAIN CONTENT
          // ═══════════════════════════════════════════════════════════════════
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Login Card (now contains logo)
                          _buildLoginCard(context, isDark),
                          
                          const SizedBox(height: 32),
                          
                          // Footer
                          Text(
                            "Face Attendance v2.5.0",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark 
                                ? AppTheme.textTertiaryDark 
                                : AppTheme.textTertiaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    return Column(
      children: [
        // Animated logo container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(
            Icons.face_retouching_natural,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Face Attendance",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Smart attendance management system",
          style: TextStyle(
            fontSize: 15,
            color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark 
          ? AppTheme.surfaceDark.withOpacity(0.8) 
          : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(AppTheme.radius2XL),
        border: Border.all(
          color: isDark 
            ? AppTheme.borderDark.withOpacity(0.3) 
            : AppTheme.borderLight.withOpacity(0.5),
        ),
        boxShadow: isDark ? AppTheme.softShadowDark : AppTheme.softShadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo inside card
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.face_retouching_natural,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Header
          Text(
            "Welcome back",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Sign in to continue",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          
          // Email/ID Field
          _buildInputField(
            controller: _emailController,
            focusNode: _emailFocus,
            label: "Email or Admin ID",
            hint: "Enter your email or ID",
            icon: Icons.alternate_email_rounded,
            isDark: isDark,
            onSubmit: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 18),
          
          // Password Field
          _buildInputField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: "Password",
            hint: "Enter your password",
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            isDark: isDark,
            onSubmit: (_) => _handleLogin(),
            suffix: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword 
                  ? Icons.visibility_outlined 
                  : Icons.visibility_off_outlined,
                color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
                size: 22,
              ),
            ),
          ),
          
          // Forgot password
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
              child: Text(
                "Forgot password?",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Login Button
          _buildLoginButton(context, isDark),
          
          const SizedBox(height: 24),
          
          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: isDark ? AppTheme.borderDark : AppTheme.borderLight)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "or",
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(child: Divider(color: isDark ? AppTheme.borderDark : AppTheme.borderLight)),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Quick Login Methods
          _buildQuickAuthRow(context, isDark),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool obscure = false,
    Widget? suffix,
    Function(String)? onSubmit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          onSubmitted: onSubmit,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(
              icon,
              color: isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight,
              size: 22,
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: isDark 
              ? AppTheme.surfaceSecondaryDark 
              : AppTheme.surfaceSecondaryLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              borderSide: BorderSide(
                color: AppTheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(BuildContext context, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _handleLogin,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _isLoading 
              ? null 
              : AppTheme.primaryGradient,
            color: _isLoading 
              ? (isDark ? AppTheme.surfaceSecondaryDark : AppTheme.surfaceSecondaryLight) 
              : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            boxShadow: _isLoading ? null : [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            child: _isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.login_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Sign In",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAuthRow(BuildContext context, bool isDark) {
    if (!_biometricLoginEnabled) {
      return Row(
        children: [
          Expanded(
            child: _QuickAuthButton(
              label: 'ScanFace',
              icon: Icons.face_retouching_natural,
              isDark: isDark,
              onTap: _handleFaceLogin,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _QuickAuthButton(
            label: 'ScanFace',
            icon: Icons.face_retouching_natural,
            isDark: isDark,
            onTap: _handleFaceLogin,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickAuthButton(
            label: _biometricLabel,
            icon: _biometricIcon,
            isDark: isDark,
            onTap: _biometricAvailable ? _handleBiometricLogin : null,
          ),
        ),
      ],
    );
  }
}

class _QuickAuthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final VoidCallback? onTap;

  const _QuickAuthButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceSecondaryDark : AppTheme.surfaceSecondaryLight,
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            border: Border.all(
              color: disabled
                  ? (isDark ? AppTheme.borderDark.withOpacity(0.5) : AppTheme.borderLight.withOpacity(0.6))
                  : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: disabled
                    ? (isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight)
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? (isDark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight)
                        : (isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
