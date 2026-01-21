import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/export_service.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends ConsumerState<AttendanceHistoryScreen> {
  List<Map<String, dynamic>> _attendanceRecords = [];
  bool _isLoading = true;
  String _searchQuery = '';
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getAttendanceHistory(_selectedDate);
    if (result['success']) {
      setState(() {
        _attendanceRecords = List<Map<String, dynamic>>.from(result['data'] ?? []);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportAttendance() async {
    final result = await ApiService.exportAttendanceCSV(_selectedDate);
    if (mounted) {
      if (result['success'] == true && result['data'] is String) {
        final file = await ExportService.saveCsvString(
          result['data'] as String,
          'attendance_history_${DateFormat('yyyyMMdd').format(_selectedDate)}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report saved: ${file.path}'), backgroundColor: Colors.green),
        );
      } else if (_attendanceRecords.isNotEmpty) {
        final file = await ExportService.exportToCSV(
          _attendanceRecords,
          'attendance_history_${DateFormat('yyyyMMdd').format(_selectedDate)}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report saved: ${file.path}'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to export'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRecords {
    if (_searchQuery.isEmpty) return _attendanceRecords;
    return _attendanceRecords.where((record) {
      final name = record['student_name']?.toString().toLowerCase() ?? '';
      final studentId = record['student_id']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase()) || studentId.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> get _groupedRecords {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var record in _filteredRecords) {
      final date = record['timestamp']?.toString().split('T')[0] ?? 'Unknown';
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(record);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text("Attendance History"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadAttendance,
            icon: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Search & Filters
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: "Search by Name or ID",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.calendar_month, size: 16, color: Colors.white),
                            label: Text(DateFormat('MMM dd, yyyy').format(_selectedDate), style: const TextStyle(color: Colors.white)),
                            backgroundColor: theme.colorScheme.primary,
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                                _loadAttendance();
                              }
                            },
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Records List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredRecords.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text('No attendance records', style: theme.textTheme.titleMedium),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAttendance,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              itemCount: _groupedRecords.length,
                              itemBuilder: (context, index) {
                                final date = _groupedRecords.keys.elementAt(index);
                                final records = _groupedRecords[date]!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        DateFormat('EEEE, MMM dd').format(DateTime.parse(date)),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    ...records.map((record) => _buildHistoryCard(context, record)),
                                    const SizedBox(height: 16),
                                  ],
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
          
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              onPressed: _exportAttendance,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.download, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, Map<String, dynamic> record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = record['status'] ?? 'present';
    final Color statusColor = status == 'present' ? Colors.green : (status == 'late' ? Colors.orange : Colors.red);
    final isAbsent = status == 'absent';
    final timeStr = record['timestamp'] != null 
        ? DateFormat('hh:mm a').format(DateTime.parse(record['timestamp']))
        : '--:--';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(isAbsent ? 0.8 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey[300],
                child: Text(
                  (record['student_name'] ?? 'U')[0].toUpperCase(),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
                  child: Icon(
                    isAbsent ? Icons.cancel : (status == 'late' ? Icons.schedule : Icons.check_circle),
                    size: 16,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      record['student_name'] ?? 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize:15,
                        color: isAbsent ? Colors.grey : theme.colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ID: ${record['student_id'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(timeStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
