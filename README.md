# All-In

An offline macOS app for learning Texas Hold'em from the ground up and playing it against AI opponents.

- Bottom-up curriculum that teaches how to think, not what to memorize
- Career journey: Kitchen table → Club → Casino → High Roller
- Cash (6-max, full ring), heads-up and tournaments
- Character opponents with distinct play styles
- Stylized, game-like UI with rich animation

Status: M3 done (first playable build: theme system, animated fantasy table, main menu, Quick Play lobby; cash 6-max and heads-up against the bots). Next: M4 (analysis, coach panel, hand review, persistence). UI approved (`design/wireframes/`), implementation plan in [`docs/PLAN.md`](docs/PLAN.md). Theme: cozy high fantasy.

## Build and run

Requires Xcode 27.2 on an Apple Silicon Mac running macOS 26.

```
Tools/build.sh       # build the package and the app
Tools/run.sh         # build and launch
Tools/test.sh unit   # fast tests; see CONTRIBUTING.md for all levels
Tools/test.sh lint   # swift-format and architecture import check
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
