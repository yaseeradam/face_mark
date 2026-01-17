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
  late AnimationController _scanController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late AnimationController _rotateController;
  late Animation<double> _scanAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotateAnimation;
  
  String _loadingText = "INITIALIZING SYSTEMS...";
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    
    // Scanning line animation
    _scanController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();
    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
    
    // Pulse animation for glow effects
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
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
    
    // Rotate animation for hex ring
    _rotateController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    _rotateAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_rotateController);
    
    _fadeController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _loadingText = "LOADING MODULES...";
        _progress = 0.2;
      });
      await StorageService.initialize();
      
      setState(() {
        _loadingText = "VERIFYING CREDENTIALS...";
        _progress = 0.5;
      });
      final token = await StorageService.getToken();
      
      setState(() {
        _loadingText = "CONFIGURING INTERFACE...";
        _progress = 0.8;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      
      setState(() {
        _loadingText = "SYSTEM READY";
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
      setState(() => _loadingText = "ERROR: INITIALIZATION FAILED");
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          // ═══════════════════════════════════════════════════════════════════
          // CIRCUIT GRID BACKGROUND
          // ═══════════════════════════════════════════════════════════════════
          CustomPaint(
            size: size,
            painter: CircuitGridPainter(),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // SCANNING LINE EFFECT
          // ═══════════════════════════════════════════════════════════════════
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) {
              return Positioned(
                top: size.height * _scanAnimation.value - 2,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        const Color(0xFF00F5FF).withOpacity(0.8),
                        const Color(0xFF00F5FF),
                        const Color(0xFF00F5FF).withOpacity(0.8),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F5FF).withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // ═══════════════════════════════════════════════════════════════════
          // CORNER TECH DECORATIONS
          // ═══════════════════════════════════════════════════════════════════
          // Top-left corner
          Positioned(
            top: 40,
            left: 20,
            child: _buildCornerDecoration(true, true),
          ),
          // Top-right corner
          Positioned(
            top: 40,
            right: 20,
            child: _buildCornerDecoration(true, false),
          ),
          // Bottom-left corner
          Positioned(
            bottom: 40,
            left: 20,
            child: _buildCornerDecoration(false, true),
          ),
          // Bottom-right corner
          Positioned(
            bottom: 40,
            right: 20,
            child: _buildCornerDecoration(false, false),
          ),

          // ═══════════════════════════════════════════════════════════════════
          // HOLOGRAPHIC GLOW ORBS
          // ═══════════════════════════════════════════════════════════════════
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: size.height * 0.15,
                    left: size.width * 0.1,
                    child: _buildHoloOrb(40, const Color(0xFF00F5FF), _pulseAnimation.value),
                  ),
                  Positioned(
                    top: size.height * 0.25,
                    right: size.width * 0.15,
                    child: _buildHoloOrb(25, const Color(0xFFBF00FF), _pulseAnimation.value * 0.8),
                  ),
                  Positioned(
                    bottom: size.height * 0.3,
                    left: size.width * 0.08,
                    child: _buildHoloOrb(30, const Color(0xFF00FF88), _pulseAnimation.value * 0.9),
                  ),
                  Positioned(
                    bottom: size.height * 0.2,
                    right: size.width * 0.1,
                    child: _buildHoloOrb(35, const Color(0xFF00F5FF), _pulseAnimation.value * 0.7),
                  ),
                ],
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
                  // Hexagonal Ring with Logo
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer rotating hex ring
                        AnimatedBuilder(
                          animation: _rotateAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _rotateAnimation.value,
                              child: CustomPaint(
                                size: const Size(200, 200),
                                painter: HexRingPainter(
                                  progress: _pulseAnimation.value,
                                ),
                              ),
                            );
                          },
                        ),
                        // Inner glowing circle
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
                                    const Color(0xFF0A0E1A),
                                    const Color(0xFF0A1628),
                                    const Color(0xFF0A0E1A),
                                  ],
                                  stops: const [0.0, 0.7, 1.0],
                                ),
                                border: Border.all(
                                  color: const Color(0xFF00F5FF).withOpacity(0.5 + _pulseAnimation.value * 0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00F5FF).withOpacity(0.3 * _pulseAnimation.value),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFFBF00FF).withOpacity(0.2 * _pulseAnimation.value),
                                    blurRadius: 40,
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
                                      shaderCallback: (bounds) => const LinearGradient(
                                        colors: [Color(0xFF00F5FF), Color(0xFFBF00FF)],
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
                  
                  // App Name with holographic effect
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFF00F5FF),
                        Color(0xFFBF00FF),
                        Color(0xFF00FF88),
                        Color(0xFF00F5FF),
                      ],
                      stops: [0.0, 0.33, 0.66, 1.0],
                    ).createShader(bounds),
                    child: const Text(
                      "FACE ATTENDANCE",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Tagline
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF00F5FF).withOpacity(0.3),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "BIOMETRIC RECOGNITION SYSTEM",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF00F5FF),
                        letterSpacing: 3,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 64),
                  
                  // Progress Section
                  SizedBox(
                    width: 280,
                    child: Column(
                      children: [
                        // Status indicator row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _progress >= 1.0 
                                            ? const Color(0xFF00FF88)
                                            : const Color(0xFF00F5FF),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: (_progress >= 1.0 
                                                ? const Color(0xFF00FF88)
                                                : const Color(0xFF00F5FF))
                                                .withOpacity(_pulseAnimation.value),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _progress >= 1.0 ? "ONLINE" : "PROCESSING",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _progress >= 1.0 
                                        ? const Color(0xFF00FF88)
                                        : const Color(0xFF00F5FF),
                                    letterSpacing: 2,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              "${(_progress * 100).toInt()}%",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00F5FF),
                                letterSpacing: 1,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Tech-style progress bar
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2035),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: const Color(0xFF00F5FF).withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Stack(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                width: 280 * _progress,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF00F5FF),
                                      Color(0xFFBF00FF),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00F5FF).withOpacity(0.6),
                                      blurRadius: 10,
                                      spreadRadius: 1,
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                ">",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF00F5FF),
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _loadingText,
                                key: ValueKey(_loadingText),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.7),
                                  letterSpacing: 1,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
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
                        width: 30,
                        height: 1,
                        color: const Color(0xFF00F5FF).withOpacity(0.3),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "POWERED BY AI",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4A5568),
                          letterSpacing: 3,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 30,
                        height: 1,
                        color: const Color(0xFF00F5FF).withOpacity(0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "v2.5.0",
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF3D4556),
                      letterSpacing: 2,
                      fontFamily: 'monospace',
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

  Widget _buildCornerDecoration(bool isTop, bool isLeft) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: CornerDecorationPainter(
          isTop: isTop,
          isLeft: isLeft,
        ),
      ),
    );
  }

  Widget _buildHoloOrb(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(opacity * 0.3),
            color.withOpacity(0),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class CircuitGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A2035)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Horizontal lines
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    // Vertical lines
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw circuit nodes at intersections
    final nodePaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.15)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += 80) {
      for (double y = 0; y < size.height; y += 80) {
        canvas.drawCircle(Offset(x, y), 2, nodePaint);
      }
    }

    // Draw some random circuit paths
    final circuitPaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.08)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.3);
    path.lineTo(size.width * 0.2, size.height * 0.3);
    path.lineTo(size.width * 0.2, size.height * 0.5);
    path.lineTo(size.width * 0.4, size.height * 0.5);
    
    path.moveTo(size.width, size.height * 0.6);
    path.lineTo(size.width * 0.7, size.height * 0.6);
    path.lineTo(size.width * 0.7, size.height * 0.4);
    path.lineTo(size.width * 0.5, size.height * 0.4);

    canvas.drawPath(path, circuitPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HexRingPainter extends CustomPainter {
  final double progress;

  HexRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Draw dashed hex ring segments
    final segmentPaint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.4 + progress * 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 6; i++) {
      final startAngle = i * math.pi / 3 - math.pi / 2;
      final endAngle = startAngle + math.pi / 4;
      
      final startX = center.dx + radius * math.cos(startAngle);
      final startY = center.dy + radius * math.sin(startAngle);
      final endX = center.dx + radius * math.cos(endAngle);
      final endY = center.dy + radius * math.sin(endAngle);
      
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), segmentPaint);
    }

    // Draw corner nodes
    final nodePaint = Paint()
      ..color = const Color(0xFFBF00FF).withOpacity(0.6 + progress * 0.4)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      canvas.drawCircle(Offset(x, y), 4, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant HexRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class CornerDecorationPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;

  CornerDecorationPainter({required this.isTop, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F5FF).withOpacity(0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
