import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../utils/ui_helpers.dart';

class StudentDetailsScreen extends ConsumerStatefulWidget {
  final int? studentId;
  final Map<String, dynamic> student;

  const StudentDetailsScreen({
    super.key,
    this.studentId,
    this.student = const {},
  });

  @override
  ConsumerState<StudentDetailsScreen> createState() =>
      _StudentDetailsScreenState();
}

enum _StudentReportRangePreset { thisMonth, last30Days, last90Days, custom }

class _StudentDetailsScreenState extends ConsumerState<StudentDetailsScreen> {
  int? _studentId;
  Map<String, dynamic> _student = {};
  Map<String, dynamic> _report = {};

  _StudentReportRangePreset _rangePreset = _StudentReportRangePreset.thisMonth;
  DateTimeRange? _customRange;

  bool _loading = true;
  String? _error;
  bool _busyAction = false;

  ProviderSubscription<int>? _attendanceRefreshSubscription;

  @override
  void initState() {
    super.initState();

    _student = Map<String, dynamic>.from(widget.student);
    _studentId =
        widget.studentId ??
        _toInt(
          widget.student['id'] ??
              widget.student['student_pk'] ??
              widget.student['studentId'],
        );

    _attendanceRefreshSubscription = ref.listenManual<int>(
      attendanceRefreshProvider,
      (previous, next) {
        if (!mounted) return;
        if (_studentId != null) {
          _loadReport(showSpinner: false);
        }
      },
    );

    if (_studentId == null) {
      _loading = false;
      _error = 'Missing student id';
      return;
    }

    _loadAll();
  }

  @override
  void dispose() {
    _attendanceRefreshSubscription?.close();
    super.dispose();
  }

  bool get _isAdmin {
    final user = ref.read(authProvider).user ?? {};
    final role = (user['role'] ?? '').toString();
    return role == 'admin' || role == 'super_admin';
  }

