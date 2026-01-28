import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class ClassAttendanceScreen extends StatefulWidget {
  final int classId;
  final String? className;

  const ClassAttendanceScreen({
    super.key,
    required this.classId,
    this.className,
  });

  @override
  State<ClassAttendanceScreen> createState() => _ClassAttendanceScreenState();
}

class _ClassAttendanceScreenState extends State<ClassAttendanceScreen> {
  bool _isLoadingStudents = true;
  bool _isLoadingAttendance = true;
  String? _error;

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _students = [];
  Map<int, Map<String, dynamic>> _attendanceByStudentId = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await _loadStudents();
    await _loadAttendance();
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStudents = true;
      _error = null;
    });

    final result = await ApiService.getStudents(classId: widget.classId);
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _students = List<Map<String, dynamic>>.from(result['data'] ?? const <dynamic>[]);
        _isLoadingStudents = false;
      });
      return;
    }

    setState(() {
      _isLoadingStudents = false;
      _error = result['error']?.toString() ?? 'Failed to load students';
    });
  }

  Future<void> _loadAttendance() async {
    if (!mounted) return;
    setState(() {
      _isLoadingAttendance = true;
      _error = null;
    });

    final result = await ApiService.getAttendanceHistoryForClass(
      _selectedDate,
      classId: widget.classId,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      final records = List<Map<String, dynamic>>.from(result['data'] ?? const <dynamic>[]);
      final map = <int, Map<String, dynamic>>{};
      for (final record in records) {
        final rawId = record['student_id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (id == null) continue;
        map[id] = record;
      }
      setState(() {
        _attendanceByStudentId = map;
        _isLoadingAttendance = false;
      });
      return;
    }

    setState(() {
      _isLoadingAttendance = false;
      _error = result['error']?.toString() ?? 'Failed to load attendance';
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadAttendance();
  }

  String _statusLabel(Map<String, dynamic>? record) {
    final raw = record?['status']?.toString().toLowerCase().trim();
    if (raw == 'late') return 'Late';
    if (raw == 'present') return 'Present';
    if (raw == 'absent') return 'Absent';
    return 'Not Marked';
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'present') return Colors.green;
    if (s == 'late') return Colors.orange;
    if (s == 'absent') return Colors.red;
    return Colors.grey;
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final totalStudents = _students.length;
    int present = 0;
    int late = 0;
    int absent = 0;

    for (final student in _students) {
      final id = _asInt(student['id']);
      final record = _attendanceByStudentId[id];
      final status = _statusLabel(record).toLowerCase();
      if (status == 'present') present++;
      if (status == 'late') {
        late++;
        present++;
      }
      if (status == 'absent' || status == 'not marked') absent++;
    }

    final rate = totalStudents > 0 ? ((present / totalStudents) * 100).round() : 0;
    final dateLabel = DateFormat('MMM d, yyyy').format(_selectedDate);
    final title = widget.className?.toString().trim().isNotEmpty == true
        ? widget.className!.toString()
        : 'Class Attendance';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101922) : const Color(0xFFF6F7F8),
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Pick date',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStudents();
          await _loadAttendance();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null && _error!.trim().isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: isDark ? Colors.red[200] : Colors.red[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2936) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(label: 'Students', value: '$totalStudents', color: Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(label: 'Present', value: '$present', color: Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(label: 'Absent', value: '$absent', color: Colors.red)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(label: 'Rate', value: '$rate%', color: Colors.purple)),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoadingStudents || _isLoadingAttendance)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_students.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'No students found in this class.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              )
            else
              ..._students.map((student) {
                final id = _asInt(student['id']);
                final record = _attendanceByStudentId[id];
                final status = _statusLabel(record);
                final color = _statusColor(status);
                final name = (student['full_name'] ?? student['name'] ?? 'Unknown').toString();
                final studentId = (student['student_id'] ?? '').toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2936) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (studentId.isNotEmpty)
                              Text(
                                'ID: $studentId',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                UIHelpers.showInfo(context, 'Tip: Pull down to refresh.');
              },
              icon: const Icon(Icons.info_outline),
              label: const Text('Help'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

