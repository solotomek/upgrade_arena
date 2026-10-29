# Upgrade Arena

A top-down survival game built with Flutter and Flame. Survive escalating waves,
collect enemy coin drops, find temporary supplies, and invest in permanent
upgrades between waves. Every three waves opens a new biome with a different
palette and arena style. Banked coins and upgrade ranks persist between sessions.
The pilot and enemy crews are drawn as animated, articulated characters with
distinct silhouettes and directional combat details.
On the first launch, a skippable transmission explains the stakes: rebuild after
each failed assault, cross all four sectors, defeat the Warden, and bring Haven's
stolen Dawn Engine home for the pilot's daughter, Lio. The twelfth wave ends in
a three-phase boss fight and a dedicated victory sequence. Each victory unlocks
a saved Ascension tier: future runs add more reinforcements, faster and tougher
enemies, and a Warden that hits harder and survives longer.

## Play

- Move with `WASD` or the arrow keys on desktop. On mobile, tap and drag from
	anywhere on the screen; the drag direction controls movement.
- Your weapon targets the nearest enemy and fires automatically. Hold `Space`
	to fire faster on desktop. Eliminations unlock weapons during each run:
	the service pistol, burst rifle, scattergun, grenade launcher, and bazooka.
	Projectiles lead moving targets and sweep against their movement each frame;
	auto-fire selects enemies with a clear path instead of wasting shots against
	cover. Visible hit flashes and health bars confirm damage. Enemies physically
	separate instead of piling into one another.
	Explosive rounds damage groups around their impact. Ranged enemies telegraph aimed volleys; keep moving
	to dodge their spreading shots and the fast red Stalkers. Enemies arrive outside
	the camera view, with reinforcements continuing through most of each wave.
	Gunners hold range and fire, Chargers telegraph a high-speed rush, and Bombers
	stay back while laying down broad, slow volleys. The roster keeps evolving:
	Weavers begin orbiting and sweeping shots into your path from wave 7; heavy
	Sentinels add rotating radial barrages from wave 10. Later waves also increase
	elite frequency, enemy count, and volley speed. Every wave ends with a
	commander encounter; every sixth wave brings two commanders, and the Warden
	guards the twelfth-wave finale.
- Browsers may block autoplay: the original soundtrack starts after your first
	tap or click in the game.
- Pick up coins and supplies by moving over them. Surge boosts movement, Force
	increases damage, and Repair restores health.
- Clear a wave to open the armory. Invest in Power, Hull, Stride, Rapid Fire,
	Magnet, Salvage, Regeneration, and Critical Hit upgrades; each rank increases
	in cost at an accelerating rate. Salvage grants a bonus for every fourth
	elimination per rank. Magnet upgrades pull every nearby drop toward you with a visible
	energy stream; its top rank reaches roughly 458 world units.
- Press `Escape` to pause. Leaving a run keeps your banked coins and upgrades.
- An original, procedurally generated ambient soundtrack plays during the run.

## Run

Start the configured Android emulator from VS Code's device selector, or list
available emulators with:

```powershell
flutter emulators
```

Then run the app on the selected device:

```powershell
flutter devices
flutter run -d <device-id>
```

To run a quick browser build, use `flutter run -d chrome`.

## Verify

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Iteration APKs are saved separately under `build/iterations/`.

## Structure

- `lib/game/arena_game.dart` contains the Flame game loop, arena generation,
	collision, enemies, projectiles, pickups, and upgrade state.
- `lib/main.dart` contains the Flutter HUD, menus, touch controls, and local
	progress persistence.
