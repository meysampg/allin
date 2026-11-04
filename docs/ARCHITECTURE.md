# Architecture

Summary of the rules in [`PLAN.md`](PLAN.md) section 1. The plan is the source of truth; read it for detail.

## Modules and boundaries

All logic lives in the local package `Packages/AllInKit`. The app target (`AllIn/`) is a thin SwiftUI shell.

```
PokerCore ──► PokerEquity ──► PokerAI ──► PokerAnalysis ──► Curriculum ──► AllInStore
    │                            ▲
    └──► PokerHost ──────────────┘ (tests and the CLI only; PokerAI does not import PokerHost)
ThemeKit ──► TableKit (SpriteKit, + PokerCore)
ThemeKit ──► AllInUI  (SwiftUI, + PokerCore, PokerEquity)
App ──► everything
```

Imports flow only along the arrows. PokerCore imports only the Swift stdlib and Foundation. See PLAN.md section 1.2 for the full table of what each module may import and owns.

## The hard import rule

The engine modules (PokerCore, PokerEquity, PokerHost, PokerAI, PokerAnalysis, Curriculum, plus PokerAbstraction and Solver when they exist) never import SwiftUI, AppKit, SpriteKit or SwiftData. They must stay portable to a Linux server. `Tools/test.sh lint` greps for violations and fails.

## Concurrency and determinism

- Engine types are `Sendable` value types. `HandReducer` is a pure function: `(HandState, Command) throws -> (HandState, [GameEvent])`.
- `GameHost` is an `actor`. UI controllers are `@MainActor @Observable final class`. SpriteKit scenes stay on the main actor.
- `StrategyProvider` is `Sendable` and stateless per call. Adaptive state (`PlayerModel`) is passed in as an immutable snapshot at the start of each hand.
- Randomness is always `inout some RandomNumberGenerator` with `SeededRNG` (xoshiro256**). Nothing calls `SystemRandomNumberGenerator` except seed creation in the app layer. Any hand, spot or simulation replays from its seed and action log.
- AI, equity and grading never run on the main actor. The UI shows progressive results.
- Swift 6 language mode with strict concurrency everywhere.

## Seat and host event model

- A `Seat` receives events already filtered for it (`observe`) and answers `decide(_:)` with an `Action`. Implementations: `LocalHumanSeat` (app layer), `BotSeat`, `ScriptedSeat`, `RandomSeat`; a future `RemoteSeat` wraps a transport.
- The `GameHost` actor is authoritative. It validates every action against `LegalActions` and the expected `seq`; an illegal action becomes the closest legal one (check if possible, else fold) with a logged warning.
- The event log (`[LoggedEvent]`, each with a `Visibility` of public, seat or host-only) is the hand history. `HandReplayer` rebuilds every state from it exactly; review, archive and stats all consume the same log. A seat-filtered log never contains another seat's hole cards before showdown.
- The UI plays a spectator stream back through an `AnimationQueue`; the host may run ahead of the animations.

## Other conventions

- Poker words stay real; only art, names and voice are fantasy.
- Grades come from EV, and luck is reported separately.
- Every bot exposes its strategy as a probability distribution (white box).
- Offline only: sandbox on, no network entitlement.

## Where the code differs from PLAN.md (M2)

- `StrategyProvider.distribution(for:)` takes only a `DecisionContext`; the hole cards are `context.holeCards` (no `hand:` parameter).
- Exact flop hand-vs-range equity takes about 20–60 ms, not 5 ms, so live callers use Monte Carlo.
- `preflop169.bin` is about 376 KB (47,008 entries), not 120 KB.
- There is no `RangeTracker` yet. Bots read the hero through `PerceivedRange` (PokerEquity) with `readSkill` blur. M4 adds a batched Bayesian tracker.
- `allin-tool sim` and the Sim gates use heads-up duplicate deals for win rates and 6-max (personality + 5 Oryn) for style stats.

## Where the code differs from PLAN.md (M3)

- M3.7 (app shell) ran after M3.6, not alongside it, because `RootView` injects the AllInUI `Theme` environment and uses its button style.
- Bet-size maths lives in AllInUI (`AllInUI/Table/BetSizing.swift`) so it can be unit-tested; the app target has no unit-test target.
- `allin-tool` links TableKit (SpriteKit) for `theme render-cards` and `theme render-table`, so the tool is macOS-only.
- The Arena button is not on the main menu until M7. The next hand starts on Space or a click (no auto-deal), which keeps UI tests deterministic.
- Table keys go through the menu-bar `Commands` (`FocusedValues.tableActions`) with an `.onKeyPress` fallback.
- `TableModel` collects every seat's bet (folded seats included) when a street is dealt, because the host emits `potsUpdated` only at the end of a hand.
- `AnimationQueue` in `.spriteKit` mode starts each SKAction and waits for its duration with `Task.sleep` instead of awaiting the action, so a paused or hidden scene cannot hang the queue.
- `SeatLayout` uses hand-placed bet spots for 2, 6 and 9 seats, and the dealer shoe sits at the top right of the rail.
- The UI tests and `Tools/screens.sh` need macOS Automation Mode enabled (`automationmodetool`) and Screen Recording permission for the terminal.
