import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyphor_vault/features/splash_auth/screens/pin_entry_screen.dart';
import 'package:cyphor_vault/shared/theme/app_palette.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

void main() {
  for (final width in [360.0, 390.0, 412.0, 458.0, 600.0]) {
    testWidgets('PinEntryScreen horizontal alignment at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: const ProviderScope(
            child: PinEntryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final screenCenter = tester.getCenter(find.byType(Scaffold));
      final pinFieldCenter = tester.getCenter(find.byType(MaterialPinField));
      final iconCenter = tester.getCenter(find.byIcon(Icons.lock_outline_rounded));
      final titleCenter = tester.getCenter(find.text('Enter PIN'));
      final buttonCenter = tester.getCenter(find.text('Forgot PIN? Recover vault'));

      expect(pinFieldCenter.dx, equals(screenCenter.dx));
      expect(iconCenter.dx, equals(screenCenter.dx));
      expect(titleCenter.dx, equals(screenCenter.dx));
      expect(buttonCenter.dx, equals(screenCenter.dx));
    });
  }
}
