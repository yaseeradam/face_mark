import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';

class BulkOperationsService {
  static Future<File?> pickCSVFile() async {
    // For now, return null - file picker would need platform-specific implementation
    return null;
  }

  static Future<List<Map<String, dynamic>>> parseCSV(File csvFile) async {
    final content = await csvFile.readAsString();
    final fields = const CsvToListConverter().convert(content);

    if (fields.isEmpty) return [];

    final headers = fields.first.map((e) => e.toString()).toList();
    final data = <Map<String, dynamic>>[];

    for (int i = 1; i < fields.length; i++) {
      final row = fields[i];
      final Map<String, dynamic> record = {};

      for (int j = 0; j < headers.length && j < row.length; j++) {
        record[headers[j]] = row[j];
      }
      data.add(record);
    }

    return data;
  }

  static Future<Map<String, dynamic>> bulkImportStudents(List<Map<String, dynamic>> students) async {
    int successCount = 0;
    int failureCount = 0;
    final errors = <String>[];

    for (final student in students) {
      try {
        final result = await ApiService.createStudent({
          'student_id': student['student_id'] ?? '',
          'name': student['name'] ?? '',
          'class_id': student['class_id'] ?? '',
          'email': student['email'] ?? '',
        });

        if (result['success']) {
          successCount++;
        } else {
          failureCount++;
          errors.add('${student['student_id']}: ${result['error']}');
        }
      } catch (e) {
        failureCount++;
        errors.add('${student['student_id']}: $e');
      }
    }

    return {
      'success': successCount,
      'failed': failureCount,
      'errors': errors,
    };
  }

  static Future<File> generateStudentTemplate() async {
    final headers = ['student_id', 'name', 'class_id', 'email'];
    final sampleData = [
      ['STU001', 'John Doe', '1', 'john@example.com'],
      ['STU002', 'Jane Smith', '1', 'jane@example.com'],
    ];

    final csvData = [headers, ...sampleData];
    final csvString = const ListToCsvConverter().convert(csvData);

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/student_template.csv');
    await file.writeAsString(csvString);

    return file;
  }

  static Future<Map<String, dynamic>> bulkExportStudents() async {
    final result = await ApiService.getStudents();

    if (!result['success']) {
      return {'success': false, 'error': result['error']};
    }

    final students = result['data'] as List;
    final csvData = [
      ['Student ID', 'Name', 'Class', 'Email', 'Created At'],
      ...students.map((s) => [
        s['student_id'] ?? '',
        s['name'] ?? '',
        s['class_name'] ?? '',
        s['email'] ?? '',
        s['created_at'] ?? '',
      ]),
    ];

    final csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/students_export.csv');
    await file.writeAsString(csvString);

    return {'success': true, 'file': file};
  }
}