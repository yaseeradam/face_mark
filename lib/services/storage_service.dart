import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class StorageService {
  static const _storage = FlutterSecureStorage();
  static SharedPreferences? _prefs;
  static Database? _database;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    // Skip database initialization on web since sqflite doesn't support web
    if (!kIsWeb) {
      await _initDatabase();
    }
    _initialized = true;
  }

  static Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance.db');
    
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE students(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT UNIQUE,
            name TEXT,
            class_id INTEGER,
            face_data TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE attendance(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT,
            date TEXT,
            time TEXT,
            status TEXT
          )
        ''');
      },
    );
  }

  // Secure storage for tokens
  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: 'auth_token');
  }

  // Regular preferences
  static Future<void> saveBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  static bool getBool(String key, {bool defaultValue = false}) {
    return _prefs?.getBool(key) ?? defaultValue;
  }

  static Future<void> saveString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  static Future<void> removeString(String key) async {
    await _prefs?.remove(key);
  }

  // Database operations
  static Future<void> insertStudent(Map<String, dynamic> student) async {
    await _database?.insert('students', student);
  }

  static Future<List<Map<String, dynamic>>> getStudents() async {
    return await _database?.query('students') ?? [];
  }

  static Future<void> insertAttendance(Map<String, dynamic> attendance) async {
    await _database?.insert('attendance', attendance);
  }

  static Future<List<Map<String, dynamic>>> getAttendance() async {
    return await _database?.query('attendance') ?? [];
  }
}