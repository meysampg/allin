# Contributing

Plan and task breakdown: [`docs/PLAN.md`](docs/PLAN.md). Architecture rules: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Requirements

Xcode 27.2, Swift 6.4.x, macOS 26, Apple Silicon. There is no CI; the scripts in `Tools/` are the only gate.

## Build and run

```
Tools/build.sh                 # swift package + macOS app (if AllIn.xcodeproj exists), into build/DerivedData
Tools/run.sh [app args]        # build and launch; args go to the app, e.g. -AllInDemo YES -AllInScreen table -AllInSeed 7
Tools/screens.sh [screen ids]  # PNG of the app window per demo screen into build/screens/
```

## Test levels

`Tools/test.sh <level>...` (default `unit`). Levels whose targets do not exist yet are skipped with a message.

| Level | Runs |
|---|---|
| `unit` | `swift test`, skipping Heavy and Sim (under 2 min) |
| `heavy` | release-mode `Heavy` tests (under 10 min) |
| `sim` | release-mode `Sim` tests (under 10 min) |
| `content` | `ContentTests`, the content validator |
| `ui` | XCUITest smoke tests (`AllInUITests`) |
| `lint` | `swift format lint` plus the engine-module import check |
| `all` | everything |

Run `unit` and `lint` before every commit.

## Content authoring

Curriculum and characters are JSON in `Content/`. Workflow (validate, preview, stats, hot-load) is in PLAN.md section 6.5; the field reference will live in `docs/CONTENT_GUIDE.md`. `Tools/test.sh content` is the gate.

## Formatting

`swift format` with the config in `.swift-format` (2-space indent, 120 columns). Fix with `swift format format -i --configuration .swift-format <files>`.

## Commits

- Short imperative subject, for example `Add HandEvaluator golden tests`; one logical change per commit.
- Commit freely while working; push when the task is done.
- Tests ship with the code they cover. Engine changes must keep determinism: same seed, same result.

## Workflow: Sonnet codes, Haiku tests

Work follows PLAN.md section 10. Each milestone task is sized for one Sonnet subagent that owns a fixed list of files and must not edit files owned by other tasks. Opus plans; Sonnet writes the code and its tests; Haiku runs the checks listed under "What Haiku runs at the end of each milestone" (PLAN.md section 9) and reports results. A milestone is done when those checks are green.
