import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'storage_service.dart';

class ApiService {
  // For Android emulator use 10.0.2.2, for iOS simulator use localhost
  // For physical device via USB: use localhost with adb reverse
  // For physical device via WiFi: use computer's local IP
  static const String baseUrl = 'http://13.51.55.238:8100'; // Network connection
  static String? _token;

  static String? uploadsUrl(String? relativePath) {
    final raw = relativePath?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final normalized = raw.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    final segments = <String>[
      'uploads',
      ...normalized.split('/').where((s) => s.trim().isNotEmpty),
    ];

    return Uri.parse(baseUrl).resolveUri(Uri(pathSegments: segments)).toString();
  }

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
          response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
          break;
        case 'POST':
          if (file != null) {
            var request = http.MultipartRequest('POST', uri);
            request.headers.addAll(headers);
            if (fields != null) request.fields.addAll(fields);
            request.files.add(await http.MultipartFile.fromPath('file', file.path));
            final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
            response = await http.Response.fromStream(streamedResponse);
          } else {
            response = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
          }
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 30));
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
        // Try to extract meaningful error message
        String errorMessage = 'Request failed with status ${response.statusCode}';

        try {
          if (response.body.isNotEmpty) {
            final error = jsonDecode(response.body);
            // Handle case where detail could be a List (FastAPI validation errors)
            final errorDetail = error['detail'] ?? error['message'] ?? error['error'];
            if (errorDetail != null) {
              if (errorDetail is List) {
                errorMessage = errorDetail.map((e) => e['msg'] ?? e.toString()).join(', ');
              } else {
                errorMessage = errorDetail.toString();
              }
            } else {
              errorMessage = response.body.toString();
            }
          }
        } catch (e) {
          errorMessage = 'Server returned invalid JSON: ${response.body}';
        }

        return {'success': false, 'error': errorMessage, 'status_code': response.statusCode};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> _refreshToken() async {
    try {
      final refreshToken = StorageService.getString('refresh_token');
      if (refreshToken == null) return {'success': false};

      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 30));

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

  static Future<Map<String, dynamic>> faceLogin(File imageFile) async {
    return await _makeRequest(
      'POST',
      '/auth/face-login',
      file: imageFile,
      retryOnAuth: false,
    );
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    // Skip token refresh on 401 for login since there's no valid token yet
    final identifier = email.trim();
    final isEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(identifier);
    final body = {
      'identifier': identifier,
      'password': password,
      if (isEmail) 'email': identifier, // Backward-compatible with older auth payloads.
    };
    final result = await _makeRequest(
      'POST',
      '/auth/login',
      body: body,
      retryOnAuth: false,
    );
    if (result['success'] && result['data']['access_token'] != null) {
      _token = result['data']['access_token'];
      await StorageService.saveToken(_token!);
    }
    return result;
  }

  static Future<void> logout() async {
    await StorageService.clearToken();
    await StorageService.removeString('user_profile');
    _token = null;
  }

  // Test connectivity to the server
  static Future<Map<String, dynamic>> testConnectivity() async {
    try {
      if (!await _hasConnection()) {
        return {'success': false, 'error': 'No internet connection'};
      }

      final uri = Uri.parse('$baseUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Server is reachable'};
      } else {
        return {'success': false, 'error': 'Server not responding properly', 'status': response.statusCode};
      }
    } catch (e) {
      return {'success': false, 'error': 'Cannot connect to server: ${e.toString()}'};
    }
  }

  // Profile & Settings endpoints
  static Future<Map<String, dynamic>> getProfile() async {
    return await _makeRequest('GET', '/teachers/me');
  }

  static Future<Map<String, dynamic>> getAttendanceSettings() async {
    return await _makeRequest('GET', '/attendance/settings');
  }

  static Future<Map<String, dynamic>> updateAttendanceSettings(Map<String, dynamic> settings) async {
    return await _makeRequest('PUT', '/attendance/settings', body: settings);
  }

  static Future<Map<String, dynamic>> setupFaceId(File imageFile) async {
    return await _makeRequest(
      'POST',
      '/teachers/setup-face-id',
      file: imageFile,
    );
  }

  static Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) async {
    return await _makeRequest('POST', '/teachers/change-password', body: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  // Admin User Management endpoints
  static Future<Map<String, dynamic>> getUsers() async {
    return await _makeRequest('GET', '/teachers/');
  }

  static Future<Map<String, dynamic>> getUserById(String userId) async {
    return await _makeRequest('GET', '/teachers/$userId');
  }

  static Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    return await _makeRequest('POST', '/teachers/', body: userData);
  }

  static Future<Map<String, dynamic>> updateUser(String userId, Map<String, dynamic> userData) async {
    return await _makeRequest('PUT', '/teachers/$userId', body: userData);
  }

  static Future<Map<String, dynamic>> deleteUser(String userId) async {
    return await _makeRequest('DELETE', '/teachers/$userId');
  }

  static Future<Map<String, dynamic>> updateUserStatus(String userId, String status) async {
    return await _makeRequest('PUT', '/teachers/$userId', body: {'status': status});
  }

  static Future<Map<String, dynamic>> bulkDeleteUsers(List<int> userIds) async {
    return await _makeRequest('POST', '/teachers/bulk-delete', body: {'teacher_ids': userIds});
  }

  static Future<Map<String, dynamic>> exportUsersToCSV() async {
    try {
      if (!await _hasConnection()) {
        return {'success': false, 'error': 'No internet connection'};
      }

      final uri = Uri.parse('$baseUrl/teachers/export/csv');
      final headers = await _getHeaders();
      
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': response.body};
      } else {
        return {'success': false, 'error': 'Failed to export CSV'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }

  // Organization management endpoints (Super Admin)
  static Future<Map<String, dynamic>> getOrganizations() async {
    return await _makeRequest('GET', '/organizations/');
  }

  static Future<Map<String, dynamic>> createOrganization(Map<String, dynamic> orgData) async {
    return await _makeRequest('POST', '/organizations/', body: orgData);
  }

  static Future<Map<String, dynamic>> updateOrganization(String orgId, Map<String, dynamic> orgData) async {
    return await _makeRequest('PUT', '/organizations/$orgId', body: orgData);
  }

  static Future<Map<String, dynamic>> deleteOrganization(String orgId) async {
    return await _makeRequest('DELETE', '/organizations/$orgId');
  }

  // Teacher endpoints
  static Future<Map<String, dynamic>> getTeachers() async {
    return await _makeRequest('GET', '/teachers/');
  }

  static Future<Map<String, dynamic>> getTeacherById(int teacherId) async {
    return await _makeRequest('GET', '/teachers/$teacherId');
  }

  static Future<Map<String, dynamic>> createTeacher(Map<String, dynamic> teacherData) async {
    return await _makeRequest('POST', '/teachers/', body: teacherData);
  }

  static Future<Map<String, dynamic>> updateTeacher(int teacherId, Map<String, dynamic> teacherData) async {
    return await _makeRequest('PUT', '/teachers/$teacherId', body: teacherData);
  }

  static Future<Map<String, dynamic>> deleteTeacher(int teacherId) async {
    return await _makeRequest('DELETE', '/teachers/$teacherId');
  }

  // Class endpoints
  static Future<Map<String, dynamic>> getClasses() async {
    return await _makeRequest('GET', '/classes/');
  }

  static Future<Map<String, dynamic>> getClassById(int classId) async {
    return await _makeRequest('GET', '/classes/$classId');
  }

  static Future<Map<String, dynamic>> createClass(Map<String, dynamic> classData) async {
    return await _makeRequest('POST', '/classes/', body: classData);
  }

  static Future<Map<String, dynamic>> updateClass(int classId, Map<String, dynamic> classData) async {
    return await _makeRequest('PUT', '/classes/$classId', body: classData);
  }

  static Future<Map<String, dynamic>> deleteClass(int classId) async {
    return await _makeRequest('DELETE', '/classes/$classId');
  }

  // Student endpoints
  static Future<Map<String, dynamic>> getStudents({int? classId}) async {
    String endpoint = '/students/';
    if (classId != null) endpoint += '?class_id=$classId';
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> getStudentById(int studentId) async {
    return await _makeRequest('GET', '/students/$studentId');
  }

  static Future<Map<String, dynamic>> createStudent(Map<String, dynamic> studentData) async {
    return await _makeRequest('POST', '/students/', body: studentData);
  }

  static Future<Map<String, dynamic>> updateStudent(int studentId, Map<String, dynamic> studentData) async {
    return await _makeRequest('PUT', '/students/$studentId', body: studentData);
  }

  static Future<Map<String, dynamic>> deleteStudent(int studentId) async {
    return await _makeRequest('DELETE', '/students/$studentId');
  }

  static Future<Map<String, dynamic>> registerStudent({
    required String studentId,
    required String name,
    required int classId,
    required File imageFile,
  }) async {
    // 1. Create Student Record
    final studentData = {
      'student_id': studentId,
      'full_name': name,
      'class_id': classId,
    };
    
    final createResult = await _makeRequest('POST', '/students/', body: studentData);
    if (!createResult['success']) {
      return createResult;
    }

    final int dbId = createResult['data']['id'];

    // 2. Register Face
    return await _makeRequest(
      'POST',
      '/face/register',
      file: imageFile,
      fields: {'student_id': dbId.toString()},
    );
  }

  static Future<Map<String, dynamic>> verifyFace({
    int? classId,
    bool autoMark = false,
    String checkInType = 'morning',
    required File imageFile,
  }) async {
    final fields = {'auto_mark': autoMark.toString()};
    fields['check_in_type'] = checkInType;
    if (classId != null) {
      fields['class_id'] = classId.toString();
    }
    
    return await _makeRequest(
      'POST',
      '/face/verify',
      file: imageFile,
      fields: fields,
    );
  }

  // Face recognition endpoints
  static Future<Map<String, dynamic>> registerFace({
    required int studentId,
    required File imageFile,
  }) async {
    return await _makeRequest(
      'POST',
      '/face/register',
      file: imageFile,
      fields: {'student_id': studentId.toString()},
    );
  }

  static Future<Map<String, dynamic>> deleteFace(int studentId) async {
    return await _makeRequest('DELETE', '/face/$studentId');
  }

  // Attendance endpoints
  static Future<Map<String, dynamic>> markAttendance(Map<String, dynamic> attendanceData) async {
    final studentId = attendanceData['student_id'];
    final classId = attendanceData['class_id'];
    final confidenceScore = attendanceData['confidence_score'] ?? 0.0;
    final checkInType = attendanceData['check_in_type'] ?? 'morning';
    final endpoint = '/attendance/mark?student_id=$studentId&class_id=$classId&confidence_score=$confidenceScore&check_in_type=$checkInType';
    return await _makeRequest('POST', endpoint);
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

  static Future<Map<String, dynamic>> getAttendanceHistory(DateTime? date) async {
    String endpoint = '/attendance/history';
    if (date != null) {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      endpoint += '?date=$dateStr';
    }
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> getAttendanceHistoryForClass(DateTime? date, {int? classId}) async {
    String endpoint = '/attendance/history';
    final params = <String>[];
    if (date != null) {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      params.add('date=$dateStr');
    }
    if (classId != null) {
      params.add('class_id=$classId');
    }
    if (params.isNotEmpty) {
      endpoint += '?${params.join('&')}';
    }
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> exportAttendanceCSV(DateTime date) async {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    try {
      if (!await _hasConnection()) {
        return {'success': false, 'error': 'No internet connection'};
      }
      final uri = Uri.parse('$baseUrl/attendance/export/csv?date=$dateStr');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': response.body};
      }
      return {'success': false, 'error': 'Failed to export CSV', 'status_code': response.statusCode};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> exportClassAttendanceReportCSV({
    required int classId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final end = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

    try {
      if (!await _hasConnection()) {
        return {'success': false, 'error': 'No internet connection'};
      }
      final uri = Uri.parse('$baseUrl/reports/attendance/$classId?start_date=$start&end_date=$end&format=csv');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': response.body};
      }
      return {'success': false, 'error': 'Failed to export report CSV', 'status_code': response.statusCode};
    } catch (e) {
      return {'success': false, 'error': 'Connection error: ${e.toString()}'};
    }
  }

  // Dashboard & Statistics endpoints
  static Future<Map<String, dynamic>> getDashboardStats() async {
    return await _makeRequest('GET', '/dashboard/stats');
  }

  static Future<Map<String, dynamic>> getRecentActivity({int limit = 10}) async {
    return await _makeRequest('GET', '/dashboard/activity?limit=$limit');
  }

  // Reports endpoints
  static Future<Map<String, dynamic>> getAttendanceReport({
    required int classId,
    String? startDate,
    String? endDate,
    String? format, // 'json', 'csv', 'pdf'
  }) async {
    String endpoint = '/reports/attendance/$classId';
    List<String> params = [];
    if (startDate != null) params.add('start_date=$startDate');
    if (endDate != null) params.add('end_date=$endDate');
    if (format != null) params.add('format=$format');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';
    return await _makeRequest('GET', endpoint);
  }

  static Future<Map<String, dynamic>> getStudentReport(String studentId, {String? startDate, String? endDate}) async {
    String endpoint = '/reports/student/$studentId';
    List<String> params = [];
    if (startDate != null) params.add('start_date=$startDate');
    if (endDate != null) params.add('end_date=$endDate');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';
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