  DateTimeRange get _activeRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_rangePreset) {
      case _StudentReportRangePreset.thisMonth:
        return DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
      case _StudentReportRangePreset.last30Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 30)),
          end: today,
        );
      case _StudentReportRangePreset.last90Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 90)),
          end: today,
        );
      case _StudentReportRangePreset.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(today.year, today.month, 1),
              end: today,
            );
    }
  }

  String _dateParam(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _rangeLabel(DateTimeRange range) {
    final fmt = DateFormat.yMMMd();
    return '${fmt.format(range.start)} - ${fmt.format(range.end)}';
  }

  Future<void> _setRangePreset(_StudentReportRangePreset preset) async {
    if (preset == _StudentReportRangePreset.custom) {
      await _pickCustomRange();
      return;
    }

    if (!mounted) return;
    setState(() => _rangePreset = preset);
    await _loadReport(showSpinner: true);
  }

  Future<void> _pickCustomRange() async {
    final lastDate = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
      initialDateRange: _customRange ?? _activeRange,
    );
    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _rangePreset = _StudentReportRangePreset.custom;
      _customRange = picked;
    });

    await _loadReport(showSpinner: true);
  }

  Future<void> _loadAll({bool showSpinner = true}) async {
    final id = _studentId;
    if (id == null) return;

    if (mounted && showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final range = _activeRange;
      final results = await Future.wait([
        ApiService.getStudentById(id),
        ApiService.getStudentReport(
          id.toString(),
          startDate: _dateParam(range.start),
          endDate: _dateParam(range.end),
        ),
      ]);

      final studentRes = results[0];
      final reportRes = results[1];

      if (!mounted) return;

      final nextStudent =
          (studentRes['success'] == true && studentRes['data'] is Map)
          ? Map<String, dynamic>.from(studentRes['data'] as Map)
          : _student;
      final nextReport =
          (reportRes['success'] == true && reportRes['data'] is Map)
          ? Map<String, dynamic>.from(reportRes['data'] as Map)
          : <String, dynamic>{};

      setState(() {
        _student = nextStudent;
        _report = nextReport;
        _loading = false;
        _error = studentRes['success'] == true
            ? null
            : (studentRes['error']?.toString() ?? 'Failed to load student');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load student: $e';
      });
    }
  }

  Future<void> _loadReport({bool showSpinner = true}) async {
    final id = _studentId;
    if (id == null) return;

    if (mounted && showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final range = _activeRange;
      final reportRes = await ApiService.getStudentReport(
        id.toString(),
        startDate: _dateParam(range.start),
        endDate: _dateParam(range.end),
      );
      if (!mounted) return;

      if (reportRes['success'] == true && reportRes['data'] is Map) {
        setState(() {
          _report = Map<String, dynamic>.from(reportRes['data'] as Map);
          _loading = false;
        });
        return;
      }

      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _buildRangeCard(ThemeData theme) {
    final range = _activeRange;
    final label = _rangeLabel(range);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range, size: 18),
              const SizedBox(width: 8),
              Text(
                'Report Range',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('This Month'),
                selected: _rangePreset == _StudentReportRangePreset.thisMonth,
                onSelected: _busyAction
                    ? null
                    : (selected) {
                        if (!selected) return;
                        _setRangePreset(_StudentReportRangePreset.thisMonth);
                      },
              ),
              ChoiceChip(
                label: const Text('30 Days'),
                selected: _rangePreset == _StudentReportRangePreset.last30Days,
                onSelected: _busyAction
                    ? null
                    : (selected) {
                        if (!selected) return;
                        _setRangePreset(_StudentReportRangePreset.last30Days);
                      },
              ),
              ChoiceChip(
                label: const Text('90 Days'),
                selected: _rangePreset == _StudentReportRangePreset.last90Days,
                onSelected: _busyAction
                    ? null
                    : (selected) {
                        if (!selected) return;
                        _setRangePreset(_StudentReportRangePreset.last90Days);
                      },
              ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _rangePreset == _StudentReportRangePreset.custom,
                onSelected: _busyAction ? null : (_) => _pickCustomRange(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  Future<void> _updateFace() async {
    final id = _studentId;
    if (id == null) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) UIHelpers.showError(context, 'No camera found');
        return;
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      if (!mounted) return;
      final XFile? photo = await showDialog<XFile>(
        context: context,
        builder: (context) => _CameraCaptureDialog(camera: frontCamera),
      );
      if (photo == null) return;

      if (!mounted) return;
      setState(() => _busyAction = true);

      final res = await ApiService.registerFace(
        studentId: id,
        imageFile: File(photo.path),
      );

      if (!mounted) return;
      setState(() => _busyAction = false);

      if (res['success'] == true) {
        UIHelpers.showSuccess(context, 'Face updated');
        await _loadAll(showSpinner: false);
        return;
      }

      UIHelpers.showError(context, res['error']?.toString() ?? 'Update failed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyAction = false);
      UIHelpers.showError(context, 'Camera error: $e');
    }
  }

  Future<void> _deleteStudent() async {
    final id = _studentId;
    if (id == null) return;

    final confirmed = await UIHelpers.showConfirmDialog(
      context: context,
      title: 'Delete student',
      message:
          'Are you sure you want to delete this student? This cannot be undone.',
      confirmText: 'Delete',
      isDangerous: true,
    );
    if (!confirmed) return;

    if (!mounted) return;
    setState(() => _busyAction = true);

    final res = await ApiService.deleteStudent(id);

    if (!mounted) return;
    setState(() => _busyAction = false);

    if (res['success'] == true) {
      UIHelpers.showSuccess(context, 'Student deleted');
      Navigator.of(context).pop(true);
      return;
    }

    UIHelpers.showError(context, res['error']?.toString() ?? 'Delete failed');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = (_student['full_name'] ?? _student['name'] ?? 'Student')
        .toString();
    final studentCode = (_student['student_id'] ?? '').toString();
    final className = (_student['class_name'] ?? _student['className'] ?? '')
        .toString();
    final faceEnrolled = _student['face_enrolled'] == true;
    final photoUrl = ApiService.uploadsUrl(_student['photo_path']?.toString());

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _studentId == null
                ? null
                : () => _loadAll(showSpinner: true),
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (_isAdmin && _studentId != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'update_face') _updateFace();
                if (value == 'delete') _deleteStudent();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'update_face', child: Text('Update face')),
                PopupMenuItem(value: 'delete', child: Text('Delete student')),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_studentId == null)
            _ErrorState(message: 'Missing student id')
          else if (_loading && _student.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _student.isEmpty)
            _ErrorState(
              message: _error!,
              onRetry: () => _loadAll(showSpinner: true),
            )
          else
            RefreshIndicator(
              onRefresh: () => _loadAll(showSpinner: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _StudentHeaderCard(
                    name: name,
                    studentId: studentCode,
                    className: className,
                    faceEnrolled: faceEnrolled,
                    photoUrl: photoUrl,
                  ),
                  const SizedBox(height: 16),
                  _buildRangeCard(theme),
                  const SizedBox(height: 16),
                  _AttendanceSummaryCard(report: _report),
                  const SizedBox(height: 16),
                  _AttendanceHistoryCard(report: _report),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          if (_busyAction)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.2),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Please wait...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: !_isAdmin || _studentId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busyAction ? null : _updateFace,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Update Face'),
            ),
    );
  }
}

class _StudentHeaderCard extends StatelessWidget {
  final String name;
  final String studentId;
  final String className;
  final bool faceEnrolled;
  final String? photoUrl;

