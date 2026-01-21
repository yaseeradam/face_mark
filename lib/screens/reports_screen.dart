import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart'; // For date formatting
import '../services/api_service.dart';
import '../services/export_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  final int? initialClassId;
  final String? initialClassName;

  const ReportsScreen({super.key, this.initialClassId, this.initialClassName});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic> _stats = {
    'present': 0,
    'absent': 0, // Need backend support or full calculation
    'late': 0,
    'rate': 0.0,
    'total': 0,
  };
  
  // Filters
  int? _selectedClassId;
  List<Map<String, dynamic>> _classes = [];
  String _dateFilter = "today"; // today, week, month

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.initialClassId;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // 1. Fetch Classes (for filter)
    final classResult = await ApiService.getClasses();
    if (classResult['success']) {
      _classes = List<Map<String, dynamic>>.from(classResult['data'] ?? []);
    }

    // 2. Fetch Attendance Logs (Today or Filtered)
    // For now, we fetch 'Today' as default
    final result = await ApiService.getTodayAttendance(classId: _selectedClassId);
    final logs = _resolveLogs(result['data']);
    _logs = logs;

    int present = _presentCountFromLogs(logs);
    int totalStudents = 0;
    double rate = 0;

    if (_selectedClassId != null) {
      final summary = await ApiService.getAttendanceSummary(_selectedClassId!);
      if (summary['success'] == true) {
        final summaryData = _resolveStatsData(summary['data']);
        totalStudents = _asInt(summaryData['total_students'] ?? summaryData['total']);
        present = _asInt(summaryData['present_students'] ?? summaryData['present']);
        rate = _normalizeRate(summaryData['attendance_rate'], present, totalStudents);
      }
    } else {
      final dashboard = await ApiService.getDashboardStats();
      if (dashboard['success'] == true) {
        final dashboardData = _resolveStatsData(dashboard['data']);
        totalStudents = _asInt(dashboardData['total_students'] ?? dashboardData['total']);
        final presentToday = _asInt(dashboardData['present_today'] ?? dashboardData['present_students']);
        if (presentToday > 0) present = presentToday;
        rate = _normalizeRate(dashboardData['attendance_rate'], present, totalStudents);
      }
    }

    final absent = totalStudents > 0 ? (totalStudents - present).clamp(0, totalStudents) : 0;
    if (rate == 0 && totalStudents > 0) {
      rate = (present / totalStudents) * 100;
    }

    setState(() {
      _stats['present'] = present;
      _stats['absent'] = absent;
      _stats['rate'] = rate.toStringAsFixed(0);
      _stats['total'] = totalStudents;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new),
          style: IconButton.styleFrom(
            backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
        title: Text(
          widget.initialClassName != null
              ? "Attendance • ${widget.initialClassName}"
              : "Attendance Reports",
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () async {
              final exportResult = await ApiService.exportAttendanceCSV(DateTime.now());
              if (!context.mounted) return;
              if (exportResult['success'] == true && exportResult['data'] is String) {
                final file = await ExportService.saveCsvString(
                  exportResult['data'] as String,
                  'attendance_report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Report saved: ${file.path}')),
                );
              } else if (_logs.isNotEmpty) {
                final file = await ExportService.exportToCSV(
                  _logs.map((log) => _mapLogForExport(log)).toList(),
                  'attendance_report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Report saved: ${file.path}')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(exportResult['error'] ?? 'Failed to export report')),
                );
              }
            },
            icon: Icon(Icons.download, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // Stats Grid
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.4,
              children: [
                _buildStatCard(context, "Present Today", "${_stats['present']}", null, Icons.check_circle, true),
                _buildStatCard(context, "Absent Today", "${_stats['absent']}", null, Icons.cancel, false, iconColor: Colors.red),
                _buildStatCard(context, "Attendance Rate", "${_stats['rate']}%", null, Icons.trending_up, false, iconColor: theme.colorScheme.primary),
                // _buildStatCard(context, "Late Arrival", "${_stats['late']}", null, Icons.schedule, false, iconColor: Colors.orange),
                // _buildStatCard(context, "Avg. Rate", "${_stats['rate']}%", null, Icons.trending_up, false, iconColor: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 24),
            
            // Filters
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Filters", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                TextButton(onPressed: _loadData, child: const Text("Reset")),
              ],
            ),
            const SizedBox(height: 8),
            
            // Class Filter
             DropdownButtonFormField<int>(
                value: _selectedClassId,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.class_),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  filled: true,
                  fillColor: theme.cardColor,
                  hintText: "All Classes"
                ),
                items: [
                   const DropdownMenuItem<int>(value: null, child: Text("All Classes")),
                   ..._classes.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['class_name'] ?? c['name'] ?? 'Class'))),
                ],
                onChanged: (v) {
                   setState(() => _selectedClassId = v);
                   _loadData();
                },
              ),
            
            const SizedBox(height: 24),
            Text("Detailed Logs", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            if (_isLoading)
               const Center(child: CircularProgressIndicator())
            else if (_logs.isEmpty)
               const Center(child: Padding(padding: EdgeInsets.all(32), child: Text("No attendance records found for today.")))
            else
               // List Items
               ListView.builder(
                 shrinkWrap: true,
                 physics: const NeverScrollableScrollPhysics(),
                 itemCount: _logs.length,
                 itemBuilder: (context, index) {
                    final log = _logs[index];
                    final String name = log['student_name'] ?? 'Unknown';
                    final String idStr = log['student_student_id'] ?? '-';
                    final String time = log['timestamp'] != null 
                        ? DateFormat('hh:mm a').format(DateTime.parse(log['timestamp'])) 
                        : '--:--';
                    
                    return _buildReportItem(context, name, "ID: #$idStr • $time", "Present", Colors.green);
                 },
               ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, String? trend, IconData icon, bool isPrimary, {Color? iconColor}) {
    final theme = Theme.of(context);
    final bgColor = isPrimary ? theme.colorScheme.primary : theme.cardColor;
    final textColor = isPrimary ? Colors.white : theme.colorScheme.onSurface;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPrimary ? [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
        border: !isPrimary ? Border.all(color: Colors.grey.withOpacity(0.1)) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: isPrimary ? Colors.white70 : Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
              Icon(icon, color: iconColor ?? Colors.white70, size: 20),
            ],
          ),
          Text(value, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildReportItem(BuildContext context, String name, String subtitle, String status, Color statusColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[100]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                 Text(subtitle, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _resolveLogs(dynamic raw) {
    if (raw is List) {
      return List<Map<String, dynamic>>.from(raw);
    }
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'] ?? raw['records'] ?? raw['attendance'];
      if (inner is List) {
        return List<Map<String, dynamic>>.from(inner);
      }
    }
    return [];
  }

  Map<String, dynamic> _resolveStatsData(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'] ?? raw['summary'] ?? raw['stats'];
      if (inner is Map<String, dynamic>) return inner;
      return raw;
    }
    return {};
  }

  int _presentCountFromLogs(List<Map<String, dynamic>> logs) {
    final Set<String> unique = {};
    for (final log in logs) {
      final id = log['student_id']?.toString() ?? log['student_student_id']?.toString();
      if (id != null && id.isNotEmpty) unique.add(id);
    }
    return unique.isEmpty ? logs.length : unique.length;
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll('%', '').trim();
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  double _normalizeRate(dynamic value, int present, int total) {
    double rate = _asDouble(value);
    if (rate == 0 && total > 0) {
      rate = (present / total) * 100;
    }
    if (rate > 0 && rate <= 1) {
      rate *= 100;
    }
    return rate;
  }

  Map<String, dynamic> _mapLogForExport(Map<String, dynamic> log) {
    return {
      'student_name': log['student_name'] ?? log['full_name'] ?? 'Unknown',
      'student_id': log['student_student_id'] ?? log['student_id'] ?? '',
      'class_name': log['class_name'] ?? '',
      'status': log['status'] ?? 'present',
      'timestamp': log['timestamp'] ?? log['marked_at'] ?? '',
    };
  }
}
