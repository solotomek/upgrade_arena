import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum RunPhase { intro, title, playing, armory, paused, ended, victory }

enum UpgradeType {
  power,
  hull,
  stride,
  rapid,
  magnet,
  salvage,
  regen,
  critical,
}

enum PickupType { coin, surge, force, repair }

enum _EnemyType { stalker, gunner, charger, bomber, weaver, sentinel }

enum ArenaWeapon { sidearm, burst, scattergun, grenadeLauncher, bazooka }

class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.wave,
    required this.health,
    required this.maxHealth,
    required this.wallet,
    required this.kills,
    required this.seed,
    required this.powerLevel,
    required this.hullLevel,
    required this.strideLevel,
    required this.surgeSeconds,
    required this.forceSeconds,
    required this.bossHealth,
    required this.bossMaxHealth,
    required this.remainingThreats,
    required this.threatTier,
  });

  final RunPhase phase;
  final int wave;
  final double health;
  final double maxHealth;
  final int wallet;
  final int kills;
  final int seed;
  final int powerLevel;
  final int hullLevel;
  final int strideLevel;
  final double surgeSeconds;
  final double forceSeconds;
  final double bossHealth;
  final double bossMaxHealth;
  final int remainingThreats;
  final int threatTier;

  double get healthFraction => maxHealth == 0 ? 0 : health / maxHealth;
  double get bossHealthFraction =>
      bossMaxHealth == 0 ? 0 : bossHealth / bossMaxHealth;

  String? get activePower {
    if (surgeSeconds > 0) return 'SURGE';
    if (forceSeconds > 0) return 'FORCE';
    return null;
  }
}

class GameCore extends FlameGame with KeyboardEvents {
  GameCore({required this.onSave, this.onIntroSeen, bool showIntro = false})
    : _phase = showIntro ? RunPhase.intro : RunPhase.title {
    _generateArena();
    snapshot = ValueNotifier(_makeSnapshot());
  }

  static const double arenaWidth = 1800;
  static const double arenaHeight = 1320;
  static const Color ink = Color(0xFF0D1512);
  static const Color mint = Color(0xFF93F5B6);
  static const Color gold = Color(0xFFFFCF72);
  static const Color coral = Color(0xFFFF796A);

  final Future<void> Function(
    int wallet,
    Map<UpgradeType, int> levels,
    int threatTier,
  )
  onSave;
  final VoidCallback? onIntroSeen;
  late final ValueNotifier<GameSnapshot> snapshot;

  final Vector2 _player = Vector2(arenaWidth / 2, arenaHeight / 2);
  Vector2 _viewportSize = Vector2(900, 700);
  final List<Rect> _obstacles = [];
  final List<_Enemy> _enemies = [];
  final List<_Bullet> _bullets = [];
  final List<_Bullet> _enemyBullets = [];
  final List<_Pickup> _pickups = [];
  final Map<UpgradeType, int> _levels = {
    UpgradeType.power: 0,
    UpgradeType.hull: 0,
    UpgradeType.stride: 0,
    UpgradeType.rapid: 0,
    UpgradeType.magnet: 0,
    UpgradeType.salvage: 0,
    UpgradeType.regen: 0,
    UpgradeType.critical: 0,
  };
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  RunPhase _phase = RunPhase.title;
  Vector2 _touchMove = Vector2.zero();
  bool _touchFire = false;
  bool _runActive = false;
  int _wallet = 0;
  int _threatTier = 0;
  int _wave = 0;
  int _kills = 0;
  int _remainingSpawns = 0;
  int _pendingWaveBosses = 0;
  int _enemiesSpawnedThisWave = 0;
  final Set<_EnemyType> _enemyTypesSpawned = {};
  int _seed = 0;
  double _health = 70;
  double _fireCooldown = 0;
  double _snapshotCooldown = 0;
  double _surgeTimer = 0;
  double _forceTimer = 0;
  double _spawnCooldown = 0;
  double _visualTime = 0;
  double _damageFlash = 0;
  bool _playerMoving = false;
  final Vector2 _playerVelocity = Vector2.zero();
  math.Random _random = math.Random();

  double get maxHealth => 70 + (_levels[UpgradeType.hull] ?? 0) * 14;
  int get wallet => _wallet;
  int get threatTier => _threatTier;
  int get pendingReinforcements => _remainingSpawns;
  int get enemyProjectileCount => _enemyBullets.length;
  List<Vector2> get enemyProjectilePositions =>
      _enemyBullets.map((bullet) => bullet.position.clone()).toList();
  int get concurrentEnemyLimit =>
      math.min(36, 18 + sectorIndex * 2 + _threatTier * 2);
  List<Vector2> get enemyPositions =>
      _enemies.map((enemy) => enemy.position.clone()).toList();
  double get minimumEnemyClearance {
    var minimumClearance = double.infinity;
    for (var first = 0; first < _enemies.length; first++) {
      for (var second = first + 1; second < _enemies.length; second++) {
        final clearance =
            _enemies[first].position.distanceTo(_enemies[second].position) -
            _enemies[first].radius -
            _enemies[second].radius;
        minimumClearance = math.min(minimumClearance, clearance);
      }
    }
    return minimumClearance;
  }

  Set<String> get enemyTypesSpawned =>
      _enemyTypesSpawned.map((type) => type.name).toSet();
  bool isInsideCameraView(Vector2 point, {double margin = 0}) =>
      _visibleWorldRect.inflate(margin).contains(Offset(point.x, point.y));
  double get pickupMagnetRange {
    final rank = level(UpgradeType.magnet);
    return rank == 0 ? 30 : 30 + rank * 25 + rank * rank * 2.5;
  }

  int get wave => _wave;
  int get kills => _kills;
  int get seed => _seed;
  Vector2 get playerPosition => _player.clone();
  int level(UpgradeType type) => _levels[type] ?? 0;
  int get sectorIndex => math.max(0, _wave - 1) ~/ 3;
  String get sectorName => const [
    'VERDANT WILDS',
    'FOUNDRY CORE',
    'CRYO VAULT',
    'NEON ABYSS',
  ][sectorIndex % 4];
  String get bossName =>
      _wave % 12 == 0 ? 'THE WARDEN' : 'WAVE $_wave COMMANDER';
  ArenaWeapon get currentWeapon => weaponForKills(_kills);
  String get weaponName => switch (currentWeapon) {
    ArenaWeapon.sidearm => 'SERVICE PISTOL',
    ArenaWeapon.burst => 'BURST RIFLE',
    ArenaWeapon.scattergun => 'SCATTERGUN',
    ArenaWeapon.grenadeLauncher => 'GRENADE LAUNCHER',
    ArenaWeapon.bazooka => 'BAZOOKA',
  };
  String get weaponStatus {
    final weapon = currentWeapon;
    final next = switch (weapon) {
      ArenaWeapon.sidearm => (12, 'BURST RIFLE'),
      ArenaWeapon.burst => (30, 'SCATTERGUN'),
      ArenaWeapon.scattergun => (55, 'GRENADE LAUNCHER'),
      ArenaWeapon.grenadeLauncher => (90, 'BAZOOKA'),
      ArenaWeapon.bazooka => null,
    };
    return next == null
        ? '$weaponName · MAX WEAPON'
        : '$weaponName · ${next.$1 - _kills} KILLS TO ${next.$2}';
  }

  static ArenaWeapon weaponForKills(int kills) {
    if (kills >= 90) return ArenaWeapon.bazooka;
    if (kills >= 55) return ArenaWeapon.grenadeLauncher;
    if (kills >= 30) return ArenaWeapon.scattergun;
    if (kills >= 12) return ArenaWeapon.burst;
    return ArenaWeapon.sidearm;
  }

