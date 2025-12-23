import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

class NavigationGuard {
  static bool canAccess(WidgetRef ref, String route) {
    final authState = ref.read(authProvider);
    
    final publicRoutes = ['/splash', '/login'];
    if (publicRoutes.contains(route)) return true;
    
    return authState.isAuthenticated;
  }

  static void checkAuthAndNavigate(BuildContext context, WidgetRef ref, String route) {
    if (canAccess(ref, route)) {
      Navigator.pushNamed(context, route);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }
}

class AuthGuardWrapper extends ConsumerWidget {
  final Widget child;
  final String routeName;

  const AuthGuardWrapper({
    super.key,
    required this.child,
    required this.routeName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    if (!NavigationGuard.canAccess(ref, routeName)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return child;
  }
}