import 'package:flutter_riverpod/flutter_riverpod.dart';

// Loading state provider
final loadingProvider = StateNotifierProvider<LoadingNotifier, bool>((ref) {
  return LoadingNotifier();
});

class LoadingNotifier extends StateNotifier<bool> {
  LoadingNotifier() : super(false);

  void setLoading(bool loading) {
    state = loading;
  }
}

// Error state provider
final errorProvider = StateNotifierProvider<ErrorNotifier, String?>((ref) {
  return ErrorNotifier();
});

class ErrorNotifier extends StateNotifier<String?> {
  ErrorNotifier() : super(null);

  void setError(String? error) {
    state = error;
  }

  void clearError() {
    state = null;
  }
}

// Authentication state provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthState {
  final bool isAuthenticated;
  final String? token;
  final Map<String, dynamic>? user;

  AuthState({
    this.isAuthenticated = false,
    this.token,
    this.user,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? token,
    Map<String, dynamic>? user,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      token: token ?? this.token,
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState());

  void login(String token, Map<String, dynamic> user) {
    state = state.copyWith(
      isAuthenticated: true,
      token: token,
      user: user,
    );
  }

  void logout() {
    state = AuthState();
  }
}

// Navigation state provider
final navigationProvider = StateProvider<int>((ref) => 0);

// Increment to force-refresh attendance-dependent UI (dashboard, student stats, etc.)
final attendanceRefreshProvider = StateProvider<int>((ref) => 0);
