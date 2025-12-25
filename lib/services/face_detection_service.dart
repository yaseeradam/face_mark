import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../services/api_service.dart';
import '../services/storage_service.dart';

class FaceDetectionService {
  static Future<Map<String, dynamic>> detectFaces(File imageFile) async {
    try {
      // First optimize the image
      final optimizedImage = await optimizeImage(imageFile);
      
      // Send to backend for face detection
      final uri = Uri.parse('${ApiService.baseUrl}/face/detect');
      final request = http.MultipartRequest('POST', uri);
      
      // Add auth headers
      final token = await StorageService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      request.files.add(await http.MultipartFile.fromPath('file', optimizedImage.path));
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        return {
          'success': true,
          'faces': data['faces'] ?? [],
          'count': data['face_count'] ?? 0,
          'quality': data['quality'] ?? 'unknown'
        };
      } else {
        return {
          'success': false,
          'error': 'Face detection failed',
          'faces': [],
          'count': 0
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection error: $e',
        'faces': [],
        'count': 0
      };
    }
  }

  static Future<Map<String, dynamic>> registerFace(int studentId, File imageFile) async {
    try {
      final optimizedImage = await optimizeImage(imageFile);
      
      // First detect faces to validate quality
      final detection = await detectFaces(optimizedImage);
      if (!detection['success'] || detection['count'] != 1) {
        return {
          'success': false,
          'error': detection['count'] == 0 
            ? 'No face detected' 
            : detection['count'] > 1 
              ? 'Multiple faces detected' 
              : detection['error']
        };
      }

      // Register face with backend
      return await ApiService.registerFace(
        studentId: studentId,
        imageFile: optimizedImage,
      );
    } catch (e) {
      return {'success': false, 'error': 'Registration failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyFace(int classId, File imageFile) async {
    try {
      final optimizedImage = await optimizeImage(imageFile);
      
      // First detect faces
      final detection = await detectFaces(optimizedImage);
      if (!detection['success'] || detection['count'] != 1) {
        return {
          'success': false,
          'error': detection['count'] == 0 
            ? 'No face detected' 
            : detection['count'] > 1 
              ? 'Multiple faces detected' 
              : detection['error']
        };
      }

      // Verify face with backend
      return await ApiService.verifyFace(
        classId: classId,
        imageFile: optimizedImage,
      );
    } catch (e) {
      return {'success': false, 'error': 'Verification failed: $e'};
    }
  }

  static String getQualityFeedback(Map<String, dynamic> detection) {
    if (!detection['success']) {
      return detection['error'] ?? 'Detection failed';
    }
    
    final count = detection['count'] ?? 0;
    if (count == 0) return "No face detected";
    if (count > 1) return "Multiple faces detected - ensure only one person";
    
    final quality = detection['quality'] ?? 'unknown';
    switch (quality.toLowerCase()) {
      case 'good':
        return "Good quality face detected";
      case 'poor':
        return "Poor image quality - move closer and ensure good lighting";
      case 'blurry':
        return "Image too blurry - hold camera steady";
      case 'dark':
        return "Image too dark - improve lighting";
      default:
        return "Face detected - position properly in frame";
    }
  }

  static Future<File> optimizeImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) throw Exception('Could not decode image');
      
      // Resize to optimal size for face recognition (640x640 max)
      img.Image resized = image;
      if (image.width > 640 || image.height > 640) {
        final ratio = image.width > image.height 
          ? 640 / image.width 
          : 640 / image.height;
        resized = img.copyResize(
          image, 
          width: (image.width * ratio).round(),
          height: (image.height * ratio).round()
        );
      }
      
      // Enhance image for better face recognition
      resized = img.adjustColor(resized, contrast: 1.1, brightness: 1.05);
      
      // Compress with high quality for face recognition
      final compressedBytes = img.encodeJpg(resized, quality: 95);
      
      // Save optimized image
      final optimizedFile = File('${imageFile.path}_optimized.jpg');
      await optimizedFile.writeAsBytes(compressedBytes);
      
      return optimizedFile;
    } catch (e) {
      // If optimization fails, return original
      return imageFile;
    }
  }

  static void dispose() {
    // Cleanup if needed
  }
}