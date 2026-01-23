import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../theme/app_theme.dart';

class FaceCaptureScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool requireSmile;
  final bool requireEyesOpen;
  final bool autoCapture;
  final Duration processingInterval;
  final ResolutionPreset resolution;

  const FaceCaptureScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.requireSmile = true,
    this.requireEyesOpen = true,
    this.autoCapture = true,
    this.processingInterval = const Duration(milliseconds: 150),
    this.resolution = ResolutionPreset.medium,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;

  bool _isCameraInitialized = false;
  bool _isDetectingFaces = false;
  bool _isProcessingImage = false;
  bool _isCapturing = false;

  String _guidanceMessage = 'Position your face in the frame';
  Color _guidanceColor = Colors.white70;
  bool _faceDetected = false;
  bool _faceValid = false;
  bool _smiling = false;
  bool _eyesOpen = false;

  DateTime? _lastFrameProcessed;
  int _readyFrameCount = 0;
  static const int _requiredReadyFrames = 5;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _initializeCamera();
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
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        widget.resolution,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
      _startFaceDetection();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guidanceMessage = 'Camera failed to start';
        _guidanceColor = Colors.redAccent;
      });
    }
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _isDetectingFaces = true;
    _cameraController!.startImageStream((CameraImage image) {
      if (!_isDetectingFaces || _isProcessingImage || _isCapturing) return;
      final now = DateTime.now();
      if (_lastFrameProcessed != null && now.difference(_lastFrameProcessed!) < widget.processingInterval) {
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
      _updateGuidance(faces);
    } catch (_) {
      if (mounted) {
        setState(() {
          _guidanceMessage = 'Hold still...';
          _guidanceColor = Colors.orangeAccent;
        });
      }
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
    } catch (_) {
      return null;
    }
  }

  void _updateGuidance(List<Face> faces) {
    if (!mounted) return;

    setState(() {
      if (faces.isEmpty) {
        _faceDetected = false;
        _faceValid = false;
        _smiling = false;
        _eyesOpen = false;
        _readyFrameCount = 0;
        _guidanceMessage = 'No face detected';
        _guidanceColor = Colors.orangeAccent;
        return;
      }

      final face = faces.first;
      _faceDetected = true;

      final headY = face.headEulerAngleY ?? 0;
      final headZ = face.headEulerAngleZ ?? 0;
      final isHeadStraight = headY.abs() <= 15 && headZ.abs() <= 10;

      final leftEyeOpen = face.leftEyeOpenProbability;
      final rightEyeOpen = face.rightEyeOpenProbability;
      _eyesOpen = leftEyeOpen != null && rightEyeOpen != null && leftEyeOpen > 0.5 && rightEyeOpen > 0.5;

      final smileProb = face.smilingProbability;
      _smiling = smileProb != null && smileProb > 0.6;

      final needsEyes = widget.requireEyesOpen;
      final needsSmile = widget.requireSmile;

      final eyesOk = !needsEyes || _eyesOpen;
      final smileOk = !needsSmile || _smiling;
      _faceValid = isHeadStraight && eyesOk && smileOk;

      if (!isHeadStraight) {
        _guidanceMessage = 'Look straight at the camera';
        _guidanceColor = Colors.orangeAccent;
        _readyFrameCount = 0;
        return;
      }

      if (needsEyes && !_eyesOpen) {
        _guidanceMessage = 'Open your eyes';
        _guidanceColor = Colors.orangeAccent;
        _readyFrameCount = 0;
        return;
      }

      if (needsSmile && !_smiling) {
        _guidanceMessage = 'Smile to verify';
        _guidanceColor = Colors.orangeAccent;
        _readyFrameCount = 0;
        return;
      }

      if (_faceValid) {
        _readyFrameCount++;
        _guidanceColor = Colors.greenAccent;
        _guidanceMessage = widget.autoCapture
            ? 'Hold steady... ${(_requiredReadyFrames - _readyFrameCount).clamp(0, _requiredReadyFrames)}'
            : 'Ready to capture';
      } else {
        _readyFrameCount = 0;
        _guidanceMessage = 'Adjust your face position';
        _guidanceColor = Colors.orangeAccent;
      }
    });

    if (widget.autoCapture && _faceValid && _readyFrameCount >= _requiredReadyFrames && !_isCapturing) {
      Future.microtask(_captureAndReturn);
    }
  }

  Future<void> _captureAndReturn() async {
    if (_isCapturing) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isCapturing = true;
      _guidanceMessage = 'Capturing...';
      _guidanceColor = Colors.lightBlueAccent;
    });

    try {
      _stopFaceDetection();
      await Future.delayed(const Duration(milliseconds: 200));
      final XFile photo = await _cameraController!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, photo);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _readyFrameCount = 0;
        _guidanceMessage = 'Capture failed. Try again.';
        _guidanceColor = Colors.redAccent;
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _startFaceDetection();
      });
    }
  }

  @override
  void dispose() {
    _stopFaceDetection();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _isCameraInitialized && _cameraController != null
                ? CameraPreview(_cameraController!)
                : const Center(child: CircularProgressIndicator()),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FaceOverlayPainter(color: Colors.white.withOpacity(0.18)),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _guidanceColor.withOpacity(0.7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCapturing
                            ? Icons.hourglass_top
                            : (_faceDetected ? Icons.face : Icons.face_retouching_off),
                        color: _guidanceColor,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _guidanceMessage,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _guidanceColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isCapturing ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMD)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_isCapturing || !_faceDetected) ? null : _captureAndReturn,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMD)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isCapturing) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          const Text('Capturing'),
                        ] else ...[
                          const Icon(Icons.camera_alt_rounded, size: 18),
                          const SizedBox(width: 8),
                          const Text('Capture'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FaceOverlayPainter extends CustomPainter {
  final Color color;
  const _FaceOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;

    final shortest = size.shortestSide;
    final radius = shortest * 0.34;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, radius, paint);

    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.9);

    final cornerLen = radius * 0.22;
    final r = radius;

    final tl = Offset(center.dx - r, center.dy - r);
    final tr = Offset(center.dx + r, center.dy - r);
    final bl = Offset(center.dx - r, center.dy + r);
    final br = Offset(center.dx + r, center.dy + r);

    canvas.drawLine(tl, tl.translate(cornerLen, 0), corner);
    canvas.drawLine(tl, tl.translate(0, cornerLen), corner);
    canvas.drawLine(tr, tr.translate(-cornerLen, 0), corner);
    canvas.drawLine(tr, tr.translate(0, cornerLen), corner);
    canvas.drawLine(bl, bl.translate(cornerLen, 0), corner);
    canvas.drawLine(bl, bl.translate(0, -cornerLen), corner);
    canvas.drawLine(br, br.translate(-cornerLen, 0), corner);
    canvas.drawLine(br, br.translate(0, -cornerLen), corner);
  }

  @override
  bool shouldRepaint(covariant _FaceOverlayPainter oldDelegate) => oldDelegate.color != color;
}
