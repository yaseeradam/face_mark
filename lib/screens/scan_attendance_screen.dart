import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class ScanAttendanceScreen extends StatefulWidget {
  const ScanAttendanceScreen({super.key});

  @override
  State<ScanAttendanceScreen> createState() => _ScanAttendanceScreenState();
}

class _ScanAttendanceScreenState extends State<ScanAttendanceScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  CameraLensDirection _cameraDirection = CameraLensDirection.front;
  late AnimationController _scanAnimationController;
  late AnimationController _cardSlideController;
  late AnimationController _successPulseController;
  late Animation<Offset> _cardSlideAnimation;
  late Animation<double> _successPulseAnimation;
  
  // ML Kit Face Detection
  FaceDetector? _faceDetector;
  bool _isDetectingFaces = false;
  bool _isProcessingImage = false;
  
  // Real-time feedback state
  String _faceGuidanceMessage = "Position your face in the frame";
  Color _faceGuidanceColor = Colors.white70;
  bool _isFaceValid = false;
  bool _isLivenessVerified = false;
  bool _faceDetected = false;
  
  // Auto-capture state
  DateTime? _lastCaptureTime;
  int _readyFrameCount = 0;
  static const _requiredReadyFrames = 3; // Reduced for faster capture
  static const _autoCaptureCooldown = Duration(seconds: 3); // Reduced cooldown
  
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isScanning = false;
  Map<String, dynamic>? _recognizedStudent;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _initializeFaceDetector();
    _initializeCamera();
    
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _cardSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardSlideController,
      curve: Curves.easeOutCubic,
    ));
    
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
  
  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _loadClasses() async {
    debugPrint('📚 Loading classes...');
    final result = await ApiService.getClasses();
    if (!mounted) return;
    
    if (result['success']) {
      final classes = List<Map<String, dynamic>>.from(result['data'] ?? []);
      debugPrint('📚 Loaded ${classes.length} classes');
      setState(() {
        _classes = classes;
        // Auto-select first class if none selected
        if (_selectedClassId == null && classes.isNotEmpty) {
          _selectedClassId = classes.first['id'];
          debugPrint('📚 Auto-selected class: $_selectedClassId');
        }
      });
    } else {
      debugPrint('❌ Failed to load classes: ${result['error']}');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == _cameraDirection,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _startFaceDetection();
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }
  
  Future<void> _flipCamera() async {
    if (_isScanning) return; // Don't flip while scanning
    
    // Stop detection and dispose current camera
    _stopFaceDetection();
    await _cameraController?.dispose();
    
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    _isDetectingFaces = true;
    _cameraController!.startImageStream((CameraImage image) {
      if (!_isDetectingFaces || _isProcessingImage || _isScanning) return;
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
      
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;
      
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
        _faceGuidanceMessage = "No face detected";
        _faceGuidanceColor = Colors.orange;
        _readyFrameCount = 0;
        return;
      }
      
      final face = faces.first;
      _faceDetected = true;
      
      final headAngleY = face.headEulerAngleY;
      final headAngleZ = face.headEulerAngleZ;
      final leftEyeOpen = face.leftEyeOpenProbability;
      final rightEyeOpen = face.rightEyeOpenProbability;
      
      // Make head angle check more lenient
      bool isHeadStraight = headAngleY != null && headAngleZ != null &&
                           headAngleY.abs() <= 20 && headAngleZ.abs() <= 15;
      
      // Make eye check optional - some cameras/conditions don't return this
      bool eyesOpen = true; // Default to true
      if (leftEyeOpen != null && rightEyeOpen != null) {
        eyesOpen = leftEyeOpen > 0.3 && rightEyeOpen > 0.3; // Lower threshold
      }
      
      debugPrint('👁️ Face: headY=${headAngleY?.toStringAsFixed(1)}, headZ=${headAngleZ?.toStringAsFixed(1)}, leftEye=$leftEyeOpen, rightEye=$rightEyeOpen, straight=$isHeadStraight, eyes=$eyesOpen');
      
      _isFaceValid = isHeadStraight;
      _isLivenessVerified = eyesOpen;
      
      if (!eyesOpen) {
        _faceGuidanceMessage = "Please open your eyes";
        _faceGuidanceColor = Colors.orange;
        _readyFrameCount = 0;
      } else if (!isHeadStraight) {
        _faceGuidanceMessage = "Please look straight";
        _faceGuidanceColor = Colors.orange;
        _readyFrameCount = 0;
      } else if (_isFaceValid && _isLivenessVerified) {
        _readyFrameCount++;
        debugPrint('📊 Ready frames: $_readyFrameCount / $_requiredReadyFrames, classId: $_selectedClassId, isScanning: $_isScanning');
        
        if (_readyFrameCount >= _requiredReadyFrames) {
          // Check if class is selected
          if (_selectedClassId == null) {
            _faceGuidanceMessage = "⚠️ Select a class first!";
            _faceGuidanceColor = Colors.red;
            _readyFrameCount = 0; // Reset to allow retry
          } else if (!_isScanning) {
            final now = DateTime.now();
            final canCapture = _lastCaptureTime == null || 
                             now.difference(_lastCaptureTime!) > _autoCaptureCooldown;
            
            if (canCapture) {
              debugPrint('🚀 TRIGGERING CAPTURE NOW!');
              _faceGuidanceMessage = "Capturing...";
              _faceGuidanceColor = Colors.blue;
              _lastCaptureTime = now;
              _readyFrameCount = 0;
              
              Future.microtask(() => _autoCaptureFace());
            } else {
              final remaining = _autoCaptureCooldown.inSeconds - now.difference(_lastCaptureTime!).inSeconds;
              _faceGuidanceMessage = "Ready! Wait ${remaining}s...";
              _faceGuidanceColor = Colors.green;
            }
          }
        } else {
          _faceGuidanceMessage = "Hold steady... ${_requiredReadyFrames - _readyFrameCount}";
          _faceGuidanceColor = Colors.green;
        }
      } else {
        _faceGuidanceMessage = "Hold steady...";
        _faceGuidanceColor = Colors.white70;
        _readyFrameCount = 0;
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
    _cardSlideController.dispose();
    _successPulseController.dispose();
    super.dispose();
  }

  Future<void> _scanFace() async {
    if (_selectedClassId == null) {
      UIHelpers.showWarning(context, "Please select a class first");
      return;
    }

    if (!mounted || _isScanning) return;
    
    setState(() {
      _isScanning = true;
      _recognizedStudent = {}; // Empty to show loading
    });
    
    _cardSlideController.forward();

    try {
      // IMPORTANT: Stop image stream before taking picture
      _stopFaceDetection();
      
      // Wait for stream to fully stop
      await Future.delayed(const Duration(milliseconds: 300));
      
      debugPrint('📸 Taking picture for face verification...');
      final XFile photo = await _cameraController!.takePicture();
      debugPrint('📸 Picture taken: ${photo.path}');
      
      debugPrint('🔍 Calling API to verify face for class $_selectedClassId');
      final result = await ApiService.verifyFace(
        classId: _selectedClassId!,
        imageFile: File(photo.path),
      );
      
      debugPrint('🔍 API Result: $result');

      if (!mounted) return;
      setState(() => _isScanning = false);

      if (result['success'] && result['data'] != null) {
        // Student recognized - show details
        debugPrint('✅ Student recognized: ${result['data']}');
        setState(() => _recognizedStudent = result['data']);
        
        _successPulseController.forward().then((_) {
          _successPulseController.reverse();
        });
        
        UIHelpers.showSuccess(context, "Attendance marked successfully!");
      } else {
        // Not recognized - show red error card
        debugPrint('❌ Face not recognized: ${result['error']}');
        setState(() {
          _recognizedStudent = {
            'error': true,
            'message': result['error'] ?? 'Face not recognized in database'
          };
        });
      }
      
      // Restart face detection after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _cameraController != null && _cameraController!.value.isInitialized) {
          _startFaceDetection();
        }
      });
      
    } catch (e) {
      debugPrint('❌ Scan Error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _recognizedStudent = {
            'error': true,
            'message': "Scan Error: ${e.toString()}"
          };
        });
        
        // Restart face detection
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _cameraController != null) {
            _startFaceDetection();
          }
        });
      }
    }
  }
  
  void _resetScan() {
    _cardSlideController.reverse();
    setState(() {
      _recognizedStudent = null;
      _readyFrameCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E2936) : Colors.white,
        elevation: 0,
        title: const Text(
          "Mark Attendance",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Class Selection
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2936) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: DropdownButtonFormField<int>(
                value: _selectedClassId,
                decoration: const InputDecoration(
                  labelText: "Select Class",
                  prefixIcon: Icon(Icons.class_),
                  border: InputBorder.none,
                ),
                items: _classes.map((c) => DropdownMenuItem<int>(
                  value: c['id'],
                  child: Text(c['class_name'] ?? c['name']),
                )).toList(),
                onChanged: (v) => setState(() => _selectedClassId = v),
              ),
            ),
            
            // Camera Viewport
            Expanded(
              flex: 5,
              child: _buildCameraViewport(theme, isDark),
            ),
            
            // Student Details Card (if recognized)
            Expanded(
              flex: 5,
              child: _buildStudentDetailsCard(theme, isDark),
            ),
          ],
        ),
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
            
            // Manual Scan Button (bottom center) - fallback if auto-capture doesn't work
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (_faceDetected && _selectedClassId != null && !_isScanning) 
                        ? _scanFace 
                        : null,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: (_faceDetected && _selectedClassId != null && !_isScanning)
                            ? Colors.green.withOpacity(0.9)
                            : Colors.grey.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isScanning ? Icons.hourglass_top : Icons.camera_alt,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isScanning ? "Scanning..." : "Scan Now",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningOverlay(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use 70% of available width, max 280
        final faceFrameSize = (constraints.maxWidth * 0.7).clamp(200.0, 280.0);
        
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Guidance Message
            if (_recognizedStudent == null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  border: Border.all(
                    color: _faceGuidanceColor.withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _faceDetected 
                          ? (_isFaceValid && _isLivenessVerified 
                              ? Icons.check_circle 
                              : Icons.info_outline)
                          : Icons.face_retouching_off,
                      color: _faceGuidanceColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _faceGuidanceMessage,
                        style: TextStyle(
                          color: _faceGuidanceColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Face Frame (dynamic size)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: faceFrameSize,
              height: faceFrameSize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _recognizedStudent != null
                      ? Colors.green.withOpacity(0.8)
                      : (_isFaceValid && _isLivenessVerified
                          ? Colors.green.withOpacity(0.8)
                          : _faceDetected
                              ? Colors.orange.withOpacity(0.6)
                              : Colors.white.withOpacity(0.2)),
                  width: _isFaceValid && _isLivenessVerified ? 2.5 : 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Scanning Line
                  if (_recognizedStudent == null)
                    AnimatedBuilder(
                      animation: _scanAnimationController,
                      builder: (context, child) {
                        return Positioned(
                          top: faceFrameSize * _scanAnimationController.value,
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
                                      ? Colors.green.withOpacity(0.8)
                                      : theme.colorScheme.primary.withOpacity(0.8),
                                  blurRadius: 10,
                                  spreadRadius: 1,
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
          ],
        );
      },
    );
  }
  
  Widget _buildStudentDetailsCard(ThemeData theme, bool isDark) {
    if (_recognizedStudent == null) {
      // Show placeholder
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2936) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.face_retouching_natural,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              "Scan a student's face",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Position face in the frame to identify",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    
    // Check if error
    final isError = _recognizedStudent!['error'] == true;
    
    return SlideTransition(
      position: _cardSlideAnimation,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2936) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: isError ? _buildErrorState(theme, isDark) : _buildSuccessState(theme, isDark),
      ),
    );
  }
  
  Widget _buildErrorState(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              size: 40,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Not Recognized",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _recognizedStudent!['message'] ?? 'Face not found in database',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _resetScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Try Again",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSuccessState(ThemeData theme, bool isDark) {
    if (_isScanning) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              "Verifying face...",
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }
    
    final student = _recognizedStudent!;
    final studentName = student['student_name'] ?? student['name'] ?? 'Unknown';
    final studentId = student['student_id'] ?? 'N/A';
    final confidenceScore = student['confidence_score'] ?? 0.0;
    final attendanceMarked = student['attendance_marked'] ?? false;
    final photoPath = student['photo_path'];
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Student Photo or Success Indicator
          ScaleTransition(
            scale: _successPulseAnimation,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 3),
                color: Colors.green.withOpacity(0.1),
              ),
              child: ClipOval(
                child: photoPath != null && photoPath.toString().isNotEmpty
                    ? Image.network(
                        '${ApiService.baseUrl}/uploads/$photoPath',
                        fit: BoxFit.cover,
                        errorBuilder: (c, o, s) => const Icon(
                          Icons.check_circle,
                          size: 50,
                          color: Colors.green,
                        ),
                      )
                    : const Icon(
                        Icons.check_circle,
                        size: 50,
                        color: Colors.green,
                      ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Student Name
          Text(
            studentName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          // Student ID
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "ID: $studentId",
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Details Grid
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  Icons.verified,
                  "Confidence",
                  "${(confidenceScore * 100).toStringAsFixed(1)}%",
                  theme,
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  attendanceMarked ? Icons.check_circle : Icons.info_outline,
                  "Status",
                  attendanceMarked ? "Attendance Marked" : "Already Marked",
                  theme,
                  valueColor: attendanceMarked ? Colors.green : Colors.orange,
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  Icons.access_time,
                  "Time",
                  "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                  theme,
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _resetScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Scan Next Student",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(IconData icon, String label, String value, ThemeData theme, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? theme.textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }
}
