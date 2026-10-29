import 'dart:async';
import 'dart:math' as math;

import 'package:flame_audio/flame_audio.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/arena_game.dart';

const _background = Color(0xFF0D1512);
const _panel = Color(0xFF18231E);
const _line = Color(0xFF34473B);
const _mint = Color(0xFF93F5B6);
const _gold = Color(0xFFFFCF72);
const _muted = Color(0xFF9BAFA2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    UpgradeArenaApp(
      preferences: preferences,
      musicEnabled: true,
      showIntroOnLaunch: !(preferences.getBool('storySeen') ?? false),
    ),
  );
}

class UpgradeArenaApp extends StatefulWidget {
  const UpgradeArenaApp({
    super.key,
    required this.preferences,
    this.musicEnabled = false,
    this.showIntroOnLaunch = false,
  });

  final SharedPreferences preferences;
  final bool musicEnabled;
  final bool showIntroOnLaunch;

  @override
  State<UpgradeArenaApp> createState() => _UpgradeArenaAppState();
}

class _UpgradeArenaAppState extends State<UpgradeArenaApp> {
  late final GameCore _game;

  @override
  void initState() {
    super.initState();
    _game = GameCore(
      onSave: _saveProgress,
      showIntro: widget.showIntroOnLaunch,
      onIntroSeen: () {
        unawaited(widget.preferences.setBool('storySeen', true));
      },
    );
    _game.restoreProgress(widget.preferences.getInt('bankedCoins') ?? 0, {
      for (final type in UpgradeType.values)
        type: widget.preferences.getInt('upgrade.${type.name}') ?? 0,
    }, threatTier: widget.preferences.getInt('threatTier') ?? 0);
  }

  Future<void> _saveProgress(
    int wallet,
    Map<UpgradeType, int> levels,
    int threatTier,
  ) async {
    await widget.preferences.setInt('bankedCoins', wallet);
    await widget.preferences.setInt('threatTier', threatTier);
    for (final entry in levels.entries) {
      await widget.preferences.setInt('upgrade.${entry.key.name}', entry.value);
    }
  }

  @override
  void dispose() {
    _game.pauseEngine();
    _game.snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Upgrade Arena',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          primary: _mint,
          secondary: _gold,
          surface: _panel,
          error: Color(0xFFFF796A),
        ),
        fontFamily: 'monospace',
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _mint,
            foregroundColor: const Color(0xFF102117),
            minimumSize: const Size(54, 50),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
      home: _ArenaScreen(game: _game, musicEnabled: widget.musicEnabled),
    );
  }
}

class _ArenaScreen extends StatefulWidget {
  const _ArenaScreen({required this.game, required this.musicEnabled});

  final GameCore game;
  final bool musicEnabled;

