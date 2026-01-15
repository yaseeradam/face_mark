import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class RegisterStudentScreen extends StatefulWidget {
  const RegisterStudentScreen({super.key});

  @override
  State<RegisterStudentScreen> createState() => _RegisterStudentScreenState();
}

class _RegisterStudentScreenState extends State<RegisterStudentScreen> 
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _nameController = TextEditingController();
  
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  late AnimationController _scanAnimationController;
  late AnimationController _successPulseController;
  late Animation<double> _successPulseAnimation;
  
  // ML Kit Face Detection
  FaceDetector? _faceDetector;
  bool _isDetectingFaces = false;
  bool _isProcessingImage = false;
  
  // Real-time feedback
  String _faceGuidanceMessage = "Position your face in the frame";
  Color _faceGuidanceColor = Colors.white70;
  bool _isFaceValid = false;
  bool _isLivenessVerified = false;
  bool _faceDetected = false;
  
  // Auto-capture state
  DateTime? _lastCaptureTime;
  int _readyFrameCount = 0;
  static const _requiredReadyFrames = 5;
  static const _autoCaptureCooldown = Duration(seconds: 5);
  
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isRegistering = false;
  XFile? _capturedPhoto; // Store captured photo for preview

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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
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
  
  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    _isDetectingFaces = true;
    _cameraController!.startImageStream((CameraImage image) {
      if (!_isDetectingFaces || _isProcessingImage || _isRegistering) return;
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
      
      bool isHeadStraight = headAngleY != null && headAngleZ != null &&
                           headAngleY.abs() <= 15 && headAngleZ.abs() <=10;
      bool eyesOpen = leftEyeOpen != null && rightEyeOpen != null &&
                     leftEyeOpen > 0.5 && rightEyeOpen > 0.5;
      
      _isFaceValid = isHeadStraight && eyesOpen;
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
        
        if (_readyFrameCount >= _requiredReadyFrames && 
            !_isRegistering && 
            _formKey.currentState != null &&
            _formKey.currentState!.validate() &&
            _selectedClassId != null) {
          final now = DateTime.now();
          final canCapture = _lastCaptureTime == null || 
                           now.difference(_lastCaptureTime!) > _autoCaptureCooldown;
          
          if (canCapture) {
            _faceGuidanceMessage = "Capturing...";
            _faceGuidanceColor = Colors.blue;
            _lastCaptureTime = now;
            _readyFrameCount = 0;
            
            Future.microtask(() => _handleRegistration());
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
        _readyFrameCount = 0;
      }
    });
  }

  @override
  void dispose() {
    _stopFaceDetection();
    _cameraController?.dispose();
    _faceDetector?.close();
    _scanAnimationController.dispose();
    _successPulseController.dispose();
    _studentIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate() || _selectedClassId == null) {
      UIHelpers.showWarning(context, "Please fill all fields and select a class");
      return;
    }

    if (!mounted) return;
    setState(() => _isRegistering = true);

    try {
      // Capture Face
      final XFile photo = await _cameraController!.takePicture();
      
      // Store photo for preview
      if (mounted) {
        setState(() => _capturedPhoto = photo);
      }
      
      // Register via API
      final result = await ApiService.registerStudent(
        studentId: _studentIdController.text,
        name: _nameController.text,
        classId: _selectedClassId!,
        imageFile: File(photo.path),
      );

      if (!mounted) return;
      
      if (result['success']) {
        UIHelpers.showSuccess(context, "Student Registered Successfully!");
        if (mounted) Navigator.pop(context);
      } else {
        final errorMsg = result['error']?.toString() ?? 'Unknown error';
        UIHelpers.showError(context, "Registration Failed: $errorMsg");
        // Clear photo on error so user can retry
        if (mounted) {
          setState(() => _capturedPhoto = null);
        }
      }
    } catch (e) {
      if (mounted) {
        UIHelpers.showError(context, "Error: $e");
        setState(() => _capturedPhoto = null);
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
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
            // Top Navigation
            _buildTopNavigation(context, theme, isDark),
            
            // Camera Viewport (50%)
            Expanded(
              child: _buildCameraViewport(theme, isDark),
            ),
            
            // Form Bottom Sheet (50%) - ALWAYS VISIBLE
            Expanded(
              child: _buildFormBottomSheet(theme, isDark),
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
              "Register Student",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // Balance for symmetry
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
        // Real-time face feedback badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _faceGuidanceMessage,
                style: TextStyle(
                  color: _faceGuidanceColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        
        // Face Frame
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            border: Border.all(
              color: _isFaceValid && _isLivenessVerified
                  ? Colors.green.withOpacity(0.8)
                  : _faceDetected
                      ? Colors.orange.withOpacity(0.6)
                      : Colors.white.withOpacity(0.2),
              width: _isFaceValid && _isLivenessVerified ? 2.5 : 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // Scanning Line
              AnimatedBuilder(
                animation: _scanAnimationController,
                builder: (context, child) {
                  return Positioned(
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
                  );
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        Text(
          _isFaceValid && _isLivenessVerified
              ? "Ready! Fill the form below"
              : "Position your face in the frame",
          style: TextStyle(
            color: _isFaceValid && _isLivenessVerified
                ? Colors.green[300]
                : Colors.white70,
            fontSize: 14,
            fontWeight: _isFaceValid && _isLivenessVerified
                ? FontWeight.w600
                : FontWeight.w300,
          ),
        ),
      ],
    );
  }
  
  Widget _buildFormBottomSheet(ThemeData theme, bool isDark) {
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
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              
              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show captured photo as profile picture
                        if (_capturedPhoto != null)
                          Column(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.colorScheme.primary.withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.file(
                                    File(_capturedPhoto!.path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      "Photo Captured",
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        
                        TextFormField(
                          controller: _studentIdController,
                          decoration: const InputDecoration(
                            labelText: "Student ID",
                            prefixIcon: Icon(Icons.badge),
                          ),
                          validator: (v) => v!.isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: "Full Name",
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (v) => v!.isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: _selectedClassId,
                          decoration: const InputDecoration(
                            labelText: "Class",
                            prefixIcon: Icon(Icons.class_),
                          ),
                          items: _classes.map((c) => DropdownMenuItem<int>(
                            value: c['id'],
                            child: Text(c['class_name'] ?? c['name']),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedClassId = v),
                          validator: (v) => v == null ? "Required" : null,
                        ),
                        const SizedBox(height: 20),
                        
                        if (_isRegistering)
                          const Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text("Registering student..."),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
