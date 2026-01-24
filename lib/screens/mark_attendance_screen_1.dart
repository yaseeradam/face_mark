import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
  static const _autoCaptureCooldown = Duration(milliseconds: 900);
  int _readyFrameCount = 0; // Count frames where face is ready
  static const _requiredReadyFrames = 2; // Need consecutive ready frames

  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isScanning = false;
  Map<String, dynamic>? _recognizedStudent;
  bool _multipleCheckinsEnabled = false;
  String _checkInType = 'morning';
  bool _lockToGoingOut = false;
  DateTime? _lastFrameProcessed;
  static const _frameProcessingInterval = Duration(milliseconds: 150);

  bool get _hasRecognizedStudent =>
      _recognizedStudent != null &&
      _recognizedStudent!.isNotEmpty &&
      _recognizedStudent!['error'] != true;

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
      CurvedAnimation(parent: _successPulseController, curve: Curves.easeInOut),
    );

    // Shimmer animation for loading state
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  void _loadCheckinSettings() {
    final enabled = StorageService.getBool(
      'settings_multiple_checkins',
      defaultValue: false,
    );
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

    if (result['success'] == true) {
      final classes = List<Map<String, dynamic>>.from(
        result['data'] ?? <dynamic>[],
      );
      final selected = _selectedClassId;
      final isSelectionValid =
          selected == null || classes.any((c) => _asInt(c['id']) == selected);

      setState(() {
        _classes = classes;
        if (!isSelectionValid) _selectedClassId = null;
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
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) return;

    _isDetectingFaces = true;
    _cameraController!
        .startImageStream((CameraImage image) {
          if (!_isDetectingFaces ||
              _isProcessingImage ||
              _isScanning ||
              _hasRecognizedStudent) {
            return;
          }
          final now = DateTime.now();
          if (_lastFrameProcessed != null &&
              now.difference(_lastFrameProcessed!) < _frameProcessingInterval) {
            return;
          }
          _lastFrameProcessed = now;
          _processImageForFaceDetection(image);
        })
        .catchError((e) {
          debugPrint('Image stream error: $e');
          _isDetectingFaces = false;
        });
  }

  void _stopFaceDetection() {
    _isDetectingFaces = false;
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
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
      final rotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );

      if (rotation == null) return null;

      // Get the image format
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final bytesBuilder = BytesBuilder(copy: false);
      for (final plane in image.planes) {
        bytesBuilder.add(plane.bytes);
      }
      final bytes = bytesBuilder.toBytes();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
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
        _readyFrameCount = 0;
        _faceGuidanceMessage =
            "No face detected - Position your face in the frame";
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
      const maxYAngle = 20.0; // Max left-right turn
      const maxZAngle = 15.0; // Max tilt

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
        eyesOpen =
            _leftEyeOpenProbability! > 0.5 && _rightEyeOpenProbability! > 0.5;
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
        if (_readyFrameCount >= _requiredReadyFrames && !_isScanning) {
          final now = DateTime.now();
          final canCapture =
              _lastCaptureTime == null ||
              now.difference(_lastCaptureTime!) > _autoCaptureCooldown;

          if (canCapture) {
            _faceGuidanceMessage = "Capturing...";
            _faceGuidanceColor = Colors.blue;
            _lastCaptureTime = now;
            _readyFrameCount = 0;

            // Trigger auto-capture
            Future.microtask(() => _autoCaptureFace());
          } else {
            final remaining =
                _autoCaptureCooldown.inSeconds -
                now.difference(_lastCaptureTime!).inSeconds;
            _faceGuidanceMessage = "Ready! Wait ${remaining}s...";
            _faceGuidanceColor = Colors.green;
          }
        } else {
          _faceGuidanceMessage =
              "Hold steady... ${_requiredReadyFrames - _readyFrameCount}";
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
    if (_isScanning) return;
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      if (mounted) {
        UIHelpers.showError(context, "Camera not ready yet");
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _recognizedStudent = null; // Keep shimmer/loading state
    });

    try {
      // Stop streaming before taking a picture (camera plugin requirement)
      _isDetectingFaces = false;
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await Future.delayed(const Duration(milliseconds: 200));

      final XFile photo = await _cameraController!.takePicture();

      final result = await ApiService.verifyFace(
        classId: _selectedClassId,
        checkInType: _checkInType,
        imageFile: File(photo.path),
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Update bottom sheet with student data
        final data = Map<String, dynamic>.from(
          (result['data'] ?? const <String, dynamic>{}) as Map,
        );

        // If Morning already marked, automatically switch to Going Out and lock.
        if (_multipleCheckinsEnabled &&
            _checkInType == 'morning' &&
            data['attendance_marked'] == true) {
          _checkInType = 'outing';
          _lockToGoingOut = true;
        }

        setState(() {
          _isScanning = false;
          _recognizedStudent = data;
        });

        // Trigger success animations
        _statusBadgeController.forward();
        _successPulseController.forward().then((_) {
          _successPulseController.reverse();
        });

        UIHelpers.showSuccess(context, "Face recognized successfully!");
      } else {
        // Show error state and resume scanning
        setState(() {
          _isScanning = false;
          _recognizedStudent = {
            'error': true,
            'message': result['error'] ?? 'Face not recognized',
          };
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          final current = _recognizedStudent;
          if (current != null && current['error'] == true) {
            _resetScan();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _recognizedStudent = {'error': true, 'message': "Scan Error: $e"};
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          final current = _recognizedStudent;
          if (current != null && current['error'] == true) {
            _resetScan();
          }
        });
      }
    }
  }

  void _resetScan() {
    _statusBadgeController.reverse();
    setState(() {
      _isScanning = false;
      _recognizedStudent = null; // Back to shimmer state
      _readyFrameCount = 0; // Reset auto-capture counter
      _checkInType = 'morning';
      _lockToGoingOut = false;
      _faceDetected = false;
      _isFaceValid = false;
      _isLivenessVerified = false;
      _faceGuidanceMessage = "Position your face in the frame";
      _faceGuidanceColor = Colors.white70;
    });
    _startFaceDetection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF101922)
          : const Color(0xFFF6F7F8),
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
            Expanded(child: _buildPersistentBottomSheet(theme, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavigation(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).maybePop(),
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
    final isDark = theme.brightness == Brightness.dark;
    final hasError =
        _recognizedStudent != null && _recognizedStudent!['error'] == true;
    final errorMessage = hasError
        ? (_recognizedStudent!['message']?.toString() ?? 'Face not recognized')
              .trim()
        : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameSize = math
            .min(constraints.maxWidth * 0.78, constraints.maxHeight * 0.65)
            .clamp(180.0, 320.0);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Face frame (tap to capture if auto-capture struggles)
            GestureDetector(
              onTap:
                  (!_isScanning &&
                      !_hasRecognizedStudent &&
                      _isFaceValid &&
                      _isLivenessVerified)
                  ? _scanFace
                  : null,
              child: _buildFaceFrame(theme, frameSize),
            ),

            // Top badge (only when recognized)
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(child: _buildRecognizedBadge()),
            ),

            // Bottom guidance pill (always)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: _buildGuidancePill(isDark),
            ),

            // Center modal feedback
            if (_isScanning)
              _buildCenterModal(
                isDark: isDark,
                icon: Icons.search,
                title: "Scanning...",
                message: "Hold still for verification",
                accent: theme.colorScheme.primary,
                showProgress: true,
              )
            else if (hasError)
              _buildCenterModal(
                isDark: isDark,
                icon: Icons.person_off_outlined,
                title: "Face not recognized",
                message: errorMessage.isNotEmpty
                    ? errorMessage
                    : "This face is not registered in the system.",
                accent: Colors.redAccent,
                actionText: "Try again",
                onAction: _resetScan,
              )
            else if (!_faceDetected && !_hasRecognizedStudent)
              _buildCenterModal(
                isDark: isDark,
                icon: Icons.face_retouching_off,
                title: "No face detected",
                message: "Place your face inside the frame",
                accent: Colors.orangeAccent,
              ),
          ],
        );
      },
    );
  }

  Widget _buildRecognizedBadge() {
    if (!_hasRecognizedStudent || !_faceDetected)
      return const SizedBox.shrink();
    return ScaleTransition(
      scale: _statusBadgeAnimation,
      child: FadeTransition(
        opacity: _statusBadgeAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.25),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _successPulseAnimation,
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Face Recognized",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidancePill(bool isDark) {
    final Color borderColor = _hasRecognizedStudent
        ? Colors.green.withOpacity(0.55)
        : (_isFaceValid && _isLivenessVerified)
        ? Colors.green.withOpacity(0.45)
        : _faceGuidanceColor.withOpacity(0.35);

    final Color iconColor = _hasRecognizedStudent
        ? Colors.greenAccent
        : (_isFaceValid && _isLivenessVerified)
        ? Colors.greenAccent
        : Colors.white70;

    final String message = _hasRecognizedStudent
        ? "Hold still for verification"
        : _faceGuidanceMessage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _hasRecognizedStudent
                ? Icons.verified
                : (_faceDetected
                      ? Icons.info_outline
                      : Icons.face_retouching_off),
            size: 18,
            color: iconColor,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterModal({
    required bool isDark,
    required IconData icon,
    required String title,
    required String message,
    required Color accent,
    bool showProgress = false,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
                if (showProgress) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                ],
                if (actionText != null && onAction != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: accent.withOpacity(0.7)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(actionText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaceFrame(ThemeData theme, double frameSize) {
    return AnimatedBuilder(
      animation: _hasRecognizedStudent
          ? _successPulseController
          : _scanAnimationController,
      builder: (context, child) {
        final scale = _hasRecognizedStudent
            ? _successPulseAnimation.value
            : 1.0;

        Color frameColor;
        double frameWidth;
        if (_hasRecognizedStudent) {
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
            width: frameSize,
            height: frameSize,
            decoration: BoxDecoration(
              border: Border.all(color: frameColor, width: frameWidth),
              borderRadius: BorderRadius.circular(16),
              boxShadow:
                  (_hasRecognizedStudent ||
                      (_isFaceValid && _isLivenessVerified))
                  ? [
                      BoxShadow(
                        color:
                            (_hasRecognizedStudent
                                    ? theme.colorScheme.primary
                                    : Colors.green)
                                .withOpacity(0.35),
                        blurRadius: 26,
                        spreadRadius: 3,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                ..._buildCornerIndicators(),
                if (!_hasRecognizedStudent)
                  Positioned(
                    top: frameSize * _scanAnimationController.value,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: (_isFaceValid && _isLivenessVerified)
                            ? Colors.green.withOpacity(0.8)
                            : theme.colorScheme.primary.withOpacity(0.8),
                        boxShadow: [
                          BoxShadow(
                            color: (_isFaceValid && _isLivenessVerified)
                                ? Colors.green.withOpacity(0.7)
                                : theme.colorScheme.primary.withOpacity(0.7),
                            blurRadius: 14,
                            spreadRadius: 1,
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
          color: isValid
              ? Colors.green.withOpacity(0.5)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isValid ? Colors.green : Colors.grey),
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
    final color = _hasRecognizedStudent
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.primary.withOpacity(0.6);

    return [
      // Animated corners
      _buildCorner(
        0,
        0,
        size,
        color,
        thickness,
        BorderRadius.only(topLeft: Radius.circular(8)),
        Border(
          top: BorderSide(color: color, width: thickness),
          left: BorderSide(color: color, width: thickness),
        ),
      ),
      _buildCorner(
        0,
        null,
        size,
        color,
        thickness,
        BorderRadius.only(topRight: Radius.circular(8)),
        Border(
          top: BorderSide(color: color, width: thickness),
          right: BorderSide(color: color, width: thickness),
        ),
      ),
      _buildCorner(
        null,
        0,
        size,
        color,
        thickness,
        BorderRadius.only(bottomLeft: Radius.circular(8)),
        Border(
          bottom: BorderSide(color: color, width: thickness),
          left: BorderSide(color: color, width: thickness),
        ),
      ),
      _buildCorner(
        null,
        null,
        size,
        color,
        thickness,
        BorderRadius.only(bottomRight: Radius.circular(8)),
        Border(
          bottom: BorderSide(color: color, width: thickness),
          right: BorderSide(color: color, width: thickness),
        ),
      ),
    ];
  }

  Widget _buildCorner(
    double? top,
    double? left,
    double size,
    Color color,
    double thickness,
    BorderRadius radius,
    Border border,
  ) {
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
              decoration: BoxDecoration(border: border, borderRadius: radius),
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
    final isLoading =
        _isScanning &&
        (_recognizedStudent == null || _recognizedStudent!.isEmpty);
    final isError =
        _recognizedStudent != null &&
        _recognizedStudent!.containsKey('error') &&
        _recognizedStudent!['error'] == true;
    final isSuccess =
        _recognizedStudent != null &&
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
                      if (!isSuccess && _classes.isNotEmpty) ...[
                        _buildClassSelector(theme, isDark),
                        const SizedBox(height: 16),
                      ],

                      // Show different content based on state
                      if (isShimmer) _buildShimmerContent(theme, isDark),
                      if (isLoading) _buildLoadingState(theme, isDark),
                      if (isError)
                        _buildErrorState(
                          _recognizedStudent!['message'] ?? 'Unknown error',
                          theme,
                          isDark,
                        ),
                      if (isSuccess) ...[
                        _buildAnimatedProfileHeader(
                          _recognizedStudent!,
                          theme,
                          isDark,
                        ),
                        const SizedBox(height: 20),
                        _buildAnimatedStatsGrid(now, theme, isDark),
                        const SizedBox(height: 16),
                        _buildAnimatedActionButtons(
                          _recognizedStudent!,
                          theme,
                          isDark,
                        ),
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

  Widget _buildClassSelector(ThemeData theme, bool isDark) {
    return DropdownButtonFormField<int?>(
      value: _selectedClassId,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.class_),
        labelText: "Class (optional)",
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF6F7F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text("All Classes")),
        ..._classes.map((c) {
          final rawId = c['id'];
          final int? id = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '');
          if (id == null) return null;
          final name = (c['class_name'] ?? c['name'] ?? 'Class').toString();
          return DropdownMenuItem<int?>(value: id, child: Text(name));
        }).whereType<DropdownMenuItem<int?>>(),
      ],
      onChanged: _isScanning
          ? null
          : (v) => setState(() => _selectedClassId = v),
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
                if (isError)
                  _buildErrorState(
                    student['message'] ?? 'Unknown error',
                    theme,
                    isDark,
                  ),
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
                      Theme.of(context).colorScheme.primary.withOpacity(
                        0.35 + pulseValue * 0.15,
                      ),
                      Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    ]
                  : [
                      isDark ? Colors.grey[800]! : Colors.grey[300]!,
                      isDark ? Colors.grey[600]! : Colors.grey[100]!,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
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

  Widget _buildAnimatedProfileHeader(
    Map<String, dynamic> student,
    ThemeData theme,
    bool isDark,
  ) {
    final isMarked = student['attendance_marked'] == true;
    final studentName =
        (student['full_name'] ??
                student['student_name'] ??
                student['name'] ??
                'Unknown')
            .toString();
    final studentIdLabel =
        (student['student_student_id'] ??
                student['studentId'] ??
                student['student_id'] ??
                'N/A')
            .toString();
    final classId =
        _asInt(student['class_id'] ?? student['classId']) ?? _selectedClassId;
    final className =
        (student['class_name'] ??
                student['className'] ??
                _classNameForId(classId) ??
                'Class N/A')
            .toString();

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
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child:
                        ApiService.uploadsUrl(
                              student['photo_path']?.toString(),
                            ) ==
                            null
                        ? Icon(
                            Icons.person,
                            size: 32,
                            color: theme.colorScheme.primary,
                          )
                        : Image.network(
                            ApiService.uploadsUrl(
                              student['photo_path']?.toString(),
                            )!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                  ),
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
                        child: const Icon(
                          Icons.check,
                          size: 12,
                          color: Colors.white,
                        ),
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
                  studentName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "ID: $studentIdLabel",
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (isMarked ? Colors.green : theme.colorScheme.primary)
                        .withOpacity(isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isMarked ? "PRESENT" : "MATCH",
                    style: TextStyle(
                      color: isMarked
                          ? (isDark ? Colors.green[300] : Colors.green[700])
                          : (isDark ? Colors.blue[200] : Colors.blue[700]),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  className,
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
              value:
                  "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
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

  Widget _buildAnimatedActionButtons(
    Map<String, dynamic> student,
    ThemeData theme,
    bool isDark,
  ) {
    final disableGoingIn = _lockToGoingOut || _checkInType == 'outing';
    final isMarked = student['attendance_marked'] == true;
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
                      label: const Text("Going In"),
                      selected: _checkInType == 'morning',
                      onSelected: disableGoingIn
                          ? null
                          : (selected) {
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
                        setState(() {
                          _checkInType = 'outing';
                          _lockToGoingOut = true;
                        });
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: isMarked
                      ? null
                      : () async {
                          final studentDbId =
                              _asInt(student['id']) ??
                              _asInt(student['student_id']);
                          final classId =
                              _asInt(
                                student['class_id'] ?? student['classId'],
                              ) ??
                              _selectedClassId;
                          if (studentDbId == null || classId == null) {
                            UIHelpers.showError(
                              context,
                              "Missing student/class info. Please try scanning again.",
                            );
                            return;
                          }

                          final result = await ApiService.markAttendance({
                            'student_id': studentDbId,
                            'class_id': classId,
                            'confidence_score':
                                student['confidence_score'] ??
                                student['confidenceScore'],
                            'check_in_type': _checkInType,
                          });

                          if (!mounted) return;
                          if (result['success'] == true) {
                            setState(() {
                              _recognizedStudent = {
                                ...student,
                                'attendance_marked': true,
                                'class_id': classId,
                              };
                            });
                            UIHelpers.showSuccess(
                              context,
                              "Attendance confirmed!",
                            );
                          } else {
                            UIHelpers.showError(
                              context,
                              result['error'] ?? 'Failed to confirm',
                            );
                          }
                        },
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(
                    isMarked ? "Already Present" : "Confirm Attendance",
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                    shadowColor: theme.colorScheme.primary.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  String? _classNameForId(int? classId) {
    if (classId == null) return null;
    for (final c in _classes) {
      if (_asInt(c['id']) == classId) {
        return (c['class_name'] ?? c['name'])?.toString();
      }
    }
    return null;
  }
}