  @override
  State<_ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<_ArenaScreen> {
  late final Future<void> _audioInitialization;
  bool _audioInitialized = false;
  bool _musicStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.musicEnabled) {
      _audioInitialization = _initializeAudio();
      if (!kIsWeb) unawaited(_startMusic());
    } else {
      _audioInitialization = Future<void>.value();
    }
  }

  Future<void> _initializeAudio() async {
    try {
      await FlameAudio.bgm.initialize();
      _audioInitialized = true;
    } on MissingPluginException catch (error, stackTrace) {
      _reportAudioError(error, stackTrace);
    } on PlatformException catch (error, stackTrace) {
      _reportAudioError(error, stackTrace);
    }
  }

  Future<void> _startMusic() async {
    if (_musicStarted || !widget.musicEnabled) return;
    _musicStarted = true;
    try {
      await _audioInitialization;
      if (!_audioInitialized) {
        _musicStarted = false;
        return;
      }
      await FlameAudio.bgm.play('sector_theme.wav', volume: 0.24);
    } on MissingPluginException catch (error, stackTrace) {
      _musicStarted = false;
      _reportAudioError(error, stackTrace);
    } on PlatformException catch (error, stackTrace) {
      _musicStarted = false;
      _reportAudioError(error, stackTrace);
    }
  }

  void _reportAudioError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'arena audio',
        context: ErrorDescription('while initializing background music'),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.musicEnabled) unawaited(FlameAudio.bgm.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => unawaited(_startMusic()),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameWidget<GameCore>(game: widget.game, autofocus: true),
                SafeArea(
                  child: ValueListenableBuilder<GameSnapshot>(
                    valueListenable: widget.game.snapshot,
                    builder: (context, snapshot, _) => Stack(
                      children: [
                        if (snapshot.phase == RunPhase.playing)
                          _TouchControls(game: widget.game),
                        if (snapshot.phase == RunPhase.playing)
                          _GameHud(game: widget.game, snapshot: snapshot),
                        if (snapshot.phase == RunPhase.title)
                          _TitleScreen(game: widget.game, snapshot: snapshot),
                        if (snapshot.phase == RunPhase.intro)
                          _StoryIntro(game: widget.game),
                        if (snapshot.phase == RunPhase.armory)
                          _ArmoryScreen(game: widget.game, snapshot: snapshot),
                        if (snapshot.phase == RunPhase.paused)
                          _PauseScreen(game: widget.game, snapshot: snapshot),
                        if (snapshot.phase == RunPhase.ended)
                          _RunEndedScreen(
                            game: widget.game,
                            snapshot: snapshot,
                          ),
                        if (snapshot.phase == RunPhase.victory)
                          _VictoryScreen(game: widget.game, snapshot: snapshot),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameHud extends StatelessWidget {
  const _GameHud({required this.game, required this.snapshot});

  final GameCore game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      left: 14,
      right: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'WAVE ${snapshot.wave.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        game.sectorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _mint.withAlpha(210),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${game.kills} ELIMINATED',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'ASCENSION ${snapshot.threatTier + 1}  ·  ${snapshot.remainingThreats} HOSTILES',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  game.weaponStatus,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                _HealthBar(fraction: snapshot.healthFraction),
                if (snapshot.bossHealthFraction > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${game.bossName}  ·  PHASE ${snapshot.bossHealthFraction <= 0.25
                        ? 'III'
                        : snapshot.bossHealthFraction <= 0.5
                        ? 'II'
                        : 'I'}',
                    style: const TextStyle(
                      color: Color(0xFFFF8067),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 220,
                    height: 7,
                    child: LinearProgressIndicator(
                      value: snapshot.bossHealthFraction.clamp(0, 1),
                      backgroundColor: const Color(0xFF48221F),
                      color: const Color(0xFFFF654A),
                    ),
                  ),
                ],
                if (snapshot.activePower case final power?) ...[
                  const SizedBox(height: 6),
                  Text(
                    '$power  ${_pickupSeconds(snapshot)}',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CoinReadout(coins: snapshot.wallet),
          const SizedBox(width: 8),
          _IconButton(
            icon: Icons.pause_rounded,
            label: 'Pause run',
            onPressed: game.pauseRun,
          ),
        ],
      ),
    );
  }

  String _pickupSeconds(GameSnapshot snapshot) {
    final seconds = snapshot.surgeSeconds > 0
        ? snapshot.surgeSeconds
        : snapshot.forceSeconds;
    return '${seconds.ceil()}s';
  }
}

class _StoryIntro extends StatefulWidget {
  const _StoryIntro({required this.game});

  final GameCore game;

  @override
  State<_StoryIntro> createState() => _StoryIntroState();
}

class _StoryIntroState extends State<_StoryIntro> {
  static const _chapters = [
    (
      'THE LAST LIGHT',
      'The refuge of Haven has one night of power left. Your daughter, Lio, is waiting beneath its failing shield.',
    ),
    (
      'THE DAWN ENGINE',
      'Its stolen core lies beyond four hostile sectors, guarded by a war machine called the Warden.',
    ),
    (
      'DEATH IS A DOOR',
      'Haven’s echo-vault can rebuild you from your last imprint. You wake again; the salvage you carried home remains.',
    ),
    (
      'BRING BACK THE SUN',
      'Cross the arena. Break the Warden. Bring the Dawn Engine home before Haven goes dark.',
    ),
  ];

  int _chapter = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_chapter == _chapters.length - 1) {
        timer.cancel();
        widget.game.finishIntro();
      } else {
        setState(() => _chapter++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters[_chapter];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.game.finishIntro,
      child: Container(
        color: const Color(0xF20A1016),
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = constraints.maxWidth < 580
                ? constraints.maxWidth - 40
                : 540.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _Panel(
                width: panelWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Eyebrow('INCOMING TRANSMISSION  ·  HAVEN'),
                    const SizedBox(height: 8),
                    const Text(
                      '47 YEARS AFTER THE BLACKOUT',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 9,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(
                      width: double.infinity,
                      height: 150,
                      child: CustomPaint(painter: _StoryArtwork()),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: Column(
                        key: ValueKey(_chapter),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.$1,
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            chapter.$2,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        for (var index = 0; index < _chapters.length; index++)
                          Container(
                            width: index == _chapter ? 22 : 6,
                            height: 4,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: index == _chapter ? _mint : _line,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          _chapter == _chapters.length - 1
                              ? 'TAP TO BEGIN'
                              : 'TAP ANYWHERE TO SKIP',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StoryArtwork extends CustomPainter {
  const _StoryArtwork();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.53);
    final core = Paint()..color = const Color(0xFFFFCF72);
    for (var ring = 3; ring > 0; ring--) {
      canvas.drawCircle(
        center,
        19 + ring * 17,
        Paint()
          ..color = const Color(0x1893F5B6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.drawCircle(center, 16, Paint()..color = const Color(0x55FFCF72));
    canvas.drawCircle(center, 7, core);
    canvas.drawCircle(
      center,
      42,
      Paint()
        ..color = const Color(0x6693F5B6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final warden = Path()
      ..moveTo(size.width * 0.82, size.height * 0.16)
      ..lineTo(size.width * 0.91, size.height * 0.75)
      ..lineTo(size.width * 0.80, size.height * 0.65)
      ..lineTo(size.width * 0.73, size.height * 0.86)
      ..lineTo(size.width * 0.70, size.height * 0.35)
      ..close();
    canvas.drawPath(warden, Paint()..color = const Color(0x99FF654A));

    final ship = Path()
      ..moveTo(size.width * 0.15, size.height * 0.35)
      ..lineTo(size.width * 0.23, size.height * 0.53)
      ..lineTo(size.width * 0.12, size.height * 0.49)
      ..lineTo(size.width * 0.08, size.height * 0.57)
      ..close();
    canvas.drawPath(ship, Paint()..color = _mint);
    canvas.drawLine(
      Offset(size.width * 0.17, size.height * 0.54),
      Offset(center.dx - 48, center.dy),
      Paint()
        ..color = const Color(0x6693F5B6)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_StoryArtwork oldDelegate) => false;
}

class _TitleScreen extends StatelessWidget {
  const _TitleScreen({required this.game, required this.snapshot});

  final GameCore game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _Panel(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Eyebrow(
                'ASCENSION ${game.threatTier + 1}  /  ${game.sectorName}',
              ),
              const SizedBox(height: 14),
              const Text(
                'UPGRADE\nARENA',
                style: TextStyle(
                  color: Colors.white,
                  height: 0.94,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Every wave pays for the next advantage.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatBlock(
                      label: 'BANKED',
                      value: '${snapshot.wallet}',
                      icon: Icons.circle,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatBlock(
                      label: 'POWER',
                      value: '${snapshot.powerLevel}',
                      icon: Icons.bolt_rounded,
                      color: _mint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatBlock(
                      label: 'HULL',
                      value: '${snapshot.hullLevel}',
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFFFF9A83),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: game.beginRun,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('DEPLOY'),
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: game.openArmory,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('OPEN ARMORY'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArmoryScreen extends StatelessWidget {
  const _ArmoryScreen({required this.game, required this.snapshot});

  final GameCore game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final activeRun = snapshot.wave > 0;
    return Container(
      color: const Color(0xDD0A100D),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: _Panel(
          width: 660,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Eyebrow('PERMANENT MODIFICATIONS'),
                        SizedBox(height: 8),
                        Text(
                          'FIELD ARMORY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CoinReadout(coins: snapshot.wallet),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth < 590
                      ? (constraints.maxWidth - 10) / 2
                      : (constraints.maxWidth - 20) / 3;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final type in UpgradeType.values)
                        SizedBox(
                          width: cardWidth,
                          child: _UpgradeTile(game: game, type: type),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: game.continueFromArmory,
                  icon: Icon(
                    activeRun ? Icons.arrow_forward_rounded : Icons.close,
                  ),
                  label: Text(activeRun ? 'DEPLOY NEXT WAVE' : 'BACK TO BASE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({required this.game, required this.type});

  final GameCore game;
  final UpgradeType type;

  @override
  Widget build(BuildContext context) {
    final level = game.level(type);
    final cost = game.upgradeCost(type);
    final maxed = level >= 9;
    final icon = switch (type) {
      UpgradeType.power => Icons.bolt_rounded,
      UpgradeType.hull => Icons.favorite_rounded,
      UpgradeType.stride => Icons.speed_rounded,
      UpgradeType.rapid => Icons.flash_on_rounded,
      UpgradeType.magnet => Icons.attractions_rounded,
      UpgradeType.salvage => Icons.savings_rounded,
      UpgradeType.regen => Icons.healing_rounded,
      UpgradeType.critical => Icons.track_changes_rounded,
    };
    final tint = switch (type) {
      UpgradeType.power => _gold,
      UpgradeType.hull => const Color(0xFFFF9A83),
      UpgradeType.stride => _mint,
      UpgradeType.rapid => const Color(0xFFFFAC68),
      UpgradeType.magnet => const Color(0xFF79DDF0),
      UpgradeType.salvage => _gold,
      UpgradeType.regen => const Color(0xFF90E8C4),
      UpgradeType.critical => const Color(0xFFD58CFF),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101A15),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(height: 9),
          Text(
            game.upgradeName(type),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            game.upgradeEffect(type),
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 7),
          Text(
            'RANK $level  /  9',
            style: TextStyle(color: tint, fontSize: 10),
          ),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: ValueKey('upgrade-buy-${type.name}'),
              onPressed: maxed || game.wallet < cost
                  ? null
                  : () => game.buyUpgrade(type),
              child: Text(maxed ? 'MAXED' : 'BUY  ·  $cost'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseScreen extends StatelessWidget {
  const _PauseScreen({required this.game, required this.snapshot});

  final GameCore game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xDD0A100D),
      alignment: Alignment.center,
      child: _Panel(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Eyebrow('WAVE ${snapshot.wave.toString().padLeft(2, '0')}'),
            const SizedBox(height: 10),
            const Text(
              'PAUSED',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: game.resumeRun,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('RESUME'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: game.abandonRun,
                icon: const Icon(Icons.home_rounded),
                label: const Text('ABANDON RUN'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunEndedScreen extends StatelessWidget {
  const _RunEndedScreen({required this.game, required this.snapshot});

  final GameCore game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xDD0A100D),
      alignment: Alignment.center,
      child: _Panel(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('SIGNAL LOST'),
            const SizedBox(height: 10),
            const Text(
              'RUN OVER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Wave ${snapshot.wave}  ·  ${snapshot.kills} eliminations',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              '${snapshot.wallet} coins banked',
              style: const TextStyle(color: _gold, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: game.beginRun,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('RUN IT BACK'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: game.openArmory,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('SPEND COINS'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VictoryScreen extends StatelessWidget {
  const _VictoryScreen({required this.game, required this.snapshot});

  final GameCore game;
  final GameSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF20A1016),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth < 506
              ? constraints.maxWidth - 36
              : 470.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: _Panel(
              width: panelWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Eyebrow(
                    'ASCENSION ${game.threatTier} CLEARED  //  NEXT ${game.threatTier + 1}',
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 2200),
                    builder: (context, progress, _) => SizedBox(
                      width: double.infinity,
                      height: 110,
                      child: CustomPaint(
                        painter: _VictoryArtwork(progress: progress),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'THE FIRST\nSUNRISE',
                    style: TextStyle(
                      color: _gold,
                      height: 0.96,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'The Warden falls. The Dawn Engine catches, then floods '
                    'the sky with light. Across the radio, Lio counts a '
                    'sunrise she thought she would never see.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBlock(
                          label: 'WAVES CLEARED',
                          value: '${snapshot.wave}',
                          icon: Icons.flag_rounded,
                          color: _mint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatBlock(
                          label: 'WARDEN DEFEATED',
                          value: 'YES',
                          icon: Icons.shield_rounded,
                          color: _gold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatBlock(
                          label: 'SALVAGE BANKED',
                          value: '${snapshot.wallet}',
                          icon: Icons.circle,
                          color: _gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: game.beginRun,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('START A NEW ASCENT'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: game.returnToTitle,
                      child: const Text('RETURN TO HAVEN'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VictoryArtwork extends CustomPainter {
  const _VictoryArtwork({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.78;
    final sunCenter = Offset(size.width * 0.5, horizon);
    final radius = 35 * Curves.easeOutBack.transform(progress);
    for (var ray = 0; ray < 24; ray++) {
      final angle = ray * math.pi / 12;
      final inner = Offset(
        sunCenter.dx + math.cos(angle) * (radius + 8),
        sunCenter.dy + math.sin(angle) * (radius + 8),
      );
      final outer = Offset(
        sunCenter.dx + math.cos(angle) * (radius + 19),
        sunCenter.dy + math.sin(angle) * (radius + 19),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = _gold.withAlpha((130 * progress).round())
          ..strokeWidth = ray.isEven ? 2 : 1,
      );
    }
    canvas.drawCircle(
      sunCenter,
      radius + 8,
      Paint()..color = const Color(0x33FFCF72),
    );
    canvas.drawCircle(
      sunCenter,
      radius,
      Paint()..color = const Color(0xFFFFCF72),
    );
    final ridge = Path()
      ..moveTo(0, horizon + 16)
      ..lineTo(size.width * 0.18, horizon - 4)
      ..lineTo(size.width * 0.31, horizon + 8)
      ..lineTo(size.width * 0.48, horizon - 12)
      ..lineTo(size.width * 0.66, horizon + 7)
      ..lineTo(size.width * 0.82, horizon - 2)
      ..lineTo(size.width, horizon + 14)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ridge, Paint()..color = const Color(0xFF182A23));
    canvas.drawLine(
      Offset(0, horizon + 17),
      Offset(size.width, horizon + 17),
      Paint()
        ..color = _mint.withAlpha(100)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_VictoryArtwork oldDelegate) =>
      progress != oldDelegate.progress;
}

class _TouchControls extends StatefulWidget {
  const _TouchControls({required this.game});

  final GameCore game;

  @override
  State<_TouchControls> createState() => _TouchControlsState();
}

class _TouchControlsState extends State<_TouchControls> {
  static const double _stickRadius = 68;
  int? _activePointer;
  Offset? _anchor;
  Offset _drag = Offset.zero;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _anchor = event.localPosition;
    _updateMovement(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _activePointer) {
      _updateMovement(event.localPosition);
    }
  }

  void _updateMovement(Offset position) {
    final delta = position - _anchor!;
    final distance = delta.distance;
    final limited = distance > _stickRadius
        ? delta * (_stickRadius / distance)
        : delta;
    setState(() => _drag = limited);
    widget.game.setMovement(
      distance < 8
          ? Vector2.zero()
          : Vector2(limited.dx / _stickRadius, limited.dy / _stickRadius),
    );
  }

  void _releasePointer(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _anchor = null;
    setState(() => _drag = Offset.zero);
    widget.game.setMovement(Vector2.zero());
  }

  @override
  void dispose() {
    widget.game.setMovement(Vector2.zero());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        label:
            'Tap and drag anywhere to move. Your weapon fires automatically.',
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _releasePointer,
          onPointerCancel: _releasePointer,
          child: CustomPaint(
            painter: _TouchIndicator(anchor: _anchor, drag: _drag),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _anchor == null ? 0.8 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Text(
                      'DRAG ANYWHERE TO MOVE  ·  AUTO-FIRE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TouchIndicator extends CustomPainter {
  const _TouchIndicator({required this.anchor, required this.drag});

  final Offset? anchor;
  final Offset drag;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = anchor;
    if (origin == null) return;
    canvas.drawCircle(
      origin,
      68,
      Paint()
        ..color = const Color(0x5593F5B6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      origin + drag,
      20,
      Paint()..color = const Color(0xCC93F5B6),
    );
    canvas.drawCircle(
      origin + drag,
      20,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TouchIndicator oldDelegate) =>
      anchor != oldDelegate.anchor || drag != oldDelegate.drag;
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: 180,
        height: 7,
        child: LinearProgressIndicator(
          value: fraction.clamp(0, 1),
          backgroundColor: const Color(0xFF462C27),
          color: fraction < 0.3 ? const Color(0xFFFF796A) : _mint,
        ),
      ),
    );
  }
}

class _CoinReadout extends StatelessWidget {
  const _CoinReadout({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0xDD111A15),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 10, color: _gold),
          const SizedBox(width: 7),
          Text(
            '$coins',
            style: const TextStyle(
              color: _gold,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111A15),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 8),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xDD111A15),
        foregroundColor: Colors.white,
        side: const BorderSide(color: _line),
        fixedSize: const Size(42, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _mint,
        fontSize: 9,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
