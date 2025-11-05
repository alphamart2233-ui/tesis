// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Widget smoke test', () {
    testWidgets('renderiza un widget básico sin excepciones', (tester) async {
      // Construye un árbol mínimo y estable para el test.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Hola, FinTrack EC')),
          ),
        ),
      );

      // Verificaciones sencillas
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Hola, FinTrack EC'), findsOneWidget);
    });
  });
}
