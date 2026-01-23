import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
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
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _rotateController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _waveAnimation;
  
  String _loadingText = "Initializing...";
  double _progress = 0.0;

  // Theme colors matching AppTheme
  static const Color _primary = Color(0xFF10B981);       // Emerald-500
  static const Color _primaryLight = Color(0xFF34D399); // Emerald-400
  static const Color _primaryDark = Color(0xFF059669);  // Emerald-600
  static const Color _accent = Color(0xFF22C55E);        // Green-500
  static const Color _backgroundDark = Color(0xFF0F172A);     // Slate-900
  static const Color _surfaceDark = Color(0xFF1E293B);        // Slate-800
  static const Color _textPrimary = Color(0xFFF8FAFC);    // Slate-50
  static const Color _textSecondary = Color(0xFF94A3B8);  // Slate-400

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for glow effects
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Fade in animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    
    // Rotate animation for ring
    _rotateController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();
    _rotateAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_rotateController);
    
    // Wave animation for background
    _waveController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
    _waveAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_waveController);
    
    _fadeController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _loadingText = "Loading modules...";
        _progress = 0.2;
      });
      await StorageService.initialize();
      
      setState(() {
        _loadingText = "Verifying credentials...";
        _progress = 0.5;
      });
      final token = await StorageService.getToken();
      
      setState(() {
        _loadingText = "Configuring interface...";
        _progress = 0.8;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      
      setState(() {
        _loadingText = "Ready";
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
      setState(() => _loadingText = "Connection failed");
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _rotateController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _backgroundDark,
      body: Stack(
        children: [
          // ═══════════════════════════════════════════════════════════════════
          // SUBTLE GRADIENT BACKGROUND
          // ═══════════════════════════════════════════════════════════════════
          AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: size,
                painter: SoftGradientPainter(
                  animation: _waveAnimation.value,
                  primaryColor: _primary,
                  accentColor: _accent,
                ),
              );
            },
          ),

          // ═══════════════════════════════════════════════════════════════════
          // FLOATING PARTICLES
          // ═══════════════════════════════════════════════════════════════════
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: size,
                painter: FloatingParticlesPainter(
                  animation: _pulseAnimation.value,
                  color: _primaryLight,
                ),
              );
            },
          ),

          // ═══════════════════════════════════════════════════════════════════
          // MAIN CONTENT
          // ═══════════════════════════════════════════════════════════════════
          FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Circular Ring with Logo
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer rotating ring
                        AnimatedBuilder(
                          animation: _rotateAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _rotateAnimation.value,
                              child: AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return CustomPaint(
                                    size: const Size(200, 200),
                                    painter: ModernRingPainter(
                                      progress: _pulseAnimation.value,
                                      primaryColor: _primary,
                                      secondaryColor: _primaryLight,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                        // Inner glowing circle with logo
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    _surfaceDark,
                                    _backgroundDark,
                                  ],
                                  stops: const [0.5, 1.0],
                                ),
                                border: Border.all(
                                  color: _primary.withOpacity(0.4 + _pulseAnimation.value * 0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primary.withOpacity(0.25 * _pulseAnimation.value),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: _primaryLight.withOpacity(0.15 * _pulseAnimation.value),
                                    blurRadius: 50,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'lib/public/android-chrome-192x192.png',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return ShaderMask(
                                      shaderCallback: (bounds) => LinearGradient(
                                        colors: [_primary, _primaryLight],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ).createShader(bounds),
                                      child: const Icon(
                                        Icons.face_retouching_natural,
                                        size: 56,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // App Name with gradient
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [_primary, _primaryLight, _accent],
                      stops: const [0.0, 0.5, 1.0],
                    ).createShader(bounds),
                    child: const Text(
                      "Face Attendance",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Tagline
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _primary.withOpacity(0.3),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      "Biometric Recognition System",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 56),
                  
                  // Modern Loader Section
                  Column(
                    children: [
                      // Animated Dots Loader
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(3, (index) {
                              final delay = index * 0.2;
                              final animValue = ((_pulseAnimation.value + delay) % 1.0);
                              final scale = 0.6 + (math.sin(animValue * math.pi) * 0.4);
                              final opacity = 0.4 + (math.sin(animValue * math.pi) * 0.6);
                              
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                child: Transform.scale(
                                  scale: scale,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: _primary.withOpacity(opacity),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: _primary.withOpacity(opacity * 0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 28),
                      
                      // Loading Text with fade animation
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _loadingText,
                          key: ValueKey(_loadingText),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Subtle progress indicator
                      if (_progress < 1.0)
                        SizedBox(
                          width: 120,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _progress,
                              backgroundColor: _surfaceDark,
                              valueColor: AlwaysStoppedAnimation<Color>(_primary.withOpacity(0.7)),
                              minHeight: 3,
                            ),
                          ),
                        )
                      else
                        // Checkmark when complete
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _primary.withOpacity(0.15),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primary.withOpacity(_pulseAnimation.value * 0.3),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                color: _primary,
                                size: 20,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // FOOTER
          // ═══════════════════════════════════════════════════════════════════
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, _primary.withOpacity(0.4)],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        "Powered by AI",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _textSecondary.withOpacity(0.7),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 40,
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_primary.withOpacity(0.4), Colors.transparent],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "v2.5.0",
                    style: TextStyle(
                      fontSize: 11,
                      color: _textSecondary.withOpacity(0.5),
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

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class SoftGradientPainter extends CustomPainter {
  final double animation;
  final Color primaryColor;
  final Color accentColor;

  SoftGradientPainter({
    required this.animation,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Top-right gradient orb
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryColor.withOpacity(0.12 + math.sin(animation) * 0.03),
          primaryColor.withOpacity(0.05),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.85, size.height * 0.15),
        radius: size.width * 0.5,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      size.width * 0.5,
      paint1,
    );

    // Bottom-left gradient orb
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          accentColor.withOpacity(0.1 + math.cos(animation) * 0.03),
          accentColor.withOpacity(0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.15, size.height * 0.85),
        radius: size.width * 0.45,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.85),
      size.width * 0.45,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant SoftGradientPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

class FloatingParticlesPainter extends CustomPainter {
  final double animation;
  final Color color;

  FloatingParticlesPainter({
    required this.animation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw subtle floating particles
    final random = math.Random(42);
    for (int i = 0; i < 15; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final particleSize = 1.5 + random.nextDouble() * 2;
      final opacity = 0.1 + animation * 0.15 + random.nextDouble() * 0.1;
      
      paint.color = color.withOpacity(opacity);
      canvas.drawCircle(
        Offset(baseX, baseY + math.sin(animation + i) * 10),
        particleSize,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FloatingParticlesPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

class ModernRingPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;

  ModernRingPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Draw segmented arcs
    final arcPaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final startAngle = i * math.pi / 4 + math.pi / 16;
      final sweepAngle = math.pi / 6;
      
      final opacity = 0.3 + progress * 0.4;
      arcPaint.color = i % 2 == 0 
          ? primaryColor.withOpacity(opacity)
          : secondaryColor.withOpacity(opacity * 0.8);
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }

    // Draw corner dots
    final dotPaint = Paint()
      ..color = primaryColor.withOpacity(0.6 + progress * 0.4)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ModernRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
