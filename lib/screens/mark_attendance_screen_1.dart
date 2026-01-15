import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
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
  late AnimationController _shimmerController;
  late Animation<double> _bottomSheetAnimation;
  late Animation<double> _statusBadgeAnimation;
  late Animation<double> _successPulseAnimation;
  late Animation<double> _shimmerAnimation;
  
  // ML Kit Face Detection
  FaceDetector? _faceDetector;
  bool _isDetectingFaces = false;
  bool _isProcessingImage = false;
  
  // Real-time feedback state
  String _faceGuidanceMessage = "Position your face in the frame";
  Color _faceGuidanceColor = Colors.white70;
  bool _isFaceValid = false;
  bool _isLivenessVerified = false;
  double? _headAngleY;
  double? _headAngleZ;
  double? _smilingProbability;
  double? _leftEyeOpenProbability;
  double? _rightEyeOpenProbability;
  bool _faceDetected = false;
  
  // Auto-capture state
  DateTime? _lastCaptureTime;
  bool _hasAutoCapture = false;
  static const _autoCaptureCooldown = Duration(seconds: 5); // Wait 5 seconds between captures
  int _readyFrameCount = 0; // Count frames where face is ready
  static const _requiredReadyFrames = 5; // Need 5 consecutive ready frames
  
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isScanning = false;
  Map<String, dynamic>? _recognizedStudent;
  bool _multipleCheckinsEnabled = false;
  String _checkInType = 'morning';
  DateTime? _lastFrameProcessed;
  static const _frameProcessingInterval = Duration(milliseconds: 150);
  
  @override
  void initState() {
    super.initState();
    _loadClasses();
    _initializeFaceDetector();
    _initializeCamera();
    _loadCheckinSettings();
    
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
    
    // Shimmer animation for loading state
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _loadCheckinSettings() {
    final enabled = StorageService.getBool('settings_multiple_checkins', defaultValue: false);
    setState(() => _multipleCheckinsEnabled = enabled);
  }
  
  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true, // Enable smiling and eye detection
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    );
    _faceDetector = FaceDetector(options: options);
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
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        // Start real-time face detection
        _startFaceDetection();
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }
  
  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    _isDetectingFaces = true;
    _cameraController!.startImageStream((CameraImage image) {
      if (!_isDetectingFaces || _isProcessingImage || _isScanning) return;
      final now = DateTime.now();
      if (_lastFrameProcessed != null &&
          now.difference(_lastFrameProcessed!) < _frameProcessingInterval) {
        return;
      }
      _lastFrameProcessed = now;
      _processImageForFaceDetection(image);
    });
  }
  
  void _stopFaceDetection() {
    _isDetectingFaces = false;
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }
  }
  
  Future<void> _processImageForFaceDetection(CameraImage image) async {
    if (_faceDetector == null || _isProcessingImage) return;
    
    _isProcessingImage = true;
    
    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _isProcessingImage = false;
        return;
      }
      
      // Detect faces
      final faces = await _faceDetector!.processImage(inputImage);
      
      if (!mounted) {
        _isProcessingImage = false;
        return;
      }
      
      _updateFaceGuidance(faces);
    } catch (e) {
      debugPrint('Face detection error: $e');
    }
    
    _isProcessingImage = false;
  }
  
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
      
      if (rotation == null) return null;
      
      // Get the image format
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;
      
      // Create input image from bytes
      final plane = image.planes.first;
      
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Image conversion error: $e');
      return null;
    }
  }
  
  void _updateFaceGuidance(List<Face> faces) {
    if (!mounted) return;
    
    setState(() {
      if (faces.isEmpty) {
        _faceDetected = false;
        _isFaceValid = false;
        _isLivenessVerified = false;
        _faceGuidanceMessage = "No face detected - Position your face in the frame";
        _faceGuidanceColor = Colors.orange;
        _headAngleY = null;
        _headAngleZ = null;
        _smilingProbability = null;
        _leftEyeOpenProbability = null;
        _rightEyeOpenProbability = null;
        return;
      }
      
      final face = faces.first;
      _faceDetected = true;
      
      // Get head angles
      _headAngleY = face.headEulerAngleY; // Left-Right rotation
      _headAngleZ = face.headEulerAngleZ; // Tilt
      _smilingProbability = face.smilingProbability;
      _leftEyeOpenProbability = face.leftEyeOpenProbability;
      _rightEyeOpenProbability = face.rightEyeOpenProbability;
      
      // Check head position (thresholds in degrees)
      const maxYAngle = 15.0; // Max left-right turn
      const maxZAngle = 10.0; // Max tilt
      
      bool isHeadStraight = true;
      String headMessage = "";
      
      if (_headAngleY != null && _headAngleY!.abs() > maxYAngle) {
        isHeadStraight = false;
        if (_headAngleY! > 0) {
          headMessage = "Please look straight - Turn right slightly";
        } else {
          headMessage = "Please look straight - Turn left slightly";
        }
      }
      
      if (_headAngleZ != null && _headAngleZ!.abs() > maxZAngle) {
        isHeadStraight = false;
        if (_headAngleZ! > 0) {
          headMessage = "Please look straight - Tilt head right";
        } else {
          headMessage = "Please look straight - Tilt head left";
        }
      }
      
      // Liveness check - eyes should be open
      bool eyesOpen = true;
      if (_leftEyeOpenProbability != null && _rightEyeOpenProbability != null) {
        eyesOpen = _leftEyeOpenProbability! > 0.5 && _rightEyeOpenProbability! > 0.5;
      }
      
      // Check for smiling (optional liveness indicator)
      bool hasLivenessIndicator = false;
      if (_smilingProbability != null && _smilingProbability! > 0.3) {
        hasLivenessIndicator = true;
      }
      if (eyesOpen) {
        hasLivenessIndicator = true;
      }
      
      // Determine overall face validity
      _isFaceValid = isHeadStraight && eyesOpen;
      _isLivenessVerified = hasLivenessIndicator;
      
      // Set guidance message and color
      if (!eyesOpen) {
        _faceGuidanceMessage = "Please open your eyes";
        _faceGuidanceColor = Colors.orange;
        _readyFrameCount = 0; // Reset counter
      } else if (!isHeadStraight) {
        _faceGuidanceMessage = headMessage;
        _faceGuidanceColor = Colors.orange;
        _readyFrameCount = 0; // Reset counter
      } else if (_isFaceValid && _isLivenessVerified) {
        _readyFrameCount++;
        
        // Check if we should auto-capture
        if (_readyFrameCount >= _requiredReadyFrames && !_isScanning && _selectedClassId != null) {
          final now = DateTime.now();
          final canCapture = _lastCaptureTime == null || 
                           now.difference(_lastCaptureTime!) > _autoCaptureCooldown;
          
          if (canCapture) {
            _faceGuidanceMessage = "Capturing...";
            _faceGuidanceColor = Colors.blue;
            _lastCaptureTime = now;
            _readyFrameCount = 0;
            
            // Trigger auto-capture
            Future.microtask(() => _autoCaptureFace());
          } else {
            final remaining = _autoCaptureCooldown.inSeconds - now.difference(_lastCaptureTime!).inSeconds;
            _faceGuidanceMessage = "Ready! Wait ${remaining}s...";
            _faceGuidanceColor = Colors.green;
          }
        } else {
          _faceGuidanceMessage = "Hold steady... ${_requiredReadyFrames - _readyFrameCount}";
          _faceGuidanceColor = Colors.green;
        }
      } else {
        _faceGuidanceMessage = "Hold steady...";
        _faceGuidanceColor = Colors.white70;
        _readyFrameCount = 0; // Reset counter
      }
    });
  }
  
  Future<void> _autoCaptureFace() async {
    if (_selectedClassId == null || _isScanning) return;
    await _scanFace();
  }

  @override
  void dispose() {
    _stopFaceDetection();
    _cameraController?.dispose();
    _faceDetector?.close();
    _scanAnimationController.dispose();
    _bottomSheetController.dispose();
    _statusBadgeController.dispose();
    _successPulseController.dispose();
    _shimmerController.dispose();
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
      _recognizedStudent = {}; // Empty object to show loading state in bottom sheet
    });

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
        // Show error state in bottom sheet - STAYS VISIBLE
        setState(() {
          _recognizedStudent = {
            'error': true,
            'message': result['error'] ?? 'Face not recognized'
          };
        });
        
        // Error stays visible - user can manually retry or system will auto-capture again if they reposition
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
        
        // Error stays visible - user can manually retry or system will auto-capture again
      }
    }
  }
  
  void _resetScan() {
    _statusBadgeController.reverse();
    setState(() {
      _recognizedStudent = null; // Back to shimmer state
      _readyFrameCount = 0; // Reset auto-capture counter
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
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
            
            // Camera Viewport - 50% of screen
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
            
            // Bottom Sheet - ALWAYS VISIBLE - 50% of screen
            Expanded(
              child: _buildPersistentBottomSheet(theme, isDark),
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
          const SizedBox(width: 48), // Balance for symmetry
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
        // Real-time face feedback badge (when scanning not active)
        if (_recognizedStudent == null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              border: Border.all(
                color: _faceGuidanceColor.withOpacity(0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: _faceGuidanceColor.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status icon based on face state
                Icon(
                  _faceDetected 
                      ? (_isFaceValid && _isLivenessVerified 
                          ? Icons.check_circle 
                          : Icons.info_outline)
                      : Icons.face_retouching_off,
                  color: _faceGuidanceColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _faceGuidanceMessage,
                    style: TextStyle(
                      color: _faceGuidanceColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        
        // Liveness indicator row
        if (_recognizedStudent == null && _faceDetected)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Eyes status
                _buildLivenessIndicator(
                  icon: Icons.visibility,
                  label: "Eyes",
                  isValid: _leftEyeOpenProbability != null && 
                           _rightEyeOpenProbability != null &&
                           _leftEyeOpenProbability! > 0.5 && 
                           _rightEyeOpenProbability! > 0.5,
                ),
                const SizedBox(width: 16),
                // Head position status
                _buildLivenessIndicator(
                  icon: Icons.face,
                  label: "Position",
                  isValid: _headAngleY != null && 
                           _headAngleZ != null && 
                           _headAngleY!.abs() <= 15 && 
                           _headAngleZ!.abs() <= 10,
                ),
                const SizedBox(width: 16),
                // Smile status (optional)
                _buildLivenessIndicator(
                  icon: Icons.sentiment_satisfied_alt,
                  label: "Live",
                  isValid: _isLivenessVerified,
                ),
              ],
            ),
          ),
        
        // Success badge (after face recognized)
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
        
        // Face Frame with dynamic border color based on face validity
        AnimatedBuilder(
          animation: _recognizedStudent != null ? _successPulseController : _scanAnimationController,
          builder: (context, child) {
            final scale = _recognizedStudent != null 
                ? _successPulseAnimation.value 
                : 1.0;
            
            // Determine frame color based on state
            Color frameColor;
            double frameWidth;
            if (_recognizedStudent != null) {
              frameColor = theme.colorScheme.primary.withOpacity(0.8);
              frameWidth = 3;
            } else if (_isFaceValid && _isLivenessVerified) {
              frameColor = Colors.green.withOpacity(0.8);
              frameWidth = 2.5;
            } else if (_faceDetected) {
              frameColor = Colors.orange.withOpacity(0.6);
              frameWidth = 2;
            } else {
              frameColor = Colors.white.withOpacity(0.2);
              frameWidth = 1;
            }
            
            return Transform.scale(
              scale: scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: frameColor,
                    width: frameWidth,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: (_recognizedStudent != null || (_isFaceValid && _isLivenessVerified))
                      ? [
                          BoxShadow(
                            color: (_recognizedStudent != null 
                                ? theme.colorScheme.primary 
                                : Colors.green).withOpacity(0.4),
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
                            color: (_isFaceValid && _isLivenessVerified)
                                ? Colors.green.withOpacity(0.8)
                                : theme.colorScheme.primary.withOpacity(0.8),
                            boxShadow: [
                              BoxShadow(
                                color: (_isFaceValid && _isLivenessVerified)
                                    ? Colors.green.withOpacity(0.8)
                                    : theme.colorScheme.primary.withOpacity(0.8),
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
        
        // Instruction Text with dynamic message
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _recognizedStudent != null
                ? "Identity Confirmed ✓"
                : (_isFaceValid && _isLivenessVerified 
                    ? "Ready to scan!" 
                    : "Position your face in the frame"),
            key: ValueKey<String>(_recognizedStudent != null 
                ? "confirmed" 
                : (_isFaceValid ? "ready" : "position")),
            style: TextStyle(
              color: _recognizedStudent != null
                  ? Colors.green[300]
                  : (_isFaceValid && _isLivenessVerified 
                      ? Colors.green[300] 
                      : Colors.white70),
              fontSize: 14,
              fontWeight: (_recognizedStudent != null || (_isFaceValid && _isLivenessVerified))
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
      ],
    );
  }
  
  Widget _buildLivenessIndicator({
    required IconData icon,
    required String label,
    required bool isValid,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isValid ? Colors.green.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isValid ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isValid ? Colors.green : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isValid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 12,
            color: isValid ? Colors.green : Colors.grey.withOpacity(0.5),
          ),
        ],
      ),
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

  Widget _buildPersistentBottomSheet(ThemeData theme, bool isDark) {
    final now = DateTime.now();
    
    // Determine state: shimmer (no scan yet), loading (scanning), error, or success
    final isShimmer = _recognizedStudent == null && !_isScanning;
    final isLoading = _isScanning && (_recognizedStudent == null || _recognizedStudent!.isEmpty);
    final isError = _recognizedStudent != null && 
                    _recognizedStudent!.containsKey('error') && 
                    _recognizedStudent!['error'] == true;
    final isSuccess = _recognizedStudent != null && 
                      !_recognizedStudent!.containsKey('error') && 
                      _recognizedStudent!.isNotEmpty;
    
    return LayoutBuilder(
      builder: (context, constraints) {
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
              
              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Show different content based on state
                      if (isShimmer) _buildShimmerContent(theme, isDark),
                      if (isLoading) _buildLoadingState(theme, isDark),
                      if (isError) _buildErrorState(_recognizedStudent!['message'] ?? 'Unknown error', theme, isDark),
                      if (isSuccess) ...[ 
                        _buildAnimatedProfileHeader(_recognizedStudent!, theme, isDark),
                        const SizedBox(height: 20),
                        _buildAnimatedStatsGrid(now, theme, isDark),
                        const SizedBox(height: 16),
                        _buildAnimatedActionButtons(_recognizedStudent!, theme, isDark),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildShimmerContent(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Shimmer profile header
        _buildShimmerProfileHeader(theme, isDark),
        const SizedBox(height: 24),
        // Shimmer stats grid
        _buildShimmerStatsGrid(theme, isDark),
        const SizedBox(height: 20),
        // Shimmer action buttons
        _buildShimmerActionButtons(theme, isDark),
      ],
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
    return Column(
      children: [
        // Shimmer profile header - matching success state structure
        _buildShimmerProfileHeader(theme, isDark),
        const SizedBox(height: 24),
        // Shimmer stats grid - matching success state structure
        _buildShimmerStatsGrid(theme, isDark),
        const SizedBox(height: 20),
        // Shimmer action buttons - matching success state structure
        _buildShimmerActionButtons(theme, isDark),
      ],
    );
  }
  
  Widget _buildShimmerProfileHeader(ThemeData theme, bool isDark) {
    return Row(
      children: [
        // Shimmer profile picture
        _buildShimmerContainer(
          width: 64,
          height: 64,
          isDark: isDark,
          isCircle: true,
        ),
        const SizedBox(width: 16),
        
        // Shimmer name and ID
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShimmerContainer(
                width: double.infinity,
                height: 24,
                isDark: isDark,
                borderRadius: 6,
              ),
              const SizedBox(height: 8),
              _buildShimmerContainer(
                width: 120,
                height: 16,
                isDark: isDark,
                borderRadius: 4,
              ),
            ],
          ),
        ),
        
        // Shimmer status badge
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildShimmerContainer(
              width: 80,
              height: 24,
              isDark: isDark,
              borderRadius: 12,
            ),
            const SizedBox(height: 6),
            _buildShimmerContainer(
              width: 60,
              height: 14,
              isDark: isDark,
              borderRadius: 4,
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildShimmerStatsGrid(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildShimmerStatCard(theme, isDark)),
        const SizedBox(width: 16),
        Expanded(child: _buildShimmerStatCard(theme, isDark)),
      ],
    );
  }
  
  Widget _buildShimmerStatCard(ThemeData theme, bool isDark) {
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
              _buildShimmerContainer(
                width: 20,
                height: 20,
                isDark: isDark,
                borderRadius: 4,
              ),
              const SizedBox(width: 8),
              _buildShimmerContainer(
                width: 60,
                height: 14,
                isDark: isDark,
                borderRadius: 4,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildShimmerContainer(
            width: 80,
            height: 24,
            isDark: isDark,
            borderRadius: 4,
          ),
        ],
      ),
    );
  }
  
  Widget _buildShimmerActionButtons(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildShimmerContainer(
            width: double.infinity,
            height: 48,
            isDark: isDark,
            borderRadius: 12,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _buildShimmerContainer(
            width: double.infinity,
            height: 48,
            isDark: isDark,
            borderRadius: 12,
            isPrimary: true,
          ),
        ),
      ],
    );
  }
  
  Widget _buildShimmerContainer({
    required double width,
    required double height,
    required bool isDark,
    double borderRadius = 8,
    bool isCircle = false,
    bool isPrimary = false,
  }) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        // Create shimmer wave effect moving from left to right
        final shimmerValue = _shimmerAnimation.value;
        // Create a pulsing effect
        final pulseValue = (shimmerValue * 2 - 1).abs();
        
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + shimmerValue * 2, 0),
              end: Alignment(0 + shimmerValue * 2, 0),
              colors: isPrimary
                  ? [
                      Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      Theme.of(context).colorScheme.primary.withOpacity(0.35 + pulseValue * 0.15),
                      Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    ]
                  : [
                      isDark ? Colors.grey[800]! : Colors.grey[300]!,
                      isDark 
                          ? Colors.grey[600]! 
                          : Colors.grey[100]!,
                      isDark ? Colors.grey[800]! : Colors.grey[300]!,
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
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
      child: Column(
        children: [
          if (_multipleCheckinsEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Morning"),
                      selected: _checkInType == 'morning',
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() => _checkInType = 'morning');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Going Out"),
                      selected: _checkInType == 'outing',
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() => _checkInType = 'outing');
                      },
                    ),
                  ),
                ],
              ),
            ),
          Row(
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
                      'check_in_type': _checkInType,
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
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
