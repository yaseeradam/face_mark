import 'package:flutter_test/flutter_test.dart';

import 'package:frontalminds_fr/routes/app_routes.dart';

void main() {
  test('Routes include core screens', () {
    final routes = AppRoutes.routes;
    expect(routes.containsKey(AppRoutes.splash), isTrue);
    expect(routes.containsKey(AppRoutes.login), isTrue);
    expect(routes.containsKey(AppRoutes.dashboard), isTrue);
    expect(routes.containsKey(AppRoutes.studentList), isTrue);
    expect(routes.containsKey(AppRoutes.settings), isTrue);
  });
}
