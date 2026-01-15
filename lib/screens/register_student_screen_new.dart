import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/api_service.dart';
import '../providers/app_providers.dart';
import '../utils/ui_helpers.dart';

class RegisterStudentScreenNew extends ConsumerStatefulWidget {
  const RegisterStudentScreenNew({super.key});

  @override
  ConsumerState<RegisterStudentScreenNew> createState() => _RegisterStudentScreenNewState();
}

// Liveness challenge types
enum LivenessChallenge { blink, smile, turnHead }

class _RegisterStudentScreenNewState extends ConsumerState<RegisterStudentScreenNew> 
    with TickerProviderStateMixin {
  // Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _nameController = TextEditingController();
  
  // Camera & Face Detection
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  CameraLensDirection _cameraDirection = CameraLensDirection.front; // Start with front camera
  FaceDetector? _faceDetector;
  bool _isDetectingFaces = false;
  bool _isProcessingImage = false;
  
  // Animation Controllers
  late AnimationController _scanAnimationController;
  late AnimationController _successPulseController;
  late Animation<double> _successPulseAnimation;
  
  // Liveness Challenge State
  final List<LivenessChallenge> _challenges = [
    LivenessChallenge.blink,
    LivenessChallenge.smile,
    LivenessChallenge.turnHead,
  ];
  int _currentChallengeIndex = 0;
  List<bool> _challengeCompleted = [false, false, false];
  bool _isScanningPhase = true; // true = scanning, false = form filling
  bool _isCapturing = false;
  
  // Blink detection state
  bool _previousEyesClosed = false;
  bool _blinkDetected = false;
  
  // Smile detection state
  bool _smileDetected = false;
  
  // Head turn detection state
  bool _headTurnDetected = false;
  bool _wasHeadCentered = false;
  
  // Face capture after challenges
  List<XFile> _capturedFaces = [];
  int _currentScanCount = 0;
  final int _requiredScans = 1; // Only 1 scan needed after challenges
  
  // Face Detection Feedback
  String _faceGuidanceMessage = "Position your face in the frame";
  Color _faceGuidanceColor = Colors.white70;
  bool _isFaceValid = false;
  bool _isLivenessVerified = false;
  bool _faceDetected = false;
  int _readyFrameCount = 0;
  static const _requiredReadyFrames = 5; // Faster after liveness verified
  
  // Form State
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isRegistering = false;
  
  // Helper getters
  LivenessChallenge get _currentChallenge => _challenges[_currentChallengeIndex];
  bool get _allChallengesCompleted => _challengeCompleted.every((c) => c);

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
      performanceMode: FaceDetectorMode.accurate, // More accurate for registration
      minFaceSize: 0.2, // Larger face required
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
      
      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == _cameraDirection,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium, // Medium for better performance
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
  
  Future<void> _flipCamera() async {
    if (_isCapturing) return; // Don't flip while capturing
    
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
      if (!_isDetectingFaces || _isProcessingImage || _isCapturing || !_isScanningPhase) return;
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
        _previousEyesClosed = false;
        return;
      }
      
      final face = faces.first;
      _faceDetected = true;
      
      final headAngleY = face.headEulerAngleY ?? 0;
      final headAngleZ = face.headEulerAngleZ ?? 0;
      final leftEyeOpen = face.leftEyeOpenProbability ?? 0.5;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 0.5;
      final smileProbability = face.smilingProbability ?? 0.0;
      
      bool isHeadStraight = headAngleY.abs() <= 15 && headAngleZ.abs() <= 10;
      bool eyesClosed = leftEyeOpen < 0.3 && rightEyeOpen < 0.3;
      bool eyesOpen = leftEyeOpen > 0.5 && rightEyeOpen > 0.5;
      bool isSmiling = smileProbability > 0.7;
      bool headTurned = headAngleY.abs() > 25;
      bool headCentered = headAngleY.abs() <= 15;
      
      // If all challenges completed, proceed to capture
      if (_allChallengesCompleted) {
        _isFaceValid = isHeadStraight && eyesOpen;
        _isLivenessVerified = true;
        
        if (_isFaceValid && !_isCapturing) {
          _readyFrameCount++;
          if (_readyFrameCount >= _requiredReadyFrames) {
            _faceGuidanceMessage = "Perfect! Capturing...";
            _faceGuidanceColor = Colors.green;
            Future.microtask(() => _captureFace());
          } else {
            _faceGuidanceMessage = "Hold steady... ${_requiredReadyFrames - _readyFrameCount}";
            _faceGuidanceColor = Colors.green;
          }
        } else if (!_isFaceValid) {
          _faceGuidanceMessage = "Look straight at the camera";
          _faceGuidanceColor = Colors.orange;
          _readyFrameCount = 0;
        }
        return;
      }
      
      // Process current challenge
      switch (_currentChallenge) {
        case LivenessChallenge.blink:
          // Blink detection: eyes must close then reopen
          if (eyesClosed && !_previousEyesClosed) {
            _previousEyesClosed = true;
          } else if (eyesOpen && _previousEyesClosed) {
            // Blink completed!
            _blinkDetected = true;
            _challengeCompleted[_currentChallengeIndex] = true;
            _previousEyesClosed = false;
            _advanceToNextChallenge();
          }
          
          if (!_blinkDetected) {
            _faceGuidanceMessage = "👁️ Please blink your eyes";
            _faceGuidanceColor = Colors.blue;
          }
          break;
          
        case LivenessChallenge.smile:
          if (isSmiling) {
            _smileDetected = true;
            _challengeCompleted[_currentChallengeIndex] = true;
            _advanceToNextChallenge();
          } else {
            _faceGuidanceMessage = "😊 Please smile";
            _faceGuidanceColor = Colors.blue;
          }
          break;
          
        case LivenessChallenge.turnHead:
          // Head turn: must turn head then return to center
          if (headTurned && !_headTurnDetected) {
            _headTurnDetected = true;
            _wasHeadCentered = false;
          } else if (_headTurnDetected && headCentered && !_wasHeadCentered) {
            _wasHeadCentered = true;
            _challengeCompleted[_currentChallengeIndex] = true;
            _advanceToNextChallenge();
          }
          
          if (!_challengeCompleted[_currentChallengeIndex]) {
            if (!_headTurnDetected) {
              _faceGuidanceMessage = "↔️ Turn your head left or right";
              _faceGuidanceColor = Colors.blue;
            } else {
              _faceGuidanceMessage = "↔️ Now look back at the camera";
              _faceGuidanceColor = Colors.green;
            }
          }
          break;
      }
      
      _isFaceValid = false; // Not valid until all challenges complete
      _isLivenessVerified = false;
    });
  }
  
  void _advanceToNextChallenge() {
    if (_currentChallengeIndex < _challenges.length - 1) {
      _currentChallengeIndex++;
      // Reset states for next challenge
      _previousEyesClosed = false;
      _headTurnDetected = false;
      _wasHeadCentered = false;
      
      // Show success feedback briefly
      _faceGuidanceMessage = "✓ Challenge completed!";
      _faceGuidanceColor = Colors.green;
      
      // Play success animation
      _successPulseController.forward().then((_) {
        _successPulseController.reverse();
      });
    } else {
      // All challenges completed
      _faceGuidanceMessage = "All challenges completed! Hold steady...";
      _faceGuidanceColor = Colors.green;
      _readyFrameCount = 0;
      
      // Play success animation
      _successPulseController.forward().then((_) {
        _successPulseController.reverse();
      });
    }
  }
  
  Future<void> _captureFace() async {
    if (_isCapturing || _currentScanCount >= _requiredScans) return;
    
    setState(() => _isCapturing = true);
    
    try {
      // Stop face detection temporarily
      _stopFaceDetection();
      
      // Wait a moment for image stream to stop
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Capture the photo
      final XFile photo = await _cameraController!.takePicture();
      
      if (mounted) {
        setState(() {
          _capturedFaces.add(photo);
          _currentScanCount++;
          _readyFrameCount = 0;
        });
        
        // Play success animation
        _successPulseController.forward().then((_) {
          _successPulseController.reverse();
        });
        
        // If we've captured all 3 scans, move to form phase
        if (_currentScanCount >= _requiredScans) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            setState(() => _isScanningPhase = false);
            // Dispose camera since we're done scanning
            _cameraController?.dispose();
            _cameraController = null;
          }
        } else {
          // Wait 2 seconds before next scan
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() => _isCapturing = false);
            // Restart face detection for next scan
            _startFaceDetection();
          }
        }
      }
    } catch (e) {
      debugPrint('Error capturing face: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
        _startFaceDetection();
      }
    }
  }
  
  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate() || _selectedClassId == null) {
      UIHelpers.showWarning(context, "Please fill all fields and select a class");
      return;
    }
    
    if (_capturedFaces.length < _requiredScans) {
      UIHelpers.showWarning(context, "Please complete face scanning first");
      return;
    }

    if (!mounted) return;
    setState(() => _isRegistering = true);

    try {
      // 1. Check if face is already registered
      final verifyResult = await ApiService.verifyFace(
        imageFile: File(_capturedFaces[0].path),
      );

      if (verifyResult['success'] == true && verifyResult['data']['success'] == true) {
        if (!mounted) return;
        final studentName = verifyResult['data']['student_name'];
        final studentId = verifyResult['data']['student_id'];
        
        // Show specific error for duplicate face
        UIHelpers.showError(
          context, 
          "This person is already registered as:\n$studentName (ID: $studentId)",
        );
        setState(() => _isRegistering = false);
        return;
      }

      // 2. Proceed with registration if face is not found
      final result = await ApiService.registerStudent(
        studentId: _studentIdController.text,
        name: _nameController.text,
        classId: _selectedClassId!,
        imageFile: File(_capturedFaces[0].path), // Using first scan
      );

      if (!mounted) return;
      
      if (result['success']) {
        await _showSuccessModal(
          studentName: _nameController.text,
          studentId: _studentIdController.text,
        );
        if (mounted) Navigator.pop(context, true);
      } else {
        final errorMsg = result['error']?.toString() ?? 'Unknown error';
        UIHelpers.showError(context, "Registration Failed: $errorMsg");
      }
    } catch (e) {
      if (mounted) {
        UIHelpers.showError(context, "Error: $e");
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }
  
  Future<void> _showSuccessModal({
    required String studentName,
    required String studentId,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Container();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        
        return ScaleTransition(
          scale: Tween<double>(begin: 0.5, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: animation,
            child: AlertDialog(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.all(32),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Checkmark
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF10B981),
                            size: 56,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Title
                  const Text(
                    "Registration Successful!",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  
                  // Subtitle
                  Text(
                    "Face data has been saved",
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // Student Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person_rounded,
                              color: const Color(0xFF6366F1),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                studentName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.badge_rounded,
                              color: const Color(0xFF6366F1),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "ID: $studentId",
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Done Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Done",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  void _retakeScan(int index) {
    setState(() {
      _capturedFaces.removeAt(index);
      _currentScanCount--;
      _isScanningPhase = true;
    });
    
    // Reinitialize camera
    _initializeCamera();
  }
  
  void _resetAllScans() {
    setState(() {
      _capturedFaces.clear();
      _currentScanCount = 0;
      _isScanningPhase = true;
      
      // Reset liveness challenge states
      _currentChallengeIndex = 0;
      _challengeCompleted = [false, false, false];
      _blinkDetected = false;
      _smileDetected = false;
      _headTurnDetected = false;
      _wasHeadCentered = false;
      _previousEyesClosed = false;
      _readyFrameCount = 0;
    });
    
    // Reinitialize camera
    _initializeCamera();
  }
  
  Widget _buildChallengeIndicator({
    required IconData icon,
    required String label,
    required bool isCompleted,
    required bool isActive,
    required bool isDark,
  }) {
    final Color bgColor;
    final Color iconColor;
    final Color borderColor;
    
    if (isCompleted) {
      bgColor = Colors.green.withOpacity(0.2);
      iconColor = Colors.green;
      borderColor = Colors.green;
    } else if (isActive) {
      bgColor = Colors.blue.withOpacity(0.2);
      iconColor = Colors.blue;
      borderColor = Colors.blue;
    } else {
      bgColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
      iconColor = isDark ? Colors.grey[500]! : Colors.grey[400]!;
      borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    }
    
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Icon(
            isCompleted ? Icons.check : icon,
            color: iconColor,
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isCompleted 
                ? Colors.green 
                : (isActive ? Colors.blue : (isDark ? Colors.grey[400] : Colors.grey[600])),
          ),
        ),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user ?? {};
    final role = (user['role'] ?? 'teacher').toString();
    final isAdmin = role == 'admin' || role == 'super_admin';

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E2936) : Colors.white,
          elevation: 0,
          title: const Text(
            "Register Student",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Text(
            "Access restricted to administrators",
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E2936) : Colors.white,
        elevation: 0,
        title: Text(
          _isScanningPhase ? "Scan Face" : "Register Student",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isScanningPhase ? _buildScanningPhase(theme, isDark) : _buildFormPhase(theme, isDark),
      ),
    );
  }
  
  Widget _buildScanningPhase(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Challenge Progress Indicator
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                _allChallengesCompleted 
                    ? "Liveness Verified!" 
                    : "Security Check ${_currentChallengeIndex + 1}/3",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _allChallengesCompleted ? Colors.green : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _allChallengesCompleted 
                    ? "Hold steady for photo capture"
                    : "Complete the challenges below",
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              // Challenge progress indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildChallengeIndicator(
                    icon: Icons.remove_red_eye_outlined,
                    label: "Blink",
                    isCompleted: _challengeCompleted[0],
                    isActive: _currentChallengeIndex == 0 && !_allChallengesCompleted,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 16),
                  _buildChallengeIndicator(
                    icon: Icons.sentiment_satisfied_alt,
                    label: "Smile",
                    isCompleted: _challengeCompleted[1],
                    isActive: _currentChallengeIndex == 1 && !_allChallengesCompleted,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 16),
                  _buildChallengeIndicator(
                    icon: Icons.swap_horiz,
                    label: "Turn",
                    isCompleted: _challengeCompleted[2],
                    isActive: _currentChallengeIndex == 2 && !_allChallengesCompleted,
                    isDark: isDark,
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Camera Viewport
        Expanded(
          child: Container(
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
                  if (_isCameraInitialized && _cameraController != null)
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
                ],
              ),
            ),
          ),
        ),
        
        // Captured Previews
        if (_capturedFaces.isNotEmpty)
          Container(
            height: 100,
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _capturedFaces.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_capturedFaces[index].path),
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        
        const SizedBox(height: 16),
      ],
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
                  if (!_isCapturing)
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
            
            const SizedBox(height: 12),
            
            Text(
              _isCapturing 
                  ? "Capturing scan $_currentScanCount..."
                  : (_isFaceValid && _isLivenessVerified
                      ? "Perfect position!"
                      : "Position your face in the frame"),
              style: TextStyle(
                color: _isFaceValid && _isLivenessVerified
                    ? Colors.green[300]
                    : Colors.white70,
                fontSize: 13,
                fontWeight: _isFaceValid && _isLivenessVerified
                    ? FontWeight.w600
                    : FontWeight.w300,
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildFormPhase(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Face Scans Completed!",
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "$_requiredScans scans captured successfully",
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _resetAllScans,
                    child: const Text("Retake"),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Captured Face Previews
            const Text(
              "Captured Face Scans",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _capturedFaces.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(_capturedFaces[index].path),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                "${index + 1}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Form Title
            const Text(
              "Student Information",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Student ID Field
            TextFormField(
              controller: _studentIdController,
              decoration: InputDecoration(
                labelText: "Student ID",
                prefixIcon: const Icon(Icons.badge),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E2936) : Colors.white,
              ),
              validator: (v) => v!.isEmpty ? "Student ID is required" : null,
            ),
            
            const SizedBox(height: 16),
            
            // Full Name Field
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Full Name",
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E2936) : Colors.white,
              ),
              validator: (v) => v!.isEmpty ? "Full Name is required" : null,
            ),
            
            const SizedBox(height: 16),
            
            // Class Selection
            DropdownButtonFormField<int>(
              value: _selectedClassId,
              decoration: InputDecoration(
                labelText: "Class",
                prefixIcon: const Icon(Icons.class_),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E2936) : Colors.white,
              ),
              items: _classes.map((c) => DropdownMenuItem<int>(
                value: c['id'],
                child: Text(c['class_name'] ?? c['name']),
              )).toList(),
              onChanged: (v) => setState(() => _selectedClassId = v),
              validator: (v) => v == null ? "Please select a class" : null,
            ),
            
            const SizedBox(height: 32),
            
            // Register Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isRegistering ? null : _handleRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: _isRegistering
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Register Student",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Info Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Face will be converted to embeddings and saved securely for attendance verification",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
