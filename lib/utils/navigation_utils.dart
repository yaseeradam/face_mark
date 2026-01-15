class NavigationUtils {
  static List<String> keysForRole(String role) {
    return ['home', 'scan', 'students', 'reports', 'settings'];
  }

  static int indexForKey(String role, String key) {
    final keys = keysForRole(role);
    final index = keys.indexOf(key);
    return index >= 0 ? index : 0;
  }
}
