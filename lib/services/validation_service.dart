class ValidationService {
  static String? validateStudentId(String? value) {
    if (value == null || value.isEmpty) return 'Student ID is required';
    if (value.length < 6) return 'Student ID must be at least 6 characters';
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(value)) return 'Only uppercase letters and numbers allowed';
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.isEmpty) return 'Name is required';
    if (value.length < 2) return 'Name must be at least 2 characters';
    if (value.length > 50) return 'Name cannot exceed 50 characters';
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value)) return 'Only letters and spaces allowed';
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return 'Invalid email format';
    return null;
  }

  static String? validateIdentifier(String? value) {
    if (value == null || value.isEmpty) return 'Email or ID is required';
    final emailPattern = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    final idPattern = RegExp(r'^[A-Z0-9]+$');
    if (!emailPattern.hasMatch(value) && !idPattern.hasMatch(value.toUpperCase())) {
      return 'Enter a valid email or ID';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) return '$fieldName is required';
    return null;
  }
}
