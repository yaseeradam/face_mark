import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'storage_service.dart';

class ApiService {
  static const String baseUrl = 'http://your-server-ip:8000'; // Update with your actual server IP
  static String? _token;

  static Future<bool> _hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  static Future<Map<String, dynamic>> _makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    File? file,
    Map<String, String>? fields,
    bool retryOnAuth = true,
  }) async {
    try {
      if (!await _hasConnection()) {
        return {'success': false, 'error': 'No internet connection'};
      }

      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders();
      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(Duration(seconds: 30));
          break;
        case 'POST':
          if (file != null) {
            var request = http.MultipartRequest('POST', uri);
            request.headers.addAll(headers);
            if (fields != null) request.fields.addAll(fields);
            request.files.add(await http.MultipartFile.fromPath('file', file.path));
            final streamedResponse = await request.send().timeout(Duration(seconds: 60));
            response = await http.Response.fromStream(streamedResponse);
          } else {
            response = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(Duration(seconds: 30));
          }
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(Duration(seconds: 30));
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(Duration(seconds: 30));
          break;
        default:
          return {'success': false, 'error': 'Invalid HTTP method'};
      }

      if (response.statusCode == 401 && retryOnAuth) {
        // Try to refresh token
        final refreshResult = await _refreshToken();
        if (refreshResult['success']) {
          // Retry the original request
          return await _makeRequest(method, endpoint, body: body, file: file, fields: fields, retryOnAuth: false);
        } else {
          await StorageService.clearToken();
          return {'success': false, 'error': 'Session expired. Please login again.', 'needsAuth': true};
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
        return {'success': true, 'data': data};
      } else {
        final error = response.body.isNotEmpty ? jsonDecode(response.body) : {};
        return {'success': false, 'error': error['message'] ?? 'Request failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> _refreshToken() async {
    try {
      final refreshToken = await StorageService.getString('refresh_token');
      if (refreshToken == null) return {'success': false};

      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access_token'];
        await StorageService.saveToken(_token!);
        if (data['refresh_token'] != null) {
          await StorageService.saveString('refresh_token', data['refresh_token']);
        }
        return {'success': true, 'data': data};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    _token ??= await StorageService.getToken();
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // Auth endpoints
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await _makeRequest('POST', '/auth/login', body: {'email': email, 'password': password});
    if (result['success'] && result['data']['access_token'] != null) {
      _token = result['data']['access_token'];
      await StorageService.saveToken(_token!);
    }
    return result;
  }

  static Future<void> logout() async {
    await StorageService.clearToken();
    _token = null;
  }

  // Teacher endpoints
  static Future<Map<String, dynamic>> getTeachers() async {
    return await _makeRequest('GET', '/teachers/');
  }

  static Future<Map<String, dynamic>> createTeacher(Map<String, dynamic> teacherData) async {
    return await _makeRequest('POST', '/teachers/', body: teacherData);
  }

  // Class endpoints
  static Future<Map<String, dynamic>> getClasses() async {
    return await _makeRequest('GET', '/classes/');
  }

  static Future<Map<String, dynamic>> createClass(Map<String, dynamic> classData) async {
    return await _makeRequest('POST', '/classes/', body: classData);
  }

  // Student endpoints
  static Future<Map<String, dynamic>> getStudents({int? classId}) async {
    String endpoint = '/students/';
    if (classId != null) endpoint += '?class_id=$classId';
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> createStudent(Map<String, dynamic> studentData) async {
    return await _makeRequest('POST', '/students/', body: studentData);
  }

  // Face recognition endpoints
  static Future<Map<String, dynamic>> registerFace(int studentId, File imageFile) async {
    return await _makeRequest('POST', '/face/register', file: imageFile, fields: {'student_id': studentId.toString()});
  }

  static Future<Map<String, dynamic>> verifyFace(int classId, File imageFile) async {
    return await _makeRequest('POST', '/face/verify', file: imageFile, fields: {'class_id': classId.toString()});
  }

  // Attendance endpoints
  static Future<Map<String, dynamic>> markAttendance(Map<String, dynamic> attendanceData) async {
    return await _makeRequest('POST', '/attendance/mark', body: attendanceData);
  }

  static Future<Map<String, dynamic>> getTodayAttendance({int? classId}) async {
    String endpoint = '/attendance/today';
    if (classId != null) endpoint += '?class_id=$classId';
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> getAttendanceByClass(int classId, {String? date}) async {
    String endpoint = '/attendance/by-class/$classId';
    if (date != null) endpoint += '?date_filter=$date';
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> getAttendanceSummary(int classId, {String? date}) async {
    String endpoint = '/attendance/summary/$classId';
    if (date != null) endpoint += '?date_filter=$date';
    return await _makeRequest('GET', endpoint);
  }

  static void setToken(String token) {
    _token = token;
  }

  static void clearToken() {
    _token = null;
  }

  static bool get isAuthenticated => _token != null;
}