import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/export_service.dart';

DateTimeRange _defaultReportRange() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTimeRange(
    start: today.subtract(const Duration(days: 29)),
    end: today,
  );
}

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
  List<Map<String, dynamic>> _classes = [];
  int? _selectedClassId;
  DateTime _selectedDate = DateTime.now();
  DateTimeRange _reportRange = _defaultReportRange();

  Map<String, dynamic> _stats = {
    'present': 0,
    'absent': 0,
    'late': 0,
    'rate': '0',
    'total': 0,
  };

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.initialClassId;
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _reportRange = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
      end: DateTime(now.year, now.month, now.day),
    );
    _loadData();
  }

  String _formatApiDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  String _formatDisplayDate(DateTime date) => DateFormat('MMM d, yyyy').format(date);

  String _formatDisplayRange(DateTimeRange range) {
    final start = DateFormat('MMM d, yyyy').format(range.start);
    final end = DateFormat('MMM d, yyyy').format(range.end);
    return '$start - $end';
  }

  String _selectedClassName() {
    final selected = _classes.where((c) => c['id'] == _selectedClassId).toList();
    if (selected.isNotEmpty) {
      return (selected.first['class_name'] ?? selected.first['name'] ?? 'Class').toString();
    }
    return widget.initialClassName ?? 'Class';
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final classResult = await ApiService.getClasses();
    if (!mounted) return;
    if (classResult['success'] == true) {
      _classes = List<Map<String, dynamic>>.from(classResult['data'] ?? <dynamic>[]);
    }

    final historyResult = await ApiService.getAttendanceHistoryForClass(
      _selectedDate,
      classId: _selectedClassId,
    );
    if (!mounted) return;

    final logs = _resolveLogs(historyResult['data']);
    logs.sort((a, b) {
      final at = _parseTimestamp(a)?.millisecondsSinceEpoch ?? 0;
      final bt = _parseTimestamp(b)?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    int totalStudentsHint = 0;
    if (_selectedClassId != null) {
      final summary = await ApiService.getAttendanceSummary(
        _selectedClassId!,
        date: _formatApiDate(_selectedDate),
      );
      if (!mounted) return;
      if (summary['success'] == true) {
        final summaryData = _resolveStatsData(summary['data']);
        totalStudentsHint = _asInt(summaryData['total_students'] ?? summaryData['total']);
      }
    }

    final derived = _deriveCountsFromLogs(logs, totalStudentsHint: totalStudentsHint);

    if (!mounted) return;
    setState(() {
      _logs = logs;
      _stats = derived;
      _isLoading = false;
    });
  }

  Future<void> _pickLogDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadData();
  }

  Future<void> _pickReportRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: _reportRange,
    );
    if (picked == null) return;
    setState(() => _reportRange = picked);
  }

  Future<void> _exportDetailedLogsCsv() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a class first.')));
      return;
    }
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No logs to export for the selected date.')));
      return;
    }

    final className = _selectedClassName().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final datePart = DateFormat('yyyyMMdd').format(_selectedDate);
    final filename = 'attendance_logs_${className}_$datePart';

    final rows = _logs.map(_mapLogForExport).toList();
    final file = await ExportService.exportToCSV(rows, filename);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report saved: ${file.path}')));
  }

  Future<void> _exportSummaryCsv() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a class first.')));
      return;
    }

    final result = await ApiService.exportClassAttendanceReportCSV(
      classId: _selectedClassId!,
      startDate: _reportRange.start,
      endDate: _reportRange.end,
    );
    if (!mounted) return;

    if (result['success'] == true && result['data'] is String) {
      final className = _selectedClassName().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      final start = DateFormat('yyyyMMdd').format(_reportRange.start);
      final end = DateFormat('yyyyMMdd').format(_reportRange.end);
      final filename = 'attendance_summary_${className}_${start}_$end';
      final file = await ExportService.saveCsvString(result['data'] as String, filename);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report saved: ${file.path}')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['error'] ?? 'Failed to export report')),
    );
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
          _selectedClassId != null ? "Attendance • ${_selectedClassName()}" : "Attendance Reports",
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'export_detailed':
                  await _exportDetailedLogsCsv();
                  break;
                case 'export_summary':
                  await _exportSummaryCsv();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export_detailed', child: Text('Download Detailed CSV (Selected Date)')),
              PopupMenuItem(value: 'export_summary', child: Text('Download Summary CSV (Date Range)')),
            ],
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
            if (_selectedClassId != null) ...[
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.4,
                children: [
                  _buildStatCard(context, "Present", "${_stats['present']}", Icons.check_circle, true),
                  _buildStatCard(context, "Absent", "${_stats['absent']}", Icons.cancel, false, iconColor: Colors.red),
                  _buildStatCard(context, "Attendance Rate", "${_stats['rate']}%", Icons.trending_up, false, iconColor: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 24),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
                ),
                child: const Text('Select a class to see totals and download class reports.'),
              ),
              const SizedBox(height: 24),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Filters", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _selectedClassId = null;
                      _selectedDate = DateTime(now.year, now.month, now.day);
                      _reportRange = DateTimeRange(
                        start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
                        end: DateTime(now.year, now.month, now.day),
                      );
                    });
                    _loadData();
                  },
                  child: const Text("Reset"),
                ),
              ],
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<int>(
              value: _selectedClassId,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.class_),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                filled: true,
                fillColor: theme.cardColor,
                hintText: "All Classes",
              ),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text("All Classes")),
                ..._classes.map(
                  (c) => DropdownMenuItem<int>(
                    value: c['id'],
                    child: Text(c['class_name'] ?? c['name'] ?? 'Class'),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _selectedClassId = v);
                _loadData();
              },
            ),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickLogDate,
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text('Log date: ${_formatDisplayDate(_selectedDate)}'),
            ),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickReportRange,
              icon: const Icon(Icons.date_range_rounded),
              label: Text('Summary range: ${_formatDisplayRange(_reportRange)}'),
            ),

            const SizedBox(height: 24),
            Text("Detailed Logs", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_logs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text("No attendance records found for ${_formatDisplayDate(_selectedDate)}."),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final name = (log['student_name'] ?? log['full_name'] ?? 'Unknown').toString();
                  final idStr = (log['student_student_id'] ?? log['student_id'] ?? '-').toString();
                  final className = (log['class_name'] ?? '').toString();
                  final checkInType = (log['check_in_type'] ?? '').toString();
                  final ts = _parseTimestamp(log);
                  final time = ts != null ? DateFormat('hh:mm a').format(ts) : '--:--';
                  final status = (log['status'] ?? 'present').toString();
                  final statusColor = _statusColor(status);
                  final confidence = _confidenceLabel(log);

                  final parts = <String>[
                    'ID: #$idStr',
                    if (className.isNotEmpty) className,
                    time,
                    if (checkInType.isNotEmpty) checkInType.toUpperCase(),
                    if (confidence.isNotEmpty) confidence,
                  ];

                  return _buildReportItem(context, name, parts.join(' • '), status.toUpperCase(), statusColor);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, bool isPrimary, {Color? iconColor}) {
    final theme = Theme.of(context);
    final bgColor = isPrimary ? theme.colorScheme.primary : theme.cardColor;
    final textColor = isPrimary ? Colors.white : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isPrimary
            ? [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
            : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
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

    final icon = status.toLowerCase().contains('absent')
        ? Icons.cancel
        : (status.toLowerCase().contains('late') ? Icons.schedule : Icons.check_circle);

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
            child: Icon(icon, color: statusColor),
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

  DateTime? _parseTimestamp(Map<String, dynamic> log) {
    final raw = log['timestamp'] ?? log['marked_at'] ?? log['markedAt'];
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _confidenceLabel(Map<String, dynamic> log) {
    final raw = log['confidence_score'] ?? log['confidence'];
    if (raw == null) return '';
    final value = _asDouble(raw);
    if (value == 0) return '';
    final percent = (value > 0 && value <= 1) ? value * 100 : value;
    return '${percent.toStringAsFixed(0)}%';
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase().trim();
    if (s == 'late') return Colors.orange;
    if (s == 'absent') return Colors.red;
    return Colors.green;
  }

  List<Map<String, dynamic>> _resolveLogs(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (raw is Map<String, dynamic>) {
      final inner = raw['data'] ?? raw['records'] ?? raw['attendance'];
      if (inner is List) {
        return inner.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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

  Map<String, dynamic> _deriveCountsFromLogs(List<Map<String, dynamic>> logs, {required int totalStudentsHint}) {
    final Map<String, String> statusByStudent = {};
    int lateCount = 0;

    for (final log in logs) {
      final studentId = (log['student_id'] ?? log['student_student_id'])?.toString();
      if (studentId == null || studentId.isEmpty) continue;
      final status = (log['status'] ?? 'present').toString().toLowerCase().trim();

      final prev = statusByStudent[studentId];
      if (prev == null) {
        statusByStudent[studentId] = status;
      } else {
        final prevIsPresent = prev == 'present' || prev == 'late';
        final nextIsPresent = status == 'present' || status == 'late';
        if (!prevIsPresent && nextIsPresent) {
          statusByStudent[studentId] = status;
        }
        if (prev == 'present' && status == 'late') {
          statusByStudent[studentId] = status;
        }
      }
    }

    int present = 0;
    int absent = 0;
    for (final entry in statusByStudent.entries) {
      final s = entry.value;
      if (s == 'present' || s == 'late') {
        present++;
        if (s == 'late') lateCount++;
      } else if (s == 'absent') {
        absent++;
      }
    }

    int total = totalStudentsHint > 0 ? totalStudentsHint : (present + absent);
    if (total > 0) {
      absent = (total - present).clamp(0, total);
    }
    final rate = total > 0 ? ((present / total) * 100).toStringAsFixed(0) : '0';

    return {
      'present': present,
      'absent': absent,
      'late': lateCount,
      'rate': rate,
      'total': total,
    };
  }

  Map<String, dynamic> _mapLogForExport(Map<String, dynamic> log) {
    final ts = _parseTimestamp(log);
    final date = ts != null ? DateFormat('yyyy-MM-dd').format(ts) : '';
    final time = ts != null ? DateFormat('HH:mm:ss').format(ts) : '';
    final status = (log['status'] ?? 'present').toString();
    final className = (log['class_name'] ?? '').toString();
    final checkInType = (log['check_in_type'] ?? '').toString();
    final confidence = _confidenceLabel(log);

    return {
      'Attendance ID': (log['id'] ?? '').toString(),
      'Date': date,
      'Time': time,
      'Student Name': (log['student_name'] ?? log['full_name'] ?? 'Unknown').toString(),
      'Student DB ID': (log['student_id'] ?? '').toString(),
      'Student ID': (log['student_student_id'] ?? '').toString(),
      'Class ID': (log['class_id'] ?? '').toString(),
      'Class': className,
      'Status': status,
      'Check In Type': checkInType,
      'Confidence': confidence,
      'Marked At': ts?.toIso8601String() ?? (log['timestamp'] ?? log['marked_at'] ?? '').toString(),
    };
  }
}
