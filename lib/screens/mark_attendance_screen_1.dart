import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class MarkAttendanceScreen1 extends StatefulWidget {
  const MarkAttendanceScreen1({super.key});

  @override
  State<MarkAttendanceScreen1> createState() => _MarkAttendanceScreen1State();
}

class _MarkAttendanceScreen1State extends State<MarkAttendanceScreen1>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  late AnimationController _scanAnimationController;
  late AnimationController _bottomSheetController;
  late AnimationController _statusBadgeController;
  late AnimationController _successPulseController;
  late Animation<double> _bottomSheetAnimation;
  late Animation<double> _statusBadgeAnimation;
  late Animation<double> _successPulseAnimation;
  
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isScanning = false;
  Map<String, dynamic>? _recognizedStudent;
  
  @override
  void initState() {
    super.initState();
    _loadClasses();
    _initializeCamera();
    
    // Scanning line animation (continuous)
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Bottom sheet slide up animation
    _bottomSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bottomSheetAnimation = CurvedAnimation(
      parent: _bottomSheetController,
      curve: Curves.easeOutCubic,
    );
    
    // Status badge fade & scale animation
    _statusBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _statusBadgeAnimation = CurvedAnimation(
      parent: _statusBadgeController,
      curve: Curves.easeOutBack,
    );
    
    // Success pulse animation (when face recognized)
    _successPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _successPulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _successPulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _loadClasses() async {
    final result = await ApiService.getClasses();
    if (!mounted) return;
    
    if (result['success']) {
      setState(() {
        _classes = List<Map<String, dynamic>>.from(result['data'] ?? []);
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _scanAnimationController.dispose();
    _bottomSheetController.dispose();
    _statusBadgeController.dispose();
    _successPulseController.dispose();
    super.dispose();
  }

  Future<void> _scanFace() async {
    if (_selectedClassId == null) {
      UIHelpers.showWarning(context, "Please select a class first");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _recognizedStudent = {}; // Empty object to trigger bottom sheet
    });
    
    // Show bottom sheet immediately with loading state
    _bottomSheetController.forward();

    try {
      final XFile photo = await _cameraController!.takePicture();
      
      final result = await ApiService.verifyFace(
        classId: _selectedClassId!,
        imageFile: File(photo.path),
      );

      if (!mounted) return;
      setState(() => _isScanning = false);

      if (result['success']) {
        // Update bottom sheet with student data
        setState(() => _recognizedStudent = result['data']);
        
        // Trigger success animations
        _statusBadgeController.forward();
        _successPulseController.forward().then((_) {
          _successPulseController.reverse();
        });
        
        UIHelpers.showSuccess(context, "Face recognized successfully!");
      } else {
        // Show error state in modal
        setState(() {
          _recognizedStudent = {
            'error': true,
            'message': result['error'] ?? 'Face not recognized'
          };
        });
        
        // Auto-hide after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _resetScan();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _recognizedStudent = {
            'error': true,
            'message': "Scan Error: $e"
          };
        });
        
        // Auto-hide after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _resetScan();
          }
        });
      }
    }
  }
  
  void _resetScan() {
    _bottomSheetController.reverse();
    _statusBadgeController.reverse();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _recognizedStudent = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Stack(
          children: [
            // Full Screen Layout
            Column(
              children: [
                // Top Navigation with fade in
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 400),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: _buildTopNavigation(context, theme, isDark),
                ),
                
                // Camera Viewport - Takes most of the space
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: _buildCameraViewport(theme, isDark),
                  ),
                ),
              ],
            ),
            
            // Bottom Sheet with slide animation
            if (_recognizedStudent != null)
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(_bottomSheetAnimation),
                child: _buildResultBottomSheet(theme, isDark),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavigation(BuildContext context, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
            ),
          ),
          const Expanded(
            child: Text(
              "Mark Attendance",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.help_outline),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewport(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera Feed
            if (_isCameraInitialized)
              CameraPreview(_cameraController!)
            else
              Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            
            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                  ],
                  stops: const [0.0, 0.3, 1.0],
                ),
              ),
            ),
            
            // Scanning UI Overlay
            _buildScanningOverlay(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningOverlay(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Status Badge with animation
        if (_recognizedStudent != null)
          ScaleTransition(
            scale: _statusBadgeAnimation,
            child: FadeTransition(
              opacity: _statusBadgeAnimation,
              child: Container(
                margin: const EdgeInsets.only(bottom: 40),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _successPulseAnimation,
                      child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Face Recognized",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        
        // Face Frame with pulse on success
        AnimatedBuilder(
          animation: _recognizedStudent != null ? _successPulseController : _scanAnimationController,
          builder: (context, child) {
            final scale = _recognizedStudent != null 
                ? _successPulseAnimation.value 
                : 1.0;
            
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _recognizedStudent != null
                        ? theme.colorScheme.primary.withOpacity(0.8)
                        : Colors.white.withOpacity(0.2),
                    width: _recognizedStudent != null ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _recognizedStudent != null
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    // Corner Indicators with animation
                    ..._buildCornerIndicators(),
                    
                    // Scanning Line (only when not recognized)
                    if (_recognizedStudent == null)
                      Positioned(
                        top: 280 * _scanAnimationController.value,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.8),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withOpacity(0.8),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 24),
        
        // Instruction Text with fade animation
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _recognizedStudent != null
                ? "Identity Confirmed ✓"
                : "Hold still for verification",
            key: ValueKey<bool>(_recognizedStudent != null),
            style: TextStyle(
              color: _recognizedStudent != null
                  ? Colors.green[300]
                  : Colors.white70,
              fontSize: 14,
              fontWeight: _recognizedStudent != null 
                  ? FontWeight.w600 
                  : FontWeight.w300,
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Class Selector with slide animation
        if (_recognizedStudent == null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: DropdownButton<int>(
                  value: _selectedClassId,
                  hint: const Text(
                    "Select Class",
                    style: TextStyle(color: Colors.white70),
                  ),
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E2936),
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  items: _classes.map((c) {
                    return DropdownMenuItem<int>(
                      value: c['id'],
                      child: Text(
                        c['class_name'] ?? c['name'] ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedClassId = value),
                ),
              ),
            ),
          ),
        
        const SizedBox(height: 16),
        
        // Scan Button with scale animation on press
        if (_recognizedStudent == null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _scanFace,
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.face_retouching_natural),
              label: Text(_isScanning ? "Scanning..." : "Scan Face"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                elevation: 8,
                shadowColor: theme.colorScheme.primary.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCornerIndicators() {
    const size = 32.0;
    const thickness = 4.0;
    final color = _recognizedStudent != null 
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.primary.withOpacity(0.6);

    return [
      // Animated corners
      _buildCorner(0, 0, size, color, thickness, BorderRadius.only(topLeft: Radius.circular(8)), 
                   Border(top: BorderSide(color: color, width: thickness), left: BorderSide(color: color, width: thickness))),
      _buildCorner(0, null, size, color, thickness, BorderRadius.only(topRight: Radius.circular(8)), 
                   Border(top: BorderSide(color: color, width: thickness), right: BorderSide(color: color, width: thickness))),
      _buildCorner(null, 0, size, color, thickness, BorderRadius.only(bottomLeft: Radius.circular(8)), 
                   Border(bottom: BorderSide(color: color, width: thickness), left: BorderSide(color: color, width: thickness))),
      _buildCorner(null, null, size, color, thickness, BorderRadius.only(bottomRight: Radius.circular(8)), 
                   Border(bottom: BorderSide(color: color, width: thickness), right: BorderSide(color: color, width: thickness))),
    ];
  }

  Widget _buildCorner(double? top, double? left, double size, Color color, 
                      double thickness, BorderRadius radius, Border border) {
    return Positioned(
      top: top,
      left: left,
      right: left == null ? 0 : null,
      bottom: top == null ? 0 : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                border: border,
                borderRadius: radius,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultBottomSheet(ThemeData theme, bool isDark) {
    final student = _recognizedStudent!;
    final now = DateTime.now();
    
    // Check state: loading, error, or success
    final isLoading = student.isEmpty || (student.isEmpty && _isScanning);
    final isError = student.containsKey('error') && student['error'] == true;
    final isSuccess = !isLoading && !isError;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle with animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 48 * value,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[600] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            },
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              children: [
                // Show different content based on state
                if (isLoading) _buildLoadingState(theme, isDark),
                if (isError) _buildErrorState(student['message'] ?? 'Unknown error', theme, isDark),
                if (isSuccess) ...[
                  _buildAnimatedProfileHeader(student, theme, isDark),
                  const SizedBox(height: 24),
                  _buildAnimatedStatsGrid(now, theme, isDark),
                  const SizedBox(height: 20),
                  _buildAnimatedActionButtons(student, theme, isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoadingState(ThemeData theme, bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Scanning animation
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Scanning Face...",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Please wait while we verify your identity",
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Skeleton loaders for upcoming content
              _buildSkeletonLoader(theme, isDark),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildSkeletonLoader(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            // Avatar skeleton
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.grey[800] : Colors.grey[200],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 150,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildErrorState(String message, ThemeData theme, bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (0.2 * value),
          child: Opacity(
            opacity: value,
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Error icon with animation
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Recognition Failed",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: _resetScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Try Again"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedProfileHeader(Map<String, dynamic> student, ThemeData theme, bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(-20 * (1 - value), 0),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Row(
        children: [
          // Profile Picture with scale animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.primary, width: 2),
                    image: student['photo_path'] != null
                        ? DecorationImage(
                            image: NetworkImage(
                                '${ApiService.baseUrl}/uploads/${student['photo_path']}'),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: student['photo_path'] == null
                      ? Icon(Icons.person, size: 32, color: theme.colorScheme.primary)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2936) : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          
          // Name and ID
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student['full_name'] ?? student['name'] ?? 'Unknown',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "ID: ${student['student_id'] ?? 'N/A'}",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Status Badge with bounce
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "PRESENT",
                    style: TextStyle(
                      color: isDark ? Colors.green[300] : Colors.green[700],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  student['class_name'] ?? 'Class N/A',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedStatsGrid(DateTime now, ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(-20 * (1 - value), 0),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: _buildStatCard(
              icon: Icons.access_time,
              label: "TIME IN",
              value: "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
              suffix: now.hour < 12 ? "AM" : "PM",
              theme: theme,
              isDark: isDark,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(20 * (1 - value), 0),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: _buildStatCard(
              icon: Icons.calendar_today,
              label: "DATE",
              value: "${_getMonthName(now.month)} ${now.day}",
              theme: theme,
              isDark: isDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    String? suffix,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.grey[800]!) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              children: suffix != null
                  ? [
                      TextSpan(
                        text: " $suffix",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedActionButtons(Map<String, dynamic> student, ThemeData theme, bool isDark) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _resetScan,
              icon: const Icon(Icons.edit, size: 20),
              label: const Text("Manual Entry"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await ApiService.markAttendance({
                  'student_id': student['id'],
                  'class_id': _selectedClassId,
                  'status': 'present',
                });
                
                if (mounted) {
                  if (result['success']) {
                    UIHelpers.showSuccess(context, "Attendance confirmed!");
                    Navigator.pop(context);
                  } else {
                    UIHelpers.showError(context, result['error'] ?? 'Failed to confirm');
                  }
                }
              },
              icon: const Icon(Icons.check, size: 20),
              label: const Text("Confirm Attendance"),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 4,
                shadowColor: theme.colorScheme.primary.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
