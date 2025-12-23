import 'package:flutter/material.dart' hide ErrorWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontalminds_fr/widgets/common_widgets.dart';

void main() {
  group('Common Widgets Tests', () {
    testWidgets('LoadingWidget displays correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingWidget(message: 'Loading test'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading test'), findsOneWidget);
    });

    testWidgets('ErrorWidget displays correctly', (WidgetTester tester) async {
      bool retryPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorWidget(
              message: 'Test error message',
              onRetry: () => retryPressed = true,
            ),
          ),
        ),
      );

      expect(find.text('Test error message'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retryPressed, true);
    });

    testWidgets('LoadingButton shows loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoadingButton(
              text: 'Test Button',
              isLoading: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('ValidatedTextField shows validation error', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValidatedTextField(
              label: 'Test Field',
              controller: controller,
              validator: (value) => value?.isEmpty == true ? 'Required' : null,
            ),
          ),
        ),
      );

      expect(find.text('Test Field'), findsOneWidget);
      
      // Enter invalid text and trigger validation
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      
      // The validation should trigger on text change
      expect(find.text('Required'), findsOneWidget);
    });
  });
}