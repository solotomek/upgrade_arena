import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upgrade_arena/game/arena_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new permanent upgrades spend coins and are included in saves', () {
    Map<UpgradeType, int>? savedLevels;
    var savedThreatTier = -1;
    final game = GameCore(
      onSave: (wallet, levels, threatTier) async {
        savedLevels = levels;
        savedThreatTier = threatTier;
      },
    );
    game.restoreProgress(100, {}, threatTier: 3);
    game.openArmory();

    for (final type in [
      UpgradeType.salvage,
      UpgradeType.rapid,
      UpgradeType.magnet,
      UpgradeType.regen,
      UpgradeType.critical,
    ]) {
      expect(game.buyUpgrade(type), isTrue);
    }
    expect(game.wallet, 60);
    for (final type in [
      UpgradeType.salvage,
      UpgradeType.rapid,
      UpgradeType.magnet,
      UpgradeType.regen,
      UpgradeType.critical,
    ]) {
      expect(game.level(type), 1);
    }
    expect(savedLevels?[UpgradeType.salvage], 1);
    expect(savedLevels?[UpgradeType.critical], 1);
    expect(savedThreatTier, 3);
    expect(game.threatTier, 3);

    game.snapshot.dispose();
  });

  test(
    'kills unlock the weapon ladder and upgrade costs rise quadratically',
    () {
      expect(GameCore.weaponForKills(0), ArenaWeapon.sidearm);
      expect(GameCore.weaponForKills(11), ArenaWeapon.sidearm);
      expect(GameCore.weaponForKills(12), ArenaWeapon.burst);
      expect(GameCore.weaponForKills(30), ArenaWeapon.scattergun);
      expect(GameCore.weaponForKills(55), ArenaWeapon.grenadeLauncher);
      expect(GameCore.weaponForKills(90), ArenaWeapon.bazooka);

      final game = GameCore(onSave: (wallet, levels, threatTier) async {});
      expect(game.upgradeCost(UpgradeType.power), 8);
      game.restoreProgress(0, {UpgradeType.power: 1});
      expect(game.upgradeCost(UpgradeType.power), 11);
      expect(game.weaponStatus, contains('SERVICE PISTOL'));
      game.snapshot.dispose();
    },
  );

  test(
    'magnet upgrade scales from a small pickup radius to screen-wide pull',
    () {
      final game = GameCore(onSave: (wallet, levels, threatTier) async {});
      expect(game.pickupMagnetRange, 30);

      game.restoreProgress(0, {UpgradeType.magnet: 1});
      expect(game.pickupMagnetRange, 57.5);

      game.restoreProgress(0, {UpgradeType.magnet: 9});
      expect(game.pickupMagnetRange, 457.5);
      game.snapshot.dispose();
    },
  );

  test('new sectors unlock every three waves', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});

    game.beginRun();
    expect(game.wave, 1);
    expect(game.sectorName, 'VERDANT WILDS');

    for (var wave = 2; wave <= 13; wave++) {
      game.openArmory();
      game.continueFromArmory();
      if (wave == 4) expect(game.sectorName, 'FOUNDRY CORE');
      if (wave == 7) expect(game.sectorName, 'CRYO VAULT');
      if (wave == 10) expect(game.sectorName, 'NEON ABYSS');
    }

    expect(game.wave, 13);
    expect(game.sectorName, 'VERDANT WILDS');
    expect(game.sectorIndex, 4);

    game.snapshot.dispose();
  });

  test('enemy roster evolves over later waves', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    game.onGameResize(Vector2(640, 480));
    game.beginRun();

    expect(game.enemyPositions, isNotEmpty);
    expect(
      game.enemyPositions.every(
        (position) => !game.isInsideCameraView(position, margin: 90),
      ),
      isTrue,
    );
    expect(game.concurrentEnemyLimit, greaterThan(8));

    for (var wave = 2; wave <= 5; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }

    expect(
      game.enemyTypesSpawned,
      containsAll(['stalker', 'gunner', 'charger', 'bomber']),
    );

    for (var wave = 6; wave <= 7; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }
    expect(game.enemyTypesSpawned, contains('weaver'));

    for (var wave = 8; wave <= 10; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }
    expect(game.enemyTypesSpawned, contains('sentinel'));
    expect(
      game.enemyPositions.every(
        (position) => !game.isInsideCameraView(position, margin: 90),
      ),
      isTrue,
    );
    game.snapshot.dispose();
  });

  test('the final sector ends in a named boss encounter', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});

    game.beginRun();
    for (var wave = 2; wave <= 12; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }

    expect(game.wave, 12);
    expect(game.sectorName, 'NEON ABYSS');
    expect(game.bossName, 'THE WARDEN');
    expect(game.snapshot.value.bossHealthFraction, 0);
    expect(game.snapshot.value.remainingThreats, 8);

    game.snapshot.dispose();
  });

  test('every wave reserves a commander, with pairs on milestone waves', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    game.beginRun();

    int pendingBosses() =>
        game.snapshot.value.remainingThreats -
        game.pendingReinforcements -
        game.enemyPositions.length;
    expect(pendingBosses(), 1);

    for (var wave = 2; wave <= 6; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }

    expect(pendingBosses(), 2);
    game.snapshot.dispose();
  });

  test('higher ascensions increase wave crowds and boss health', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    game.restoreProgress(0, {}, threatTier: 3);
    game.beginRun();

    expect(game.snapshot.value.threatTier, 3);
    expect(game.snapshot.value.remainingThreats, 48);

    for (var wave = 2; wave <= 12; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }

    expect(game.snapshot.value.bossMaxHealth, greaterThan(2200));
    expect(game.snapshot.value.remainingThreats, 17);

    game.snapshot.dispose();
  });

  test('reinforcements arrive while a wave is still in progress', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    game.beginRun();
    final queuedAtStart = game.pendingReinforcements;
    expect(queuedAtStart, greaterThan(0));

    for (var step = 0; step < 20; step++) {
      game.update(0.05);
    }

    expect(game.pendingReinforcements, lessThan(queuedAtStart));
    game.snapshot.dispose();
  });

  test(
    'first-wave enemies stay separated and the pistol earns early kills',
    () {
      final game = GameCore(onSave: (wallet, levels, threatTier) async {});
      game.onGameResize(Vector2(640, 480));
      game.beginRun();

      for (
        var step = 0;
        step < 300 && game.snapshot.value.phase == RunPhase.playing;
        step++
      ) {
        game.update(0.05);
        expect(game.minimumEnemyClearance, greaterThanOrEqualTo(3.9));
      }

      expect(game.kills, greaterThanOrEqualTo(2));
      game.snapshot.dispose();
    },
  );

  test('an unattended pilot can be overwhelmed by an ascension wave', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    game.restoreProgress(0, {}, threatTier: 5);
    game.beginRun();

    for (
      var step = 0;
      step < 2400 && game.snapshot.value.phase == RunPhase.playing;
      step++
    ) {
      game.update(0.05);
    }

    expect(game.snapshot.value.phase, RunPhase.ended);
    expect(game.snapshot.value.health, 0);
    game.snapshot.dispose();
  });

  test('gunner volleys demand movement and base hull is less forgiving', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    expect(game.snapshot.value.maxHealth, 70);
    game.beginRun();
    game.openArmory();
    game.continueFromArmory();

    for (
      var step = 0;
      step < 100 &&
          game.snapshot.value.phase == RunPhase.playing &&
          game.enemyProjectileCount < 2;
      step++
    ) {
      game.update(0.05);
    }

    expect(game.enemyProjectileCount, greaterThanOrEqualTo(2));
    game.snapshot.dispose();
  });

  test('stationary player is hit by later-wave fire around arena cover', () {
    final game = GameCore(onSave: (wallet, levels, threatTier) async {});
    game.onGameResize(Vector2(640, 480));
    game.beginRun();
    for (var wave = 2; wave <= 5; wave++) {
      game.openArmory();
      game.continueFromArmory();
    }

    for (
      var step = 0;
      step < 1200 &&
          game.snapshot.value.phase == RunPhase.playing &&
          game.snapshot.value.health >= game.snapshot.value.maxHealth;
      step++
    ) {
      game.update(0.05);
    }

    expect(game.snapshot.value.health, lessThan(game.snapshot.value.maxHealth));
    game.snapshot.dispose();
  });

  test('original ambient soundtrack is bundled with the app', () async {
    final music = await rootBundle.load('assets/audio/sector_theme.wav');

    expect(music.lengthInBytes, greaterThan(1000000));
  });
}