  const _StudentHeaderCard({
    required this.name,
    required this.studentId,
    required this.className,
    required this.faceEnrolled,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = faceEnrolled ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.12),
              border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
            ),
            child: ClipOval(
              child: photoUrl == null
                  ? Center(
                      child: faceEnrolled
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 30,
                            )
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                    )
                  : Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: faceEnrolled
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 30,
                                )
                              : Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  studentId.isEmpty ? 'ID: —' : 'ID: $studentId',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  className.isEmpty ? 'Class: —' : 'Class: $className',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              faceEnrolled ? 'Registered' : 'Pending',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  final Map<String, dynamic> report;

  const _AttendanceSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final totalDays = _readInt(report, ['total_days', 'totalDays']);
    final daysPresent = _readInt(report, [
      'days_present',
      'present_days',
      'present',
    ]);
    final daysAbsent = _readInt(report, [
      'days_absent',
      'absent_days',
      'absent',
    ]);
    final attendanceRate = _readDouble(report, [
      'attendance_rate',
      'attendanceRate',
    ]);

    final safeTotal = totalDays > 0 ? totalDays : (daysPresent + daysAbsent);
    final safeRate = attendanceRate > 0
        ? attendanceRate
        : (safeTotal > 0 ? (daysPresent / safeTotal) * 100 : 0.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, size: 18),
              const SizedBox(width: 8),
              Text(
                'Attendance Summary',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Present',
                  value: daysPresent.toString(),
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'Absent',
                  value: daysAbsent.toString(),
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'Total',
                  value: safeTotal.toString(),
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: (safeRate.clamp(0, 100)) / 100,
              backgroundColor: theme.dividerColor.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Attendance rate: ${safeRate.toStringAsFixed(1)}%',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

class _AttendanceHistoryCard extends StatelessWidget {
  final Map<String, dynamic> report;

  const _AttendanceHistoryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = report['attendance_history'];
    final history = raw is List
        ? List<Map<String, dynamic>>.from(raw.whereType<Map>())
        : <Map<String, dynamic>>[];

    history.sort((a, b) {
      final da = (a['date'] ?? '').toString();
      final db = (b['date'] ?? '').toString();
      final ta = (a['time'] ?? '').toString();
      final tb = (b['time'] ?? '').toString();
      return ('$db $tb').compareTo('$da $ta');
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 8),
              Text(
                'Recent Attendance',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Text(
              'No attendance history found.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length.clamp(0, 30),
              separatorBuilder: (context, index) => Divider(
                height: 16,
                color: theme.dividerColor.withOpacity(0.2),
              ),
              itemBuilder: (context, index) {
                final item = history[index];
                final dateText = _formatDate(item['date']?.toString());
                final timeText = _formatTime(item['time']?.toString());
                final status = (item['status'] ?? 'present').toString();
                final confidence = _readDouble(item, [
                  'confidence',
                  'confidence_score',
                ]);
                final color = status.toLowerCase() == 'absent'
                    ? Colors.red
                    : Colors.green;

                return Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateText,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeText.isEmpty ? status : '$status • $timeText',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (confidence > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.dividerColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${(confidence * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraCaptureDialog extends StatefulWidget {
  final CameraDescription camera;
  const _CameraCaptureDialog({required this.camera});

  @override
  State<_CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<_CameraCaptureDialog> {
  CameraController? _controller;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              onPressed: _capturing ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  onPressed: _capturing
                      ? null
                      : () async {
                          setState(() => _capturing = true);
                          try {
                            final photo = await controller.takePicture();
                            if (!mounted) return;
                            Navigator.of(this.context).pop(photo);
                          } catch (_) {
                            if (!mounted) return;
                            setState(() => _capturing = false);
                          }
                        },
                  child: _capturing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _readInt(Map<String, dynamic> source, List<String> keys) {
  for (final k in keys) {
    final v = source[k];
    if (v == null) continue;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
  }
  return 0;
}

double _readDouble(Map<String, dynamic> source, List<String> keys) {
  for (final k in keys) {
    final v = source[k];
    if (v == null) continue;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll('%', '').trim();
      return double.tryParse(cleaned) ?? 0;
    }
  }
  return 0;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String _formatDate(String? isoDate) {
  if (isoDate == null || isoDate.trim().isEmpty) return '—';
  try {
    final dt = DateTime.parse(isoDate);
    return DateFormat.yMMMd().format(dt);
  } catch (_) {
    return isoDate;
  }
}

String _formatTime(String? isoTime) {
  if (isoTime == null || isoTime.trim().isEmpty) return '';
  try {
    final dt = DateTime.parse('1970-01-01T$isoTime');
    return DateFormat.Hm().format(dt);
  } catch (_) {
    return isoTime;
  }
}