  Color get _floorColor => const [
    Color(0xFF17231E),
    Color(0xFF291B19),
    Color(0xFF17232B),
    Color(0xFF21182C),
  ][sectorIndex % 4];
  Color get _floorTileColor => const [
    Color(0xFF1A2922),
    Color(0xFF38231E),
    Color(0xFF1B2C38),
    Color(0xFF2C1F3C),
  ][sectorIndex % 4];
  Color get _accentColor => const [
    Color(0xFF7CE2A0),
    Color(0xFFFF986E),
    Color(0xFF83DDF7),
    Color(0xFFD58CFF),
  ][sectorIndex % 4];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _publish();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _viewportSize = size.clone();
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    _pressedKeys
      ..clear()
      ..addAll(keysPressed);

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_phase == RunPhase.intro) {
        finishIntro();
      } else if (_phase == RunPhase.playing) {
        _runActive = false;
        _setPhase(RunPhase.title);
      } else if (_phase == RunPhase.armory) {
        continueFromArmory();
      } else if (_phase == RunPhase.victory || _phase == RunPhase.ended) {
        returnToTitle();
      }
      return KeyEventResult.handled;
    }

    final gameKeys = {
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.space,
    };
    return gameKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void restoreProgress(
    int wallet,
    Map<UpgradeType, int> levels, {
    int threatTier = 0,
  }) {
    _wallet = math.max(0, wallet);
    _threatTier = math.max(0, threatTier);
    for (final type in UpgradeType.values) {
      _levels[type] = math.max(0, levels[type] ?? 0);
    }
    _health = maxHealth;
    _publish();
  }

  void setMovement(Vector2 movement) {
    _touchMove = movement;
  }

  void setFireHeld(bool value) {
    _touchFire = value;
  }

  void beginRun() {
    _runActive = true;
    _wave = 0;
    _kills = 0;
    _health = maxHealth;
    _surgeTimer = 0;
    _forceTimer = 0;
    _remainingSpawns = 0;
    _pendingWaveBosses = 0;
    _spawnCooldown = 0;
    _fireCooldown = 0;
    _touchMove = Vector2.zero();
    _touchFire = false;
    _beginNextWave();
  }

  void openArmory() {
    _setPhase(RunPhase.armory);
  }

  void finishIntro() {
    if (_phase != RunPhase.intro) return;
    onIntroSeen?.call();
    _setPhase(RunPhase.title);
  }

  void continueFromArmory() {
    if (_runActive) {
      _beginNextWave();
    } else {
      _setPhase(RunPhase.title);
    }
  }

  void pauseRun() {
    if (_phase == RunPhase.playing) _setPhase(RunPhase.paused);
  }

  void abandonRun() {
    _runActive = false;
    _touchMove = Vector2.zero();
    _touchFire = false;
    _setPhase(RunPhase.title);
  }

  void resumeRun() {
    if (_phase == RunPhase.paused) _setPhase(RunPhase.playing);
  }

  void returnToTitle() {
    if (_phase == RunPhase.ended || _phase == RunPhase.victory) {
      _setPhase(RunPhase.title);
    }
  }

  int upgradeCost(UpgradeType type) => 8 + level(type) * level(type) * 3;

  String upgradeName(UpgradeType type) => switch (type) {
    UpgradeType.power => 'PULSE CORE',
    UpgradeType.hull => 'REINFORCED HULL',
    UpgradeType.stride => 'ION TREADS',
    UpgradeType.rapid => 'RAPID COIL',
    UpgradeType.magnet => 'SALVAGE MAGNET',
    UpgradeType.salvage => 'SCAVENGER PROTOCOL',
    UpgradeType.regen => 'NANO-REPAIR',
    UpgradeType.critical => 'OVERCHARGE LENS',
  };

  String upgradeEffect(UpgradeType type) => switch (type) {
    UpgradeType.power => 'DAMAGE +7',
    UpgradeType.hull => 'VITALITY +14',
    UpgradeType.stride => 'SPEED +12%',
    UpgradeType.rapid => 'FIRE RATE +12%',
    UpgradeType.magnet =>
      'PULL RADIUS +${(27.5 + level(UpgradeType.magnet) * 5).round()} / SPEED +50',
    UpgradeType.salvage => 'BONUS COINS EVERY 4 KILLS / RANK',
    UpgradeType.regen => 'REGEN +0.55 / SEC',
    UpgradeType.critical => 'CRIT CHANCE +7%',
  };

  bool buyUpgrade(UpgradeType type) {
    final cost = upgradeCost(type);
    if (_phase != RunPhase.armory || _wallet < cost || level(type) >= 9) {
      return false;
    }

    final oldMaxHealth = maxHealth;
    _wallet -= cost;
    _levels[type] = level(type) + 1;
    if (type == UpgradeType.hull) {
      _health = math.min(maxHealth, _health + maxHealth - oldMaxHealth);
    }
    _saveProgress();
    _publish();
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_phase != RunPhase.playing) return;

    final step = dt.clamp(0, 0.05).toDouble();
    _visualTime += step;
    _damageFlash = math.max(0, _damageFlash - step);
    _surgeTimer = math.max(0, _surgeTimer - step);
    _forceTimer = math.max(0, _forceTimer - step);
    _health = math.min(
      maxHealth,
      _health + level(UpgradeType.regen) * 0.35 * step,
    );
    _movePlayer(step);
    _fire(step);
    _spawnReinforcements(step);
    for (final enemy in _enemies) {
      enemy.hitFlash = math.max(0, enemy.hitFlash - step);
    }
    _moveEnemies(step);
    _moveBullets(step);
    _moveEnemyBullets(step);
    _collectPickups(step);

    if (_enemies.isEmpty && _remainingSpawns == 0 && _pendingWaveBosses > 0) {
      _spawnWaveBoss();
    }

    if (_health <= 0) {
      _health = 0;
      _runActive = false;
      _saveProgress();
      _setPhase(RunPhase.ended);
      return;
    }

    if (_enemies.isEmpty && _remainingSpawns == 0) {
      if (_wave % 12 == 0) {
        _runActive = false;
        _threatTier++;
        _saveProgress();
        _setPhase(RunPhase.victory);
      } else {
        _setPhase(RunPhase.armory);
      }
    }

    _snapshotCooldown -= step;
    if (_snapshotCooldown <= 0) {
      _snapshotCooldown = 0.12;
      _publish();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawColor(ink, BlendMode.src);

    final cameraX = math.max(
      size.x / 2,
      math.min(_player.x, arenaWidth - size.x / 2),
    );
    final cameraY = math.max(
      size.y / 2,
      math.min(_player.y, arenaHeight - size.y / 2),
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y));
    canvas.translate(size.x / 2 - cameraX, size.y / 2 - cameraY);
    _drawFloor(canvas, cameraX, cameraY);
    _drawArena(canvas);
    _drawPickups(canvas);
    _drawBullets(canvas);
    _drawEnemies(canvas);
    _drawPlayer(canvas);
    canvas.restore();
  }

  void _movePlayer(double dt) {
    final left =
        _pressedKeys.contains(LogicalKeyboardKey.keyA) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft);
    final right =
        _pressedKeys.contains(LogicalKeyboardKey.keyD) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight);
    final up =
        _pressedKeys.contains(LogicalKeyboardKey.keyW) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowUp);
    final down =
        _pressedKeys.contains(LogicalKeyboardKey.keyS) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown);

    final movement = Vector2(
      (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0) + _touchMove.x,
      (down ? 1.0 : 0.0) - (up ? 1.0 : 0.0) + _touchMove.y,
    );
    _playerMoving = movement.length2 > 0.02;
    if (movement.length2 > 1) movement.normalize();
    final speed =
        (190 + level(UpgradeType.stride) * 12) * (_surgeTimer > 0 ? 1.55 : 1.0);
    final previousPosition = _player.clone();
    _moveBody(_player, movement * speed * dt, 15);
    if (dt > 0) _playerVelocity.setFrom((_player - previousPosition) / dt);
  }

  void _fire(double dt) {
    _fireCooldown -= dt;
    if (_fireCooldown > 0 || _enemies.isEmpty) return;

    final targets = _enemies.toList()
      ..sort(
        (first, second) => first.position
            .distanceTo(_player)
            .compareTo(second.position.distanceTo(_player)),
      );
    final visibleTargets = targets
        .where((enemy) => _hasClearShot(_player, enemy.position))
        .toList();
    if (visibleTargets.isEmpty) return;
    final target = visibleTargets.first;
    final aimProjectileSpeed = _weaponProjectileSpeed(currentWeapon);
    final flightTime =
        (target.position.distanceTo(_player) / aimProjectileSpeed)
            .clamp(0.0, 0.65)
            .toDouble();
    final predictedPosition = target.position + target.velocity * flightTime;
    final aimTarget = _hasClearShot(_player, predictedPosition)
        ? predictedPosition
        : target.position;
    final aim = aimTarget - _player;
    if (aim.length2 == 0) return;
    aim.normalize();

    final weapon = currentWeapon;
    final (
      shots,
      damage,
      spread,
      projectileSpeed,
      blastRadius,
      cooldown,
    ) = switch (weapon) {
      ArenaWeapon.sidearm => (1, 36.0, 0.0, 620.0, 0.0, 0.28),
      ArenaWeapon.burst => (3, 16.0, 0.075, 640.0, 0.0, 0.38),
      ArenaWeapon.scattergun => (5, 12.0, 0.21, 530.0, 0.0, 0.62),
      ArenaWeapon.grenadeLauncher => (1, 42.0, 0.0, 340.0, 78.0, 0.88),
      ArenaWeapon.bazooka => (1, 78.0, 0.0, 430.0, 118.0, 1.05),
    };
    final criticalMultiplier =
        _random.nextDouble() < level(UpgradeType.critical) * 0.07 ? 2.0 : 1.0;
    for (var index = 0; index < shots; index++) {
      final angle =
          math.atan2(aim.y, aim.x) + _spreadOffset(index, shots, spread);
      final direction = Vector2(math.cos(angle), math.sin(angle));
      _bullets.add(
        _Bullet(
          position: _player + direction * 22,
          velocity: direction * projectileSpeed,
          damage:
              (damage + level(UpgradeType.power) * 7) *
              (_forceTimer > 0 ? 1.8 : 1.0) *
              criticalMultiplier,
          blastRadius: blastRadius,
          heavy: blastRadius > 0,
          life: blastRadius > 0 ? 6 : 1.5,
        ),
      );
    }
    _fireCooldown =
        _touchFire ||
            _pressedKeys.contains(LogicalKeyboardKey.space) ||
            _surgeTimer > 0
        ? math.max(0.1, 0.14 / (1 + level(UpgradeType.rapid) * 0.12))
        : math.max(0.16, cooldown / (1 + level(UpgradeType.rapid) * 0.12));
  }

  double _spreadOffset(int index, int count, double spread) {
    if (count.isOdd) return (index - count ~/ 2) * spread;
    if (index == 0) return 0;
    final radius = (index + 1) ~/ 2;
    return (index.isOdd ? -radius : radius) * spread;
  }

  double _weaponProjectileSpeed(ArenaWeapon weapon) => switch (weapon) {
    ArenaWeapon.sidearm => 620,
    ArenaWeapon.burst => 640,
    ArenaWeapon.scattergun => 530,
    ArenaWeapon.grenadeLauncher => 340,
    ArenaWeapon.bazooka => 430,
  };

  void _moveEnemies(double dt) {
    final previousPositions = {
      for (final enemy in _enemies) enemy: enemy.position.clone(),
    };
    for (final enemy in _enemies) {
      enemy.previousPosition.setFrom(enemy.position);
      enemy.velocity.setZero();
      final towardPlayer = _player - enemy.position;
      final distance = towardPlayer.length;
      if (enemy.type == _EnemyType.charger) {
        enemy.attackCooldown -= dt;
        if (enemy.charging) {
          enemy.chargeTimer -= dt;
          if (enemy.chargeTimer <= 0) {
            enemy.charging = false;
            enemy.chargeCooldown = math.max(1.8, 3.2 - _wave * 0.04);
          }
          _moveBody(
            enemy.position,
            enemy.chargeDirection * enemy.speed * 2.8 * dt,
            enemy.radius,
          );
          if (enemy.position.distanceTo(_player) < enemy.radius + 22) {
            _damagePlayer(enemy.damage * 1.35);
            enemy.charging = false;
            enemy.chargeCooldown = 2.0;
          }
          continue;
        }
        enemy.chargeCooldown -= dt;
        if (enemy.chargeCooldown <= 0 && distance < 520) {
          enemy.charging = true;
          enemy.chargeTimer = 0.55;
          enemy.chargeDirection = towardPlayer.clone();
          if (enemy.chargeDirection.length2 > 0) {
            enemy.chargeDirection.normalize();
          }
          continue;
        }
        if (distance > enemy.radius + 15) {
          _steerEnemy(enemy, towardPlayer, dt);
        } else if (enemy.attackCooldown <= 0) {
          enemy.attackCooldown = 0.55;
          _damagePlayer(enemy.damage);
        }
      } else if (enemy.type == _EnemyType.weaver) {
        enemy.attackCooldown -= dt;
        const preferredDistance = 285.0;
        if (!_hasClearShot(enemy.position, _player)) {
          _seekClearFiringPosition(enemy, preferredDistance, dt);
        } else if (distance > preferredDistance + 50) {
          _steerEnemy(enemy, towardPlayer, dt);
        } else if (distance < preferredDistance - 55) {
          _steerEnemy(enemy, -towardPlayer, dt);
        } else {
          final orbit =
              Vector2(-towardPlayer.y, towardPlayer.x) *
              enemy.orbitDirection.toDouble();
          _steerEnemy(enemy, orbit, dt);
        }
        _fireEnemyVolley(enemy, distance, 3, 0.16);
      } else if (enemy.type == _EnemyType.gunner ||
          enemy.type == _EnemyType.bomber ||
          enemy.type == _EnemyType.sentinel ||
          enemy.boss) {
        enemy.attackCooldown -= dt;
        final preferredDistance = switch (enemy.type) {
          _EnemyType.bomber => 330.0,
          _EnemyType.sentinel => 290.0,
          _ => 255.0,
        };
        if (!_hasClearShot(enemy.position, _player)) {
          _seekClearFiringPosition(enemy, preferredDistance, dt);
        } else if (distance > preferredDistance + 40) {
          _steerEnemy(enemy, towardPlayer, dt);
        } else if (distance < preferredDistance - 55) {
          _steerEnemy(enemy, -towardPlayer, dt);
        }
        final shots = enemy.boss
            ? (enemy.health <= enemy.maxHealth * 0.25
                  ? 7
                  : enemy.health <= enemy.maxHealth / 2
                  ? 5
                  : 3)
            : enemy.type == _EnemyType.sentinel
            ? 8
            : enemy.type == _EnemyType.bomber
            ? 5
            : _wave >= 6
            ? 3
            : 2;
        _fireEnemyVolley(
          enemy,
          distance,
          shots,
          enemy.type == _EnemyType.bomber
              ? 0.38
              : enemy.boss && enemy.health <= enemy.maxHealth * 0.25
              ? 0.27
              : 0.2,
        );
      } else if (distance > enemy.radius + 15) {
        _steerEnemy(enemy, towardPlayer, dt);
      } else {
        enemy.attackCooldown -= dt;
        if (enemy.attackCooldown <= 0) {
          enemy.attackCooldown = 0.48;
          _damagePlayer(enemy.damage);
        }
      }
    }
    _resolveEnemyOverlaps();
    if (dt > 0) {
      for (final enemy in _enemies) {
        enemy.velocity.setFrom(
          (enemy.position - previousPositions[enemy]!) / dt,
        );
      }
    }
  }

  void _resolveEnemyOverlaps() {
    const clearance = 4.0;
    const candidateAngles = [0.0, 0.55, -0.55, 1.1, -1.1, 1.65, -1.65];
    for (var pass = 0; pass < 8; pass++) {
      for (var firstIndex = 0; firstIndex < _enemies.length; firstIndex++) {
        final first = _enemies[firstIndex];
        for (
          var secondIndex = firstIndex + 1;
          secondIndex < _enemies.length;
          secondIndex++
        ) {
          final second = _enemies[secondIndex];
          final offset = second.position - first.position;
          final distance = offset.length;
          final requiredDistance = first.radius + second.radius + clearance;
          if (distance >= requiredDistance) continue;

          final direction = distance > 0.001
              ? offset / distance
              : Vector2(
                  math.cos((firstIndex * 17 + secondIndex * 31).toDouble()),
                  math.sin((firstIndex * 17 + secondIndex * 31).toDouble()),
                );
          final pushDistance = requiredDistance - distance;
          var separated = false;
          for (final angle in candidateAngles) {
            final candidateDirection = Vector2(
              direction.x * math.cos(angle) - direction.y * math.sin(angle),
              direction.x * math.sin(angle) + direction.y * math.cos(angle),
            );
            final firstPosition =
                first.position - candidateDirection * (pushDistance / 2);
            final secondPosition =
                second.position + candidateDirection * (pushDistance / 2);
            if (_hitsObstacle(firstPosition, first.radius) ||
                _hitsObstacle(secondPosition, second.radius)) {
              continue;
            }
            first.position.setFrom(firstPosition);
            second.position.setFrom(secondPosition);
            separated = true;
            break;
          }
          if (separated) continue;

          for (final angle in candidateAngles) {
            final candidateDirection = Vector2(
              direction.x * math.cos(angle) - direction.y * math.sin(angle),
              direction.x * math.sin(angle) + direction.y * math.cos(angle),
            );
            final candidate =
                second.position + candidateDirection * pushDistance;
            if (_hitsObstacle(candidate, second.radius) ||
                candidate.distanceTo(first.position) < requiredDistance) {
              continue;
            }
            second.position.setFrom(candidate);
            separated = true;
            break;
          }
          if (separated) continue;

          for (final angle in candidateAngles) {
            final candidateDirection = Vector2(
              direction.x * math.cos(angle) - direction.y * math.sin(angle),
              direction.x * math.sin(angle) + direction.y * math.cos(angle),
            );
            final candidate =
                first.position - candidateDirection * pushDistance;
            if (_hitsObstacle(candidate, first.radius) ||
                candidate.distanceTo(second.position) < requiredDistance) {
              continue;
            }
            first.position.setFrom(candidate);
            break;
          }
        }
      }
    }
  }

  void _fireEnemyVolley(
    _Enemy enemy,
    double distance,
    int shots,
    double spread,
  ) {
    if (distance >= (enemy.boss ? 620 : 470) || enemy.attackCooldown > 0) {
      return;
    }
    if (!_hasClearShot(enemy.position, _player)) return;

    final bossPhase = !enemy.boss
        ? 1
        : enemy.health <= enemy.maxHealth * 0.25
        ? 3
        : enemy.health <= enemy.maxHealth / 2
        ? 2
        : 1;
    enemy.attackCooldown = enemy.boss
        ? switch (bossPhase) {
            3 => 0.8,
            2 => 1.15,
            _ => 1.75,
          }
        : enemy.type == _EnemyType.sentinel
        ? math.max(1.25, 2.7 - _wave * 0.045)
        : enemy.type == _EnemyType.bomber
        ? math.max(1.1, 2.1 - _wave * 0.04) + _random.nextDouble() * 0.35
        : math.max(0.75, 1.7 - _wave * 0.07) + _random.nextDouble() * 0.3;

    final toPlayer = _player - enemy.position;
    if (toPlayer.length2 == 0) return;
    toPlayer.normalize();
    final projectileSpeed = switch (enemy.type) {
      _EnemyType.bomber => 165.0,
      _EnemyType.sentinel => 205.0,
      _EnemyType.weaver => 220.0,
      _ => enemy.boss ? 270.0 : 255.0,
    };
    final flightTime = (enemy.position.distanceTo(_player) / projectileSpeed)
        .clamp(0.0, 0.8)
        .toDouble();
    final predictedPlayer = _player + _playerVelocity * flightTime;
    final predictedAim = predictedPlayer - enemy.position;
    if (predictedAim.length2 == 0) return;
    predictedAim.normalize();
    final aimAngle =
        math.atan2(predictedAim.y, predictedAim.x) +
        (enemy.type == _EnemyType.weaver
            ? _visualTime * 0.8 * enemy.orbitDirection
            : 0);
    for (var index = 0; index < shots; index++) {
      final radial = enemy.type == _EnemyType.sentinel;
      final angle = radial
          ? _visualTime * 0.32 + index * math.pi * 2 / shots
          : aimAngle + _spreadOffset(index, shots, spread);
      final direction = Vector2(math.cos(angle), math.sin(angle));
      final projectileDamage = enemy.boss
          ? (15 + bossPhase * 5 + _threatTier * 2).toDouble()
          : enemy.type == _EnemyType.bomber
          ? (16 + _wave * 1.7).toDouble()
          : enemy.type == _EnemyType.sentinel
          ? (14 + _wave * 1.8).toDouble()
          : (11 + _wave * 1.5).toDouble();
      _enemyBullets.add(
        _Bullet(
          position: enemy.position + direction * (enemy.radius + 5),
          velocity: direction * projectileSpeed,
          damage: projectileDamage,
          life: 20,
          heavy:
              enemy.boss ||
              enemy.type == _EnemyType.bomber ||
              enemy.type == _EnemyType.sentinel,
        ),
      );
    }
  }

  bool _hasClearShot(Vector2 from, Vector2 to) {
    final delta = to - from;
    final distance = delta.length;
    final samples = math.max(1, (distance / 10).ceil());
    for (var index = 1; index < samples; index++) {
      final point = from + delta * (index / samples);
      if (_hitsObstacle(point, 3)) return false;
    }
    return true;
  }

  void _seekClearFiringPosition(
    _Enemy enemy,
    double preferredRange,
    double dt,
  ) {
    Vector2? bestPosition;
    var bestScore = double.infinity;
    for (var index = 0; index < 24; index++) {
      final angle = index * math.pi * 2 / 24;
      final candidate =
          _player + Vector2(math.cos(angle), math.sin(angle)) * preferredRange;
      if (_hitsObstacle(candidate, enemy.radius) ||
          !_hasClearShot(candidate, _player)) {
        continue;
      }
      final score =
          candidate.distanceTo(enemy.position) +
          (_visibleWorldRect.contains(Offset(candidate.x, candidate.y))
              ? 90
              : 0);
      if (score < bestScore) {
        bestScore = score;
        bestPosition = candidate;
      }
    }
    final target = bestPosition;
    if (target == null) {
      _steerEnemy(enemy, _player - enemy.position, dt);
      return;
    }
    _steerEnemy(enemy, target - enemy.position, dt);
  }

  void _steerEnemy(_Enemy enemy, Vector2 desiredDirection, double dt) {
    if (desiredDirection.length2 == 0) return;
    desiredDirection.normalize();
    const angles = [
      0.0,
      0.45,
      -0.45,
      0.85,
      -0.85,
      1.25,
      -1.25,
      1.7,
      -1.7,
      2.2,
      -2.2,
      math.pi,
    ];
    Vector2? bestDirection;
    var bestScore = double.negativeInfinity;
    for (final angle in angles) {
      final direction = Vector2(
        desiredDirection.x * math.cos(angle) -
            desiredDirection.y * math.sin(angle),
        desiredDirection.x * math.sin(angle) +
            desiredDirection.y * math.cos(angle),
      );
      final nextPosition = enemy.position + direction * enemy.speed * dt;
      if (_hitsObstacle(nextPosition, enemy.radius)) continue;
      final score = direction.dot(desiredDirection);
      if (score > bestScore) {
        bestScore = score;
        bestDirection = direction;
      }
    }

    if (bestDirection == null) {
      _moveBody(
        enemy.position,
        desiredDirection * enemy.speed * dt,
        enemy.radius,
      );
      return;
    }
    enemy.position.add(bestDirection * enemy.speed * dt);
  }

  void _moveBullets(double dt) {
    final spentBullets = <_Bullet>{};
    final defeatedEnemies = <_Enemy>{};

    for (final bullet in _bullets) {
      final previousPosition = bullet.position.clone();
      bullet.position.add(bullet.velocity * dt);
      bullet.life -= dt;
      final contact = _firstObstacleContact(
        previousPosition,
        bullet.position,
        3,
      );
      final outsideArena =
          bullet.position.x < 0 ||
          bullet.position.y < 0 ||
          bullet.position.x > arenaWidth ||
          bullet.position.y > arenaHeight;
      final segmentEnd = contact ?? bullet.position.clone();
      var impacted = contact != null || outsideArena || bullet.life <= 0;
      if (contact != null) bullet.position.setFrom(contact);

      var firstEnemyContactT = double.infinity;
      Vector2? firstEnemyContactPosition;
      _Enemy? firstEnemyHit;
      for (final enemy in _enemies) {
        if (defeatedEnemies.contains(enemy)) continue;
        final enemyContact = contact == null
            ? movingCircleContact(
                previousPosition,
                segmentEnd,
                enemy.previousPosition,
                enemy.position,
                enemy.radius + 4,
              )
            : segmentCircleContact(
                previousPosition,
                segmentEnd,
                enemy.position,
                enemy.radius + 4,
              );
        if (enemyContact != null && enemyContact.$1 < firstEnemyContactT) {
          firstEnemyContactT = enemyContact.$1;
          firstEnemyContactPosition = enemyContact.$2;
          firstEnemyHit = enemy;
          impacted = true;
        }
      }
      if (impacted) {
        spentBullets.add(bullet);
        final detonationPoint =
            contact ?? firstEnemyContactPosition ?? segmentEnd;
        if (bullet.blastRadius > 0) {
          for (final enemy in _enemies) {
            if (detonationPoint.distanceTo(enemy.position) <=
                bullet.blastRadius + enemy.radius) {
              _damageEnemy(enemy, bullet.damage);
              if (enemy.health <= 0) defeatedEnemies.add(enemy);
            }
          }
        } else if (firstEnemyHit != null) {
          _damageEnemy(firstEnemyHit, bullet.damage);
          if (firstEnemyHit.health <= 0) defeatedEnemies.add(firstEnemyHit);
        }
      }
    }

    _bullets.removeWhere(spentBullets.contains);
    for (final enemy in defeatedEnemies) {
      _enemies.remove(enemy);
      _kills++;
      _pickups.add(
        _Pickup(
          position: enemy.position.clone(),
          type: PickupType.coin,
          value: enemy.elite ? 3 : 1,
          salvageBonus: _kills % 4 == 0 ? level(UpgradeType.salvage) : 0,
        ),
      );
    }
  }

  void _damageEnemy(_Enemy enemy, double amount) {
    enemy.health -= amount;
    enemy.hitFlash = 0.18;
  }

  Vector2? _firstObstacleContact(Vector2 start, Vector2 end, double radius) {
    final delta = end - start;
    final steps = math.max(1, (delta.length / 4).ceil());
    for (var index = 1; index <= steps; index++) {
      final point = start + delta * (index / steps);
      if (_hitsObstacle(point, radius)) return point;
    }
    return null;
  }

  static (double, Vector2)? segmentCircleContact(
    Vector2 start,
    Vector2 end,
    Vector2 center,
    double radius,
  ) {
    final delta = end - start;
    final offset = start - center;
    final lengthSquared = delta.length2;
    if (lengthSquared == 0) {
      return offset.length2 <= radius * radius ? (0, start.clone()) : null;
    }

    final projection = offset.dot(delta);
    final constant = offset.length2 - radius * radius;
    if (constant <= 0) return (0, start.clone());
    final discriminant = projection * projection - lengthSquared * constant;
    if (discriminant < 0) return null;

    final t = (-projection - math.sqrt(discriminant)) / lengthSquared;
    if (t < 0 || t > 1) return null;
    return (t, start + delta * t);
  }

  static (double, Vector2)? movingCircleContact(
    Vector2 start,
    Vector2 end,
    Vector2 circleStart,
    Vector2 circleEnd,
    double radius,
  ) {
    final relativeContact = segmentCircleContact(
      start - circleStart,
      end - circleEnd,
      Vector2.zero(),
      radius,
    );
    if (relativeContact == null) return null;
    final t = relativeContact.$1;
    return (t, start + (end - start) * t);
  }

  void _moveEnemyBullets(double dt) {
    final spentBullets = <_Bullet>{};
    for (final bullet in _enemyBullets) {
      final previousPosition = bullet.position.clone();
      bullet.position.add(bullet.velocity * dt);
      bullet.life -= dt;
      final obstacleContact = _firstObstacleContact(
        previousPosition,
        bullet.position,
        5,
      );
      if (obstacleContact != null) {
        spentBullets.add(bullet);
        continue;
      }
      final playerContact = segmentCircleContact(
        previousPosition,
        bullet.position,
        _player,
        20,
      );
      if (playerContact != null) {
        _damagePlayer(bullet.damage);
        spentBullets.add(bullet);
        continue;
      }
      final outsideArena =
          bullet.position.x < 0 ||
          bullet.position.y < 0 ||
          bullet.position.x > arenaWidth ||
          bullet.position.y > arenaHeight;
      if (bullet.life <= 0 || outsideArena) {
        spentBullets.add(bullet);
      }
    }
    _enemyBullets.removeWhere(spentBullets.contains);
  }

  void _damagePlayer(double amount) {
    _health -= amount;
    _damageFlash = 0.25;
  }

  void _collectPickups(double dt) {
    final collected = <_Pickup>[];
    for (final pickup in _pickups) {
      pickup.pulse += dt * 6;
      final towardPlayer = _player - pickup.position;
      final distance = towardPlayer.length;
      pickup.isMagnetized =
          level(UpgradeType.magnet) > 0 && distance <= pickupMagnetRange;
      if (pickup.isMagnetized && distance > 0) {
        towardPlayer.normalize();
        final pullSpeed = 190 + level(UpgradeType.magnet) * 50;
        pickup.position.add(towardPlayer * math.min(distance, pullSpeed * dt));
      }
      if (pickup.position.distanceTo(_player) > 30) {
        continue;
      }
      collected.add(pickup);
      switch (pickup.type) {
        case PickupType.coin:
          _wallet += pickup.value + pickup.salvageBonus;
          _saveProgress();
        case PickupType.surge:
          _surgeTimer = 9;
        case PickupType.force:
          _forceTimer = 9;
        case PickupType.repair:
          _health = math.min(maxHealth, _health + 22);
      }
    }
    _pickups.removeWhere(collected.contains);
  }

  void _beginNextWave() {
    _wave++;
    if ((_wave - 1) % 3 == 0) _generateArena();
    _enemies.clear();
    _bullets.clear();
    _enemyBullets.clear();
    _enemiesSpawnedThisWave = 0;
    _pendingWaveBosses = _wave % 6 == 0 && _wave % 12 != 0 ? 2 : 1;
    _enemyTypesSpawned.clear();
    final isFinalWave = _wave % 12 == 0;
    if (isFinalWave) {
      _remainingSpawns = 7 + _threatTier * 3;
    } else {
      final totalEnemies = 18 + _wave * 5 + sectorIndex * 8 + _threatTier * 8;
      final openingGroup = math.min(
        totalEnemies,
        7 + sectorIndex * 2 + _threatTier * 2,
      );
      for (var index = 0; index < openingGroup; index++) {
        _spawnEnemy();
      }
      _remainingSpawns = totalEnemies - openingGroup;
    }
    _spawnCooldown = 0.8;
    _spawnSupply();
    _setPhase(RunPhase.playing);
  }

  void _spawnReinforcements(double dt) {
    if (_remainingSpawns <= 0) return;
    _spawnCooldown -= dt;
    final enemyLimit = concurrentEnemyLimit;
    final isFinalWave = _wave % 12 == 0;
    if (_spawnCooldown > 0 || _enemies.length >= enemyLimit) return;

    _spawnEnemy();
    _remainingSpawns--;
    final interval = math.max(
      0.32,
      0.72 - sectorIndex * 0.035 - _threatTier * 0.025,
    );
    _spawnCooldown = isFinalWave ? math.max(0.55, interval * 1.35) : interval;
  }

  void _spawnWaveBoss() {
    final isFinalBoss = _wave % 12 == 0;
    final bossCount = _pendingWaveBosses;
    _pendingWaveBosses = 0;
    for (var index = 0; index < bossCount; index++) {
      final finalBoss = isFinalBoss && index == 0;
      final bossHealth = _waveBossHealth(finalBoss);
      _enemies.add(
        _Enemy(
          position: _randomOffscreenFreePoint(radius: finalBoss ? 48 : 34),
          radius: finalBoss ? 48 : 34,
          health: bossHealth,
          maxHealth: bossHealth,
          speed: finalBoss ? 66 + _threatTier * 5 : 76 + _threatTier * 4,
          damage: finalBoss ? 30 + _threatTier * 4 : 24 + _threatTier * 3,
          elite: true,
          type: _EnemyType.gunner,
          boss: true,
        ),
      );
    }
    _publish();
  }

  double _waveBossHealth(bool finalBoss) => finalBoss
      ? (3600 + (_wave ~/ 12 - 1) * 700) * (1 + _threatTier * 0.45)
      : (720 + _wave * 105) * (1 + _threatTier * 0.3);

  _EnemyType _nextEnemyType() {
    final index = _enemiesSpawnedThisWave;
    if (_wave >= 10 && index % 11 == 8) return _EnemyType.sentinel;
    if (_wave >= 7 && index % 9 == 6) return _EnemyType.weaver;
    if (_wave >= 5 && index % 7 == 4) return _EnemyType.bomber;
    if (_wave >= 3 && index % 5 == 2) return _EnemyType.charger;
    if (_wave >= 2 && index % 3 == 0) return _EnemyType.gunner;
    return _EnemyType.stalker;
  }

  void _spawnEnemy() {
    final bossWave = _wave % 12 == 0;
    final eliteChance =
        (0.16 + math.min(_wave, 12) * 0.025 + sectorIndex * 0.03).clamp(
          0,
          0.52,
        );
    final elite = bossWave || _random.nextDouble() < eliteChance;
    final type = _nextEnemyType();
    final position = _randomOffscreenFreePoint(radius: elite ? 19 : 13);
    final difficulty = 1 + _threatTier * 0.18 + sectorIndex * 0.025;
    final health = (30 + _wave * 4 + (elite ? 30 : 0)) * difficulty;
    _enemies.add(
      _Enemy(
        position: position,
        radius: elite ? 19 : 13,
        health: health,
        maxHealth: health,
        speed: math.min(
          300,
          (switch (type) {
                    _EnemyType.stalker => 118,
                    _EnemyType.gunner => 96,
                    _EnemyType.charger => 105,
                    _EnemyType.bomber => 78,
                    _EnemyType.weaver => 112,
                    _EnemyType.sentinel => 48,
                  } +
                  math.min(_wave * 3, 48) +
                  (elite ? 18 : 0)) *
              (1 + _threatTier * 0.06),
        ),
        damage: (18 + _wave * 2 + (elite ? 10 : 0)) * (1 + _threatTier * 0.3),
        elite: elite,
        type: type,
      ),
    );
    _enemyTypesSpawned.add(type);
    _enemies.last.orbitDirection = _random.nextBool() ? 1 : -1;
    _enemiesSpawnedThisWave++;
  }

  Rect get _visibleWorldRect {
    final viewWidth = math.min(_viewportSize.x, arenaWidth);
    final viewHeight = math.min(_viewportSize.y, arenaHeight);
    final cameraX = math.max(
      viewWidth / 2,
      math.min(_player.x, arenaWidth - viewWidth / 2),
    );
    final cameraY = math.max(
      viewHeight / 2,
      math.min(_player.y, arenaHeight - viewHeight / 2),
    );
    return Rect.fromCenter(
      center: Offset(cameraX, cameraY),
      width: viewWidth,
      height: viewHeight,
    );
  }

  Vector2 _randomOffscreenFreePoint({required double radius}) {
    final offscreenBounds = _visibleWorldRect.inflate(90);
    for (var attempt = 0; attempt < 300; attempt++) {
      final point = Vector2(
        48 + _random.nextDouble() * (arenaWidth - 96),
        48 + _random.nextDouble() * (arenaHeight - 96),
      );
      if (offscreenBounds.contains(Offset(point.x, point.y)) ||
          _hitsObstacle(point, radius) ||
          point.distanceTo(_player) < 280 ||
          !_hasEnemyClearance(point, radius)) {
        continue;
      }
      return point;
    }

    final candidates = <Vector2>[
      Vector2(offscreenBounds.left - radius - 4, _player.y),
      Vector2(offscreenBounds.right + radius + 4, _player.y),
      Vector2(_player.x, offscreenBounds.top - radius - 4),
      Vector2(_player.x, offscreenBounds.bottom + radius + 4),
    ];
    for (final point in candidates) {
      point.x = point.x.clamp(radius, arenaWidth - radius).toDouble();
      point.y = point.y.clamp(radius, arenaHeight - radius).toDouble();
      if (!offscreenBounds.contains(Offset(point.x, point.y)) &&
          !_hitsObstacle(point, radius) &&
          _hasEnemyClearance(point, radius)) {
        return point;
      }
    }
    for (var attempt = 0; attempt < 120; attempt++) {
      final point = _randomFreePoint(minimumPlayerDistance: 450);
      if (_hasEnemyClearance(point, radius)) return point;
    }
    return _randomFreePoint(minimumPlayerDistance: 450);
  }

  bool _hasEnemyClearance(Vector2 point, double radius) => _enemies.every(
    (enemy) => point.distanceTo(enemy.position) >= radius + enemy.radius + 3,
  );

  void _spawnSupply() {
    final choices = [PickupType.surge, PickupType.force, PickupType.repair];
    _pickups.add(
      _Pickup(
        position: _randomFreePoint(minimumPlayerDistance: 100),
        type: choices[_random.nextInt(choices.length)],
      ),
    );
  }

  void _generateArena() {
    _seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    _random = math.Random(_seed);
    _obstacles.clear();
    _enemies.clear();
    _bullets.clear();
    _enemyBullets.clear();
    _pickups.clear();
    _player.setValues(arenaWidth / 2, arenaHeight / 2);

    for (var index = 0; index < 27; index++) {
      final width = 34 + _random.nextDouble() * 58;
      final height = 30 + _random.nextDouble() * 54;
      final left = 64 + _random.nextDouble() * (arenaWidth - width - 128);
      final top = 64 + _random.nextDouble() * (arenaHeight - height - 128);
      final obstacle = Rect.fromLTWH(left, top, width, height);
      if (obstacle
              .inflate(24)
              .contains(Offset(arenaWidth / 2, arenaHeight / 2)) ||
          _obstacles.any((other) => other.inflate(12).overlaps(obstacle))) {
        continue;
      }
      _obstacles.add(obstacle);
    }
  }

  Vector2 _randomFreePoint({required double minimumPlayerDistance}) {
    for (var attempt = 0; attempt < 120; attempt++) {
      final point = Vector2(
        48 + _random.nextDouble() * (arenaWidth - 96),
        48 + _random.nextDouble() * (arenaHeight - 96),
      );
      if (point.distanceTo(_player) < minimumPlayerDistance ||
          _hitsObstacle(point, 22)) {
        continue;
      }
      return point;
    }
    return Vector2(arenaWidth - 80, arenaHeight - 80);
  }

  void _moveBody(Vector2 position, Vector2 delta, double radius) {
    final nextX = Vector2(position.x + delta.x, position.y);
    if (!_hitsObstacle(nextX, radius)) position.x = nextX.x;
    final nextY = Vector2(position.x, position.y + delta.y);
    if (!_hitsObstacle(nextY, radius)) position.y = nextY.y;
  }

  bool _hitsObstacle(Vector2 point, double radius) {
    if (point.x < radius ||
        point.y < radius ||
        point.x > arenaWidth - radius ||
        point.y > arenaHeight - radius) {
      return true;
    }
    for (final obstacle in _obstacles) {
      final closestX = point.x.clamp(obstacle.left, obstacle.right);
      final closestY = point.y.clamp(obstacle.top, obstacle.bottom);
      final dx = point.x - closestX;
      final dy = point.y - closestY;
      if (dx * dx + dy * dy < radius * radius) return true;
    }
    return false;
  }

  void _drawFloor(Canvas canvas, double cameraX, double cameraY) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, arenaWidth, arenaHeight),
      Paint()..color = _floorColor,
    );
    final left = math.max(0.0, cameraX - size.x / 2).toDouble();
    final right = math.min(arenaWidth, cameraX + size.x / 2).toDouble();
    final top = math.max(0.0, cameraY - size.y / 2).toDouble();
    final bottom = math.min(arenaHeight, cameraY + size.y / 2).toDouble();
    const grid = 88.0;

    for (var y = (top / grid).floor() * grid; y < bottom; y += grid) {
      for (var x = (left / grid).floor() * grid; x < right; x += grid) {
        final column = (x / grid).floor();
        final row = (y / grid).floor();
        if ((column * 7 + row * 11 + _seed) % 5 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(x + 2, y + 2, grid - 4, grid - 4),
            Paint()..color = _floorTileColor,
          );
        }
      }
    }

    final gridPaint = Paint()
      ..color = _accentColor.withAlpha(35)
      ..strokeWidth = 1;
    for (var x = (left / grid).floor() * grid; x < right; x += grid) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), gridPaint);
    }
    for (var y = (top / grid).floor() * grid; y < bottom; y += grid) {
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);
    }

    final beacon = Offset(arenaWidth / 2, arenaHeight / 2);
    final pulse = 0.5 + math.sin(_visualTime * 2) * 0.5;
    canvas.drawCircle(
      beacon,
      72 + pulse * 8,
      Paint()
        ..color = _accentColor.withAlpha((10 + pulse * 12).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      beacon,
      58,
      Paint()
        ..color = _accentColor.withAlpha(20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawArena(Canvas canvas) {
    final borderPaint = Paint()
      ..color = _accentColor.withAlpha(170)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawRect(
      const Rect.fromLTWH(4, 4, arenaWidth - 8, arenaHeight - 8),
      borderPaint,
    );

    for (var index = 0; index < _obstacles.length; index++) {
      final rect = _obstacles[index];
      final body = RRect.fromRectAndRadius(
        rect,
        Radius.circular(sectorIndex.isEven ? 8 : rect.shortestSide / 2),
      );
      final bodyColor = const [
        Color(0xFF2B3C33),
        Color(0xFF493027),
        Color(0xFF263B49),
        Color(0xFF3C2A4D),
      ][sectorIndex % 4];
      canvas.drawRRect(body, Paint()..color = bodyColor);
      canvas.drawRRect(
        body,
        Paint()
          ..color = _accentColor.withAlpha(170)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(rect.left + 8, rect.top + 10),
        Offset(rect.right - 8, rect.top + 10),
        Paint()
          ..color = _accentColor.withAlpha(80)
          ..strokeWidth = 2,
      );
      if (index.isEven) {
        canvas.drawCircle(
          Offset(rect.right - 9, rect.bottom - 9),
          2,
          Paint()..color = _accentColor,
        );
      }
      if (sectorIndex == 1) {
        for (var stripe = 0; stripe < 3; stripe++) {
          final x = rect.left + 12 + stripe * 12;
          if (x < rect.right - 8) {
            canvas.drawLine(
              Offset(x, rect.top + 16),
              Offset(x, rect.bottom - 12),
              Paint()
                ..color = _accentColor.withAlpha(55)
                ..strokeWidth = 2,
            );
          }
        }
      } else if (sectorIndex == 2) {
        canvas.drawCircle(
          rect.center,
          rect.shortestSide * 0.23,
          Paint()
            ..color = _accentColor.withAlpha(75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  void _drawPlayer(Canvas canvas) {
    final nearest = _enemies.isEmpty
        ? Vector2(_player.x + 1, _player.y)
        : _enemies.reduce((first, second) {
            return first.position.distanceTo(_player) <
                    second.position.distanceTo(_player)
                ? first
                : second;
          }).position;
    final facing = nearest - _player;
    if (facing.length2 > 0) facing.normalize();
    final center = Offset(_player.x, _player.y);
    final gait =
        math.sin(_visualTime * (_playerMoving ? 15 : 2.5)) *
        (_playerMoving ? 3.2 : 0.6);
    final bob =
        math.sin(_visualTime * (_playerMoving ? 15 : 2.5)).abs() *
        (_playerMoving ? 1.4 : 0.35);
    final thruster = 3 + math.sin(_visualTime * 21).abs() * 4;

    canvas.drawOval(
      Rect.fromCenter(center: center.translate(0, 13), width: 31, height: 11),
      Paint()..color = const Color(0x66060D0A),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy + bob);
    canvas.rotate(math.atan2(facing.y, facing.x));

    final backpack = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-12, -8, 10, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(backpack, Paint()..color = const Color(0xFF315847));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-15, 0), width: thruster, height: 7),
      Paint()..color = const Color(0xFFFFAD66).withAlpha(180),
    );
    _drawArticulatedLimb(
      canvas,
      Offset(-3, -5),
      Offset(-7 - gait, -10),
      Offset(-11 - gait, -8),
      const Color(0xFF547C62),
      5,
    );
    _drawArticulatedLimb(
      canvas,
      Offset(-3, 5),
      Offset(-7 + gait, 10),
      Offset(-11 + gait, 8),
      const Color(0xFF547C62),
      5,
    );
    for (final side in [-1.0, 1.0]) {
      final leg = side * gait;
      _drawArticulatedLimb(
        canvas,
        const Offset(-2, 5),
        Offset(-4 + leg, side * 10),
        Offset(-6 - leg, side * 14),
        const Color(0xFF426750),
        5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-5 - leg, side * 14),
            width: 8,
            height: 5,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFB5D9B8),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, -8, 19, 16),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFF6DAB7E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2, -5, 9, 10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF274A3B),
    );
    canvas.drawCircle(const Offset(2.5, 0), 2, Paint()..color = gold);
    _drawArticulatedLimb(
      canvas,
      const Offset(4, -6),
      const Offset(8, -9),
      const Offset(11, -5),
      const Color(0xFF8DC69A),
      4,
    );
    _drawArticulatedLimb(
      canvas,
      const Offset(4, 6),
      const Offset(9, 8),
      const Offset(14, 3),
      const Color(0xFF8DC69A),
      4,
    );
    canvas.drawCircle(const Offset(9, -9), 2.2, Paint()..color = gold);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(5, -1), width: 17, height: 18),
      Paint()..color = const Color(0xFFB8D5B8),
    );
    canvas.drawArc(
      const Rect.fromLTWH(-3, -10, 17, 15),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFFE7F2D2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, -4, 8, 6),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF53D8CF),
    );
    canvas.drawCircle(const Offset(12, -1), 1.3, Paint()..color = ink);
    canvas.drawLine(
      const Offset(12, 4),
      const Offset(24, 4),
      Paint()
        ..color = const Color(0xFFE3D8A5)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      const Offset(21, 4),
      const Offset(26, 4),
      Paint()
        ..color = gold
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    final shipPulse = 0.5 + math.sin(_visualTime * 2) * 0.5;
    canvas.drawCircle(
      center,
      22 + shipPulse * 2,
      Paint()
        ..color = _accentColor.withAlpha(30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (_damageFlash > 0) {
      canvas.drawCircle(
        center,
        28 + (0.25 - _damageFlash) * 20,
        Paint()
          ..color = coral.withAlpha(
            (_damageFlash * 420).round().clamp(0, 255).toInt(),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    canvas.drawCircle(
      Offset(_player.x - facing.y * 5, _player.y + facing.x * 5),
      3,
      Paint()..color = const Color(0xFF1B5940),
    );
  }

  void _drawEnemies(Canvas canvas) {
    for (final enemy in _enemies) {
      final center = Offset(enemy.position.x, enemy.position.y);
      final color = enemy.boss
          ? const Color(0xFFFF543F)
          : switch (enemy.type) {
              _EnemyType.stalker => const Color(0xFFE76658),
              _EnemyType.gunner => const Color(0xFFE18CF2),
              _EnemyType.charger => const Color(0xFFFFA64D),
              _EnemyType.bomber => const Color(0xFF61D8C6),
              _EnemyType.weaver => const Color(0xFF82A7FF),
              _EnemyType.sentinel => const Color(0xFFFFD166),
            };
      if (enemy.boss) {
        final pulse = 0.5 + math.sin(_visualTime * 2.8) * 0.5;
        canvas.drawCircle(
          center,
          enemy.radius + 22 + pulse * 10,
          Paint()
            ..color = color.withAlpha(22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8,
        );
        for (var point = 0; point < 8; point++) {
          final angle = _visualTime * 0.28 + point * math.pi / 4;
          final inner = enemy.radius * 0.76;
          final outer = enemy.radius * (point.isEven ? 1.0 : 0.88);
          canvas.drawLine(
            center + Offset(math.cos(angle), math.sin(angle)) * inner,
            center + Offset(math.cos(angle), math.sin(angle)) * outer,
            Paint()
              ..color = color.withAlpha(175)
              ..strokeWidth = enemy.radius * 0.09
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      final towardPlayer = _player - enemy.position;
      final angle = math.atan2(towardPlayer.y, towardPlayer.x);
      final scale = enemy.boss
          ? 1.7
          : enemy.elite
          ? 1.12
          : 0.86;
      final phase = _visualTime * 12 + center.dx * 0.03 + center.dy * 0.02;
      final isRanged =
          enemy.type == _EnemyType.gunner ||
          enemy.type == _EnemyType.bomber ||
          enemy.type == _EnemyType.sentinel;
      final gait = math.sin(phase) * (isRanged ? 1.3 : 3.2) * scale;
      final bob = math.sin(phase * 2).abs() * (isRanged ? 1.0 : 1.8);
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, enemy.radius * 0.82),
          width: enemy.radius * 2.2,
          height: enemy.radius * 0.78,
        ),
        Paint()..color = const Color(0x66060D0A),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy - bob);
      canvas.rotate(angle);
      canvas.scale(scale);

      for (final side in [-1.0, 1.0]) {
        _drawArticulatedLimb(
          canvas,
          Offset(-2, side * 3),
          Offset(-3 + side * gait, side * 9),
          Offset(-5 - side * gait, side * 13),
          enemy.boss ? const Color(0xFF631E24) : const Color(0xFF642F36),
          enemy.boss ? 6 : 4,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(-5 - side * gait, side * 13),
            width: enemy.boss ? 11 : 7,
            height: enemy.boss ? 7 : 5,
          ),
          Paint()..color = const Color(0xFF321B22),
        );
      }
      final torso = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, 0),
          width: enemy.radius * (enemy.boss ? 1.25 : 1.5),
          height: enemy.radius * (enemy.boss ? 1.3 : 1.25),
        ),
        Radius.circular(
          enemy.boss
              ? 12
              : enemy.elite
              ? 8
              : 6,
        ),
      );
      canvas.drawRRect(torso, Paint()..color = color);
      canvas.drawRRect(
        torso,
        Paint()
          ..color = enemy.boss
              ? const Color(0xFFFFA18A)
              : enemy.type == _EnemyType.charger
              ? const Color(0xFFFFE0A1)
              : enemy.type == _EnemyType.bomber
              ? const Color(0xFFB5FFF0)
              : enemy.type == _EnemyType.weaver
              ? const Color(0xFFD8E1FF)
              : enemy.type == _EnemyType.sentinel
              ? const Color(0xFFFFE6A0)
              : enemy.type == _EnemyType.gunner
              ? const Color(0xFFF3C8FF)
              : const Color(0xFFFFB49A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = enemy.elite ? 2.5 : 1.4,
      );
      for (final side in [-1.0, 1.0]) {
        _drawArticulatedLimb(
          canvas,
          Offset(1, side * enemy.radius * 0.38),
          Offset(enemy.radius * 0.48, side * enemy.radius * 0.65 + gait * 0.35),
          Offset(enemy.radius * 0.63, side * enemy.radius * 0.38),
          color,
          enemy.boss ? 7 : 4,
        );
      }
      final headRadius = enemy.radius * (enemy.boss ? 0.48 : 0.43);
      canvas.drawCircle(
        Offset(enemy.radius * 0.24, -enemy.radius * 0.2),
        headRadius,
        Paint()..color = enemy.boss ? const Color(0xFF4A1A20) : color,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(enemy.radius * 0.45, -enemy.radius * 0.18),
            width: headRadius * 0.8,
            height: enemy.boss ? 8 : 4,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = enemy.boss ? gold : const Color(0xFFFFD18B),
      );
      if (enemy.elite) {
        final hornPaint = Paint()
          ..color = enemy.boss ? const Color(0xFF3C1720) : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = enemy.boss ? 5 : 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(0, -headRadius * 0.5),
          Offset(-headRadius * 0.65, -headRadius * 1.55),
          hornPaint,
        );
        canvas.drawLine(
          Offset(headRadius * 0.48, -headRadius * 0.48),
          Offset(headRadius * 1.25, -headRadius * 1.3),
          hornPaint,
        );
      }
      if (enemy.charging) {
        final charge = (1 - enemy.chargeTimer / 0.55).clamp(0, 1);
        canvas.drawCircle(
          center,
          enemy.radius + 10 + charge * 14,
          Paint()
            ..color = const Color(0xFFFFD174)
                .withAlpha(100 + (charge * 100).round())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (isRanged) {
        final charge = (1 - enemy.attackCooldown / 0.7).clamp(0, 1);
        canvas.drawLine(
          Offset(enemy.radius * 0.45, enemy.radius * 0.38),
          Offset(enemy.radius * 1.02, enemy.radius * 0.38),
          Paint()
            ..color = enemy.boss
                ? gold
                : enemy.type == _EnemyType.bomber
                ? const Color(0xFFB5FFF0)
                : const Color(0xFFF3C8FF)
            ..strokeWidth = enemy.boss ? 6 : 3.5
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          Offset(enemy.radius * 1.02, enemy.radius * 0.38),
          (enemy.boss ? 4 : 2.5) + charge * 3,
          Paint()
            ..color =
                (enemy.boss
                        ? gold
                        : enemy.type == _EnemyType.bomber
                        ? const Color(0xFFB5FFF0)
                        : const Color(0xFFF3C8FF))
                    .withAlpha(170 + (charge * 85).round()),
        );
      }
      canvas.restore();

      if (enemy.type == _EnemyType.weaver) {
        for (var blade = 0; blade < 3; blade++) {
          final bladeAngle =
              _visualTime * enemy.orbitDirection + blade * math.pi * 2 / 3;
          final bladePosition =
              center +
              Offset(math.cos(bladeAngle), math.sin(bladeAngle)) *
                  (enemy.radius + 9);
          canvas.drawCircle(
            bladePosition,
            3,
            Paint()..color = const Color(0xFFD8E1FF),
          );
        }
      } else if (enemy.type == _EnemyType.sentinel &&
          enemy.attackCooldown < 1.0) {
        final charge = (1 - enemy.attackCooldown).clamp(0, 1);
        final innerRadius = enemy.radius + 8;
        final outerRadius = innerRadius + 10 + charge * 14;
        final telegraph = Paint()
          ..color = const Color(0xFFFFD166)
              .withAlpha(70 + (charge * 130).round())
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(
          center,
          outerRadius,
          telegraph..style = PaintingStyle.stroke,
        );
        for (var ray = 0; ray < 8; ray++) {
          final rayAngle = _visualTime * 0.32 + ray * math.pi / 4;
          canvas.drawLine(
            center +
                Offset(math.cos(rayAngle), math.sin(rayAngle)) * innerRadius,
            center +
                Offset(math.cos(rayAngle), math.sin(rayAngle)) * outerRadius,
            telegraph..style = PaintingStyle.fill,
          );
        }
      }

      if (enemy.hitFlash > 0) {
        final progress = 1 - enemy.hitFlash / 0.18;
        canvas.drawCircle(
          center,
          enemy.radius + 3 + progress * 8,
          Paint()
            ..color = const Color(0xFFFFF2CA)
                .withAlpha((enemy.hitFlash / 0.18 * 230).round())
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        canvas.drawCircle(
          center,
          enemy.radius * 0.55,
          Paint()
            ..color = const Color(0xFFFFD166)
                .withAlpha((enemy.hitFlash / 0.18 * 65).round()),
        );
      }

      if (isRanged && enemy.attackCooldown < 0.7) {
        final charge = (1 - enemy.attackCooldown / 0.7).clamp(0, 1);
        canvas.drawCircle(
          center,
          enemy.radius + 6 + charge * 9,
          Paint()
            ..color =
                (enemy.boss
                        ? color
                        : enemy.type == _EnemyType.bomber
                        ? const Color(0xFF61D8C6)
                        : const Color(0xFFF3C8FF))
                    .withAlpha(145)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      final bar = Rect.fromLTWH(
        enemy.position.x - math.max(16.0, enemy.radius),
        enemy.position.y - enemy.radius - 9,
        math.max(32.0, enemy.radius * 2),
        5,
      );
      canvas.drawRect(bar, Paint()..color = const Color(0xFF452B27));
      canvas.drawRect(
        Rect.fromLTWH(
          bar.left,
          bar.top,
          bar.width * (enemy.health / enemy.maxHealth).clamp(0, 1),
          bar.height,
        ),
        Paint()..color = gold,
      );
    }
  }

  void _drawBullets(Canvas canvas) {
    for (final bullet in _bullets) {
      final center = Offset(bullet.position.x, bullet.position.y);
      final direction = bullet.velocity;
      final length = direction.length;
      if (length > 0) {
        canvas.drawLine(
          center - Offset(direction.x / length, direction.y / length) * 13,
          center,
          Paint()
            ..color = const Color(0xFFFFAD42).withAlpha(210)
            ..strokeWidth = bullet.heavy ? 6 : 3
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(
        center,
        bullet.heavy ? 7 : 5,
        Paint()..color = const Color(0xFFFFAD42),
      );
      canvas.drawCircle(center, 2.5, Paint()..color = const Color(0xFFFFF2CA));
    }
    for (final bullet in _enemyBullets) {
      final center = Offset(bullet.position.x, bullet.position.y);
      final direction = bullet.velocity;
      final length = direction.length;
      final color = bullet.heavy
          ? const Color(0xFFFF654A)
          : const Color(0xFFE18CF2);
      if (length > 0) {
        canvas.drawLine(
          center - Offset(direction.x / length, direction.y / length) * 11,
          center,
          Paint()
            ..color = color.withAlpha(155)
            ..strokeWidth = bullet.heavy ? 7 : 4
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(center, bullet.heavy ? 8 : 5, Paint()..color = color);
      canvas.drawCircle(center, 2, Paint()..color = const Color(0xFFFFF2FF));
    }
  }

  void _drawPickups(Canvas canvas) {
    for (final pickup in _pickups) {
      final center = Offset(pickup.position.x, pickup.position.y);
      final pulse = math.sin(pickup.pulse) * 2;
      final color = switch (pickup.type) {
        PickupType.coin => gold,
        PickupType.surge => const Color(0xFF6FE4E0),
        PickupType.force => const Color(0xFFFF9C73),
        PickupType.repair => mint,
      };
      if (pickup.isMagnetized) {
        final towardPlayer = Offset(
          _player.x - center.dx,
          _player.y - center.dy,
        );
        canvas.drawLine(
          center,
          Offset(_player.x, _player.y),
          Paint()
            ..color = color.withAlpha(45)
            ..strokeWidth = 1.5,
        );
        for (var particle = 0; particle < 3; particle++) {
          final progress = (pickup.pulse * 0.8 + particle / 3) % 1;
          final point = center + towardPlayer * progress;
          canvas.drawCircle(
            point,
            2 + math.sin(pickup.pulse * 2 + particle) * 0.7,
            Paint()..color = color.withAlpha(190),
          );
        }
      }
      canvas.drawCircle(
        center,
        12 + pulse + (pickup.isMagnetized ? 3 : 0),
        Paint()..color = color.withAlpha(pickup.isMagnetized ? 95 : 55),
      );
      canvas.drawCircle(center, 8 + pulse, Paint()..color = color);
      if (pickup.type == PickupType.repair) {
        final paint = Paint()
          ..color = const Color(0xFF1A4934)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - 3, center.dy),
          Offset(center.dx + 3, center.dy),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx, center.dy - 3),
          Offset(center.dx, center.dy + 3),
          paint,
        );
      } else {
        canvas.drawCircle(center, 3, Paint()..color = const Color(0xFF423823));
      }
    }
  }

  GameSnapshot _makeSnapshot() => GameSnapshot(
    phase: _phase,
    wave: _wave,
    health: _health,
    maxHealth: maxHealth,
    wallet: _wallet,
    kills: _kills,
    seed: _seed,
    powerLevel: level(UpgradeType.power),
    hullLevel: level(UpgradeType.hull),
    strideLevel: level(UpgradeType.stride),
    surgeSeconds: _surgeTimer,
    forceSeconds: _forceTimer,
    bossHealth: _activeBoss?.health ?? 0,
    bossMaxHealth:
        _activeBoss?.maxHealth ??
        (_pendingWaveBosses > 0 && _wave % 12 == 0 ? _waveBossHealth(true) : 0),
    remainingThreats: _enemies.length + _remainingSpawns + _pendingWaveBosses,
    threatTier: _threatTier,
  );

  _Enemy? get _activeBoss {
    for (final enemy in _enemies) {
      if (enemy.boss) return enemy;
    }
    return null;
  }

  void _setPhase(RunPhase phase) {
    _phase = phase;
    if (phase != RunPhase.playing) {
      _touchMove = Vector2.zero();
      _touchFire = false;
    }
    _publish();
  }

  void _publish() {
    snapshot.value = _makeSnapshot();
  }

  void _saveProgress() {
    unawaited(
      onSave(_wallet, Map<UpgradeType, int>.from(_levels), _threatTier),
    );
  }
}

void _drawArticulatedLimb(
  Canvas canvas,
  Offset shoulder,
  Offset elbow,
  Offset hand,
  Color color,
  double width,
) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(shoulder, elbow, paint);
  canvas.drawLine(
    elbow,
    hand,
    Paint()
      ..color = color.withAlpha(225)
      ..strokeWidth = width * 0.78
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawCircle(
    elbow,
    width * 0.32,
    Paint()..color = const Color(0xFFD5B7A0),
  );
}

class _Enemy {
  _Enemy({
    required this.position,
    required this.radius,
    required this.health,
    required this.maxHealth,
    required this.speed,
    required this.damage,
    required this.elite,
    required this.type,
    this.boss = false,
  }) : previousPosition = position.clone(),
       attackCooldown = boss ? 2.2 : 0.6,
       chargeCooldown = type == _EnemyType.charger ? 1.6 : 0;

  final Vector2 position;
  final Vector2 previousPosition;
  final double radius;
  final double maxHealth;
  final double speed;
  final double damage;
  final bool elite;
  final _EnemyType type;
  final bool boss;
  final Vector2 velocity = Vector2.zero();
  double health;
  double attackCooldown;
  double chargeCooldown;
  double hitFlash = 0;
  double chargeTimer = 0;
  int orbitDirection = 1;
  bool charging = false;
  Vector2 chargeDirection = Vector2.zero();
}

class _Bullet {
  _Bullet({
    required this.position,
    required this.velocity,
    required this.damage,
    this.heavy = false,
    this.blastRadius = 0,
    this.life = 1.5,
  });

  final Vector2 position;
  final Vector2 velocity;
  final double damage;
  final bool heavy;
  final double blastRadius;
  double life;
}

class _Pickup {
  _Pickup({
    required this.position,
    required this.type,
    this.value = 0,
    this.salvageBonus = 0,
  });

  final Vector2 position;
  final PickupType type;
  final int value;
  final int salvageBonus;
  double pulse = 0;
  bool isMagnetized = false;
}
