import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import '../services/face_detection_service.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'dart:io';

class MarkAttendanceScreen1 extends ConsumerStatefulWidget {
  final int classId;
  
  const MarkAttendanceScreen1({super.key, required this.classId});

  @override
  ConsumerState<MarkAttendanceScreen1> createState() => _MarkAttendanceScreen1State();
}

class _MarkAttendanceScreen1State extends ConsumerState<MarkAttendanceScreen1> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _statusMessage = "Position face in frame";
  Map<String, dynamic>? _recognizedStudent;
  File? _capturedImage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final success = await CameraService.initialize();
    setState(() => _isCameraInitialized = success);
    if (success) _startFaceVerification();
  }

  void _startFaceVerification() {
    // Auto-capture and verify every 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isProcessing) {
        _captureAndVerify();
      }
    });
  }

  Future<void> _captureAndVerify() async {
    if (_isProcessing || !_isCameraInitialized) return;
    
    setState(() {
      _isProcessing = true;
      _statusMessage = "Analyzing face...";
    });

    try {
      final image = await CameraService.takePicture();
      if (image != null) {
        setState(() => _capturedImage = image);
        
        // Verify face with backend
        final result = await FaceDetectionService.verifyFace(widget.classId, image);
        
        if (result['success']) {
          final studentData = result['data'];
          setState(() {
            _recognizedStudent = studentData;
            _statusMessage = "Face recognized!";
          });
          
          // Auto-mark attendance after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) _markAttendance();
          });
        } else {
          setState(() {
            _statusMessage = result['error'] ?? "Face not recognized";
            _recognizedStudent = null;
          });
          
          // Retry after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _statusMessage = "Position face in frame");
              _startFaceVerification();
            }
          });
        }
      }
    } catch (e) {
      setState(() => _statusMessage = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _markAttendance() async {
    if (_recognizedStudent == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final result = await ApiService.markAttendance({
        'student_id': _recognizedStudent!['student_id'],
        'class_id': widget.classId,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'present',
      });
      
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attendance marked for ${_recognizedStudent!['name']}'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Show success for 3 seconds then reset
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _recognizedStudent = null;
              _statusMessage = "Position face in frame";
            });
            _startFaceVerification();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error']), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    CameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: _isCameraInitialized && CameraService.controller != null
                ? CameraPreview(CameraService.controller!)
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
          ),
          
          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black45, Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                        style: IconButton.styleFrom(backgroundColor: Colors.white10),
                      ),
                      const Text(
                        "Mark Attendance",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: _captureAndVerify,
                        icon: const Icon(Icons.camera_alt, color: Colors.white),
                        style: IconButton.styleFrom(backgroundColor: Colors.white10),
                      ),
                    ],
                  ),
                ),
                
                // Camera View UI
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Status Badge
                      Positioned(
                        top: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _recognizedStudent != null ? Icons.check_circle : Icons.face,
                                color: _recognizedStudent != null ? Colors.greenAccent : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _statusMessage,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Face Frame
                      SizedBox(
                        width: 280,
                        height: 280,
                        child: Stack(
                          children: [
                            // Corners
                            Align(alignment: Alignment.topLeft, child: _buildCorner(theme.colorScheme.primary, true, true)),
                            Align(alignment: Alignment.topRight, child: _buildCorner(theme.colorScheme.primary, true, false)),
                            Align(alignment: Alignment.bottomLeft, child: _buildCorner(theme.colorScheme.primary, false, true)),
                            Align(alignment: Alignment.bottomRight, child: _buildCorner(theme.colorScheme.primary, false, false)),
                            
                            // Scanner Line
                            if (_isProcessing)
                              AnimatedBuilder(
                                animation: _controller,
                                builder: (context, child) {
                                  return Positioned(
                                    top: 280 * _controller.value,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withOpacity(0.8),
                                        boxShadow: [
                                          BoxShadow(color: theme.colorScheme.primary, blurRadius: 10),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      
                      Positioned(
                        bottom: 40,
                        child: Text(
                          _isProcessing ? "Processing..." : "Hold still for verification",
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Bottom Sheet
                if (_recognizedStudent != null)
                  Container(
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(3)))),
                        const SizedBox(height: 24),
                        
                        // Student Profile
                        Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: theme.colorScheme.primary, width: 2),
                                color: Colors.grey[300],
                              ),
                              child: Icon(Icons.person, size: 32, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_recognizedStudent!['name'] ?? 'Unknown', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                  Text("ID: ${_recognizedStudent!['student_id'] ?? 'N/A'}", style: TextStyle(color: Colors.grey[500])),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                              child: const Text("Present", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Confirm Button
                        LoadingButton(
                          text: "Confirm Attendance",
                          onPressed: _markAttendance,
                          isLoading: _isProcessing,
                          icon: Icons.check,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(Color color, bool isTop, bool isLeft) {
    const size = 30.0;
    const thickness = 4.0;
    const radius = 10.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: (isTop && isLeft) ? const Radius.circular(radius) : Radius.zero,
          topRight: (isTop && !isLeft) ? const Radius.circular(radius) : Radius.zero,
          bottomLeft: (!isTop && isLeft) ? const Radius.circular(radius) : Radius.zero,
          bottomRight: (!isTop && !isLeft) ? const Radius.circular(radius) : Radius.zero,
        ),
        border: Border(
          top: isTop ? BorderSide(color: color, width: thickness) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: thickness) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: thickness) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: thickness) : BorderSide.none,
        ),
      ),
    );
  }
}