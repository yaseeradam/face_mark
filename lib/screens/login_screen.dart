import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/validation_service.dart';
import '../providers/app_providers.dart';
import '../widgets/common_widgets.dart';
import '../utils/ui_helpers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final emailError = ValidationService.validateEmail(_emailController.text);
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
      ref.read(authProvider.notifier).login(result['data']['access_token'], result['data']['user'] ?? {});
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } else {
      UIHelpers.showError(context, result['error'] ?? 'Login failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.5,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Nav
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Center(
                    child: Text(
                      "Admin Portal",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 400),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Logo/Header
                            Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.face_6,
                                  size: 32,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Welcome Back",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Sign in to manage attendance",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 32),
                            // Inputs
                            Text("Admin ID or Email", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.mail_outline),
                                hintText: "admin@company.com",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF101922) : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Password", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text("Forgot Password?"),
                                ),
                              ],
                            ),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                hintText: "••••••••",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF101922) : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () async {
                                setState(() => _isLoading = true);
                                final result = await ApiService.testConnectivity();
                                setState(() => _isLoading = false);

                                if (result['success']) {
                                  UIHelpers.showSuccess(context, 'Server is reachable');
                                } else {
                                  UIHelpers.showError(context, 'Server test failed: ${result['error']}');
                                }
                              },
                              child: const Text("Test Server Connection"),
                            ),
                            const SizedBox(height: 16),
                            // Login Button
                            LoadingButton(
                              text: "Log In",
                              onPressed: _handleLogin,
                              isLoading: _isLoading,
                              icon: Icons.login,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[200])),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text("Or continue with", style: theme.textTheme.bodySmall),
                                ),
                                Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[200])),
                              ],
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: Icon(Icons.face, color: theme.colorScheme.primary),
                              label: Text("Login with Face ID", style: TextStyle(color: theme.colorScheme.onSurface)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text("Version 2.4.0 (Build 302)", style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
