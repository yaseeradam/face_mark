class SearchService {
  static List<Map<String, dynamic>> searchStudents(
    List<Map<String, dynamic>> students,
    String query, {
    String? classFilter,
    String? statusFilter,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    if (students.isEmpty) return [];

    var filtered = students.where((student) {
      // Text search
      if (query.isNotEmpty) {
        final searchFields = [
          student['name']?.toString().toLowerCase() ?? '',
          student['student_id']?.toString().toLowerCase() ?? '',
          student['email']?.toString().toLowerCase() ?? '',
        ];

        final queryLower = query.toLowerCase();
        final matchesQuery = searchFields.any((field) => field.contains(queryLower));
        if (!matchesQuery) return false;
      }

      // Class filter
      if (classFilter != null && classFilter.isNotEmpty) {
        if (student['class_id']?.toString() != classFilter) return false;
      }

      // Status filter
      if (statusFilter != null && statusFilter.isNotEmpty) {
        if (student['status']?.toString() != statusFilter) return false;
      }

      // Date range filter
      if (dateFrom != null || dateTo != null) {
        final createdAt = DateTime.tryParse(student['created_at']?.toString() ?? '');
        if (createdAt != null) {
          if (dateFrom != null && createdAt.isBefore(dateFrom)) return false;
          if (dateTo != null && createdAt.isAfter(dateTo)) return false;
        }
      }

      return true;
    }).toList();

    return filtered;
  }

  static List<Map<String, dynamic>> searchAttendance(
    List<Map<String, dynamic>> attendance,
    String query, {
    String? statusFilter,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    if (attendance.isEmpty) return [];

    return attendance.where((record) {
      // Text search
      if (query.isNotEmpty) {
        final searchFields = [
          record['student_name']?.toString().toLowerCase() ?? '',
          record['student_id']?.toString().toLowerCase() ?? '',
          record['class_name']?.toString().toLowerCase() ?? '',
        ];

        final queryLower = query.toLowerCase();
        final matchesQuery = searchFields.any((field) => field.contains(queryLower));
        if (!matchesQuery) return false;
      }

      // Status filter
      if (statusFilter != null && statusFilter.isNotEmpty) {
        if (record['status']?.toString() != statusFilter) return false;
      }

      // Date range filter
      if (dateFrom != null || dateTo != null) {
        final recordDate = DateTime.tryParse(record['date']?.toString() ?? '');
        if (recordDate != null) {
          if (dateFrom != null && recordDate.isBefore(dateFrom)) return false;
          if (dateTo != null && recordDate.isAfter(dateTo)) return false;
        }
      }

      return true;
    }).toList();
  }

  static List<Map<String, dynamic>> sortData(
    List<Map<String, dynamic>> data,
    String sortBy,
    bool ascending,
  ) {
    final sorted = List<Map<String, dynamic>>.from(data);

    sorted.sort((a, b) {
      final aValue = a[sortBy];
      final bValue = b[sortBy];

      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return ascending ? -1 : 1;
      if (bValue == null) return ascending ? 1 : -1;

      int comparison;
      if (aValue is String && bValue is String) {
        comparison = aValue.toLowerCase().compareTo(bValue.toLowerCase());
      } else if (aValue is DateTime && bValue is DateTime) {
        comparison = aValue.compareTo(bValue);
      } else {
        comparison = aValue.toString().compareTo(bValue.toString());
      }

      return ascending ? comparison : -comparison;
    });

    return sorted;
  }

  static List<String> getSuggestions(
    List<Map<String, dynamic>> data,
    String field,
    String query,
  ) {
    final suggestions = <String>{};

    for (final item in data) {
      final value = item[field]?.toString();
      if (value != null && value.toLowerCase().contains(query.toLowerCase())) {
        suggestions.add(value);
      }
    }

    return suggestions.take(5).toList();
  }
}