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
