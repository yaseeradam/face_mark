import 'dart:io';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ExportService {
  static Future<File> exportToCSV(List<Map<String, dynamic>> data, String filename) async {
    if (data.isEmpty) throw Exception('No data to export');
    
    final headers = data.first.keys.toList();
    final rows = data.map((item) => headers.map((header) => item[header]?.toString() ?? '').toList()).toList();
    
    final csvData = [headers, ...rows];
    final csvString = const ListToCsvConverter().convert(csvData);
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename.csv');
    await file.writeAsString(csvString);
    
    return file;
  }

  static Future<File> exportToPDF(List<Map<String, dynamic>> data, String title, String filename) async {
    final pdf = pw.Document();
    
    if (data.isEmpty) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Text('No data available', style: const pw.TextStyle(fontSize: 24)),
            );
          },
        ),
      );
    } else {
      final headers = data.first.keys.toList();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data.map((item) => headers.map((header) => item[header]?.toString() ?? '').toList()).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 20),
              pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
            ];
          },
        ),
      );
    }
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename.pdf');
    await file.writeAsBytes(await pdf.save());
    
    return file;
  }

  static Future<File> exportAttendanceReport(List<Map<String, dynamic>> attendanceData) async {
    final filename = 'attendance_report_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    return await exportToPDF(attendanceData, 'Attendance Report', filename);
  }

  static Future<File> exportStudentList(List<Map<String, dynamic>> studentData) async {
    final filename = 'student_list_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    return await exportToCSV(studentData, filename);
  }

  static Future<File> saveCsvString(String csvData, String filename) async {
    if (csvData.trim().isEmpty) throw Exception('No data to export');
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename.csv');
    await file.writeAsString(csvData);
    return file;
  }
}
