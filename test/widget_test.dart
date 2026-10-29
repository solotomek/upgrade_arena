// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:upgrade_arena/game/arena_game.dart';
import 'package:upgrade_arena/main.dart';

void main() {
  testWidgets('player can deploy from the title screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(UpgradeArenaApp(preferences: preferences));
    await tester.pump();

    expect(find.text('DEPLOY'), findsOneWidget);
    await tester.tap(find.text('DEPLOY'));
    await tester.pump();

    expect(find.text('WAVE 01'), findsOneWidget);
  });

  testWidgets('first-run story can be skipped into the main menu', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      UpgradeArenaApp(preferences: preferences, showIntroOnLaunch: true),
    );
    await tester.pump();

    expect(find.text('THE LAST LIGHT'), findsOneWidget);
    expect(find.text('DEPLOY'), findsNothing);
    await tester.tap(find.text('TAP ANYWHERE TO SKIP'));
    await tester.pump();
    await tester.pump();

    expect(find.text('DEPLOY'), findsOneWidget);
    expect(preferences.getBool('storySeen'), isTrue);
  });

  testWidgets('touch dragging from the game area moves the player', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(UpgradeArenaApp(preferences: preferences));
    await tester.pump();
    await tester.tap(find.text('DEPLOY'));
    await tester.pump();

    final game = tester
        .widget<GameWidget<GameCore>>(find.byType(GameWidget<GameCore>))
        .game!;
    final start = game.playerPosition;
    final gesture = await tester.startGesture(const Offset(170, 400));
    await gesture.moveBy(const Offset(68, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();

    expect(game.playerPosition.x, greaterThan(start.x));
  });

  testWidgets('armory upgrades spend and persist banked coins', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bankedCoins': 20,
      'threatTier': 3,
      'upgrade.power': 0,
      'upgrade.hull': 0,
      'upgrade.stride': 0,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(UpgradeArenaApp(preferences: preferences));
    await tester.pump();
    await tester.tap(find.text('OPEN ARMORY'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('upgrade-buy-power')));
    await tester.pump();

    expect(preferences.getInt('bankedCoins'), 12);
    expect(preferences.getInt('threatTier'), 3);
    expect(preferences.getInt('upgrade.power'), 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(UpgradeArenaApp(preferences: preferences));
    await tester.pump();
    await tester.tap(find.text('OPEN ARMORY'));
    await tester.pump();

    expect(find.text('RANK 1  /  9'), findsOneWidget);
    expect(find.text('BUY  ·  11'), findsOneWidget);
  });
}
