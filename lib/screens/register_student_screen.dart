import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class RegisterStudentScreen extends StatefulWidget {
  const RegisterStudentScreen({super.key});

  @override
  State<RegisterStudentScreen> createState() => _RegisterStudentScreenState();
}

class _RegisterStudentScreenState extends State<RegisterStudentScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _nameController = TextEditingController();
  
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  late AnimationController _animationController;
  
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  bool _isRegistering = false;
  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _initializeCamera();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
      
      // Force Front Camera
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
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
    _animationController.dispose();
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
      debugPrint("Starting registration for: ${_studentIdController.text}");
      
      // 1. Capture Face directly in the app
      final XFile photo = await _cameraController!.takePicture();
      debugPrint("Photo captured: ${photo.path}");
      
      // 2. Register via API
      final result = await ApiService.registerStudent(
        studentId: _studentIdController.text,
        name: _nameController.text,
        classId: _selectedClassId!,
        imageFile: File(photo.path),
      );
      
      debugPrint("Registration result: $result");

      if (!mounted) return;
      
      if (result['success']) {
        UIHelpers.showSuccess(context, "Student Registered Successfully!");
        if (mounted) Navigator.pop(context);
      } else {
        final errorMsg = result['error']?.toString() ?? 'Unknown error';
        debugPrint("Registration failed: $errorMsg");
        UIHelpers.showError(context, "Registration Failed: $errorMsg");
      }
    } catch (e, stackTrace) {
      debugPrint("Registration exception: $e");
      debugPrint("Stack trace: $stackTrace");
      if (mounted) {
        UIHelpers.showError(context, "Error: $e");
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text("Register Student")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scanner Preview
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isCameraInitialized)
                      CameraPreview(_cameraController!)
                    else
                      const Center(child: CircularProgressIndicator()),
                    
                    // Scanning Animation Line
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return CustomPaint(
                          size: const Size(double.infinity, 300),
                          painter: ScannerLinePainter(percent: _animationController.value, color: theme.colorScheme.primary),
                        );
                      },
                    ),
                    
                    // Face Frame
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              TextFormField(
                controller: _studentIdController,
                decoration: const InputDecoration(labelText: "Student ID", prefixIcon: Icon(Icons.badge)),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedClassId,
                decoration: const InputDecoration(labelText: "Class", prefixIcon: Icon(Icons.class_)),
                items: _classes.map((c) => DropdownMenuItem<int>(
                  value: c['id'],
                  child: Text(c['class_name'] ?? c['name']),
                )).toList(),
                onChanged: (v) => setState(() => _selectedClassId = v),
              ),
              const SizedBox(height: 32),
              
              ElevatedButton.icon(
                onPressed: _isRegistering ? null : _handleRegistration,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isRegistering 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Icon(Icons.how_to_reg),
                label: Text(_isRegistering ? "Processing..." : "Scan & Register Student"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerLinePainter extends CustomPainter {
  final double percent;
  final Color color;
  ScannerLinePainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final y = size.height * percent;
    
    // Draw the moving line
    canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), paint);

    // Draw a subtle glow/gradient for the line
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0), color.withOpacity(0.4), color.withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, y - 20, size.width, 40));
    
    canvas.drawRect(Rect.fromLTWH(20, y - 20, size.width - 40, 40), shadowPaint);
  }

  @override
  bool shouldRepaint(covariant ScannerLinePainter oldDelegate) => oldDelegate.percent != percent;
}
