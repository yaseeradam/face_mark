import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _floatAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  
  String _loadingText = "Initializing...";
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    
    // Floating animation for logo
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    
    // Pulse animation for glow effect
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Fade in animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    
    _fadeController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _loadingText = "Loading storage...";
        _progress = 0.2;
      });
      await StorageService.initialize();
      
      setState(() {
        _loadingText = "Checking authentication...";
        _progress = 0.5;
      });
      final token = await StorageService.getToken();
      
      setState(() {
        _loadingText = "Loading preferences...";
        _progress = 0.8;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      
      setState(() {
        _loadingText = "Ready!";
        _progress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 400));
      
      if (mounted) {
        if (token != null) {
          ApiService.setToken(token);
          final cachedProfile = StorageService.getString('user_profile');
          Map<String, dynamic> user = {};
          if (cachedProfile != null && cachedProfile.isNotEmpty) {
            try {
              user = Map<String, dynamic>.from(jsonDecode(cachedProfile));
            } catch (_) {}
          }

          final profileResult = await ApiService.getProfile();
          if (profileResult['success'] && profileResult['data'] != null) {
            user = Map<String, dynamic>.from(profileResult['data']);
            await StorageService.saveString('user_profile', jsonEncode(user));
          }

          ref.read(authProvider.notifier).login(token, user);
          Navigator.pushReplacementNamed(context, '/dashboard');
        } else {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      setState(() => _loadingText = "Error loading app");
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
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
          // GRADIENT BACKGROUND
          // ═══════════════════════════════════════════════════════════════════
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF0F172A),
                        const Color(0xFF1E1B4B),
                        const Color(0xFF0F172A),
                      ]
                    : [
                        const Color(0xFFF8FAFC),
                        const Color(0xFFEEF2FF),
                        const Color(0xFFF5F3FF),
                      ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // DECORATIVE ELEMENTS
          // ═══════════════════════════════════════════════════════════════════
          
          // Top-left glow
          Positioned(
            top: -size.height * 0.15,
            left: -size.width * 0.2,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: size.width * 0.7,
                  height: size.width * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.primary.withOpacity(_pulseAnimation.value * 0.3),
                        AppTheme.primary.withOpacity(0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Bottom-right glow
          Positioned(
            bottom: -size.height * 0.1,
            right: -size.width * 0.15,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: size.width * 0.6,
                  height: size.width * 0.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.accent.withOpacity(_pulseAnimation.value * 0.25),
                        AppTheme.accent.withOpacity(0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Floating particles/dots effect
          ...List.generate(6, (index) {
            final positions = [
              Offset(size.width * 0.1, size.height * 0.2),
              Offset(size.width * 0.85, size.height * 0.15),
              Offset(size.width * 0.15, size.height * 0.75),
              Offset(size.width * 0.9, size.height * 0.65),
              Offset(size.width * 0.5, size.height * 0.1),
              Offset(size.width * 0.7, size.height * 0.85),
            ];
            final sizes = [8.0, 6.0, 10.0, 5.0, 7.0, 9.0];
            
            return Positioned(
              left: positions[index].dx,
              top: positions[index].dy,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.3 + (_pulseAnimation.value * 0.3),
                    child: Container(
                      width: sizes[index],
                      height: sizes[index],
                      decoration: BoxDecoration(
                        color: index.isEven ? AppTheme.primary : AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            );
          }),

          // ═══════════════════════════════════════════════════════════════════
          // MAIN CONTENT
          // ═══════════════════════════════════════════════════════════════════
          FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  AnimatedBuilder(
                    animation: _floatAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -_floatAnimation.value),
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.4),
                                blurRadius: 40,
                                offset: const Offset(0, 16),
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Gradient overlay
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withOpacity(0.2),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                // Logo image or fallback icon
                                Image.asset(
                                  'lib/public/android-chrome-192x192.png',
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.face_retouching_natural,
                                      size: 64,
                                      color: Colors.white,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // App Name
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        AppTheme.primary,
                        AppTheme.accent,
                      ],
                    ).createShader(bounds),
                    child: Text(
                      "FACE ATTENDANCE",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Tagline
                  Text(
                    "Smart attendance made simple",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  
                  const SizedBox(height: 64),
                  
                  // Progress Section
                  SizedBox(
                    width: 240,
                    child: Column(
                      children: [
                        // Animated Progress Bar
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.08),
                          ),
                          child: Stack(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                width: 240 * _progress,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: AppTheme.primaryGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withOpacity(0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Loading Text
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _loadingText,
                            key: ValueKey(_loadingText),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppTheme.textTertiaryDark
                                  : AppTheme.textTertiaryLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // FOOTER
          // ═══════════════════════════════════════════════════════════════════
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  Text(
                    "Powered by AI",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppTheme.textTertiaryDark
                          : AppTheme.textTertiaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "v2.5.0",
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.textTertiaryDark.withOpacity(0.7)
                          : AppTheme.textTertiaryLight.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
