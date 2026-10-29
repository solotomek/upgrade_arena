# Project Notes

- This is a Flutter and Flame top-down survival game.
- Keep gameplay simulation, arena generation, combat, and drops in `lib/game/arena_game.dart`.
- Keep Flutter overlays, touch controls, and local persistence in `lib/main.dart`.
- Preserve both keyboard controls and mobile touch controls when changing input.
- Run `flutter analyze`, `flutter test`, and `flutter build apk --debug` for verification.
- Game visuals are drawn procedurally; do not add external assets unless requested.