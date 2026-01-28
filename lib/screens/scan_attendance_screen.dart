import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/ui_helpers.dart';

class ScanAttendanceScreen extends StatefulWidget {
  const ScanAttendanceScreen({super.key});

  @override
  State<ScanAttendanceScreen> createState() => _ScanAttendanceScreenState();
}

class _ScanAttendanceScreenState extends State<ScanAttendanceScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  CameraLensDirection _cameraDirection = CameraLensDirection.front;
  bool _isChangingCamera = false;
  bool _lifecyclePaused = false;
  late AnimationController _scanAnimationController;

  // ML Kit Face Detection
  FaceDetector? _faceDetector;
  bool _isDetectingFaces = false;
  bool _isProcessingImage = false;

  // Real-time feedback state
  bool _isFaceValid = false;
  bool _isLivenessVerified = false;
  bool _faceDetected = false;
  bool _isSmiling = false; // Smile detection for liveness
  String _guidanceMessage = "Position your face in the frame";

  // Auto-capture state
  DateTime? _lastCaptureTime;
  int _readyFrameCount = 0;
  static const _requiredReadyFrames = 2;
  static const _autoCaptureCooldown = Duration(milliseconds: 900);

  bool _isScanning = false;
  Map<String, dynamic>? _recognizedStudent;
  bool _showShimmer = true; // Initially show shimmer scanning state
  bool _multipleCheckinsEnabled = false;
  String _checkInType = 'morning';
  DateTime? _lastFrameProcessed;
  static const Duration _frameProcessingInterval = Duration(milliseconds: 150);

  // Performance: limiting recognition to a class reduces server search space
  bool _isClassesLoading = false;
  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId;

  // UX/perf: single-call marking (like "one step") when enabled
  static const String _autoMarkKey = 'scan_auto_mark_attendance';
  static const String _selectedClassKey = 'scan_selected_class_id';
  bool _autoMarkAttendance = false;
  static const String _requireSmileKey = 'scan_require_smile_liveness';
  bool _requireSmileForLiveness = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFaceDetector();
    _initializeCamera();
    _loadCheckinSettings();
    _loadScanPreferences();
    _loadClasses();

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _handleCameraPause();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _handleCameraResume();
    }
  }

  Future<void> _handleCameraPause() async {
    if (_lifecyclePaused) return;
    _lifecyclePaused = true;

    try {
      await _stopFaceDetection();
      await _cameraController?.dispose();
      _cameraController = null;
    } catch (e) {
      debugPrint('Camera pause error: $e');
    }

    if (!mounted) return;
    setState(() => _isCameraInitialized = false);
  }

  Future<void> _handleCameraResume() async {
    if (!_lifecyclePaused) return;
    _lifecyclePaused = false;
    if (!mounted) return;

    await _initializeCamera();
  }

  void _loadCheckinSettings() {
    final enabled = StorageService.getBool(
      'settings_multiple_checkins',
      defaultValue: false,
    );
    setState(() {
      _multipleCheckinsEnabled = enabled;
    });
  }

  void _loadScanPreferences() {
    _autoMarkAttendance = StorageService.getBool(
      _autoMarkKey,
      defaultValue: false,
    );
    _requireSmileForLiveness = StorageService.getBool(
      _requireSmileKey,
      defaultValue: false,
    );
    final storedClassId = StorageService.getString(_selectedClassKey);
    _selectedClassId = storedClassId == null
        ? null
        : int.tryParse(storedClassId);
  }

  Future<void> _loadClasses() async {
    if (_isClassesLoading) return;
    if (!mounted) return;
    setState(() => _isClassesLoading = true);

    final result = await ApiService.getClasses();
    if (!mounted) return;

    if (result['success'] == true) {
      final classes = List<Map<String, dynamic>>.from(
        result['data'] ?? <dynamic>[],
      );
      int? selected = _selectedClassId;

      if (selected != null && classes.every((c) => c['id'] != selected)) {
        selected = null;
      }
      // Default to first available class for faster matching
      selected ??= classes.isNotEmpty ? (classes.first['id'] as int?) : null;

      setState(() {
        _classes = classes;
        _selectedClassId = selected;
        _isClassesLoading = false;
      });

      if (selected != null) {
        await StorageService.saveString(_selectedClassKey, selected.toString());
      }

      return;
    }

    setState(() => _isClassesLoading = false);
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    if (_isChangingCamera) return;
    _isChangingCamera = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == _cameraDirection,
        orElse: () => cameras.first,
      );

      await _stopFaceDetection();
      await _cameraController?.dispose();

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startFaceDetection();
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    } finally {
      _isChangingCamera = false;
    }
  }

  Future<void> _flipCamera() async {
    if (_isScanning || _isChangingCamera) return; // Don't flip while scanning

    // Toggle camera direction
    setState(() {
      _cameraDirection = _cameraDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      _isCameraInitialized = false;
    });

    // Reinitialize with new direction
    await _initializeCamera();
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

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

  Future<void> _stopFaceDetection() async {
    _isDetectingFaces = false;
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.stopImageStream();
      } catch (e) {
        debugPrint('Stop image stream error: $e');
      }
    }
  }

  Future<void> _processImageForFaceDetection(CameraImage image) async {
    if (_faceDetector == null || _isProcessingImage) return;

    _isProcessingImage = true;

    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _isProcessingImage = false;
        return;
      }

      final faces = await _faceDetector!.processImage(inputImage);

      if (!mounted) {
        _isProcessingImage = false;
        return;
      }

      _updateFaceLogic(faces);
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

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      if (image.planes.isEmpty) return null;
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
      return null;
    }
  }

  void _updateFaceLogic(List<Face> faces) {
    if (!mounted) return;

    setState(() {
      if (faces.isEmpty) {
        _faceDetected = false;
        _isFaceValid = false;
        _isSmiling = false;
        _readyFrameCount = 0;
        _guidanceMessage = "Position your face in the frame";
        return;
      }

      final face = faces.first;
      _faceDetected = true;

      // Face validation
      final headAngleY = face.headEulerAngleY ?? 0;
      final headAngleZ = face.headEulerAngleZ ?? 0;
      final smileProbability = face.smilingProbability ?? 0.0;

      bool isHeadStraight = headAngleY.abs() <= 20 && headAngleZ.abs() <= 15;
      _isSmiling = smileProbability > 0.6;

      // Fast mode (FaceID-style): no smile required.
      // Optional smile requirement can be enabled for basic liveness checking.
      _isLivenessVerified = !_requireSmileForLiveness || _isSmiling;
      _isFaceValid = isHeadStraight && _isLivenessVerified;

      // Update guidance message
      if (!isHeadStraight) {
        _guidanceMessage = "Look straight at the camera";
        _readyFrameCount = 0;
      } else if (_requireSmileForLiveness && !_isSmiling) {
        _guidanceMessage = "😊 Please smile to verify";
        _readyFrameCount = 0;
      } else if (_isFaceValid) {
        _guidanceMessage = "Perfect! Hold steady...";
        _readyFrameCount++;

        if (_readyFrameCount >= _requiredReadyFrames && !_isScanning) {
          final now = DateTime.now();
          final canCapture =
              _lastCaptureTime == null ||
              now.difference(_lastCaptureTime!) > _autoCaptureCooldown;

          if (canCapture && _recognizedStudent == null) {
            _lastCaptureTime = now;
            _readyFrameCount = 0;
            Future.microtask(() => _identifyFace());
          }
        }
      }
    });
  }

  Future<void> _identifyFace() async {
    if (_isScanning) return;

    if (!mounted) return;
    setState(() {
      _isScanning = true;
    });

    try {
      // 1. Stop Stream
      await _stopFaceDetection();
      await Future.delayed(const Duration(milliseconds: 200)); // stabilized

      // 2. Capture
      final XFile photo = await _cameraController!.takePicture();

      // 3. API Call (Global Search)
      final result = await ApiService.verifyFace(
        imageFile: File(photo.path),
        classId: _selectedClassId,
        autoMark: _autoMarkAttendance,
        checkInType: _checkInType,
      );

      if (!mounted) return;

      if (result['success'] && result['data'] != null) {
        final data = Map<String, dynamic>.from(result['data'] as Map);
        debugPrint('✅ Face Identified: $data');

        // Defensive: backend can sometimes return success without a valid match
        final hasStudentId =
            data['student_id'] != null || data['student_student_id'] != null;
        final hasClassId = data['class_id'] != null;

        if (!hasStudentId || !hasClassId) {
          setState(() {
            _recognizedStudent = {
              'error': true,
              'message': "This person is not registered in the system",
            };
            _showShimmer = false;
            _isScanning = false;
          });
          return;
        }

        setState(() {
          _recognizedStudent = data;
          _showShimmer = false;
          _isScanning = false;
        });

        if (_autoMarkAttendance == true && data['attendance_marked'] == true) {
          UIHelpers.showSuccess(context, "Attendance marked");
        }

        // Don't restart scanning immediately, wait for user action
      } else {
        // Check if we have confidence score and threshold information
        final data = result['data'];
        final confidenceScore = data?['confidence_score'];
        final threshold = data?['threshold'];

        String errorMessage = 'Face not recognized';

        // If we have both confidence and threshold, show detailed message
        if (confidenceScore != null && threshold != null) {
          final confidencePercent = (confidenceScore * 100).toStringAsFixed(0);
          final thresholdPercent = (threshold * 100).toStringAsFixed(0);
          errorMessage =
              'Low confidence: $confidencePercent% (required: $thresholdPercent%)';
        } else if (data?['message'] != null) {
          errorMessage = data['message'];
        }

        debugPrint('❌ Face Not Recognized: $errorMessage');
        setState(() {
          _recognizedStudent = {
            'error': true,
            'message': errorMessage,
            'confidence_score': confidenceScore,
            'threshold': threshold,
          };
          _showShimmer = false; // Show error state
          _isScanning = false;
        });

        // Auto-retry after delay if not recognized
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted &&
              _recognizedStudent != null &&
              _recognizedStudent!['error'] == true) {
            _resetScan();
          }
        });
      }
    } catch (e) {
      debugPrint('Scan Error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          // Don't show critical error, just resume
          if (_recognizedStudent == null) _showShimmer = true;
        });
        _resetScan();
      }
    }
  }

  void _resetScan() {
    setState(() {
      _recognizedStudent = null;
      _showShimmer = true;
      _readyFrameCount = 0;
      _isScanning = false;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _startFaceDetection();
    });
  }

  Widget _buildScanOptions(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedClassId,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.class_),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : theme.cardColor,
                  hintText: "Select Class (faster)",
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text("All Classes (slower)"),
                  ),
                  ..._classes.map(
                    (c) => DropdownMenuItem<int>(
                      value: c['id'],
                      child: Text(c['class_name'] ?? c['name'] ?? 'Class'),
                    ),
                  ),
                ],
                onChanged: _isClassesLoading
                    ? null
                    : (v) async {
                        setState(() => _selectedClassId = v);
                        if (v == null) {
                          await StorageService.removeString(_selectedClassKey);
                        } else {
                          await StorageService.saveString(
                            _selectedClassKey,
                            v.toString(),
                          );
                        }
                      },
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: _isClassesLoading ? null : _loadClasses,
              icon: _isClassesLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              style: IconButton.styleFrom(
                backgroundColor: isDark ? Colors.white10 : theme.cardColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: _autoMarkAttendance,
          onChanged: (v) async {
            setState(() => _autoMarkAttendance = v);
            await StorageService.saveBool(_autoMarkKey, v);
          },
          title: const Text("Auto mark attendance"),
          subtitle: const Text("Faster: mark in the same scan"),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile.adaptive(
          value: _requireSmileForLiveness,
          onChanged: (v) async {
            setState(() => _requireSmileForLiveness = v);
            await StorageService.saveBool(_requireSmileKey, v);
          },
          title: const Text("Require smile (liveness)"),
          subtitle: const Text("More secure, but slower"),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Future<void> _confirmAttendance() async {
    if (_recognizedStudent == null || _recognizedStudent!['class_id'] == null)
      return;

    // Double check if already marked (prevent UI race condition)
    if (_recognizedStudent!['attendance_marked'] == true) {
      if (mounted) {
        UIHelpers.showWarning(context, "Attendance already marked for today");
      }
      return;
    }

    try {
      setState(() => _isScanning = true); // Show loading

      final result = await ApiService.markAttendance({
        'student_id': _recognizedStudent!['student_id'],
        'class_id': _recognizedStudent!['class_id'],
        'confidence_score': _recognizedStudent!['confidence_score'] ?? 0.0,
        'check_in_type': _checkInType,
      });

      if (mounted) {
        if (result['success']) {
          // Success
          UIHelpers.showSuccess(context, "Attendance Confirmed!");
          setState(() {
            _recognizedStudent!['attendance_marked'] = true;
            _isScanning = false;
          });

          final container = ProviderScope.containerOf(
            context,
            listen: false,
          );
          final refresh = container.read(attendanceRefreshProvider.notifier);
          refresh.state = refresh.state + 1;

          // Auto reset after success
          Future.delayed(const Duration(seconds: 2), _resetScan);
        } else {
          // Check if error is about duplicate attendance
          final errorMsg = result['error']?.toString().toLowerCase() ?? '';
          if (errorMsg.contains('already marked') ||
              errorMsg.contains('already present')) {
            // Update UI to reflect already marked state
            setState(() {
              _recognizedStudent!['attendance_marked'] = true;
              _isScanning = false;
            });
            UIHelpers.showWarning(
              context,
              "This student's attendance was already marked today",
            );
          } else {
            setState(() => _isScanning = false);
            UIHelpers.showError(
              context,
              result['error'] ?? "Failed to mark attendance",
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        UIHelpers.showError(context, "Failed to mark: $e");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFaceDetection();
    _cameraController?.dispose();
    _faceDetector?.close();
    _scanAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF101922)
          : const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      "Mark Attendance",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline),
                    onPressed: () {},
                    style: IconButton.styleFrom(
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                ],
              ),
            ),

            // Camera Area
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Camera
                    if (_isCameraInitialized) CameraPreview(_cameraController!),

                    // Gradient
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
                        ),
                      ),
                    ),

                    // Status Badge (Dynamic)
                    Positioned(
                      top: 24,
                      left: 0,
                      right: 0,
                      child: Center(child: _buildStatusBadge()),
                    ),

                    // Face Frame & Scanner
                    Center(child: _buildFaceFrame()),

                    // Flip Camera Button (top-right)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _flipCamera,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.flip_camera_android,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Guidance Text
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isFaceValid
                                ? Colors.green.withOpacity(0.5)
                                : Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isFaceValid
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              color: _isFaceValid
                                  ? Colors.green
                                  : Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _guidanceMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _isFaceValid
                                    ? Colors.green[300]
                                    : Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: _isFaceValid
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Sheet
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * 0.46),
              child: _buildResultSheet(theme, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    bool isRecognized =
        _recognizedStudent != null && _recognizedStudent!['error'] != true;
    bool isError =
        _recognizedStudent != null && _recognizedStudent!['error'] == true;

    if (!isRecognized && !isError)
      return const SizedBox.shrink(); // Hide if neutral/scanning

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRecognized ? Icons.check_circle : Icons.cancel,
            color: isRecognized ? Colors.greenAccent : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isRecognized ? "Face Recognized" : "Face Not Recognized",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceFrame() {
    double frameSize = 280;
    Color borderColor = Colors.white24;

    if (_recognizedStudent != null) {
      borderColor = _recognizedStudent!['error'] == true
          ? Colors.red
          : Colors.green;
    } else if (_faceDetected) {
      borderColor = Colors.blue;
    }

    return SizedBox(
      width: frameSize,
      height: frameSize,
      child: Stack(
        children: [
          // Borders
          // simplified borders using Container with border is okay,
          // or CustomPainter for corners. Using Container for simplicity matching design
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  // Scanner Logic
                  if (_showShimmer)
                    AnimatedBuilder(
                      animation: _scanAnimationController,
                      builder: (context, child) {
                        return Positioned(
                          top: frameSize * _scanAnimationController.value,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          // Corners (Absolute placement)
          // Top Left
          Positioned(
            top: 0,
            left: 0,
            child: _buildCorner(borderColor, true, true),
          ),
          // Top Right
          Positioned(
            top: 0,
            right: 0,
            child: _buildCorner(borderColor, true, false),
          ),
          // Bottom Left
          Positioned(
            bottom: 0,
            left: 0,
            child: _buildCorner(borderColor, false, true),
          ),
          // Bottom Right
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildCorner(borderColor, false, false),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(Color color, bool isTop, bool isLeft) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: isTop ? BorderSide(color: color, width: 4) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: 4) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: isTop && isLeft ? const Radius.circular(16) : Radius.zero,
          topRight: isTop && !isLeft ? const Radius.circular(16) : Radius.zero,
          bottomLeft: !isTop && isLeft
              ? const Radius.circular(16)
              : Radius.zero,
          bottomRight: !isTop && !isLeft
              ? const Radius.circular(16)
              : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildResultSheet(ThemeData theme, bool isDark) {
    // If shimmer is active or no result yet, show shimmer
    if (_showShimmer || (_recognizedStudent == null)) {
      // While scanning, avoid showing placeholder UI that looks like a student card.
      // If there is currently NO face in frame, show a simple red message only.
      if (!_faceDetected) {
        return _buildSimpleRedMessageSheet(isDark, "No face detected");
      }
      return _buildShimmerSheet(isDark);
    }

    // Result
    final student = _recognizedStudent!;
    final isError = student['error'] == true;

    if (isError) {
      return _buildErrorSheet(isDark, student['message']);
    }

    final studentName = student['student_name'] ?? 'Unknown';
    final studentId =
        student['student_student_id'] ??
        student['student_id']?.toString() ??
        'N/A';
    final photoPath = student['photo_path'];
    final isMarked = student['attendance_marked'] == true;

    // Format Time
    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(now);
    final dateStr = DateFormat('MMM dd').format(now);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScanOptions(theme, isDark),
            const SizedBox(height: 16),
            // Warning Banner if Already Marked
            if (isMarked)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "This student's attendance was already marked today",
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Student Profile
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isMarked ? Colors.orange : Colors.blueAccent,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child:
                          ApiService.uploadsUrl(photoPath?.toString()) == null
                          ? const Center(child: Icon(Icons.person))
                          : Image.network(
                              ApiService.uploadsUrl(photoPath?.toString())!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Center(child: Icon(Icons.person)),
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
                        studentName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "ID: $studentId",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isMarked
                            ? Colors.orange.withOpacity(0.1)
                            : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMarked ? Icons.event_available : Icons.verified,
                            size: 14,
                            color: isMarked ? Colors.orange[700] : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMarked ? "PRESENT" : "MATCH",
                            style: TextStyle(
                              color: isMarked
                                  ? Colors.orange[700]
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Stats
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    Icons.schedule,
                    "Time In",
                    timeStr,
                    isDark,
                    Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildInfoCard(
                    Icons.calendar_today,
                    "Date",
                    dateStr,
                    isDark,
                    Colors.orangeAccent,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Action Buttons
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
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _resetScan,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Icon(Icons.refresh),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (isMarked || _isScanning)
                        ? null
                        : () => _confirmAttendance(),
                    icon: _isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(isMarked ? Icons.check_circle : Icons.check),
                    label: Text(
                      _isScanning
                          ? "Processing..."
                          : (isMarked
                                ? "Already Present Today"
                                : "Confirm Attendance"),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isMarked
                          ? Colors.grey
                          : Colors.blueAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.5),
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: isMarked ? 0 : 4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String label,
    String value,
    bool isDark,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleRedMessageSheet(bool isDark, String message) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScanOptions(theme, isDark),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_off_outlined,
                size: 44,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerSheet(bool isDark) {
    final theme = Theme.of(context);
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScanOptions(theme, isDark),
            const SizedBox(height: 16),
            // Profile Shimmer
            Row(
              children: [
                _shimmerBox(64, 64, baseColor, isCircle: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shimmerBox(150, 24, baseColor),
                      const SizedBox(height: 8),
                      _shimmerBox(100, 16, baseColor),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Stats Shimmer
            Row(
              children: [
                Expanded(child: _shimmerBox(double.infinity, 80, baseColor)),
                const SizedBox(width: 16),
                Expanded(child: _shimmerBox(double.infinity, 80, baseColor)),
              ],
            ),
            const SizedBox(height: 24),
            // Button Shimmer
            _shimmerBox(double.infinity, 56, baseColor),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSheet(bool isDark, String message) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScanOptions(theme, isDark),
            const SizedBox(height: 16),
            // Error Icon with background
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_off_outlined,
                size: 48,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Face Not Recognized",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "This person is not registered in the system",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Helpful Tips Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: Colors.amber[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Quick Tips",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber[700],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTipItem(
                    Icons.wb_sunny_outlined,
                    "Ensure good lighting on your face",
                  ),
                  const SizedBox(height: 8),
                  _buildTipItem(
                    Icons.center_focus_strong,
                    "Position face within the frame",
                  ),
                  const SizedBox(height: 8),
                  _buildTipItem(
                    Icons.person_add_outlined,
                    "Register first if you're a new student",
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pushReplacementNamed('/register-student');
                    },
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text("Register"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _resetScan,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Scan Again"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
      ),
    );
  }

  Widget _buildTipItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _shimmerBox(
    double width,
    double height,
    Color color, {
    bool isCircle = false,
  }) {
    // Since no shimmer package, just a static placeholder with opacity or implicit animation
    // For improved experience, we can use a TweenAnimationBuilder for opacity
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(seconds: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: isCircle ? null : BorderRadius.circular(12),
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            ),
          ),
        );
      },
      onEnd: () {}, // loop handled by parent? No, simple pulse
    );
  }
}
