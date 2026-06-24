import 'package:chef_kart/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chef_kart/main.dart';

void main() {
  testWidgets('Initial screen is OnboardingScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const ChefKartApp());
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('Onboarding skip works without network images', (WidgetTester tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(
        onComplete: () => completed = true,
        disableNetworkImages: true,
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('Find Verified Home Chefs'), findsOneWidget);

    // Skip directly
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });
}
